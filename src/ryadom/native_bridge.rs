use crate::client::{Data, Interface};
use base::message_proto::{Message, RyadomControl};
use hbb_common::rendezvous_proto::ConnType;
use serde_json::{json, Value};
use std::{collections::HashMap, sync::Mutex};

lazy_static::lazy_static! { static ref STATES: Mutex<HashMap<(String,i32),Value>> = Mutex::new(HashMap::new()); }

pub fn record_control(peer: String, kind: ConnType, state: RyadomControl) {
    if state.action == "switch-request" {
        if state.version == 1 && kind == ConnType::DEFAULT_CONN {
            if let Some(session) = crate::flutter::sessions::get_session_by_peer_id(peer, kind) {
                session.ui_handler.push_event("ryadom_switch_request", &[] as &[(&str, &str)], &[]);
            }
        }
        return;
    }
    let participants: Vec<_> = state
        .participants
        .iter()
        .map(|p| json!({"id":p.id,"name":p.name}))
        .collect();
    STATES.lock().unwrap().insert((peer,kind as i32),json!({"you":state.you,"holder":state.holder,"participants":participants,"reason":state.reason}));
}

fn request(bytes: &[u8]) -> hbb_common::ResultType<Value> {
    let input: Value = serde_json::from_slice(bytes)?;
    if input["action"] == "registration-state" {
        return Ok(super::registration::snapshot());
    }
    if input["action"] == "signal-url" {
        return Ok(json!({"url":super::signaling::base_url()?}));
    }
    if input["action"] == "resume-host-state" {
        return Ok(serde_json::from_str(&crate::ipc::get_config("ryadom-resume-state")?.unwrap_or_else(||"{}".into()))?);
    }
    if input["action"] == "helper-state" {
        let mut state:Value=serde_json::from_str(&crate::ipc::get_config("ryadom-network-state")?.unwrap_or_else(||"{}".into()))?;
        let local=super::network_helper::snapshot();
        if local["deferred"]==true {state["message"]=local["message"].clone();state["deferred"]=json!(true);}
        return Ok(state);
    }
    if input["action"] == "helper-set" {
        let enabled=input["enabled"]==true;
        crate::ipc::set_config("ryadom-network-helper",if enabled{"Y".into()}else{String::new()})?;
        // Installed service and desktop client can be different processes/users. Each owns
        // its actual sockets and mapping; no port is advertised for another process's socket.
        super::network_helper::set_enabled(enabled);
        super::network_helper::start();
        #[cfg(windows)]
        if enabled { return Ok(json!({"message":super::network_helper::windows::firewall()?})); }
        return Ok(json!({"message":"Настройка помощника сохранена"}));
    }
    if input["action"] == "resume-host-revoke" {
        crate::ipc::set_config("ryadom-resume-revoke",input["id"].as_str().unwrap_or_default().into())?;
        return Ok(json!({"ok":true}));
    }
    if input["action"] == "verify-code" {
        let text = |name: &str| input[name].as_str().unwrap_or_default();
        return Ok(
            json!({"id":super::verify_code(&input["reply"],text("code"),text("nonce"),text("client"))?}),
        );
    }
    #[cfg(windows)]
    match input["action"].as_str() {
        Some("autostart-get") => return Ok(crate::platform::windows::ryadom_autostart::status()),
        Some("autostart-set") => {
            let enabled=input["enabled"].as_bool().ok_or_else(||hbb_common::anyhow::anyhow!("Нужно выбрать состояние автозапуска"))?;
            return crate::platform::windows::ryadom_autostart::set_enabled(enabled);
        }
        Some("network-get") => {
            let servers = hbb_common::ryadom_network::turn_servers();
            return Ok(
                json!({"configured":!servers.is_empty(),"sharedTestBuild":hbb_common::ryadom_network::bundled_test_build(),"urls":servers.iter().flat_map(|server|server.urls.iter()).collect::<Vec<_>>()}),
            );
        }
        Some("network-set") => {
            let raw = serde_json::to_string(&input["servers"])?;
            let protected = hbb_common::ryadom_network::protect_owner_config(&raw)?;
            hbb_common::config::Config::set_option(
                hbb_common::ryadom_network::OWNER_TURN_OPTION.into(),
                protected,
            );
            hbb_common::config::Config::set_option(
                hbb_common::ryadom_network::TURN_DISABLED_OPTION.into(),
                if input["servers"]
                    .as_array()
                    .map_or(false, |servers| servers.is_empty())
                {
                    "Y".into()
                } else {
                    String::new()
                },
            );
            return Ok(json!({"ok":true}));
        }
        _ => {}
    }
    let id: uuid::Uuid = input["session"]
        .as_str()
        .ok_or_else(|| hbb_common::anyhow::anyhow!("Missing session"))?
        .parse()?;
    let session = crate::flutter::sessions::get_session_by_session_id(&id)
        .ok_or_else(|| hbb_common::anyhow::anyhow!("Session closed"))?;
    let kind = session.lc.read().unwrap().conn_type;
    let key = (session.get_id(), kind as i32);
    let action = input["action"].as_str().unwrap_or_default();
    if action == "p2p-state" {
        let sid=session.lc.read().unwrap().session_id;
        return Ok(super::p2p::snapshot(&key.0,sid));
    }
    if action == "p2p-check" || action == "p2p-switch" {
        session.send(Data::RyadomP2P(action=="p2p-switch"));
        return Ok(json!({"ok":true}));
    }
    if action == "resume-state" {
        let lc=session.lc.read().unwrap();
        return Ok(super::resume::status(&key.0,lc.session_id,kind as i32));
    }
    if action == "local-state" {
        return Ok(STATES
            .lock()
            .unwrap()
            .get(&key)
            .cloned()
            .unwrap_or_else(|| json!({})));
    }
    if !matches!(action, "claim" | "transfer" | "release" | "query") {
        hbb_common::bail!("Unknown control action");
    }
    let mut msg = Message::new();
    msg.set_ryadom_control(RyadomControl {
        version: 1,
        action: action.into(),
        target: input["target"].as_i64().unwrap_or_default() as i32,
        ..Default::default()
    });
    let guard = session.sender.read().unwrap();
    let sender = guard
        .as_ref()
        .ok_or_else(|| hbb_common::anyhow::anyhow!("Session disconnected"))?;
    sender
        .send(Data::Message(msg))
        .map_err(|_| hbb_common::anyhow::anyhow!("Session disconnected"))?;
    Ok(json!({"ok":true}))
}

// A small, versioned C ABI keeps Ryadom-only controls out of the generated upstream bridge.
#[no_mangle]
pub unsafe extern "C" fn ryadom_request_v1(
    input: *const u8,
    length: u32,
    output: *mut u8,
    capacity: u32,
) -> i32 {
    if input.is_null() || output.is_null() || length > 65536 || capacity > 65536 {
        return -1;
    }
    let input = std::slice::from_raw_parts(input, length as usize);
    let value = match request(input) {
        Ok(value) => value,
        Err(error) => json!({"error":error.to_string()}),
    };
    let Ok(bytes) = serde_json::to_vec(&value) else {
        return -1;
    };
    if bytes.len() > capacity as usize {
        return -2;
    }
    std::ptr::copy_nonoverlapping(bytes.as_ptr(), output, bytes.len());
    bytes.len() as i32
}
