use super::{Connection, SessionKey};
use crate::ipc;
use hbb_common::tokio::sync::mpsc::UnboundedSender;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::{HashMap, HashSet},
    sync::Mutex,
    time::{Duration, Instant},
};

const GRACE: Duration = Duration::from_secs(300);
struct Grant {
    key: SessionKey,
    name: String,
    permissions: u16,
    active: HashSet<i32>,
    expires: Option<Instant>,
    last_conn: i32,
    controlled: bool,
}
#[derive(Default)]
struct Registry {
    grants: HashMap<[u8; 32], Grant>,
    conns: HashMap<i32, ([u8; 32], UnboundedSender<ipc::Data>)>,
}
lazy_static::lazy_static! { static ref REGISTRY: Mutex<Registry> = Mutex::new(Registry::default()); }
fn digest(token: &[u8]) -> [u8; 32] {
    Sha256::digest(token).into()
}
fn permissions(c: &Connection) -> u16 {
    [
        c.keyboard,
        c.clipboard,
        c.audio,
        c.file,
        c.restart,
        c.recording,
        c.block_input,
        c.privacy_mode,
    ]
    .iter()
    .enumerate()
    .fold(0, |bits, (i, enabled)| bits | ((*enabled as u16) << i))
}
fn restrict(c: &mut Connection, bits: u16) {
    c.keyboard &= bits & 1 != 0;
    c.clipboard &= bits & 2 != 0;
    c.audio &= bits & 4 != 0;
    c.file &= bits & 8 != 0;
    c.restart &= bits & 16 != 0;
    c.recording &= bits & 32 != 0;
    c.block_input &= bits & 64 != 0;
    c.privacy_mode &= bits & 128 != 0;
}
impl Registry {
    fn validate(&self, token: &[u8], key: &SessionKey, now: Instant) -> Option<u16> {
        if token.len() != 32 {
            return None;
        }
        self.grants
            .get(&digest(token))
            .filter(|g| g.key == *key && g.expires.map_or(true, |t| now < t))
            .map(|g| g.permissions)
    }
    fn revoke(&mut self, key: &[u8; 32]) -> Vec<UnboundedSender<ipc::Data>> {
        self.grants.remove(key);
        self.conns
            .values()
            .filter(|(k, _)| k == key)
            .map(|(_, tx)| tx.clone())
            .collect()
    }
}
pub fn restored(c: &mut Connection) -> bool {
    if c.lr.ryadom_session_version != 1 || c.lr.ryadom_resume_token.is_empty() {
        return false;
    }
    let bits = REGISTRY.lock().unwrap().validate(
        &c.lr.ryadom_resume_token,
        &c.session_key(),
        Instant::now(),
    );
    if let Some(bits) = bits {
        restrict(c, bits);
        c.require_2fa = None;
        c.set_conn_audit_primary_auth(super::ConnAuditPrimaryAuth::Resumed);
        return true;
    }
    false
}
pub fn issue(c: &Connection) -> Vec<u8> {
    if c.lr.ryadom_session_version != 1 || c.lr.union.is_some() {
        return Vec::new();
    }
    let now = Instant::now();
    let mut registry = REGISTRY.lock().unwrap();
    registry
        .grants
        .retain(|_, g| g.expires.map_or(true, |t| now < t));
    let token = if c.conn_audit_primary_auth == super::ConnAuditPrimaryAuth::Resumed {
        c.lr.ryadom_resume_token.to_vec()
    } else {
        hbb_common::sodiumoxide::randombytes::randombytes(32)
    };
    let hash = digest(&token);
    let grant = registry.grants.entry(hash).or_insert_with(|| Grant {
        key: c.session_key(),
        name: c.lr.my_name.chars().take(100).collect(),
        permissions: permissions(c),
        active: HashSet::new(),
        expires: None,
        last_conn: c.inner.id,
        controlled: false,
    });
    grant.active.insert(c.inner.id);
    grant.expires = None;
    grant.last_conn = c.inner.id;
    registry
        .conns
        .insert(c.inner.id, (hash, c.tx_from_authed.clone()));
    token
}
pub fn update(c: &Connection) {
    let mut registry = REGISTRY.lock().unwrap();
    let hash = registry.conns.get(&c.inner.id).map(|(k, _)| *k);
    if let Some(g) = hash.and_then(|k| registry.grants.get_mut(&k)) {
        g.permissions = permissions(c);
    }
}
pub fn revoked(id: i32) -> bool {
    let registry = REGISTRY.lock().unwrap();
    registry
        .conns
        .get(&id)
        .is_some_and(|(key, _)| !registry.grants.contains_key(key))
}
pub fn revoke_connection(c: &Connection, all: bool) {
    let senders = {
        let mut registry = REGISTRY.lock().unwrap();
        let key = registry.conns.get(&c.inner.id).map(|(k, _)| *k);
        key.filter(|key| {
            all || registry
                .grants
                .get(key)
                .map_or(true, |g| g.active.len() <= 1)
        })
        .map(|key| registry.revoke(&key))
        .unwrap_or_default()
    };
    for tx in senders {
        let _ = tx.send(ipc::Data::Close);
    }
}
pub fn detached(c: &Connection) -> bool {
    let controlled = super::ryadom_floor::controls(c.inner.id);
    let mut registry = REGISTRY.lock().unwrap();
    let Some((key, _)) = registry.conns.remove(&c.inner.id) else {
        return false;
    };
    let Some(grant) = registry.grants.get_mut(&key) else {
        return false;
    };
    grant.active.remove(&c.inner.id);
    if grant.active.is_empty() {
        grant.controlled = controlled;
        let expiry = Instant::now() + GRACE;
        grant.expires = Some(expiry);
        let lock = c.lock_after_session_end && c.keyboard;
        hbb_common::tokio::spawn(async move {
            hbb_common::tokio::time::sleep(GRACE).await;
            let expired = {
                let mut registry = REGISTRY.lock().unwrap();
                if registry
                    .grants
                    .get(&key)
                    .is_some_and(|g| g.expires == Some(expiry))
                {
                    registry.grants.remove(&key);
                    true
                } else {
                    false
                }
            };
            if expired && lock && super::Connection::alive_conns().is_empty() {
                super::lock_screen().await;
            }
        });
    }
    true
}
pub fn restore_control(c: &Connection) -> bool {
    c.conn_audit_primary_auth == super::ConnAuditPrimaryAuth::Resumed
        && REGISTRY
            .lock()
            .unwrap()
            .grants
            .get(&digest(&c.lr.ryadom_resume_token))
            .is_some_and(|g| g.controlled)
}
pub fn snapshot() -> Value {
    let registry = REGISTRY.lock().unwrap();
    let now = Instant::now();
    let sessions:Vec<_>=registry.grants.iter().filter(|(_,g)|g.expires.map_or(true,|t|now<t))
        .map(|(id,g)|json!({"id":hex::encode(id),"connection":g.last_conn,"name":g.name,"recovering":g.expires.is_some(),
            "remaining":g.expires.and_then(|t|t.checked_duration_since(now)).map(|d|d.as_secs()).unwrap_or(0)})).collect();
    json!({"sessions":sessions})
}
pub fn revoke(id: &str) {
    let Ok(bytes) = hex::decode(id) else {
        return;
    };
    let Ok(key) = <[u8; 32]>::try_from(bytes.as_slice()) else {
        return;
    };
    let senders = REGISTRY.lock().unwrap().revoke(&key);
    for tx in senders {
        let _ = tx.send(ipc::Data::Close);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn resume_requires_the_secret_same_session_unexpired_and_not_revoked() {
        let mut r = Registry::default();
        let now = Instant::now();
        let token = [4; 32];
        let key = SessionKey {
            peer_id: "peer".into(),
            name: "name".into(),
            session_id: 42,
        };
        r.grants.insert(
            digest(&token),
            Grant {
                key: key.clone(),
                name: "name".into(),
                permissions: 3,
                active: HashSet::new(),
                expires: Some(now + GRACE),
                last_conn: 1,
                controlled: false,
            },
        );
        assert_eq!(r.validate(&token, &key, now), Some(3));
        assert_eq!(r.validate(&[5; 32], &key, now), None);
        let mut other = key.clone();
        other.session_id = 43;
        assert_eq!(r.validate(&token, &other, now), None);
        assert_eq!(r.validate(&token, &key, now + GRACE), None);
        r.revoke(&digest(&token));
        assert_eq!(r.validate(&token, &key, now), None);
    }
}
