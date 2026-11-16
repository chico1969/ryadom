use super::{installer_shell::get_system_executable, validate_install_value, wide_string};
use hbb_common::{anyhow::anyhow, bail, config::{self, Config2}, toml, ResultType};
use std::{fs, io::{ErrorKind, Write}, path::{Path, PathBuf}};
use windows::{core::PCWSTR, Win32::Storage::FileSystem::{ReplaceFileW, REPLACE_FILE_FLAGS}};

const ALLOW: &str = "--ryadom-background-network";
const DENY: &str = "--ryadom-no-background-network";
const APPLY: &str = "--ryadom-apply-background-policy";

pub(super) fn selected(options: &str) -> Option<bool> {
    let mut flags = options.split_whitespace();
    if flags.clone().any(|flag| flag == DENY) { Some(false) }
    else if flags.any(|flag| flag == ALLOW) { Some(true) }
    else { None }
}

pub(crate) fn silent_options(options: &str, args: &[String]) -> String {
    let explicit = if args.iter().any(|arg| arg == DENY) { Some(false) }
        else if args.iter().any(|arg| arg == ALLOW) { Some(true) } else { None };
    match explicit {
        Some(enabled) => format!("{options} {}", if enabled { ALLOW } else { DENY }),
        None => options.to_owned(),
    }
}

pub(super) fn current() -> bool {
    let options = crate::ipc::get_options();
    !config::option2bool("stop-service", options.get("stop-service").map(String::as_str).unwrap_or(""))
}

fn update_options(raw: &str, enabled: bool) -> ResultType<String> {
    let mut value: toml::Value = toml::from_str(raw)
        .map_err(|_| anyhow!("Некорректный формат конфигурации Рядом"))?;
    let table = value.as_table_mut().ok_or_else(|| anyhow!("Некорректная конфигурация Рядом"))?;
    let options = table.entry("options").or_insert_with(|| toml::Value::Table(Default::default()))
        .as_table_mut().ok_or_else(|| anyhow!("Некорректные параметры Рядом"))?;
    if enabled { options.remove("stop-service"); }
    else { options.insert("stop-service".into(), toml::Value::String("Y".into())); }
    Ok(toml::to_string(&value)?)
}

fn apply_file(path: &Path, enabled: bool) -> ResultType<()> {
    let previous = match fs::read_to_string(path) {
        Ok(value) => value,
        Err(error) if error.kind() == ErrorKind::NotFound => String::new(),
        Err(error) => return Err(error.into()),
    };
    if previous.len() > 1024 * 1024 { bail!("Конфигурация Рядом слишком велика"); }
    let updated = update_options(&previous, enabled)?;
    let parent = path.parent().ok_or_else(|| anyhow!("Нет каталога конфигурации Рядом"))?;
    fs::create_dir_all(parent)?;
    let temporary = parent.join(format!(".ryadom-privacy-{}.tmp", uuid::Uuid::new_v4()));
    let result = (|| -> ResultType<()> {
        let mut file = fs::OpenOptions::new().write(true).create_new(true).open(&temporary)?;
        file.write_all(updated.as_bytes())?;
        file.sync_all()?;
        drop(file);
        if path.exists() {
            let target = wide_string(path.to_str().ok_or_else(|| anyhow!("Неверный путь конфигурации"))?);
            let source = wide_string(temporary.to_str().ok_or_else(|| anyhow!("Неверный временный путь"))?);
            unsafe { ReplaceFileW(PCWSTR(target.as_ptr()), PCWSTR(source.as_ptr()), PCWSTR::null(), REPLACE_FILE_FLAGS(0), None, None)?; }
        } else { fs::rename(&temporary, path)?; }
        if fs::read_to_string(path)? != updated { bail!("Windows не подтвердила настройку фоновой связи"); }
        Ok(())
    })();
    if temporary.exists() { fs::remove_file(&temporary)?; }
    result
}

fn machine_options_path() -> ResultType<PathBuf> {
    let system = get_system_executable("")?;
    Ok(system.parent().ok_or_else(|| anyhow!("Не найден каталог Windows"))?
        .join(r"ServiceProfiles\LocalService\AppData\Roaming\Ryadom\config\Ryadom2.toml"))
}

pub(crate) fn startup() -> bool {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) != Some(APPLY) { return false; }
    let result = (|| -> ResultType<()> {
        if args.len() != 2 || !matches!(args[1].as_str(), "allow" | "deny") {
            bail!("Неверные параметры настройки фоновой связи");
        }
        if !super::is_root() && !super::is_elevated(None).unwrap_or(false) {
            bail!("Для установки настройки фоновой связи нужны права администратора");
        }
        apply_file(&machine_options_path()?, args[1] == "allow")
    })();
    if let Err(error) = result {
        hbb_common::log::error!("Настройка фоновой связи не установлена: {error}");
        std::process::exit(1);
    }
    true
}

pub(super) fn configuration_commands(import: String, options: &str, exe: &str) -> ResultType<String> {
    let Some(enabled) = selected(options) else { return Ok(import); };
    validate_install_value(exe)?;
    let mode = if enabled { "allow" } else { "deny" };
    Ok(format!("{import}\r\nstart \"\" /b /wait \"{exe}\" {APPLY} {mode}\r\nif not \"%errorlevel%\"==\"0\" exit /b 9065"))
}

pub(super) fn before_shortcuts(copy: String, configuration: &mut String, options: &str) -> String {
    if selected(options).is_some() { format!("{copy}\r\n{}", std::mem::take(configuration)) }
    else { copy }
}

