use super::{ConnInner, Connection, MessageInput, SessionKey, Subscriber};
use base::message_proto::{
    login_request, message, misc, Message, Misc, RyadomControl, RyadomParticipant,
};
use hbb_common::tokio::{
    sync::oneshot,
    time::{timeout, Duration},
};
use std::{collections::BTreeMap, sync::Mutex};

#[derive(Default)]
struct Floor {
    holder: Option<i32>,
    changing: bool,
    peers: BTreeMap<i32, Participant>,
}

struct Participant {
    name: String,
    inner: ConnInner,
    key: SessionKey,
    remote: bool,
    parent: Option<i32>,
}

#[derive(Debug, PartialEq)]
enum RequestResult {
    Updated,
    Handoff(Option<i32>),
    Denied,
}
lazy_static::lazy_static! { static ref FLOOR: Mutex<Floor> = Mutex::new(Floor::default()); }

impl Floor {
    fn parent_for(&self, key: &SessionKey) -> Option<i32> {
        if key.session_id == 0 {
            return None;
        }
        self.peers
            .iter()
            .find_map(|(&id, peer)| (peer.remote && peer.key == *key).then_some(id))
    }

    fn auxiliary_allowed(&self, key: &SessionKey) -> bool {
        !self.changing
            && (self
                .parent_for(key)
                .is_some_and(|parent| self.controls(parent))
                || (self.peers.is_empty() && self.holder.is_none()))
    }

    fn controls(&self, id: i32) -> bool {
        self.holder == Some(id)
            || self.holder.is_some_and(|holder| {
                self.peers
                    .get(&id)
                    .is_some_and(|peer| peer.parent == Some(holder)
                        || ((peer.remote || peer.parent.is_some()) && peer.key.session_id != 0
                            && self.peers.get(&holder).is_some_and(|owner| owner.remote && owner.key == peer.key)))
            })
    }

    fn close_auxiliaries(&mut self, parent: i32) {
        for peer in self
            .peers
            .values_mut()
            .filter(|peer| peer.parent == Some(parent))
        {
            let mut misc = Misc::new();
            misc.set_close_reason(
                "Основной сеанс завершён или управление передано другому участнику".into(),
            );
            let mut msg = Message::new();
            msg.set_misc(misc);
            peer.inner.send(msg.into());
        }
    }

    fn request(&mut self, id: i32, action: &str, target: i32) -> RequestResult {
        if !self.peers.contains_key(&id) {
            return RequestResult::Denied;
        }
        if self.peers[&id].parent.is_some() && action != "query" {
            return RequestResult::Denied;
        }
        let id = if self.controls(id) { self.holder.unwrap_or(id) } else { id };
        match action {
            "query" => RequestResult::Updated,
            "claim" if self.holder.is_none() && !self.changing => {
                self.holder = Some(id);
                RequestResult::Updated
            }
            "release" if self.holder == Some(id) && !self.changing => {
                self.holder = None;
                self.changing = true;
                RequestResult::Handoff(None)
            }
            "transfer"
                if self.holder == Some(id)
                    && !self.changing
                    && self
                        .peers
                        .get(&target)
                        .is_some_and(|peer| peer.parent.is_none()) =>
            {
                self.holder = None;
                self.changing = true;
                RequestResult::Handoff(Some(target))
            }
            _ => RequestResult::Denied,
        }
    }
    fn publish(&mut self, reason: &str) {
        let participants: Vec<_> = self
            .peers
            .iter()
            .filter(|(_, peer)| peer.parent.is_none())
            .map(|(&id, peer)| RyadomParticipant {
                id,
                name: peer.name.clone(),
                ..Default::default()
            })
            .collect();
        let owner_key = self.holder.and_then(|id| self.peers.get(&id)).map(|peer| peer.key.clone());
        for (&you, peer) in &mut self.peers {
            let mut msg = Message::new();
            msg.set_ryadom_control(RyadomControl {
                version: 1,
                action: "state".into(),
                holder: if peer.remote && owner_key.as_ref()
                    .is_some_and(|key| key.session_id != 0 && *key == peer.key) {
                    you
                } else { self.holder.unwrap_or_default() },
                you,
                participants: participants.clone(),
                reason: reason.into(),
                ..Default::default()
            });
            peer.inner.send(msg.into());
        }
    }
}

