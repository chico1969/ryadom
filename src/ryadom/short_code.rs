use super::{device_id, signaling, valid_id};
use hbb_common::futures_util::SinkExt;
use hbb_common::{
    anyhow::anyhow,
    bail,
    config::Config,
    rand::Rng,
    sodiumoxide::crypto::sign,
    tokio::{
        self,
        time::{Duration, Instant},
    },
    ResultType,
};
use serde_json::{json, Value};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    RwLock,
};
use tokio_tungstenite::tungstenite::Message as WsMessage;

static ONLINE: AtomicBool = AtomicBool::new(false);
lazy_static::lazy_static! { static ref ACTIVE: RwLock<String> = RwLock::new(String::new()); }

pub struct Online;
impl Online {
    pub fn enter() -> Self {
        ONLINE.store(true, Ordering::Release);
        Self
    }
}
impl Drop for Online {
    fn drop(&mut self) {
        ONLINE.store(false, Ordering::Release);
    }
}
pub struct Worker(tokio::task::JoinHandle<()>);
impl Drop for Worker {
    fn drop(&mut self) {
        self.0.abort();
    }
}
pub fn start() -> Worker {
    Worker(tokio::spawn(run()))
}
pub fn active() -> String {
    if ONLINE.load(Ordering::Acquire) {ACTIVE.read().unwrap().clone()} else {String::new()}
}
pub fn valid(code: &str) -> bool {
    code.len() == 9 && code.bytes().all(|byte| byte.is_ascii_digit()) && !code.starts_with('0')
}
fn random_code() -> String {
    hbb_common::rand::thread_rng()
        .gen_range(100_000_000u32..1_000_000_000)
        .to_string()
}
fn transcript(code: &str, nonce: &str, client: &str, host: &str) -> ResultType<String> {
    if !valid(code)
        || nonce.len() != 32
        || !nonce.bytes().all(|byte| byte.is_ascii_hexdigit())
        || client.is_empty()
        || client.len() > 80
        || !client
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"-_".contains(&byte))
        || !valid_id(host)
    {
        bail!("Некорректное разрешение короткого ID");
    }
    Ok(format!("RyadomCodeV1|{code}|{nonce}|{client}|{host}"))
}
fn answer(code: &str, message: &Value) -> ResultType<Value> {
    let client = message["src"]
        .as_str()
        .ok_or_else(|| anyhow!("Нет отправителя"))?;
    let nonce = message["payload"]["metadata"]["nonce"]
        .as_str()
        .ok_or_else(|| anyhow!("Нет запроса"))?;
    let connection = message["payload"]["connectionId"]
        .as_str()
        .ok_or_else(|| anyhow!("Нет соединения"))?;
    if connection.len() > 80
        || message["type"] != "OFFER"
        || message["payload"]["metadata"]["ryadomLookup"] != 1
    {
        bail!("Не запрос ID");
    }
    let (sk, pk) = Config::get_key_pair();
    let host = device_id(&pk);
    let text = transcript(code, nonce, client, &host)?;
    let secret = sign::SecretKey::from_slice(&sk).ok_or_else(|| anyhow!("Нет ключа устройства"))?;
    let signature = sign::sign_detached(text.as_bytes(), &secret);
    Ok(
        json!({"type":"ANSWER","dst":client,"payload":{"type":"data","connectionId":connection,
        "label":"bootstrap","serialization":"raw","reliable":true,"sdp":{"type":"answer","sdp":"v=0\r\n"},
        "metadata":{"ryadomLookup":1,"code":code,"nonce":nonce,"id":host,"publicKey":hex::encode(pk),"signature":hex::encode(signature.as_ref())}}}),
    )
}
pub fn verify(value: &Value, code: &str, nonce: &str, client: &str) -> ResultType<String> {
    let host = value["id"]
        .as_str()
        .ok_or_else(|| anyhow!("Нет ID устройства"))?;
    if value["ryadomLookup"] != 1 || value["code"] != code || value["nonce"] != nonce {
        bail!("Ответ не соответствует запросу ID");
    }
    let pk = hex::decode(value["publicKey"].as_str().unwrap_or_default())?;
    if device_id(&pk) != host {
        bail!("ID не соответствует ключу устройства");
    }
    let public = sign::PublicKey::from_slice(&pk).ok_or_else(|| anyhow!("Некорректный ключ"))?;
    let signature = hex::decode(value["signature"].as_str().unwrap_or_default())?;
    let signature =
        sign::Signature::from_bytes(&signature).map_err(|_| anyhow!("Некорректная подпись ID"))?;
    if !sign::verify_detached(
        &signature,
        transcript(code, nonce, client, host)?.as_bytes(),
        &public,
    ) {
        bail!("Неверная подпись короткого ID");
    }
    Ok(host.to_owned())
}
struct Lease;
impl Drop for Lease {
    fn drop(&mut self) {
        ACTIVE.write().unwrap().clear();
    }
}
async fn serve(code: &str) -> ResultType<()> {
    let mut socket = signaling::open(&format!("ryadom-code-{code}")).await?;
    let saved_code = code.to_owned();
    tokio::task::spawn_blocking(move || Config::set_option("ryadom-short-code".into(), saved_code))
        .await?;
    *ACTIVE.write().unwrap() = code.into();
    let _lease = Lease;
    let mut heartbeat = tokio::time::interval(Duration::from_secs(5));
    let mut status = tokio::time::interval(Duration::from_secs(1));
    let mut last_lookup = Instant::now() - Duration::from_secs(1);
    loop {
        tokio::select! {
            _=heartbeat.tick()=>socket.send(WsMessage::Text(json!({"type":"HEARTBEAT"}).to_string().into())).await?,
            _=status.tick()=>if !ONLINE.load(Ordering::Acquire)||signaling::stopped(){socket.close(None).await?;return Ok(());},
            message=signaling::next(&mut socket)=>{
                let message=message?;
                if last_lookup.elapsed()<Duration::from_millis(100) {continue;}
                if let Ok(reply)=answer(code,&message) {
                    last_lookup=Instant::now();
                    socket.send(WsMessage::Text(reply.to_string().into())).await?;
                }
            }
        }
    }
}
async fn run() {
    let mut code = Config::get_option("ryadom-short-code");
    if !valid(&code) {
        code = random_code();
    }
    let mut backoff = 1;
    loop {
        if !ONLINE.load(Ordering::Acquire) || signaling::stopped() {
            tokio::time::sleep(Duration::from_secs(1)).await;
            continue;
        }
        match serve(&code).await {
            Ok(()) => backoff = 1,
            Err(error) => {
                if error.to_string().contains("ID-TAKEN") {
                    code = random_code();
                    backoff = 1;
                } else {
                    backoff = (backoff * 2).min(60);
                    super::registration::failed(&error.to_string(), backoff);
                    hbb_common::throttled_log!(
                        Duration::from_secs(60),
                        warn,
                        "Рядом: короткий ID пока недоступен: {}",
                        error
                    );
                }
            }
        }
        tokio::time::sleep(Duration::from_secs(backoff)).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn short_code_reply_is_bound_to_device_nonce_and_requester() {
        hbb_common::sodiumoxide::init().unwrap();
        let (pk, sk) = sign::gen_keypair();
        let host = device_id(&pk.0);
        let code = "123456789";
        let nonce = "0".repeat(32);
        let client = "ryadom-client-test";
        let signature = sign::sign_detached(
            transcript(code, &nonce, client, &host).unwrap().as_bytes(),
            &sk,
        );
        let value = json!({"ryadomLookup":1,"code":code,"nonce":nonce,"id":host,"publicKey":hex::encode(pk.0),"signature":hex::encode(signature.as_ref())});
        assert_eq!(verify(&value, code, &nonce, client).unwrap(), host);
        assert!(verify(&value, "123456788", &nonce, client).is_err());
        assert!(verify(&value, code, &"1".repeat(32), client).is_err());
        assert!(verify(&value, code, &nonce, "another-client").is_err());
        assert!(!valid("012345678"));
    }
}
