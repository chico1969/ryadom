use super::{device_id, valid_id};
use crate::{ConnectionMeta, ServerPtr};
use hbb_common::{
    anyhow::anyhow,
    bail,
    base64::{engine::general_purpose::STANDARD, Engine},
    config::{self, Config},
    futures_util::{SinkExt, StreamExt},
    log,
    ryadom_network::{check_transport, relay_allowed},
    tokio::{
        self,
        net::TcpStream,
        sync::{mpsc, Semaphore},
        time::{timeout, Duration},
    },
    webrtc::WebRTCStream,
    ResultType, Stream,
};
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    net::{Ipv4Addr, SocketAddr},
    sync::Arc,
};
use tokio_tungstenite::{
    tungstenite::{protocol::WebSocketConfig, Message as WsMessage},
    MaybeTlsStream, WebSocketStream,
};

const TIMEOUT: u64 = 25_000;
const MAX_SIGNAL: usize = 128 * 1024;
pub(super) type Socket = WebSocketStream<MaybeTlsStream<TcpStream>>;

struct Pending {
    stream: WebRTCStream,
    armed: bool,
}

pub(super) fn base_url() -> ResultType<String> {
    let config: Value = serde_json::from_str(include_str!("../../ryadom/signaling.json"))?;
    let url = config["url"].as_str().ok_or_else(|| anyhow!("Нет адреса службы поиска в сборке"))?;
    if !url.starts_with("wss://") {bail!("Служба поиска должна использовать защищённый WebSocket");}
    Ok(url.to_owned())
}
impl Pending {
    fn new(stream: WebRTCStream) -> Self {
        Self {
            stream,
            armed: true,
        }
    }
    fn finish(mut self) -> WebRTCStream {
        self.armed = false;
        self.stream.clone()
    }
}
impl Drop for Pending {
    fn drop(&mut self) {
        if self.armed {
            self.stream.close_detached();
        }
    }
}

pub(super) async fn open(id: &str) -> ResultType<Socket> {
    let url = format!(
        "{}&id={id}&token={}&version=1.5.5",
        base_url()?, uuid::Uuid::new_v4()
    );
    let mut cfg = WebSocketConfig::default();
    cfg.max_message_size = Some(MAX_SIGNAL);
    cfg.max_frame_size = Some(MAX_SIGNAL);
    let (mut socket, _) = timeout(
        Duration::from_millis(TIMEOUT),
        tokio_tungstenite::connect_async_with_config(url, Some(cfg), false),
    )
    .await??;
    let msg = timeout(Duration::from_millis(TIMEOUT), next(&mut socket)).await??;
    if msg["type"] != "OPEN" {
        bail!("Служба поиска отклонила регистрацию: {}", msg["type"]);
    }
    Ok(socket)
}

pub(super) async fn next(socket: &mut Socket) -> ResultType<Value> {
    loop {
        let msg = socket
            .next()
            .await
            .ok_or_else(|| anyhow!("Служба поиска недоступна"))??;
        match msg {
            WsMessage::Text(text) => return Ok(serde_json::from_str(&text)?),
            WsMessage::Ping(data) => socket.send(WsMessage::Pong(data)).await?,
            WsMessage::Close(_) => bail!("Служба поиска закрыла соединение"),
            _ => {}
        }
    }
}

fn sdp(endpoint: &str) -> ResultType<Value> {
    let raw = endpoint
        .strip_prefix("webrtc://")
        .ok_or_else(|| anyhow!("Некорректный WebRTC endpoint"))?;
    let value: Value = serde_json::from_slice(&STANDARD.decode(raw)?)?;
    validate_sdp(&value)?;
    Ok(json!({"type":value["type"],"sdp":value["sdp"]}))
}

fn validate_sdp(value: &Value) -> ResultType<()> {
    validate_sdp_policy(value, relay_allowed())
}

