use serde_json::{json, Value};
use std::sync::RwLock;

lazy_static::lazy_static! {
    static ref STATUS: RwLock<Value> = RwLock::new(json!({"phase":"starting","message":"Подключаемся к службе поиска…"}));
}

pub fn update(phase: &str, message: &str, retry_seconds: u64) {
    *STATUS.write().unwrap() =
        json!({"phase":phase,"message":message,"retrySeconds":retry_seconds});
}

pub fn failed(error: &str, retry_seconds: u64) {
    let message = if error.contains("403") {
        "Служба поиска запретила доступ из этой сети (HTTP 403). ID не зарегистрирован."
    } else if error.contains("429") || error.contains("QUOTA") {
        "Достигнут лимит службы поиска. ID пока недоступен."
    } else if error.contains("ID-TAKEN") {
        "Эта личность компьютера уже подключена. Закройте вторую копию Рядом."
    } else if error.contains("certificate")
        || error.contains("Certificate")
        || error.contains("TLS")
    {
        "Не удалось проверить защищённое соединение со службой поиска. Проверьте дату Windows и сеть."
    } else {
        "Нет связи со службой поиска. Проверьте интернет; программа повторит попытку."
    };
    update("failed", message, retry_seconds);
}

pub fn local() -> Value {
    let mut state = STATUS.read().unwrap().clone();
    let code = super::active_code();
    if super::signaling::stopped() {
        state =
            json!({"phase":"stopped","message":"Приём подключений выключен в настройках Рядом."});
    } else if !code.is_empty() {
        state = json!({"phase":"ready","message":"Готов к подключению","code":code});
    }
    state
}

pub fn snapshot() -> Value {
    crate::ipc::get_config("ryadom-registration-state")
        .ok()
        .flatten()
        .and_then(|value| serde_json::from_str(&value).ok())
        .unwrap_or_else(local)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn registration_errors_explain_denial_without_exposing_tokens() {
        failed("HTTP error: 403 Forbidden token=private", 60);
        let state = STATUS.read().unwrap().clone();
        assert_eq!(state["phase"], "failed");
        assert!(state["message"].as_str().unwrap().contains("403"));
        assert!(!state.to_string().contains("private"));
        assert_eq!(state["retrySeconds"], 60);
    }

    #[hbb_common::tokio::test]
    #[ignore = "requires the deployed signaling service"]
    async fn deployed_service_accepts_native_registration_and_rejects_duplicate() {
        use hbb_common::futures_util::SinkExt;
        let id = format!("ryadom-client-{}", uuid::Uuid::new_v4());
        let mut socket = super::super::signaling::open(&id).await.unwrap();
        let rejected = super::super::signaling::open(&id).await.err().unwrap();
        assert!(rejected.to_string().contains("ID-TAKEN"));
        socket.close(None).await.unwrap();
    }
}