const CONTROL_REQUIRED: &str =
    "Сначала получите управление в основном окне Рядом, затем откройте файлы или терминал";

fn admitted(floor: &Floor, connection: &Connection) -> bool {
    match &connection.lr.union {
        None => true,
        Some(login_request::Union::FileTransfer(_)) | Some(login_request::Union::Terminal(_)) => {
            floor.auxiliary_allowed(&connection.session_key())
        }
        _ => false,
    }
}

pub async fn admit(connection: &mut Connection) -> bool {
    let allowed = admitted(&FLOOR.lock().unwrap(), connection);
    if !allowed {
        connection.send_login_error(CONTROL_REQUIRED).await;
    }
    allowed
}

fn register(connection: &Connection) -> bool {
    let mut floor = FLOOR.lock().unwrap();
    if !admitted(&floor, connection) {
        return false;
    }
    let inner = &connection.inner;
    let key = connection.session_key();
    let remote = connection.lr.union.is_none();
    let auxiliary = matches!(
        &connection.lr.union,
        Some(login_request::Union::FileTransfer(_)) | Some(login_request::Union::Terminal(_))
    );
    // The existing private connection token shares this nonzero random session ID
    // only with the file/terminal windows opened by that desktop session.
    let parent = if auxiliary {
        floor.parent_for(&key)
    } else {
        None
    };
    if (floor.peers.is_empty() || (floor.holder.is_none() && super::ryadom_resume::restore_control(connection))) && !floor.changing {
        floor.holder = Some(inner.id());
    }
    floor.peers.insert(
        inner.id(),
        Participant {
            name: connection.lr.my_name.chars().take(100).collect(),
            inner: inner.clone(),
            key,
            remote,
            parent,
        },
    );
    floor.publish("");
    true
}

pub async fn join(connection: &mut Connection) -> bool {
    if register(connection) {
        return true;
    }
    connection.authorized = false;
    connection.send_login_error(CONTROL_REQUIRED).await;
    false
}

pub fn controls(id: i32) -> bool {
    FLOOR.lock().unwrap().controls(id)
}

pub fn click_disconnected(connection: &Connection) -> bool {
    connection.authorized
        && matches!(connection.conn_audit_primary_auth, super::ConnAuditPrimaryAuth::Click)
        && connection.lr.ryadom_session_version == 0
        && connection.stream.webrtc_disconnected()
}

pub async fn request_switch(connection: &mut Connection) -> bool {
    if connection.from_switch { return false; }
    if connection.authorized && connection.lr.union.is_none() {
        let mut msg = Message::new();
        msg.set_ryadom_control(RyadomControl {
            version: 1, action: "switch-request".into(), ..Default::default()
        });
        connection.send(msg).await;
    }
    true
}

pub async fn prepare_terminal(connection: &mut Connection) -> bool {
    let error = if !Connection::permission(
        base::config::keys::OPTION_ENABLE_TERMINAL,
        &connection.control_permissions,
    ) {
        Some("Владелец не разрешил терминал")
    } else {
        connection.fill_terminal_user_token("", "")
    };
    if let Some(error) = error {
        let mut response = base::message_proto::TerminalResponse::new();
        response.set_error(base::message_proto::TerminalError {
            message: error.into(),
            ..Default::default()
        });
        let mut msg = Message::new();
        msg.set_terminal_response(response);
        connection.inner.send(msg.into());
        return false;
    }
    connection.init_terminal_service().await;
    true
}

async fn release_input(connection: &Connection) -> bool {
    if connection.lr.union.is_some() {
        return true;
    }
    let (tx, rx) = oneshot::channel();
    if connection
        .tx_input
        .send(MessageInput::RyadomRelease(tx))
        .is_err()
    {
        return false;
    }
    matches!(timeout(Duration::from_secs(5), rx).await, Ok(Ok(())))
}