fn validate_sdp_policy(value: &Value, allow_relay: bool) -> ResultType<()> {
    let sdp = value["sdp"].as_str().ok_or_else(|| anyhow!("Нет SDP"))?;
    if sdp.len() > MAX_SIGNAL / 2
        || (!allow_relay
            && sdp.lines().any(|l| {
                l.starts_with("a=candidate:") && l.split_whitespace().any(|v| v == "relay")
            }))
    {
        bail!("Ретрансляция запрещена или SDP слишком велик");
    }
    if !matches!(value["type"].as_str(), Some("offer" | "answer")) {
        bail!("Недопустимый тип SDP");
    }
    Ok(())
}

fn endpoint(value: &Value) -> ResultType<String> {
    validate_sdp(value)?;
    Ok(format!(
        "webrtc://{}",
        STANDARD.encode(serde_json::to_vec(
            &json!({"type":value["type"],"sdp":value["sdp"],"ice_policy":"all"})
        )?)
    ))
}

fn envelope(kind: &str, peer: &str, connection: &str, sdp: Value) -> Value {
    let (_, pk) = Config::get_key_pair();
    json!({"type":kind,"dst":peer,"payload":{"type":"data","connectionId":connection,"sdp":sdp,
        "label":"bootstrap","serialization":"raw","reliable":true,
        "metadata":{"ryadomVersion":1,"publicKey":hex::encode(pk)}}})
}

fn candidate(value: &Value) -> ResultType<Option<String>> {
    candidate_policy(value, relay_allowed())
}

fn candidate_policy(value: &Value, allow_relay: bool) -> ResultType<Option<String>> {
    let text = value["candidate"]
        .as_str()
        .ok_or_else(|| anyhow!("Нет ICE-кандидата"))?;
    if text.is_empty() {
        return Ok(None);
    }
    let parts: Vec<_> = text.split_whitespace().collect();
    if text.len() > 8192
        || !parts.windows(2).any(|p| {
            p[0] == "typ"
                && (matches!(p[1], "host" | "srflx" | "prflx") || (p[1] == "relay" && allow_relay))
        })
    {
        bail!("Недопустимый или ретранслируемый ICE-кандидат");
    }
    Ok(Some(serde_json::to_string(value)?))
}

fn candidate_message(peer: &str, connection: &str, value: Value) -> Value {
    json!({"type":"CANDIDATE","dst":peer,"payload":{"type":"data","connectionId":connection,"candidate":value}})
}

pub async fn connect(peer: &str) -> ResultType<(WebRTCStream, Vec<u8>)> {
    if !valid_id(peer) {
        bail!("Некорректный ID");
    }
    timeout(Duration::from_secs(45),async {
        match connect_inner(peer,false,8_000,false).await {
            Ok(stream)=>Ok(stream),
            Err(_)=>connect_inner(peer,true,TIMEOUT,false).await,
        }
    }).await
        .map_err(|_|anyhow!(if relay_allowed() { "Не удалось установить соединение. Проверьте сеть, доступность удалённого ПК и квоту TURN." } else { "Не удалось установить прямой канал. Резервный TURN в этой сборке ещё не настроен." }))?
}

fn require_relay_configuration(configured: bool) -> ResultType<()> {
    if !configured { bail!("Для принудительного подключения через TURN настройте TURN на этом ПК"); }
    Ok(())
}

fn require_relay_transport(relayed: Option<bool>) -> ResultType<()> {
    if relayed != Some(true) { bail!("Не удалось подтвердить принудительное соединение через TURN"); }
    Ok(())
}

pub(super) async fn connect_relay(peer: &str) -> ResultType<(WebRTCStream, Vec<u8>)> {
    if !valid_id(peer) { bail!("Некорректный ID"); }
    require_relay_configuration(WebRTCStream::has_turn_server())?;
    timeout(Duration::from_secs(45),connect_inner(peer,true,TIMEOUT,true)).await
        .map_err(|_|anyhow!("Не удалось установить принудительное соединение через TURN"))?
}

