use serde_json::{json, Value};
use std::{
    collections::HashMap,
    sync::Mutex,
    time::{Duration, Instant},
};

pub const GRACE: Duration = Duration::from_secs(300);
lazy_static::lazy_static! {
    static ref CLIENTS: Mutex<HashMap<(String,u64), ClientGrant>> = Mutex::new(HashMap::new());
}
struct ClientGrant {
    token: Vec<u8>,
    lost: HashMap<i32, Instant>,
    monitor: Option<i32>,
}

pub fn connected(peer: &str, session: u64, token: &[u8], kind: i32) {
    let mut clients = CLIENTS.lock().unwrap();
    let key = (peer.into(), session);
    if let Some(grant) = clients.get_mut(&key) {
        if token.len() == 32 {
            grant.token = token.into();
        }
        grant.lost.remove(&kind);
        return;
    }
    if token.len() == 32 {
        clients.insert(
            key,
            ClientGrant {
                token: token.into(),
                lost: HashMap::new(),
                monitor: None,
            },
        );
    }
}
pub fn monitor(peer: &str, session: u64) -> Option<i32> {
    CLIENTS
        .lock()
        .unwrap()
        .get(&(peer.into(), session))
        .and_then(|g| g.monitor)
}
pub fn set_monitor(peer: &str, session: u64, monitor: i32) {
    if let Some(g) = CLIENTS.lock().unwrap().get_mut(&(peer.into(), session)) {
        g.monitor = Some(monitor);
    }
}
pub fn token(peer: &str, session: u64) -> Vec<u8> {
    token_for(peer, session, 0)
}
pub fn token_for(peer: &str, session: u64, kind: i32) -> Vec<u8> {
    let clients = CLIENTS.lock().unwrap();
    clients
        .get(&(peer.into(), session))
        .filter(|g| g.lost.get(&kind).map_or(true, |t| t.elapsed() < GRACE))
        .map(|g| g.token.clone())
        .unwrap_or_default()
}
pub fn remaining(peer: &str, session: u64) -> Option<Duration> {
    remaining_for(peer, session, 0)
}
pub fn remaining_for(peer: &str, session: u64, kind: i32) -> Option<Duration> {
    CLIENTS
        .lock()
        .unwrap()
        .get(&(peer.into(), session))
        .and_then(|g| g.lost.get(&kind).copied())
        .map(|t| GRACE.saturating_sub(t.elapsed()))
}
pub fn forget(peer: &str, session: u64) {
    CLIENTS.lock().unwrap().remove(&(peer.into(), session));
}
pub fn has_activity() -> bool {
    CLIENTS
        .lock()
        .unwrap()
        .values()
        .any(|g| g.lost.get(&0).map_or(true, |t| t.elapsed() < GRACE))
}
pub fn clear_channel(peer: &str, session: u64, kind: i32) {
    if let Some(g) = CLIENTS.lock().unwrap().get_mut(&(peer.into(), session)) {
        g.lost.remove(&kind);
    }
}
pub fn lost(peer: &str, session: u64, kind: i32) -> Option<u64> {
    let mut clients = CLIENTS.lock().unwrap();
    let grant = clients.get_mut(&(peer.into(), session))?;
    let since = *grant.lost.entry(kind).or_insert_with(Instant::now);
    GRACE.checked_sub(since.elapsed()).map(|d| d.as_secs() + 1)
}
pub fn status(peer: &str, session: u64, kind: i32) -> Value {
    let clients = CLIENTS.lock().unwrap();
    match clients.get(&(peer.into(), session)) {
        Some(g) => {
            json!({"supported":true,"recovering":g.lost.contains_key(&kind),"remaining":g.lost.get(&kind).and_then(|t|GRACE.checked_sub(t.elapsed())).map(|d|d.as_secs()).unwrap_or(0)})
        }
        None => json!({"supported":false,"recovering":false,"remaining":0}),
    }
}

pub fn login_reply<T: crate::ui_session_interface::InvokeUiSession>(
    session: &crate::ui_session_interface::Session<T>,
    reply: &base::message_proto::LoginResponse,
) -> bool {
    use crate::client::Interface;
    let sid = session.lc.read().unwrap().session_id;
    let peer = session.get_id();
    if reply.error().starts_with("RYADOM_RESUME_DENIED") {
        forget(&peer, sid);
        session.ui_handler.msgbox(
            "error",
            "Доступ завершён",
            "Разрешение на восстановление истекло или отозвано. Подключитесь заново.",
            "",
            false,
        );
        return false;
    }
    if reply.has_peer_info() {
        if let Some(code) = super::interaction::peer_short_code(&reply.peer_info().platform_additions) {
            session.lc.write().unwrap().set_option("ryadom-last-code".into(), code);
        }
        let kind = session.lc.read().unwrap().conn_type as i32;
        connected(&peer, sid, &reply.ryadom_resume_token, kind);
        #[cfg(feature = "flutter")]
        if session.lc.read().unwrap().conn_type
            == hbb_common::rendezvous_proto::ConnType::DEFAULT_CONN
        {
            super::p2p::connected(&peer, sid);
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn retries_do_not_extend_permission_and_expired_tokens_are_not_sent() {
        connected("resume-test", 1, &[7; 32], 0);
        assert_eq!(token("resume-test", 1), vec![7; 32]);
        assert_eq!(lost("resume-test", 1, 0), Some(300));
        CLIENTS
            .lock()
            .unwrap()
            .get_mut(&("resume-test".into(), 1))
            .unwrap()
            .lost
            .insert(0, Instant::now() - GRACE);
        assert!(lost("resume-test", 1, 0).is_none());
        assert!(token("resume-test", 1).is_empty());
        assert_eq!(token_for("resume-test", 1, 1), vec![7; 32]);
        forget("resume-test", 1);
    }
}
