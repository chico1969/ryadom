#[cfg(feature = "flutter")]
use crate::client::Interface;
use hbb_common::{
    anyhow::anyhow,
    bail,
    config::Config,
    tokio::{self, net::UdpSocket, time::timeout},
    webrtc::{ryadom_udp_mux, RyadomIceOptions, RyadomMapped},
    ResultType,
};
use serde_json::{json, Value};
use std::{
    net::{Ipv4Addr, SocketAddr, SocketAddrV4},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::{Duration, Instant},
};

#[path = "network_diagnostics.rs"]
mod diagnostics;
#[path = "router.rs"]
mod router;
#[cfg(windows)]
#[path = "network_windows.rs"]
pub mod windows;

const OPTION: &str = "ryadom-p2p-helper";
const REQUESTED: u32 = 3600;
static STARTED: AtomicBool = AtomicBool::new(false);
static RECEIVING: AtomicBool = AtomicBool::new(false);
lazy_static::lazy_static! {
    static ref STATE:Mutex<State>=Mutex::new(State{mapped:None,status:json!({"message":"Помощник P2P выключен"})});
}
struct State {
    mapped: Option<Arc<RyadomMapped>>,
    status: Value,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Route {
    pub local: Ipv4Addr,
    pub gateway: Ipv4Addr,
}

pub fn enabled() -> bool {
    Config::get_option(OPTION) == "Y"
}
pub fn set_enabled(value: bool) {
    Config::set_option(
        OPTION.into(),
        if value { "Y".into() } else { String::new() },
    );
}
pub fn snapshot() -> Value {
    let mut state = STATE.lock().unwrap().status.clone();
    state["enabled"] = json!(enabled());
    state
}
fn report(value: Value) {
    let mut state = STATE.lock().unwrap();
    if value.get("message").is_some() {
        for key in [
            "detail",
            "protocol",
            "port",
            "leaseSeconds",
            "renewIn",
            "remaining",
            "deferred",
        ] {
            if let Some(fields) = state.status.as_object_mut() {
                fields.remove(key);
            }
        }
    }
    if let (Some(target), Some(fields)) = (state.status.as_object_mut(), value.as_object()) {
        for (key, value) in fields {
            target.insert(key.clone(), value.clone());
        }
    }
}
pub fn ice_options(allow_turn: bool) -> RyadomIceOptions {
    // A mapped IPv4 mux must not hide a usable global IPv6 path.
    #[cfg(windows)]
    let ipv6 = windows::ipv6_available();
    #[cfg(not(windows))]
    let ipv6 = false;
    RyadomIceOptions {
        allow_turn,
        mapped: if enabled() && !ipv6 {
            STATE.lock().unwrap().mapped.clone()
        } else {
            None
        },
    }
}
pub fn start() {
    if STARTED.swap(true, Ordering::SeqCst) {
        return;
    }
    if let Err(error) = hbb_common::webrtc::WebRTCStream::ryadom_spawn(run()) {
        STARTED.store(false, Ordering::SeqCst);
        report(json!({"message":"Помощник P2P не запущен","detail":error.to_string()}));
    }
}
pub fn receiving() {
    RECEIVING.store(true, Ordering::SeqCst);
    start();
}
fn renewal_delay(seconds: u32) -> Duration {
    Duration::from_secs((seconds as u64 / 3).max(1).min(1200))
}
fn route() -> ResultType<Route> {
    #[cfg(windows)]
    {
        windows::route()
    }
    #[cfg(not(windows))]
    {
        Err(anyhow!("Автонастройка роутера доступна в Windows"))
    }
}
fn has_outgoing() -> bool {
    #[cfg(feature = "flutter")]
    {
        super::resume::has_activity()
            || crate::flutter::sessions::get_sessions().iter().any(|s| {
                s.sender
                    .read()
                    .unwrap()
                    .as_ref()
                    .is_some_and(|tx| !tx.is_closed())
            })
    }
    #[cfg(not(feature = "flutter"))]
    {
        false
    }
}
struct Lease {
    route: Route,
    port: u16,
    remote: router::Mapping,
    mapped: Arc<RyadomMapped>,
    expires: Instant,
    renew: Instant,
    retry: u64,
}
impl Lease {
    async fn create(route: Route) -> ResultType<Self> {
        let socket = UdpSocket::bind(SocketAddrV4::new(route.local, 0)).await?;
        let port = socket.local_addr()?.port();
        let mut remote = router::Mapping::create(route, port, REQUESTED).await?;
        if remote.port != port {
            let _ = remote.delete().await;
            bail!("Роутер назначил другой порт. Повторите настройку.");
        }
        if !public_ipv4(remote.external) {
            let _ = remote.delete().await;
            bail!("Адрес роутера не публичный: возможен второй NAT или NAT провайдера");
        }
        let now = Instant::now();
        let mapped = Arc::new(RyadomMapped {
            external_ip: remote.external.to_string(),
            local_ip: route.local,
            mux: ryadom_udp_mux(socket),
            users: 0.into(),
        });
        Ok(Self {
            route,
            port,
            expires: now + Duration::from_secs(remote.lifetime as u64),
            renew: now + renewal_delay(remote.lifetime),
            remote,
            mapped,
            retry: 1,
        })
    }
    async fn refresh(&mut self) {
        if Instant::now() < self.renew {
            return;
        }
        match self.remote.renew(REQUESTED).await {
            Ok(())
                if self.remote.port == self.port
                    && self.remote.external.to_string() == self.mapped.external_ip =>
            {
                let now = Instant::now();
                self.expires = now + Duration::from_secs(self.remote.lifetime as u64);
                self.renew = now + renewal_delay(self.remote.lifetime);
                self.retry = 1;
            }
            Ok(()) => {
                self.expires = Instant::now();
                report(
                    json!({"message":"Роутер изменил адрес порта. Проверяем новый путь; TURN остаётся резервом."}),
                );
            }
            Err(e) => {
                self.renew = Instant::now() + Duration::from_secs(self.retry);
                self.retry = (self.retry * 2).min(15);
                report(
                    json!({"message":"Не удалось продлить порт. Повторяем попытку.","detail":e.to_string(),"remaining":self.expires.saturating_duration_since(Instant::now()).as_secs()}),
                );
            }
        }
    }
    async fn close(mut self) {
        let _ = self.remote.delete().await;
        let _ = self.mapped.mux.close().await;
    }
    fn in_use(&self) -> bool {
        self.mapped.users.load(Ordering::SeqCst) > 0
    }
}
async fn run() {
    let mut current: Option<Lease> = None;
    let mut retired: Vec<Lease> = Vec::new();
    let mut next_attempt = Instant::now();
    let mut last_route_check = Instant::now() - Duration::from_secs(30);
    loop {
        tokio::time::sleep(Duration::from_secs(1)).await;
        let desired = enabled()
            && ((RECEIVING.load(Ordering::SeqCst) && !super::signaling::stopped())
                || has_outgoing());
        if !desired {
            STATE.lock().unwrap().mapped = None;
            if current.as_ref().is_some_and(|l| l.in_use()) {
                report(
                    json!({"message":"Выключится после завершения текущих сеансов","deferred":true}),
                );
            } else if let Some(lease) = current.take() {
                lease.close().await;
                report(json!({"message":"Помощник P2P выключен"}));
            }
        }
        if let Some(lease) = &mut current {
            lease.refresh().await;
        }
        if current
            .as_ref()
            .is_some_and(|l| Instant::now() >= l.expires)
        {
            STATE.lock().unwrap().mapped = None;
            if let Some(old) = current.take() {
                retired.push(old);
            }
            next_attempt = Instant::now();
        }
        for old in &mut retired {
            old.refresh().await;
        }
        let mut i = 0;
        while i < retired.len() {
            if !retired[i].in_use() {
                retired.remove(i).close().await;
            } else {
                i += 1;
            }
        }
        if !desired {
            continue;
        }
        if current.is_some() && last_route_check.elapsed() >= Duration::from_secs(15) {
            last_route_check = Instant::now();
            if let Ok(new) = route() {
                if current.as_ref().is_some_and(|l| l.route != new) {
                    STATE.lock().unwrap().mapped = None;
                    if let Some(old) = current.take() {
                        retired.push(old);
                    }
                    next_attempt = Instant::now();
                }
            }
        }
        if current.is_none() && Instant::now() >= next_attempt {
            report(json!({"message":"Проверяем сеть и настраиваем временный UDP-порт…"}));
            report(diagnostics::check().await);
            let result = async {
                let route = route()?;
                let mut last = anyhow!("Нет доступного проброса порта");
                for _ in 0..3 {
                    match Lease::create(route).await {
                        Ok(l) => return Ok(l),
                        Err(e) => last = e,
                    }
                }
                Err(last)
            }
            .await;
            match result {
                Ok(lease) => {
                    report(
                        json!({"message":"Временный порт настроен. Для подтверждения P2P нужна проверка со вторым ПК.",
                        "protocol":lease.remote.name(),"port":lease.port,"leaseSeconds":lease.remote.lifetime,"renewIn":renewal_delay(lease.remote.lifetime).as_secs()}),
                    );
                    STATE.lock().unwrap().mapped = Some(lease.mapped.clone());
                    current = Some(lease);
                    #[cfg(feature = "flutter")]
                    for s in crate::flutter::sessions::get_sessions() {
                        s.send(crate::client::Data::RyadomP2P(false));
                    }
                }
                Err(e) => {
                    report(
                        json!({"message":"Автонастройка роутера недоступна. Обычный P2P и TURN продолжают работать.","detail":e.to_string()}),
                    );
                    next_attempt = Instant::now() + Duration::from_secs(60);
                }
            }
        }
    }
}
pub(super) fn public_ipv4(ip: Ipv4Addr) -> bool {
    let o = ip.octets();
    !ip.is_private()
        && !ip.is_loopback()
        && !ip.is_link_local()
        && !ip.is_unspecified()
        && !ip.is_multicast()
        && !(o[0] == 100 && (64..=127).contains(&o[1]))
        && o[0] < 240
        && o[0] != 0
}
pub(super) async fn exchange(route: Route, request: &[u8]) -> ResultType<Vec<u8>> {
    let socket = UdpSocket::bind(SocketAddrV4::new(route.local, 0)).await?;
    socket
        .connect(SocketAddrV4::new(route.gateway, 5351))
        .await?;
    let mut bytes = [0u8; 1100];
    for wait in [400, 800, 1200] {
        socket.send(request).await?;
        if let Ok(Ok(size)) = timeout(Duration::from_millis(wait), socket.recv(&mut bytes)).await {
            return Ok(bytes[..size].to_vec());
        }
    }
    bail!("Роутер не ответил на запрос UDP-проброса")
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn renewal_is_early_and_uses_the_actual_lifetime() {
        assert_eq!(renewal_delay(3600), Duration::from_secs(1200));
        assert_eq!(renewal_delay(600), Duration::from_secs(200));
        assert!(!public_ipv4(Ipv4Addr::new(100, 64, 1, 2)));
        assert!(public_ipv4(Ipv4Addr::new(8, 8, 8, 8)));
    }
}