pub(super) async fn connect_direct(peer:&str)->ResultType<(WebRTCStream,Vec<u8>)> {
    timeout(Duration::from_secs(15),connect_inner(peer,false,8_000,false)).await?
}

async fn connect_inner(peer: &str, allow_turn:bool, budget:u64, force_relay:bool) -> ResultType<(WebRTCStream, Vec<u8>)> {
    let client_id = format!("ryadom-client-{}", uuid::Uuid::new_v4());
    let mut socket = open(&client_id).await?;
    let pending = Pending::new(if force_relay {
        WebRTCStream::new("",true,TIMEOUT).await?
    } else {
        WebRTCStream::new_ryadom("", TIMEOUT,
            super::network_helper::ice_options(allow_turn)).await?
    });
    let mut local = pending
        .stream
        .take_local_ice_rx()
        .ok_or_else(|| anyhow!("Нет канала ICE"))?;
    let connection = format!("dc_{}", uuid::Uuid::new_v4());
    let mut offer=envelope(
                "OFFER",
                peer,
                &connection,
                sdp(pending.stream.local_endpoint())?,
            );
    offer["payload"]["metadata"]["directOnly"]=json!(!allow_turn);
    offer["payload"]["metadata"]["networkVersion"]=json!(1);
    socket.send(WsMessage::Text(offer.to_string().into())).await?;
    let mut waiter = pending.stream.clone();
    let connected = waiter.wait_connected(budget);
    tokio::pin!(connected);
    let mut public_key = None;
    let mut early: Vec<String> = Vec::new();
    loop {
        tokio::select! {
            biased;
            result=&mut connected=>{result?;break;}
            Some(value)=local.recv()=>{
                let value:Value=serde_json::from_str(&value)?;
                if candidate(&value)?.is_some(){socket.send(WsMessage::Text(candidate_message(peer,&connection,value).to_string().into())).await?;}
            }
            message=next(&mut socket)=>{
                let message=message?;
                if matches!(message["type"].as_str(),Some("EXPIRE"|"ERROR"|"LEAVE"|"ID-TAKEN")) {bail!("Удалённый ПК не найден или служба поиска отклонила запрос");}
                if message["src"]!=peer || message["payload"]["connectionId"]!=connection {continue;}
                match message["type"].as_str() {
                    Some("ANSWER")=>{
                        if public_key.is_some(){bail!("Повторный ответ SDP");}
                        let pk=hex::decode(message["payload"]["metadata"]["publicKey"].as_str().ok_or_else(||anyhow!("Нет ключа ПК"))?)?;
                        if pk.len()!=32||device_id(&pk)!=peer {bail!("Подмена личности удалённого ПК");}
                        pending.stream.set_remote_endpoint(&endpoint(&message["payload"]["sdp"])?).await?;
                        public_key=Some(pk);
                        for value in early.drain(..){pending.stream.add_remote_ice_candidate(&value).await?;}
                    }
                    Some("CANDIDATE")=>{
                        if let Some(value)=candidate(&message["payload"]["candidate"])? {
                            if public_key.is_some(){pending.stream.add_remote_ice_candidate(&value).await?;}
                            else {if early.len()>=64{bail!("Слишком много ICE-кандидатов");}early.push(value);}
                        }
                    }
                    _=>{}
                }
            }
        }
    }
    check_transport(pending.stream.is_relayed().await, allow_turn)?;
    if force_relay { require_relay_transport(pending.stream.is_relayed().await)?; }
    let pk = public_key.ok_or_else(|| anyhow!("Нет проверенной личности ПК"))?;
    let stream = pending.finish();
    let _ = socket.close(None).await;
    Ok((stream, pk))
}

