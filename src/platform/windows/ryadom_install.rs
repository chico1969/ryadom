use super::{
    installer_files::ProtectedInstallFile,
    installer_handoff::directory,
    installer_shell::{escape_nested_cmd_ampersands, path_for_cmd_environment},
};
use hbb_common::{
    anyhow::{anyhow, Context},
    bail,
    base64::{engine::general_purpose::STANDARD, Engine},
    config::Config,
    ryadom_dpapi,
    sodiumoxide::crypto::sign,
    toml,
    ResultType,
};
use serde::{Deserialize, Serialize};
use std::{fs, path::Path};

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Snapshot {
    version: u8,
    identity: String,
    options: Option<String>,
}

fn read_config(path: &Path) -> ResultType<String> {
    if fs::metadata(path)?.len() > 1024 * 1024 {
        bail!("Конфигурация Рядом слишком велика для переноса");
    }
    Ok(fs::read_to_string(path)?)
}

fn identity(raw: &str) -> ResultType<toml::Value> {
    let value: toml::Value = toml::from_str(raw)?;
    let mut pair: (Vec<u8>, Vec<u8>) = value
        .get("key_pair")
        .ok_or_else(|| anyhow!("В переносимой конфигурации нет ключа устройства"))?
        .clone()
        .try_into()?;
    ryadom_dpapi::open_identity(&mut pair)?;
    if pair.0.len() != sign::SECRETKEYBYTES || pair.1.len() != sign::PUBLICKEYBYTES {
        bail!("Некорректный ключ переносимого устройства");
    }
    let seed = sign::Seed::from_slice(&pair.0[..sign::SEEDBYTES])
        .ok_or_else(|| anyhow!("Некорректный ключ переносимого устройства"))?;
    let (public, secret) = sign::keypair_from_seed(&seed);
    if secret.as_ref() != pair.0 || public.as_ref() != pair.1 {
        bail!("Ключи переносимого устройства не соответствуют друг другу");
    }
    Ok(value)
}

fn snapshot(source: &Path) -> ResultType<Snapshot> {
    let raw = read_config(source)?;
    let mut main = identity(&raw)?;
    let mut pair: (Vec<u8>, Vec<u8>) = main["key_pair"].clone().try_into()?;
    pair.0 = ryadom_dpapi::seal_machine(&pair.0, "Ryadom.device-key.v1")?;
    main["key_pair"] = toml::Value::try_from(pair)?;
    let options_path = source.with_file_name("Ryadom2.toml");
    let options = if options_path.exists() {
        let mut options: toml::Value = toml::from_str(&read_config(&options_path)?)?;
        let key = hbb_common::ryadom_network::OWNER_TURN_OPTION;
        if let Some(value) = options.get_mut("options").and_then(|v| v.get_mut(key)) {
            let encoded = value.as_str().ok_or_else(|| anyhow!("Неверный формат личной настройки TURN"))?;
            if !encoded.is_empty() {
                let raw = ryadom_dpapi::open(&STANDARD.decode(encoded)?, "Ryadom.TURN.owner.v1")?;
                *value = toml::Value::String(STANDARD.encode(ryadom_dpapi::seal_machine(
                    &raw, "Ryadom.TURN.owner.v1",
                )?));
            }
        }
        Some(toml::to_string(&options)?)
    } else {
        None
    };
    Ok(Snapshot { version: 1, identity: toml::to_string(&main)?, options })
}

