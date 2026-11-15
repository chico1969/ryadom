pub mod interaction;
pub mod resume;
#[cfg(feature = "flutter")]
pub mod p2p;
pub mod network_helper;
mod registration;
#[cfg(feature = "flutter")]
mod native_bridge;
mod short_code;
mod signaling;
pub use short_code::{active as active_code, verify as verify_code};
pub use registration::local as registration_state;

pub fn display_code() -> String {
    crate::ipc::get_config("ryadom-active-code")
        .ok()
        .flatten()
        .filter(|code| short_code::valid(code))
        .unwrap_or_else(active_code)
}

#[cfg(windows)]
pub fn cli(args: &[String]) -> ResultType<bool> {
    match args.first().map(String::as_str) {
        Some("--ryadom-firewall") => {
            network_helper::windows::add_firewall()?;
            Ok(true)
        }
        Some("--ryadom-code") => {
            println!("{}", display_code());
            Ok(true)
        }
        Some("--ryadom-owner-network") => {
            if args.len() != 2 {
                bail!("Нужен путь к локальному файлу TURN");
            }
            let file = std::path::Path::new(&args[1]);
            if std::fs::metadata(file)?.len() > 16 * 1024 {
                bail!("Файл TURN слишком велик");
            }
            let raw = std::fs::read_to_string(file)?;
            let protected = hbb_common::ryadom_network::protect_owner_config(&raw)?;
            Config::set_option(
                hbb_common::ryadom_network::OWNER_TURN_OPTION.into(),
                protected,
            );
            Config::set_option(
                hbb_common::ryadom_network::TURN_DISABLED_OPTION.into(),
                String::new(),
            );
            println!("Личная настройка TURN сохранена для текущего пользователя Windows.");
            Ok(true)
        }
        _ => Ok(false),
    }
}

#[cfg(feature = "flutter")]
pub use native_bridge::record_control;

use base::message_proto::{message, Message, PublicKey};
use hbb_common::{
    anyhow::anyhow,
    bail,
    config::Config,
    protobuf::Message as _,
    sodiumoxide::crypto::sign,
    tokio::time::{timeout, Duration},
    ResultType, Stream,
};
use sha2::{Digest, Sha256};

pub fn device_id(public_key: &[u8]) -> String {
    format!("ryadom-{}", hex::encode(&Sha256::digest(public_key)[..16]))
}

pub fn init_product() -> ResultType<()> {
    *hbb_common::config::APP_NAME.write().unwrap() = "Ryadom".into();
    hbb_common::sodiumoxide::init()
        .map_err(|_| anyhow!("Не удалось подготовить шифрование Рядом"))?;
    Ok(())
}

pub fn init() -> ResultType<()> {
    let (secret_key, public_key) = Config::get_key_pair();
    if public_key.len() != sign::PUBLICKEYBYTES || secret_key.len() != sign::SECRETKEYBYTES {
        bail!("Не удалось открыть ключ устройства Рядом. Проверьте доступность профиля Windows.");
    }
    Config::commit_ryadom_identity(&device_id(&public_key), (secret_key, public_key))?;
    Ok(())
}

pub async fn listen(server: crate::ServerPtr) {
    signaling::listen(server).await;
}

type Connected = (
    (
        Stream,
        bool,
        Option<Vec<u8>>,
        Option<crate::kcp_stream::KcpStream>,
        &'static str,
    ),
    (i32, String),
);