pub async fn listen(server: ServerPtr) {
    super::network_helper::receiving();
    let _codes = super::short_code::start();
    let (sk, pk) = Config::get_key_pair();
    if sk.len() != 64 || pk.len() != 32 {
        super::registration::update("failed", "Не удалось открыть ключ устройства в профиле Windows.", 0);
        log::error!("Рядом: служба не запущена, ключ устройства недоступен");
        return;
    }
    let limit = Arc::new(Semaphore::new(8));
    let mut backoff = 1;
    loop {
        if stopped() {
            tokio::time::sleep(Duration::from_secs(1)).await;
            continue;
        }
        super::registration::update("connecting", "Подключаемся к службе поиска…", 0);
        match run(server.clone(), limit.clone()).await {
            Ok(()) => backoff = 1,
            Err(err) => {
                backoff = (backoff * 2).min(60);
                super::registration::failed(&err.to_string(), backoff);
                hbb_common::throttled_log!(Duration::from_secs(60), warn, "Рядом: служба поиска недоступна: {}", err);
            }
        }
        tokio::time::sleep(Duration::from_secs(backoff)).await;
    }
}

pub(super) fn stopped() -> bool {
    config::is_outgoing_only()
        || config::option2bool("stop-service", &Config::get_option("stop-service"))
}

async fn run(server: ServerPtr, limit: Arc<Semaphore>) -> ResultType<()> {
    let mut socket = open(&Config::get_id()).await?;
    let _online = super::short_code::Online::enter();
    super::registration::update("registering", "Регистрируем короткий ID…", 0);
    let (tx, mut rx) = mpsc::channel::<Value>(32);
    let mut routes: HashMap<(String, String), mpsc::Sender<Value>> = HashMap::new();
    let mut heartbeat = tokio::time::interval(Duration::from_secs(5));
    let mut maintenance = tokio::time::interval(Duration::from_secs(1));
    loop {
        tokio::select! {
            _=heartbeat.tick()=>socket.send(WsMessage::Text(json!({"type":"HEARTBEAT"}).to_string().into())).await?,
            _=maintenance.tick()=>{
                routes.retain(|_,sender|!sender.is_closed());
                if stopped(){socket.close(None).await?;return Ok(());}
            }
            Some(message)=rx.recv()=>socket.send(WsMessage::Text(message.to_string().into())).await?,
            message=next(&mut socket)=>{
                let message=message?;
                let Some(peer)=message["src"].as_str() else {continue;};
                let Some(connection)=message["payload"]["connectionId"].as_str() else {continue;};
                if peer.len()>80||connection.len()>80{continue;}
                let key=(peer.to_owned(),connection.to_owned());
                if message["type"]=="CANDIDATE" {
                    if let Some(sender)=routes.get(&key){let _=sender.try_send(message["payload"]["candidate"].clone());}
                    continue;
                }
                if message["type"]!="OFFER"||message["payload"]["metadata"]["ryadomVersion"]!=1||routes.contains_key(&key)||routes.len()>=32{continue;}
                let Ok(permit)=limit.clone().try_acquire_owned() else {continue;};
                let (remote_tx,remote_rx)=mpsc::channel(64);
                routes.insert(key,remote_tx);
                let server=server.clone();let tx=tx.clone();
                tokio::spawn(async move {
                    if let Err(err)=accept(server,tx,remote_rx,message,permit).await {
                        hbb_common::throttled_log!(Duration::from_secs(5),warn,"Рядом: подключение отклонено: {}",err);
                    }
                });
            }
        }
    }
}