pub async fn leave(connection: &Connection) {
    let id = connection.inner.id();
    let controlled = {
        let mut floor = FLOOR.lock().unwrap();
        if !floor.peers.contains_key(&id) {
            return;
        }
        floor.peers.remove(&id);
        floor.close_auxiliaries(id);
        if floor.holder == Some(id) {
            floor.holder = None;
            floor.changing = true;
            true
        } else {
            false
        }
    };
    if controlled {
        let released = release_input(connection).await;
        let mut floor = FLOOR.lock().unwrap();
        floor.changing = !released;
        if !released {
            floor.publish("Не удалось освободить ввод. Перезапустите Рядом на удалённом ПК.");
            return;
        }
        let key = connection.session_key();
        floor.holder = floor.peers.iter().find_map(|(&id, peer)|
            (peer.remote && key.session_id != 0 && peer.key == key).then_some(id));
    }
    FLOOR
        .lock()
        .unwrap()
        .publish("Управляющий отключился. Управление можно запросить явно.");
}

pub async fn filter(connection: &mut Connection, msg: &Message) -> bool {
    let id = connection.inner.id();
    if let Some(message::Union::RyadomControl(command)) = &msg.union {
        if command.version != 1 {
            return true;
        }
        let target = {
            let mut floor = FLOOR.lock().unwrap();
            match floor.request(id, &command.action, command.target) {
                RequestResult::Updated => {
                    floor.publish("");
                    return true;
                }
                RequestResult::Handoff(target) => {
                    floor.close_auxiliaries(id);
                    floor.publish("Передача управления");
                    target
                }
                RequestResult::Denied => {
                    let reason = if floor.changing {
                        "Управление временно недоступно. Дождитесь передачи или перезапустите Рядом."
                    } else {
                        "Передать управление может только текущий управляющий"
                    };
                    floor.publish(reason);
                    return true;
                }
            }
        };
        let released = release_input(connection).await;
        let mut floor = FLOOR.lock().unwrap();
        if released {
            floor.holder = target.filter(|t| floor.peers.contains_key(t));
        }
        floor.changing = !released;
        floor.publish(if released {
            ""
        } else {
            "Не удалось освободить ввод. Перезапустите Рядом на удалённом ПК."
        });
        return true;
    }
    let controls = FLOOR.lock().unwrap().controls(id);
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    if let Some(message::Union::MouseEvent(event)) = &msg.union {
        if !controls || !connection.peer_keyboard_enabled() {
            if connection.lr.union.is_none() {
                crate::ryadom::interaction::show_pointer(id, &connection.lr.my_name, event);
            }
            return true;
        }
        crate::whiteboard::clear_ryadom_pointer(id);
    }
    if controls {
        return false;
    }
    // Observers can exchange chat, latency and frame acknowledgements, and choose a display.
    // All other messages fail closed, including future protocol extensions.
    blocked_for_observer(msg)
}

