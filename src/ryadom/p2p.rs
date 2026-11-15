//! Direct-path probes and authenticated make-before-break handoff. Never replays input.
use crate::{
    client::Interface,
    flutter::{sessions, FlutterSession},
};
use base::message_proto::{message, Message};
use hbb_common::{
    anyhow::anyhow,
    bail,
    protobuf::Message as _,
    rendezvous_proto::ConnType,
    tokio::{self, time::timeout},
    ResultType, Stream,
};
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    sync::Mutex,
    time::{Duration, Instant},
};

type Key = (String, u64);
#[derive(Default)]
struct State {
    checking: bool,
    available: Option<Instant>,
    generation: u64,
    message: String,
    prepared: Option<Prepared>,
}
struct Prepared {
    stream: Option<Stream>,
    public_key: Vec<u8>,
    created: Instant,
}
impl Drop for Prepared {
    fn drop(&mut self) {
        if let Some(s) = &self.stream {
            s.close_webrtc();
        }
    }
}
lazy_static::lazy_static! {static ref STATES:Mutex<HashMap<Key,State>>=Mutex::new(HashMap::new());}

fn session(peer: &str) -> Option<FlutterSession> {
    sessions::get_session_by_peer_id(peer.into(), ConnType::DEFAULT_CONN)
}
pub fn forget(peer: &str, sid: u64) {
    STATES.lock().unwrap().remove(&(peer.into(), sid));
}
pub fn snapshot(peer: &str, sid: u64) -> Value {
    if super::resume::token(peer, sid).len() != 32 {
        return json!({"available":false,"checking":false,"message":"Для восстановления и перехода на P2P обновите Рядом на обоих ПК и подключитесь заново."});
    }
    let states = STATES.lock().unwrap();
    let key = (peer.into(), sid);
    let direct = session(peer).is_some_and(|s| s.lc.read().unwrap().direct == Some(true));
    match states.get(&key) {
        Some(s) => {
            json!({"checking":s.checking,"available":s.available.is_some_and(|t|t.elapsed()<Duration::from_secs(60)),
            "message":if direct{"Сеанс уже идёт по P2P"}else{&s.message}})
        }
        None => {
            json!({"checking":false,"available":false,"message":"Прямой путь пока не проверен"})
        }
    }
}
pub fn connected(peer: &str, sid: u64) {
    let key = (peer.into(), sid);
    let generation = {
        let mut states = STATES.lock().unwrap();
        let s = states.entry(key.clone()).or_default();
        s.generation = s.generation.wrapping_add(1);
        s.checking = false;
        s.available = None;
        s.message = "Проверим прямой путь через 15 и 45 секунд".into();
        s.generation
    };
    tokio::spawn(async move {
        for delay in [15, 30] {
            tokio::time::sleep(Duration::from_secs(delay)).await;
            if !STATES
                .lock()
                .unwrap()
                .get(&key)
                .is_some_and(|s| s.generation == generation)
            {
                return;
            }
            request(&key.0, false);
        }
        let mut route = network_signature();
        loop {
            tokio::time::sleep(Duration::from_secs(15)).await;
            if super::resume::token(&key.0, key.1).len() != 32
                || !STATES
                    .lock()
                    .unwrap()
                    .get(&key)
                    .is_some_and(|s| s.generation == generation)
            {
                return;
            }
            let next = network_signature();
            if next != route {
                route = next;
                request(&key.0, false);
            }
        }
    });
}
fn network_signature() -> String {
    #[cfg(windows)]
    {
        format!(
            "{:?}/{}",
            super::network_helper::windows::route().ok(),
            super::network_helper::windows::ipv6_available()
        )
    }
    #[cfg(not(windows))]
    {
        String::new()
    }
}
pub fn request(peer: &str, switch: bool) {
    let Some(session) = session(peer) else {
        return;
    };
    let (sid, direct) = {
        let lc = session.lc.read().unwrap();
        (lc.session_id, lc.direct)
    };
    if direct != Some(false) || super::resume::token(peer, sid).len() != 32 {
        return;
    }
    let key = (peer.into(), sid);
    {
        let mut states = STATES.lock().unwrap();
        let s = states.entry(key.clone()).or_default();
        if s.checking {
            return;
        }
        s.checking = true;
        s.message = if switch {
            "Подготавливаем разрешённый прямой канал…"
        } else {
            "Проверяем P2P, сохраняя TURN…"
        }
        .into();
    }
    tokio::spawn(async move {
        let result = timeout(Duration::from_secs(25), prepare(&session, switch))
            .await
            .map_err(|_| anyhow!("Проверка прямого пути заняла слишком много времени"))
            .and_then(|r| r);
        let mut states = STATES.lock().unwrap();
        let Some(state) = states.get_mut(&key) else {
            return;
        };
        state.checking = false;
        match result {
            Ok(candidate) => {
                if super::resume::token(&key.0, key.1).len() != 32 {
                    return;
                }
                state.available = Some(Instant::now());
                state.message = "P2P работает: прямой канал со вторым ПК проверен".into();
                if switch {
                    state.prepared = Some(candidate);
                    session
                        .ui_handler
                        .push_event("ryadom_p2p_ready", &[] as &[(&str, &str)], &[]);
                } else {
                    session.ui_handler.push_event(
                        "ryadom_p2p_available",
                        &[] as &[(&str, &str)],
                        &[],
                    );
                }
            }
            Err(_) => {
                state.available = None;
                state.message = "Прямой путь недоступен. Работающий TURN сохранён.".into();
            }
        }
    });
}
async fn prepare(session: &FlutterSession, authorize: bool) -> ResultType<Prepared> {
    let peer = session.get_id();
    let (rtc, pk) = super::signaling::connect_direct(&peer).await?;
    let mut candidate = Prepared {
        stream: Some(Stream::WebRTC(rtc)),
        public_key: pk,
        created: Instant::now(),
    };
    let stream = candidate
        .stream
        .as_mut()
        .ok_or_else(|| anyhow!("Нет прямого канала"))?;
    stream.set_max_packet_length(64 * 1024);
    super::authenticate_host(&peer, &candidate.public_key, stream).await?;
    let hash = stream
        .next_timeout(5000)
        .await
        .ok_or_else(|| anyhow!("Нет ответа ядра"))??;
    let message = Message::parse_from_bytes(&hash)?;
    let Some(message::Union::Hash(hash)) = message.union else {
        bail!("Нет возможностей сеанса");
    };
    if hash.ryadom_session_version != 1 {
        bail!("Обновите приложение на удалённом ПК");
    }
    if !authorize {
        return Ok(candidate);
    }
    let login = {
        let lc = session.lc.read().unwrap();
        let mut login = lc.ryadom_resume_login();
        let Some(message::Union::LoginRequest(lr)) = &mut login.union else {
            bail!("Нет запроса доступа");
        };
        lr.ryadom_resume_token = super::resume::token(&peer, lc.session_id).into();
        if lr.ryadom_resume_token.len() != 32 {
            bail!("Сеанс уже завершён");
        }
        login
    };
    stream.send(&login).await?;
    let mut initial = Vec::new();
    let mut size = 0;
    loop {
        let bytes = stream
            .next_timeout(5000)
            .await
            .ok_or_else(|| anyhow!("Нет подтверждения доступа"))??;
        size += bytes.len();
        if initial.len() >= 32 || size > 1024 * 1024 {
            bail!("Слишком много данных до подтверждения доступа");
        }
        let message = Message::parse_from_bytes(&bytes)?;
        let ready = match message.union {
            Some(message::Union::LoginResponse(reply)) => {
                if !reply.has_peer_info() {
                    bail!("Разрешение отозвано или истекло");
                }
                true
            }
            Some(message::Union::VideoFrame(_)) => bail!("Видео получено до разрешения доступа"),
            _ => false,
        };
        initial.push(bytes);
        if ready {
            break;
        }
    }
    if let Stream::WebRTC(rtc) = stream {
        rtc.ryadom_prepend(initial).await?;
    }
    stream.set_max_packet_length(usize::MAX);
    Ok(candidate)
}
pub fn take(peer: &str, sid: u64) -> Option<(Stream, Vec<u8>)> {
    let mut candidate = STATES
        .lock()
        .unwrap()
        .get_mut(&(peer.into(), sid))?
        .prepared
        .take()?;
    if candidate.created.elapsed() > Duration::from_secs(30)
        || super::resume::token(peer, sid).len() != 32
    {
        return None;
    }
    Some((
        candidate.stream.take()?,
        std::mem::take(&mut candidate.public_key),
    ))
}