pub(super) fn prepare(exe: &str) -> ResultType<(String, Option<ProtectedInstallFile>)> {
    // An upgrade keeps the installed service's identity and host settings.
    if super::is_installed() {
        return Ok((String::new(), None));
    }
    let bytes = serde_json::to_vec(&snapshot(&Config::file())?)?;
    let file = ProtectedInstallFile::new(&directory::path()?.with_extension("json"), &bytes)?;
    let source = path_for_cmd_environment(file.path())?;
    let exe = escape_nested_cmd_ampersands(exe);
    let commands = format!(r#"
copy /B /Y "{source}" "%RUSTDESK_OUTPUT_DIR%\ryadom-config.json" > nul || exit /b 9059
sc stop Ryadom > nul 2>&1
sc delete Ryadom > nul 2>&1
sc create Ryadom binpath= "\"{exe}\" --ryadom-import-config \"%RUSTDESK_OUTPUT_DIR%\ryadom-config.json\" \"%RUSTDESK_OUTPUT_DIR%\ryadom-import.ok\"" start= demand DisplayName= "Ryadom configuration import"
sc start Ryadom > nul 2>&1
sc stop Ryadom > nul 2>&1
sc delete Ryadom > nul 2>&1
if not exist "%RUSTDESK_OUTPUT_DIR%\ryadom-import.ok" exit /b 9059
"#);
    Ok((commands, Some(file)))
}

fn restore(path: &Path, previous: Option<&[u8]>) -> ResultType<()> {
    match previous {
        Some(bytes) => fs::write(path, bytes)?,
        None if path.exists() => fs::remove_file(path)?,
        None => {}
    }
    Ok(())
}

fn install(value: Snapshot, target: &Path) -> ResultType<()> {
    if value.version != 1 { bail!("Неподдерживаемая версия переноса настроек"); }
    identity(&value.identity)?;
    if let Some(options) = &value.options { toml::from_str::<toml::Value>(options)?; }
    let parent = target.parent().ok_or_else(|| anyhow!("Нет каталога конфигурации"))?;
    fs::create_dir_all(parent)?;
    let options = target.with_file_name("Ryadom2.toml");
    let old_main = if target.exists() { Some(fs::read(target)?) } else { None };
    let old_options = if options.exists() { Some(fs::read(&options)?) } else { None };
    let result = (|| -> ResultType<()> {
        restore(&options, value.options.as_deref().map(str::as_bytes))?;
        fs::write(target, &value.identity)?;
        if fs::read_to_string(target)? != value.identity
            || value.options.as_ref().map_or(false, |raw| fs::read_to_string(&options).ok().as_ref() != Some(raw)) {
            bail!("Не удалось проверить сохранённую конфигурацию");
        }
        Ok(())
    })();
    if let Err(error) = result {
        restore(target, old_main.as_deref()).context("Не удалось восстановить прежний ключ после ошибки переноса")?;
        restore(&options, old_options.as_deref()).context("Не удалось восстановить прежние настройки после ошибки переноса")?;
        return Err(error);
    }
    Ok(())
}

pub(crate) fn startup() -> Option<ResultType<()>> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args.is_empty() && super::is_installed() && !super::is_cur_exe_the_installed() {
        return Some((|| {
            let (_, _, _, exe) = super::get_install_info();
            std::process::Command::new(exe).spawn()?;
            Ok(())
        })());
    }
    if args.first().map(String::as_str) != Some("--ryadom-import-config") { return None; }
    Some((|| {
        if args.len() != 3 { bail!("Неверные параметры переноса настроек"); }
        let value: Snapshot = serde_json::from_str(&read_config(Path::new(&args[1]))?)?;
        install(value, &Config::file())?;
        fs::write(&args[2], b"ok")?;
        Ok(())
    })())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ryadom_portable_import_preserves_identity_password_and_options_without_time_gate() {
        hbb_common::sodiumoxide::init().unwrap();
        let root = std::env::temp_dir().join(format!("ryadom-import-{}", uuid::Uuid::new_v4()));
        let source = root.join("portable/Ryadom.toml");
        let target = root.join("service/Ryadom.toml");
        fs::create_dir_all(source.parent().unwrap()).unwrap();
        let (pk, sk) = sign::gen_keypair();
        let password=uuid::Uuid::new_v4().to_string();
        let salt=uuid::Uuid::new_v4().to_string();
        let h1=hbb_common::config::compute_permanent_password_h1(&password,&salt);
        let stored=format!("01{}",STANDARD.encode(hbb_common::password_security::symmetric_crypt(format!("00{}",STANDARD.encode(h1)).as_bytes(),true).unwrap()));
        let device=crate::ryadom::device_id(pk.as_ref());
        let enc_id=hbb_common::password_security::encrypt_str_or_original(&device,"00",128);
        let raw = toml::to_string(&serde_json::json!({"enc_id":enc_id, "password":stored, "salt":salt, "key_pair":[sk.as_ref(),pk.as_ref()]})).unwrap();
        fs::write(&source, raw).unwrap();
        let owner = hbb_common::ryadom_network::protect_owner_config(r#"[{"urls":["turn:relay.example.com:3478"],"username":"test-user","credential":"test-only"}]"#).unwrap();
        let code=format!("{}",hbb_common::rand::random::<u32>()%900_000_000+100_000_000);
        let options = serde_json::json!({"options":{"ryadom-short-code":code,"ryadom-p2p-helper":"","approve-mode":"password","verification-method":"use-permanent-password","enable-clipboard":"N",hbb_common::ryadom_network::OWNER_TURN_OPTION:owner}});
        fs::write(source.with_file_name("Ryadom2.toml"), toml::to_string(&options).unwrap()).unwrap();
        let value = snapshot(&source).unwrap();
        install(value, &target).unwrap();
        let copied: toml::Value = toml::from_str(&fs::read_to_string(&target).unwrap()).unwrap();
        assert_eq!(copied["password"].as_str(),Some(stored.as_str()));
        assert_eq!(copied["salt"].as_str(),Some(salt.as_str()));
        assert_eq!(hbb_common::config::decode_permanent_password_h1_from_storage(copied["password"].as_str().unwrap()),Some(h1));
        let mut pair = copied["key_pair"].clone().try_into().unwrap();
        ryadom_dpapi::open_identity(&mut pair).unwrap();
        assert_eq!(pair,(sk.as_ref().to_vec(),pk.as_ref().to_vec()));
        let options: toml::Value = toml::from_str(&fs::read_to_string(target.with_file_name("Ryadom2.toml")).unwrap()).unwrap();
        assert_eq!(options["options"]["ryadom-short-code"].as_str(),Some(code.as_str()));
        assert_eq!(options["options"]["approve-mode"].as_str(),Some("password"));
        let sealed = STANDARD.decode(options["options"][hbb_common::ryadom_network::OWNER_TURN_OPTION].as_str().unwrap()).unwrap();
        assert!(String::from_utf8(ryadom_dpapi::open(&sealed,"Ryadom.TURN.owner.v1").unwrap()).unwrap().contains("test-user"));
        let before=fs::read(&target).unwrap();
        assert!(install(Snapshot{version:1,identity:"invalid".into(),options:None},&target).is_err());
        assert_eq!(fs::read(&target).unwrap(),before);
        if let Some(folder)=std::env::var_os("RYADOM_MIGRATION_FIXTURE") {
            let folder=std::path::PathBuf::from(folder);
            fs::create_dir_all(&folder).unwrap();
            fs::copy(&target,folder.join("Ryadom.toml")).unwrap();
            fs::copy(target.with_file_name("Ryadom2.toml"),folder.join("Ryadom2.toml")).unwrap();
            fs::write(folder.join("password.txt"),password).unwrap();
            fs::write(folder.join("expected.json"),serde_json::to_vec(&serde_json::json!({"id":device,"code":code})).unwrap()).unwrap();
        }
        fs::remove_dir_all(root).unwrap();
    }
}
