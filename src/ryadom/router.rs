use super::{exchange, Route};
use hbb_common::{
    anyhow::anyhow,
    bail,
    tokio::{net::UdpSocket, time::timeout},
    ResultType,
};
use std::{
    net::{Ipv4Addr, SocketAddrV4},
    time::{Duration, Instant},
};

pub struct Mapping {
    pub external: Ipv4Addr,
    pub port: u16,
    pub lifetime: u32,
    route: Route,
    internal: u16,
    kind: Kind,
}
enum Kind {
    Pcp([u8; 12]),
    NatPmp,
    Upnp(Gateway),
}
struct Gateway {
    url: reqwest::Url,
    service: String,
    description: String,
}
fn n16(b: &[u8], i: usize) -> u16 {
    u16::from_be_bytes([b[i], b[i + 1]])
}
fn n32(b: &[u8], i: usize) -> u32 {
    u32::from_be_bytes([b[i], b[i + 1], b[i + 2], b[i + 3]])
}
fn pcp_request(route: Route, port: u16, external: u16, lifetime: u32, nonce: [u8; 12]) -> Vec<u8> {
    let mut b = vec![0; 60];
    b[0] = 2;
    b[1] = 1;
    b[4..8].copy_from_slice(&lifetime.to_be_bytes());
    b[18..20].fill(255);
    b[20..24].copy_from_slice(&route.local.octets());
    b[24..36].copy_from_slice(&nonce);
    b[36] = 17;
    b[40..42].copy_from_slice(&port.to_be_bytes());
    b[42..44].copy_from_slice(&external.to_be_bytes());
    b
}
fn parse_pcp(b: &[u8], port: u16, nonce: [u8; 12]) -> ResultType<(Ipv4Addr, u16, u32)> {
    if b.len() < 60
        || b[0] != 2
        || b[1] != 129
        || b[3] != 0
        || b[24..36] != nonce
        || b[36] != 17
        || n16(b, 40) != port
    {
        bail!("PCP: отказ или неподходящий ответ роутера");
    }
    if b[44..54] != [0; 10] || b[54..56] != [255; 2] {
        bail!("PCP: роутер не выдал внешний IPv4");
    }
    Ok((
        Ipv4Addr::new(b[56], b[57], b[58], b[59]),
        n16(b, 42),
        n32(b, 4),
    ))
}
fn nat_request(port: u16, external: u16, lifetime: u32) -> Vec<u8> {
    let mut b = vec![0, 1, 0, 0];
    b.extend(port.to_be_bytes());
    b.extend(external.to_be_bytes());
    b.extend(lifetime.to_be_bytes());
    b
}
fn parse_nat(b: &[u8], port: u16) -> ResultType<(u16, u32)> {
    if b.len() < 16 || b[0] != 0 || b[1] != 129 || n16(b, 2) != 0 || n16(b, 8) != port {
        bail!("NAT-PMP: отказ или неподходящий ответ роутера");
    }
    Ok((n16(b, 10), n32(b, 12)))
}
async fn nat_ip(route: Route) -> ResultType<Ipv4Addr> {
    let b = exchange(route, &[0, 0]).await?;
    if b.len() < 12 || b[0] != 0 || b[1] != 128 || n16(&b, 2) != 0 {
        bail!("NAT-PMP: внешний адрес недоступен");
    }
    Ok(Ipv4Addr::new(b[8], b[9], b[10], b[11]))
}
impl Mapping {
    pub fn name(&self) -> &'static str {
        match self.kind {
            Kind::Pcp(_) => "PCP",
            Kind::NatPmp => "NAT-PMP",
            Kind::Upnp(_) => "UPnP IGD",
        }
    }
    pub async fn create(route: Route, port: u16, lifetime: u32) -> ResultType<Self> {
        let mut nonce = [0; 12];
        nonce.copy_from_slice(&hbb_common::sodiumoxide::randombytes::randombytes(12));
        if let Ok(b) = exchange(route, &pcp_request(route, port, port, lifetime, nonce)).await {
            if let Ok((external, mapped, life)) = parse_pcp(&b, port, nonce) {
                if life > 0 {
                    return Ok(Self {
                        external,
                        port: mapped,
                        lifetime: life,
                        route,
                        internal: port,
                        kind: Kind::Pcp(nonce),
                    });
                }
            }
        }
        if let Ok(external) = nat_ip(route).await {
            if let Ok(b) = exchange(route, &nat_request(port, port, lifetime)).await {
                if let Ok((mapped, life)) = parse_nat(&b, port) {
                    if life > 0 {
                        return Ok(Self {
                            external,
                            port: mapped,
                            lifetime: life,
                            route,
                            internal: port,
                            kind: Kind::NatPmp,
                        });
                    }
                }
            }
        }
        let gateway = Gateway::discover(route).await?;
        let external = gateway.external().await?;
        gateway.available(port).await?;
        gateway.add(route.local, port, lifetime).await?;
        let actual = gateway.owned_lifetime(route.local, port).await;
        match actual {
            Ok(life) if life > 0 => Ok(Self {
                external,
                port,
                lifetime: life,
                route,
                internal: port,
                kind: Kind::Upnp(gateway),
            }),
            _ => {
                let _ = gateway.remove(route.local, port).await;
                bail!("UPnP: временная аренда не подтверждена, постоянное правило не используется");
            }
        }
    }
    pub async fn renew(&mut self, lifetime: u32) -> ResultType<()> {
        match &self.kind {
            Kind::Pcp(nonce) => {
                let b = exchange(
                    self.route,
                    &pcp_request(self.route, self.internal, self.port, lifetime, *nonce),
                )
                .await?;
                let (ip, p, life) = parse_pcp(&b, self.internal, *nonce)?;
                self.external = ip;
                self.port = p;
                self.lifetime = life;
            }
            Kind::NatPmp => {
                let b =
                    exchange(self.route, &nat_request(self.internal, self.port, lifetime)).await?;
                let (p, life) = parse_nat(&b, self.internal)?;
                self.port = p;
                self.lifetime = life;
                self.external = nat_ip(self.route).await?;
            }
            Kind::Upnp(g) => {
                g.owned_lifetime(self.route.local, self.port).await?;
                g.add(self.route.local, self.port, lifetime).await?;
                self.lifetime = g.owned_lifetime(self.route.local, self.port).await?;
                self.external = g.external().await?;
            }
        }
        if lifetime > 0 && self.lifetime == 0 {
            bail!("Роутер не продлил временную аренду");
        }
        Ok(())
    }
    pub async fn delete(&mut self) -> ResultType<()> {
        match &self.kind {
            Kind::Pcp(nonce) => {
                let _ = exchange(
                    self.route,
                    &pcp_request(self.route, self.internal, self.port, 0, *nonce),
                )
                .await?;
            }
            Kind::NatPmp => {
                let _ = exchange(self.route, &nat_request(self.internal, self.port, 0)).await?;
            }
            Kind::Upnp(g) => g.remove(self.route.local, self.port).await?,
        }
        Ok(())
    }
}
fn text(xml: &str, name: &str) -> ResultType<String> {
    let doc = roxmltree::Document::parse(xml)?;
    doc.descendants()
        .find(|n| n.is_element() && n.tag_name().name() == name)
        .and_then(|n| n.text())
        .map(str::to_owned)
        .ok_or_else(|| anyhow!("UPnP: нет поля {name}"))
}
fn checked_url(url: reqwest::Url, route: Route) -> ResultType<reqwest::Url> {
    if url.scheme() != "http"
        || url.host_str() != Some(route.gateway.to_string().as_str())
        || !url.username().is_empty()
        || url.password().is_some()
    {
        bail!("UPnP: адрес службы не принадлежит локальному шлюзу");
    }
    Ok(url)
}
async fn body(mut response: reqwest::Response) -> ResultType<String> {
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await? {
        if bytes.len() + chunk.len() > 256 * 1024 {
            bail!("UPnP: слишком большой ответ");
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(String::from_utf8(bytes)?)
}
fn http() -> ResultType<reqwest::Client> {
    Ok(reqwest::Client::builder()
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(3))
        .build()?)
}
impl Gateway {
    async fn discover(route: Route) -> ResultType<Self> {
        let socket = UdpSocket::bind(SocketAddrV4::new(route.local, 0)).await?;
        socket.set_multicast_ttl_v4(2)?;
        socket.send_to(b"M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: upnp:rootdevice\r\n\r\n", "239.255.255.250:1900").await?;
        let deadline = Instant::now() + Duration::from_secs(3);
        let mut bytes = [0; 8192];
        while Instant::now() < deadline {
            let wait = deadline.saturating_duration_since(Instant::now());
            let (size, from) = timeout(wait, socket.recv_from(&mut bytes)).await??;
            if from.ip() != route.gateway {
                continue;
            }
            let reply = std::str::from_utf8(&bytes[..size])?;
            let location = reply
                .lines()
                .filter_map(|l| l.split_once(':'))
                .find(|(key, _)| key.eq_ignore_ascii_case("location"))
                .map(|(_, v)| v.trim())
                .ok_or_else(|| anyhow!("UPnP: адрес описания не найден"))?;
            let url = checked_url(reqwest::Url::parse(location)?, route)?;
            let xml = body(http()?.get(url.clone()).send().await?.error_for_status()?).await?;
            let doc = roxmltree::Document::parse(&xml)?;
            for service in doc
                .descendants()
                .filter(|n| n.is_element() && n.tag_name().name() == "service")
            {
                let value = |name| {
                    service
                        .children()
                        .find(|n| n.is_element() && n.tag_name().name() == name)
                        .and_then(|n| n.text())
                };
                let Some(kind) = value("serviceType") else {
                    continue;
                };
                if ![
                    "urn:schemas-upnp-org:service:WANIPConnection:1",
                    "urn:schemas-upnp-org:service:WANIPConnection:2",
                    "urn:schemas-upnp-org:service:WANPPPConnection:1",
                ]
                .contains(&kind)
                {
                    continue;
                }
                let control = value("controlURL").ok_or_else(|| anyhow!("UPnP: нет controlURL"))?;
                let endpoint = checked_url(url.join(control)?, route)?;
                return Ok(Self {
                    url: endpoint,
                    service: kind.into(),
                    description: format!(
                        "Ryadom-{}",
                        hex::encode(hbb_common::sodiumoxide::randombytes::randombytes(8))
                    ),
                });
            }
        }
        bail!("Роутер не предоставляет PCP, NAT-PMP или UPnP IGD")
    }
    async fn soap(&self, action: &str, args: &str) -> ResultType<String> {
        let xml=format!("<?xml version=\"1.0\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body><u:{action} xmlns:u=\"{}\">{args}</u:{action}></s:Body></s:Envelope>",self.service);
        let response = http()?
            .post(self.url.clone())
            .header("Content-Type", "text/xml; charset=utf-8")
            .header("SOAPAction", format!("\"{}#{action}\"", self.service))
            .body(xml)
            .send()
            .await?;
        let status = response.status();
        let xml = body(response).await?;
        if let Ok(code) = text(&xml, "errorCode") {
            bail!("UPnP: ошибка {code}");
        }
        if !status.is_success() {
            bail!("UPnP: HTTP {status}");
        }
        Ok(xml)
    }
    async fn external(&self) -> ResultType<Ipv4Addr> {
        Ok(text(
            &self.soap("GetExternalIPAddress", "").await?,
            "NewExternalIPAddress",
        )?
        .parse()?)
    }
    fn key(port: u16) -> String {
        format!("<NewRemoteHost></NewRemoteHost><NewExternalPort>{port}</NewExternalPort><NewProtocol>UDP</NewProtocol>")
    }
    async fn available(&self, port: u16) -> ResultType<()> {
        match self
            .soap("GetSpecificPortMappingEntry", &Self::key(port))
            .await
        {
            Err(e) if e.to_string() == "UPnP: ошибка 714" => Ok(()),
            Ok(_) => Err(anyhow!("UPnP: порт уже занят другим правилом")),
            Err(e) => Err(e),
        }
    }
    async fn owned_lifetime(&self, local: Ipv4Addr, port: u16) -> ResultType<u32> {
        let xml = self
            .soap("GetSpecificPortMappingEntry", &Self::key(port))
            .await?;
        if text(&xml, "NewInternalClient")? != local.to_string()
            || text(&xml, "NewInternalPort")? != port.to_string()
            || text(&xml, "NewPortMappingDescription")? != self.description
        {
            bail!("UPnP: правило принадлежит другой программе");
        }
        Ok(text(&xml, "NewLeaseDuration")?.parse()?)
    }
    async fn add(&self, local: Ipv4Addr, port: u16, lifetime: u32) -> ResultType<()> {
        let args=format!("{}<NewInternalPort>{port}</NewInternalPort><NewInternalClient>{local}</NewInternalClient><NewEnabled>1</NewEnabled><NewPortMappingDescription>{}</NewPortMappingDescription><NewLeaseDuration>{lifetime}</NewLeaseDuration>",Self::key(port),self.description);
        self.soap("AddPortMapping", &args).await?;
        Ok(())
    }
    async fn remove(&self, local: Ipv4Addr, port: u16) -> ResultType<()> {
        self.owned_lifetime(local, port).await?;
        self.soap("DeletePortMapping", &Self::key(port)).await?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn router_responses_are_bound_to_nonce_port_and_shorter_lifetime() {
        let mut reply = vec![0; 60];
        reply[0] = 2;
        reply[1] = 129;
        reply[4..8].copy_from_slice(&600u32.to_be_bytes());
        reply[24..36].fill(9);
        reply[36] = 17;
        reply[40..42].copy_from_slice(&12345u16.to_be_bytes());
        reply[42..44].copy_from_slice(&12345u16.to_be_bytes());
        reply[54..56].fill(255);
        reply[56..60].copy_from_slice(&[8, 8, 8, 8]);
        assert_eq!(parse_pcp(&reply, 12345, [9; 12]).unwrap().2, 600);
        assert!(parse_pcp(&reply, 12346, [9; 12]).is_err());
        assert!(parse_pcp(&reply, 12345, [8; 12]).is_err());
        assert!(parse_nat(&[0; 12], 12345).is_err());
        let route = Route {
            local: Ipv4Addr::new(192, 168, 1, 2),
            gateway: Ipv4Addr::new(192, 168, 1, 1),
        };
        assert!(checked_url(
            reqwest::Url::parse("http://192.168.1.1:5000/control").unwrap(),
            route
        )
        .is_ok());
        assert!(checked_url(
            reqwest::Url::parse("http://8.8.8.8/control").unwrap(),
            route
        )
        .is_err());
    }
}