fn replace_service(commands: String, previous: &str, selected: &str) -> ResultType<String> {
    let commands = if previous.is_empty() { commands } else {
        if commands.matches(previous).count() != 1 { bail!("Не удалось однозначно подготовить службу Рядом"); }
        commands.replacen(previous, "", 1)
    };
    Ok(format!("{commands}\r\n{selected}"))
}

pub(super) fn after_install_commands(commands: String, options: &str, exe: &str) -> ResultType<String> {
    let Some(enabled) = selected(options) else { return super::native_after_install_commands(commands, exe, true); };
    let service = if enabled && !config::is_outgoing_only() {
        super::service_control_command("create-service-install-choice", exe, true)?
    } else {
        r#"if exist "%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Ryadom Tray.lnk" del /f /q "%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Ryadom Tray.lnk""#.into()
    };
    replace_service(commands, &super::get_create_service(exe), &service)
}

pub(super) fn persist_user_choice(options: &str) -> ResultType<()> {
    // Both installer entry points exit; the new GUI reads this file. A Config setter
    // would rewrite the typed Config2 and discard unknown fields preserved above.
    if let Some(enabled) = selected(options) { apply_file(&Config2::file(), enabled)?; }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ryadom_install_privacy_missing_flag_preserves_and_explicit_flags_are_independent() {
        assert_eq!(selected("desktopicon no-autostart"), None);
        assert_eq!(silent_options("desktopicon", &["--silent-install".into()]), "desktopicon");
        assert_eq!(silent_options("desktopicon", &[format!(r"C:\folder {DENY}\app")]), "desktopicon");
        assert_eq!(selected(&format!("no-autostart {ALLOW}")), Some(true));
        assert_eq!(selected(&format!("autostart {DENY}")), Some(false));
        assert_eq!(selected(&format!("{ALLOW} {DENY}")), Some(false));
    }

    #[test]
    fn ryadom_install_privacy_machine_policy_precedes_one_receiving_start() {
        for (flag, legacy, replacement, starts) in [
            (ALLOW, "old-paused-tray-cleanup", "--service-control create-service", 1),
            (DENY, "old-receiving-start", "remove-startup-tray", 0),
        ] {
            let body = format!("independent-setup\r\n{legacy}\r\nfinish-setup");
            let replaced = replace_service(body, legacy, replacement).unwrap();
            let mut policy = configuration_commands("migration".into(), flag, r"C:\Program Files\Ryadom\Ryadom.exe").unwrap();
            let copy = before_shortcuts("copy-executable".into(), &mut policy, flag);
            let installation = format!("{copy}\r\ncopy-startup-tray-shortcut\r\n{policy}\r\n{replaced}");
            assert!(installation.find(APPLY).unwrap() < installation.find(replacement).unwrap());
            assert!(installation.find(APPLY).unwrap() < installation.find("copy-startup-tray-shortcut").unwrap());
            assert_eq!(installation.matches("--service-control create-service").count(), starts);
            assert!(!installation.contains(legacy));
        }
        assert_eq!(configuration_commands("unchanged-import".into(), "autostart", "").unwrap(), "unchanged-import");
        let mut import = "unchanged-import".into();
        assert_eq!(before_shortcuts("copy".into(), &mut import, "autostart"), "copy");
        assert_eq!(import, "unchanged-import");
        assert!(replace_service("oldold".into(), "old", "new").is_err());
    }

    #[test]
    fn ryadom_install_privacy_changes_only_stop_service_in_existing_config2() {
        let root = std::env::temp_dir().join(format!("ryadom-privacy-{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(&root).unwrap();
        let identity = root.join("Ryadom.toml");
        let options_path = root.join("Ryadom2.toml");
        let identity_bytes = b"identity-password-key-salt-sentinel";
        fs::write(&identity, identity_bytes).unwrap();
        let mut options = Config2::default();
        for (key, value) in [("stop-service", "Y"), (hbb_common::ryadom_network::OWNER_TURN_OPTION, "encrypted-owner-sentinel"), ("approve-mode", "password"), ("ryadom-p2p-helper", "Y")] {
            options.options.insert(key.into(), value.into());
        }
        let mut preserved = toml::Value::try_from(&options).unwrap();
        preserved.as_table_mut().unwrap().insert("future-storage-field".into(), toml::Value::String("preserved".into()));
        let original = toml::to_string(&preserved).unwrap();
        fs::write(&options_path, &original).unwrap();
        apply_file(&options_path, true).unwrap();
        let enabled: Config2 = toml::from_str(&fs::read_to_string(&options_path).unwrap()).unwrap();
        let mut expected = options.clone();expected.options.remove("stop-service");
        assert_eq!(enabled, expected);
        apply_file(&options_path, false).unwrap();
        let disabled: Config2 = toml::from_str(&fs::read_to_string(&options_path).unwrap()).unwrap();
        assert_eq!(disabled, options);
        let stored: toml::Value = toml::from_str(&fs::read_to_string(&options_path).unwrap()).unwrap();
        assert_eq!(stored["future-storage-field"], preserved["future-storage-field"]);
        assert_eq!(fs::read(&identity).unwrap(), identity_bytes);
        let resolved = root.canonicalize().unwrap();
        let temporary_parent = std::env::temp_dir().canonicalize().unwrap();
        assert_eq!(resolved.parent(), Some(temporary_parent.as_path()));
        fs::remove_dir_all(resolved).unwrap();
    }
}