fn blocked_for_observer(msg: &Message) -> bool {
    match &msg.union {
        Some(message::Union::TestDelay(_)) | Some(message::Union::ScreenshotRequest(_)) => false,
        Some(message::Union::Misc(m)) => !matches!(
            &m.union,
            Some(misc::Union::ChatMessage(_))
                | Some(misc::Union::VideoReceived(_))
                | Some(misc::Union::RefreshVideo(_))
                | Some(misc::Union::RefreshVideoDisplay(_))
                | Some(misc::Union::CaptureDisplays(_))
                | Some(misc::Union::SwitchDisplay(_))
                | Some(misc::Union::RequestCursorData(_))
                | Some(misc::Union::CloseReason(_))
        ),
        _ => true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use base::message_proto::*;
    fn floor() -> Floor {
        let mut floor = Floor::default();
        for id in [1, 2] {
            floor.peers.insert(
                id,
                Participant {
                    name: id.to_string(),
                    inner: ConnInner {
                        id,
                        ..Default::default()
                    },
                    key: SessionKey {
                        peer_id: id.to_string(),
                        name: id.to_string(),
                        session_id: id as u64,
                    },
                    remote: true,
                    parent: None,
                },
            );
        }
        floor.holder = Some(1);
        floor
    }
    #[test]
    fn monitor_channels_share_control_only_inside_the_authenticated_session() {
        let mut floor = floor();
        floor.peers.insert(3, Participant {
            name: "Второй монитор".into(), inner: ConnInner::new(3, None, None),
            key: floor.peers[&1].key.clone(), remote: true, parent: None,
        });
        assert!(floor.controls(3));
        assert!(!floor.controls(2));
        floor.holder = Some(3);
        assert!(floor.controls(1));
        assert!(floor.auxiliary_allowed(&floor.peers[&1].key));
        assert_eq!(floor.request(3, "transfer", 2), RequestResult::Handoff(Some(2)));
        floor.changing = false;
        floor.holder = Some(2);
        assert!(!floor.controls(1));
        assert!(!floor.controls(3));
    }
    #[test]
    fn only_current_controller_can_transfer_and_barrier_blocks_claims() {
        let mut floor = floor();
        assert_eq!(floor.request(2, "transfer", 2), RequestResult::Denied);
        assert_eq!(floor.request(2, "claim", 0), RequestResult::Denied);
        assert_eq!(
            floor.request(1, "transfer", 2),
            RequestResult::Handoff(Some(2))
        );
        assert_eq!(floor.holder, None);
        assert_eq!(floor.request(2, "claim", 0), RequestResult::Denied);
        floor.changing = false;
        assert_eq!(floor.request(2, "claim", 0), RequestResult::Updated);
        assert_eq!(floor.holder, Some(2));
        assert_eq!(floor.request(3, "claim", 0), RequestResult::Denied);
    }
    #[test]
    fn observer_cannot_mutate_files_terminal_clipboard_or_power() {
        for union in [
            message::Union::MouseEvent(MouseEvent::new()),
            message::Union::KeyEvent(KeyEvent::new()),
            message::Union::FileAction(FileAction::new()),
            message::Union::FileResponse(FileResponse::new()),
            message::Union::TerminalAction(TerminalAction::new()),
            message::Union::Clipboard(Clipboard::new()),
            message::Union::OsLogin(OSLogin::new()),
        ] {
            let mut msg = Message::new();
            msg.union = Some(union);
            assert!(blocked_for_observer(&msg));
        }
        let mut misc = Misc::new();
        misc.set_restart_remote_device(true);
        let mut msg = Message::new();
        msg.set_misc(misc);
        assert!(blocked_for_observer(&msg));
        let mut misc = Misc::new();
        misc.set_chat_message(ChatMessage {
            text: "Привет".into(),
            ..Default::default()
        });
        msg.set_misc(misc);
        assert!(!blocked_for_observer(&msg));
    }

    #[test]
    fn auxiliary_channels_follow_their_desktop_controller_only() {
        let mut floor = floor();
        assert!(floor.auxiliary_allowed(&floor.peers[&1].key));
        assert!(!floor.auxiliary_allowed(&floor.peers[&2].key));
        for (id, parent) in [(3, 1), (4, 2)] {
            floor.peers.insert(
                id,
                Participant {
                    name: id.to_string(),
                    inner: ConnInner::new(id, None, None),
                    key: SessionKey {
                        peer_id: parent.to_string(),
                        name: parent.to_string(),
                        session_id: parent as u64,
                    },
                    remote: false,
                    parent: Some(parent),
                },
            );
        }
        assert!(floor.controls(3));
        assert!(!floor.controls(4));
        floor.holder = Some(2);
        assert!(!floor.auxiliary_allowed(&floor.peers[&1].key));
        assert!(floor.auxiliary_allowed(&floor.peers[&2].key));
        assert!(!floor.controls(3));
        assert!(floor.controls(4));
        floor.holder = None;
        assert!(!floor.controls(3));
        assert!(!floor.controls(4));
    }
}
