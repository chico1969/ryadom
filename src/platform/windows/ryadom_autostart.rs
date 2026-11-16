use super::{
    installer_handoff::{run_cmds, InstallCommands},
    installer_shell::staged_tray_shortcut_commands,
};
use hbb_common::{anyhow::anyhow, bail, config::{self, Config}, ResultType};
use serde_json::{json, Value};
use std::path::PathBuf;
use winreg::{enums::HKEY_LOCAL_MACHINE, RegKey};

const KEY: &str = r"SOFTWARE\Ryadom";
const VALUE: &str = "AutoStart";

pub(crate) fn preference() -> bool {
    RegKey::predef(HKEY_LOCAL_MACHINE)
        .open_subkey(KEY)
        .and_then(|key| key.get_value::<u32, _>(VALUE))
        .map_or(true, |value| value != 0)
}

fn selected(options: &str, previous: bool) -> bool {
    let flags: Vec<_> = options.split_whitespace().collect();
    if flags.contains(&"no-autostart") { false }
    else if flags.contains(&"autostart") { true }
    else { previous }
}

pub(crate) fn silent_options(base: &str, args: &[String]) -> String {
    if args.iter().any(|v| v == "--no-autostart") { format!("{base} no-autostart") }
    else if args.iter().any(|v| v == "--autostart") { format!("{base} autostart") }
    else { base.to_owned() }
}

fn tray_path() -> Option<PathBuf> {
    std::env::var_os("ProgramData").map(|base| PathBuf::from(base).join(
        r"Microsoft\Windows\Start Menu\Programs\Startup\Ryadom Tray.lnk"))
}

pub(crate) fn status() -> Value {
    let installed = super::is_installed();
    let start = RegKey::predef(HKEY_LOCAL_MACHINE)
        .open_subkey(r"SYSTEM\CurrentControlSet\Services\Ryadom")
        .and_then(|key| key.get_value::<u32, _>("Start")).ok();
    let tray = tray_path().is_some_and(|path| path.is_file());
    json!({"installed":installed,"available":installed && start.is_some(),
        "enabled":if installed {start == Some(2) && tray} else {preference()},
        "serviceAutomatic":start == Some(2),"trayAutomatic":tray})
}

fn commands(enabled: bool, copy_tray: bool) -> String {
    let mode = if enabled { "auto" } else { "demand" };
    let value = if enabled { 1 } else { 0 };
    let tray = if enabled && copy_tray {
        r#"copy /B /Y "%RUSTDESK_OUTPUT_DIR%\Ryadom Tray.lnk" "%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Ryadom Tray.lnk" > nul || exit /b 9063"#
    } else if enabled {
        r#"if not exist "%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Ryadom Tray.lnk" exit /b 9063"#
    } else {
        r#"if exist "%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Ryadom Tray.lnk" del /f /q "%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Ryadom Tray.lnk"
if exist "%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Ryadom Tray.lnk" exit /b 9063"#
    };
    format!(r#"
sc config Ryadom start= {mode} > nul || exit /b 9062
{tray}
reg add HKEY_LOCAL_MACHINE\{KEY} /f /v {VALUE} /t REG_DWORD /d {value} > nul || exit /b 9064
"#)
}

fn setup_commands(options: &str, previous: bool, stopped: bool, outgoing_only: bool) -> String {
    let enabled = selected(options, previous);
    if stopped || outgoing_only {
        let value = if enabled { 1 } else { 0 };
        return format!(r#"
reg add HKEY_LOCAL_MACHINE\{KEY} /f /v {VALUE} /t REG_DWORD /d {value} > nul || exit /b 9064
"#);
    }
    // Setup already copied this shortcut and cleaned its temporary directory.
    commands(enabled, false)
}

pub(super) fn install_commands(options: &str) -> String {
    let stopped = super::ryadom_install_privacy::selected(options)
        .map(|enabled| !enabled).unwrap_or_else(|| Config::get_option("stop-service") == "Y");
    setup_commands(options, preference(), stopped, config::is_outgoing_only())
}

pub(crate) fn set_enabled(enabled: bool) -> ResultType<Value> {
    if status()["available"] != true {
        bail!("Для автозапуска требуется установленная служба Рядом. Запустите Setup.");
    }
    let (_, path, _, exe) = super::get_install_info();
    let icon = super::get_custom_icon(&path, &exe);
    let (stage, file) = staged_tray_shortcut_commands("Ryadom", &exe, icon.as_deref())?;
    run_cmds(InstallCommands { script: format!("{stage}\r\n{}",commands(enabled,true)), files:vec![file] },false,"autostart")
        .map_err(|error|anyhow!("Не удалось изменить автозапуск. Подтвердите запрос Windows или оставьте прежнюю настройку: {error}"))?;
    let value = status();
    if value["enabled"] != enabled || preference() != enabled {
        bail!("Windows не подтвердила новую настройку автозапуска");
    }
    Ok(value)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ryadom_autostart_defaults_on_and_updates_preserve_explicit_off() {
        assert!(selected("desktopicon startmenu",true));
        assert!(!selected("desktopicon startmenu",false));
        assert!(!selected("desktopicon no-autostart",true));
        assert!(selected("autostart",false));
        assert_eq!(silent_options("desktopicon",&["--no-autostart".into()]),"desktopicon no-autostart");
    }

    #[test]
    fn ryadom_autostart_setup_preserves_paused_and_outgoing_only_access() {
        for (options, previous, value) in [
            ("", true, 1), ("", false, 0),
            ("autostart", false, 1), ("no-autostart", true, 0),
        ] {
            for (stopped, outgoing_only) in [(true, false), (false, true), (true, true)] {
                assert_eq!(setup_commands(options, previous, stopped, outgoing_only).trim(),
                    format!(r#"reg add HKEY_LOCAL_MACHINE\SOFTWARE\Ryadom /f /v AutoStart /t REG_DWORD /d {value} > nul || exit /b 9064"#));
            }
        }
        let active = setup_commands("autostart", false, false, false);
        assert!(active.contains("sc config Ryadom start= auto > nul || exit /b 9062"));
        assert!(active.contains(r#"if not exist "%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Ryadom Tray.lnk" exit /b 9063"#));
    }

    #[test]
    #[ignore = "changes actual Windows service startup; run explicitly on the owner's test PC"]
    fn ryadom_autostart_on_this_pc() {
        crate::ryadom::init_product().unwrap();
        let before=status();
        assert_eq!(before["available"],true);
        let original=before["enabled"].as_bool().unwrap();
        assert_eq!(before["serviceAutomatic"],original);
        assert_eq!(before["trayAutomatic"],original);
        let result=(|| -> ResultType<()> {
            for enabled in [false,true] {
                let state=set_enabled(enabled)?;
                if state["serviceAutomatic"] != enabled || state["trayAutomatic"] != enabled {
                    bail!("Service and tray startup did not match the selected setting");
                }
            }
            Ok(())
        })();
        set_enabled(original).unwrap();
        result.unwrap();
    }
}