pub async fn connect(peer: &str, sid: u64, kind: hbb_common::rendezvous_proto::ConnType) -> ResultType<Connected> {
    let budget=resume::remaining_for(peer,sid,kind as i32).unwrap_or(Duration::from_secs(45)).min(Duration::from_secs(45));
    if budget.is_zero(){bail!("Разрешение на восстановление истекло");}
    timeout(budget,connect_inner(peer,sid,kind)).await.map_err(|_|anyhow!("Время подключения истекло"))?
}
async fn connect_inner(peer: &str, sid: u64, kind: hbb_common::rendezvous_proto::ConnType) -> ResultType<Connected> {
    network_helper::start();
    if !valid_id(peer) {
        bail!("Некорректный ID компьютера Рядом");
    }
    #[cfg(feature = "flutter")]
    if kind == hbb_common::rendezvous_proto::ConnType::DEFAULT_CONN {
        if let Some((stream, public_key)) = p2p::take(peer, sid) {
            return Ok(((stream, true, Some(public_key), None, "WebRTC P2P"), (0,String::new())));
        }
    }
    let (stream, public_key) = signaling::connect(peer).await?;
    let relayed = stream
        .is_relayed()
        .await
        .ok_or_else(|| anyhow!("Нет выбранного транспорта"))?;
    let mut stream = Stream::WebRTC(stream);
    stream.set_max_packet_length(64 * 1024);
    let result = authenticate_host(peer, &public_key, &mut stream).await;
    if let Err(err) = result {
        stream.close_webrtc();
        return Err(err);
    }
    stream.set_max_packet_length(usize::MAX);
    Ok((
        (
            stream,
            !relayed,
            Some(public_key),
            None,
            if relayed { "WebRTC TURN" } else { "WebRTC P2P" },
        ),
        (0, String::new()),
    ))
}

pub fn valid_id(id: &str) -> bool {
    id.strip_prefix("ryadom-").map_or(false, |s| {
        s.len() == 32
            && s.bytes()
                .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
    })
}

pub async fn refresh_transport<T: crate::ui_session_interface::InvokeUiSession>(
    stream: &Stream,
    ui: &T,
    last_direct: &mut bool,
    secure: bool,
) {
    let Stream::WebRTC(stream) = stream else {
        return;
    };
    if let Some(relayed) = stream.is_relayed().await {
        let direct = !relayed;
        if direct != *last_direct {
            *last_direct = direct;
            ui.set_connection_type(
                secure,
                direct,
                if relayed { "WebRTC TURN" } else { "WebRTC P2P" },
            );
        }
    }
}

async fn authenticate_host(peer: &str, pk: &[u8], stream: &mut Stream) -> ResultType<()> {
    if pk.len() != sign::PUBLICKEYBYTES || device_id(pk) != peer {
        bail!("Ключ компьютера не соответствует его ID");
    }
    let public_key = sign::PublicKey::from_slice(pk).ok_or_else(|| anyhow!("Некорректный ключ"))?;
    let incoming = timeout(Duration::from_secs(18), stream.next())
        .await?
        .ok_or_else(|| anyhow!("Компьютер закрыл соединение"))??;
    let msg = Message::parse_from_bytes(&incoming)?;
    let Some(message::Union::SignedId(signed)) = msg.union else {
        bail!("Нет подписанной личности компьютера");
    };
    let (id, box_pk, fingerprint, _) = crate::common::decode_id_pk_dtls(&signed.id, &public_key)?;
    let actual = stream
        .dtls_fingerprint(false)
        .await
        .ok_or_else(|| anyhow!("Нет отпечатка DTLS"))?;
    if id != peer || !crate::common::dtls_fingerprint_bound(&fingerprint, &actual) {
        bail!("Проверка компьютера не пройдена: ID или отпечаток канала изменён");
    }
    let (asymmetric_value, symmetric_value, key) = crate::common::create_symmetric_key_msg(box_pk);
    let mut msg = Message::new();
    msg.set_public_key(PublicKey {
        asymmetric_value: asymmetric_value.clone(),
        symmetric_value,
        kx_version: 0,
        ..Default::default()
    });
    stream.send(&msg).await?;
    stream.set_negotiated_key(
        key,
        true,
        &hbb_common::tcp::KxTranscript {
            initiator_pk: &asymmetric_value,
            responder_pk: &box_pk,
            advertised: 0,
            picked: 0,
        },
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn id_is_stable_and_binds_key() {
        let id = device_id(&[1; 32]);
        assert!(valid_id(&id));
        assert_ne!(id, device_id(&[2; 32]));
        assert!(!valid_id("123456789"));
        assert!(!valid_id(&id.to_uppercase()));
    }
}
