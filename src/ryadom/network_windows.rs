use super::Route;
use hbb_common::{anyhow::anyhow, bail, ResultType};
use std::os::windows::process::CommandExt;
use std::{
    net::{Ipv4Addr, UdpSocket},
    path::PathBuf,
    process::Command,
};

pub fn route() -> ResultType<Route> {
    use winapi::{
        shared::{winerror::ERROR_BUFFER_OVERFLOW, ws2def::AF_INET},
        um::{
            iphlpapi::GetAdaptersAddresses,
            iptypes::{GAA_FLAG_INCLUDE_GATEWAYS, IP_ADAPTER_ADDRESSES_LH},
        },
    };
    let probe = UdpSocket::bind("0.0.0.0:0")?;
    probe.connect("1.1.1.1:3478")?;
    let selected = probe.local_addr()?.ip();
    let mut len = 16_384u32;
    for _ in 0..3 {
        let mut buffer = vec![0u64; (len as usize + 7) / 8];
        let ptr = buffer.as_mut_ptr() as *mut IP_ADAPTER_ADDRESSES_LH;
        // The Windows API fills an aligned, size-bounded linked list inside this allocation.
        let result = unsafe {
            GetAdaptersAddresses(
                AF_INET as u32,
                GAA_FLAG_INCLUDE_GATEWAYS,
                std::ptr::null_mut(),
                ptr,
                &mut len,
            )
        };
        if result == ERROR_BUFFER_OVERFLOW && len <= 512 * 1024 {
            continue;
        }
        if result != 0 {
            bail!("Windows не вернула список сетевых адаптеров: {result}");
        }
        let mut adapter = ptr;
        while !adapter.is_null() {
            let a = unsafe { &*adapter };
            let mut address = a.FirstUnicastAddress;
            while !address.is_null() {
                let u = unsafe { &*address };
                if let Some(local) = unsafe { ipv4(u.Address.lpSockaddr) } {
                    if std::net::IpAddr::V4(local) == selected && !a.FirstGatewayAddress.is_null() {
                        let gateway = unsafe { ipv4((*a.FirstGatewayAddress).Address.lpSockaddr) };
                        if let Some(gateway) = gateway {
                            return Ok(Route { local, gateway });
                        }
                    }
                }
                address = u.Next;
            }
            adapter = a.Next;
        }
        break;
    }
    bail!("Не найден IPv4-шлюз текущего маршрута. Возможно, сеть использует VPN или другой способ подключения.")
}
unsafe fn ipv4(address: *mut winapi::shared::ws2def::SOCKADDR) -> Option<Ipv4Addr> {
    if address.is_null() || (*address).sa_family != winapi::shared::ws2def::AF_INET as u16 {
        return None;
    }
    let address = &*(address as *const winapi::shared::ws2def::SOCKADDR_IN);
    Some(Ipv4Addr::from(
        (*address.sin_addr.S_un.S_addr()).to_ne_bytes(),
    ))
}
pub fn ipv6_available() -> bool {
    UdpSocket::bind("[::]:0")
        .and_then(|s| {
            s.connect("[2606:4700:4700::1111]:3478")?;
            s.local_addr()
        })
        .is_ok_and(|a| match a.ip() {
            std::net::IpAddr::V6(v) => {
                let first = v.segments()[0];
                first & 0xe000 == 0x2000
            }
            _ => false,
        })
}
fn programs() -> ResultType<Vec<PathBuf>> {
    let mut paths = vec![std::env::current_exe()?.canonicalize()?];
    let (_, _, _, exe) = crate::platform::get_install_info();
    if let Ok(path) = PathBuf::from(exe).canonicalize() {
        if !paths.contains(&path) {
            paths.push(path);
        }
    }
    Ok(paths)
}
fn powershell(script: &str) -> ResultType<std::process::Output> {
    let bytes: Vec<u8> = script.encode_utf16().flat_map(u16::to_le_bytes).collect();
    let exe =
        PathBuf::from(std::env::var_os("SystemRoot").ok_or_else(|| anyhow!("Нет SystemRoot"))?)
            .join("System32/WindowsPowerShell/v1.0/powershell.exe");
    Ok(Command::new(exe)
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-EncodedCommand",
            &crate::encode64(bytes),
        ])
        .creation_flags(0x08000000)
        .output()?)
}
pub fn firewall() -> ResultType<String> {
    let mut missing = false;
    for path in programs()? {
        let path = path.to_string_lossy().replace('\'', "''");
        let script=format!("$ErrorActionPreference='Stop'; $p='{path}'; $r=Get-NetFirewallApplicationFilter -Program $p -ErrorAction SilentlyContinue | Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object {{$_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow'}} | Get-NetFirewallPortFilter | Where-Object {{$_.Protocol -eq 'UDP' -or $_.Protocol -eq 'Any'}}; if($r){{'OK'}}");
        let result = powershell(&script)?;
        if !result.status.success() || !String::from_utf8_lossy(&result.stdout).contains("OK") {
            missing = true;
        }
    }
    if !missing {
        return Ok("Брандмауэр: правило приложения уже настроено".into());
    }
    if crate::platform::is_elevated(None).unwrap_or(false) {
        add_firewall()?;
        return Ok("Брандмауэр: правило UDP настроено".into());
    }
    match crate::platform::elevate("--ryadom-firewall"){
        Ok(true)=>Ok("Запрошены права администратора для правила UDP. Остальные проверки продолжаются.".into()),
        _=>Ok("Правило UDP не изменено: повышение прав отменено или недоступно. Остальные проверки продолжаются.".into()),
    }
}
pub fn add_firewall() -> ResultType<()> {
    if !crate::platform::is_elevated(None).unwrap_or(false) {
        bail!("Для правила брандмауэра нужны права администратора");
    }
    let netsh =
        PathBuf::from(std::env::var_os("SystemRoot").ok_or_else(|| anyhow!("Нет SystemRoot"))?)
            .join("System32/netsh.exe");
    for path in programs()? {
        let name = format!(
            "name=Ryadom P2P {}",
            hex::encode(
                &hbb_common::sodiumoxide::crypto::hash::sha256::hash(
                    path.to_string_lossy().as_bytes()
                )
                .0[..8]
            )
        );
        let result = Command::new(&netsh)
            .args([
                "advfirewall",
                "firewall",
                "add",
                "rule",
                &name,
                "dir=in",
                "action=allow",
                "protocol=UDP",
                "profile=any",
                "enable=yes",
            ])
            .arg(format!("program={}", path.display()))
            .creation_flags(0x08000000)
            .output()?;
        if !result.status.success() {
            bail!("Windows не применила правило брандмауэра. Возможно, действует политика организации.");
        }
    }
    Ok(())
}