async fn negotiate_answer(
    tx: &mpsc::Sender<Value>,
    mut remote: mpsc::Receiver<Value>,
    peer: &str,
    connection: &str,
    stream: &WebRTCStream,
    allow_turn: bool,
) -> ResultType<()> {
    let mut local = stream
        .take_local_ice_rx()
        .ok_or_else(|| anyhow!("Нет канала ICE"))?;
    tx.send(envelope(
        "ANSWER",
        peer,
        connection,
        sdp(stream.local_endpoint())?,
    ))
    .await?;
    let mut waiter = stream.clone();
    let connected = waiter.wait_connected(if allow_turn { TIMEOUT } else { 10_000 });
    tokio::pin!(connected);
    loop {
        tokio::select! {
            biased;
            result=&mut connected=>return result,
            Some(value)=local.recv()=>{
                let value:Value=serde_json::from_str(&value)?;
                if candidate(&value)?.is_some(){tx.send(candidate_message(peer,connection,value)).await?;}
            }
            value=remote.recv()=>{
                let value=value.ok_or_else(||anyhow!("Служба поиска отключилась во время установки канала"))?;
                if let Some(value)=candidate(&value)?{stream.add_remote_ice_candidate(&value).await?;}
            }
        }
    }
}

async fn accept(
    server: ServerPtr,
    tx: mpsc::Sender<Value>,
    remote: mpsc::Receiver<Value>,
    message: Value,
    permit: tokio::sync::OwnedSemaphorePermit,
) -> ResultType<()> {
    if !Config::get_option("whitelist").trim().is_empty() {
        bail!("IP-фильтр не поддерживается этим прямым транспортом; соединение отклонено");
    }
    let peer = message["src"]
        .as_str()
        .ok_or_else(|| anyhow!("Нет отправителя"))?;
    let connection = message["payload"]["connectionId"]
        .as_str()
        .ok_or_else(|| anyhow!("Нет номера соединения"))?;
    let allow_turn=message["payload"]["metadata"]["directOnly"]!=true;
    let pending = Pending::new(
        WebRTCStream::new_ryadom(&endpoint(&message["payload"]["sdp"])?, TIMEOUT,
            super::network_helper::ice_options(allow_turn)).await?,
    );
    timeout(
        Duration::from_millis(TIMEOUT),
        negotiate_answer(&tx, remote, peer, connection, &pending.stream, allow_turn),
    )
    .await??;
    check_transport(pending.stream.is_relayed().await, relay_allowed())?;
    if stopped() {
        bail!("Входящий доступ остановлен владельцем");
    }
    drop(permit);
    let stream = pending.finish();
    // WebRTC's local_addr is synthetic, not an authenticated source IP.
    let address = SocketAddr::from((Ipv4Addr::LOCALHOST, 0));
    let copy = stream.clone();
    let result = crate::create_tcp_connection(
        server,
        Stream::WebRTC(stream),
        address,
        true,
        ConnectionMeta::default(),
    )
    .await;
    copy.close().await;
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn forced_relay_requires_turn_on_the_connecting_pc() {
        assert!(require_relay_configuration(false).is_err());
        assert!(require_relay_configuration(true).is_ok());
    }

    #[test]
    fn forced_relay_rejects_direct_or_unknown_transport() {
        assert!(require_relay_transport(Some(false)).is_err());
        assert!(require_relay_transport(None).is_err());
        assert!(require_relay_transport(Some(true)).is_ok());
    }

    #[test]
    fn signaling_applies_explicit_relay_policy() {
        assert!(candidate_policy(
            &json!({"candidate":"candidate:1 1 udp 1 10.0.0.1 5000 typ host"}),
            false
        )
        .unwrap()
        .is_some());
        assert!(candidate_policy(
            &json!({"candidate":"candidate:1 1 udp 1 10.0.0.1 5000 typ relay"}),
            false
        )
        .is_err());
        let sdp = json!({"type":"offer","sdp":"v=0\r\na=candidate:1 1 udp 1 10.0.0.1 5000 typ relay\r\n"});
        assert!(validate_sdp_policy(&sdp, false).is_err());
        assert!(validate_sdp_policy(&sdp, true).is_ok());
        assert!(validate_sdp_policy(&json!({"type":"rollback","sdp":"v=0"}), true).is_err());
        assert!(candidate_policy(
            &json!({"candidate":"candidate:1 1 udp 1 10.0.0.1 5000 typ relay"}),
            true
        )
        .unwrap()
        .is_some());
    }
}
