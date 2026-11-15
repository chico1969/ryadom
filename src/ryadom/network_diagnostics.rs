use hbb_common::{
    anyhow::anyhow,
    bail,
    tokio::{net::UdpSocket, time::timeout},
    ResultType,
};
use serde_json::{json, Value};
use std::time::Duration;

const SERVERS: [&str; 4] = [
    "stun.cloudflare.com:3478",
    "stun.l.google.com:19302",
    "stun.antisip.com:3478",
    "stun.nextcloud.com:443",
];
async fn binding(server: &str) -> ResultType<()> {
    let address = hbb_common::tokio::net::lookup_host(server)
        .await?
        .find(|a| a.is_ipv4())
        .ok_or_else(|| anyhow!("Нет IPv4-адреса STUN"))?;
    let socket = UdpSocket::bind("0.0.0.0:0").await?;
    socket.connect(address).await?;
    let mut request = vec![0u8; 20];
    request[1] = 1;
    request[4..8].copy_from_slice(&0x2112a442u32.to_be_bytes());
    request[8..20].copy_from_slice(&hbb_common::sodiumoxide::randombytes::randombytes(12));
    socket.send(&request).await?;
    let mut response = [0u8; 1500];
    let count = socket.recv(&mut response).await?;
    if count < 20
        || response[0..2] != [1, 1]
        || response[4..20] != request[4..20]
        || 20 + u16::from_be_bytes([response[2], response[3]]) as usize > count
    {
        bail!("Некорректный ответ STUN");
    }
    Ok(())
}
pub async fn check() -> Value {
    let mut tasks = Vec::new();
    for server in SERVERS {
        tasks.push(hbb_common::tokio::spawn(async move {
            let ok = matches!(
                timeout(Duration::from_secs(3), binding(server)).await,
                Ok(Ok(()))
            );
            json!({"server":server,"ok":ok})
        }));
    }
    let mut stun = Vec::new();
    for task in tasks {
        if let Ok(value) = task.await {
            stun.push(value);
        }
    }
    #[cfg(windows)]
    let ipv6 = super::windows::ipv6_available();
    #[cfg(not(windows))]
    let ipv6 = false;
    json!({"stun":stun,"ipv6":ipv6})
}
