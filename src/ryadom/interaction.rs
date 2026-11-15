use base::message_proto::{Hash, MouseEvent};

pub const POINTER_ORANGE: u32 = 0xffff8a1c;

pub fn low_latency_decoding(
    mut decoding: base::message_proto::SupportedDecoding,
) -> base::message_proto::SupportedDecoding {
    use base::message_proto::supported_decoding::PreferCodec;
    if decoding.prefer.enum_value() == Ok(PreferCodec::Auto)
        && decoding.ability_vp8 > 0
        && decoding.prefer_chroma.enum_value() != Ok(base::message_proto::Chroma::I444)
    {
        decoding.prefer = PreferCodec::VP8.into();
    }
    decoding
}

#[cfg(windows)]
pub fn elevation_ready() -> bool {
    crate::platform::is_installed()
        || crate::platform::is_elevated(None).unwrap_or(false)
        || crate::portable_service::client::running()
}

pub fn cursor_option(name: &str, view_only: bool) -> Option<bool> {
    match name {
        "show-remote-cursor" => Some(true),
        "show-my-cursor" => Some(view_only),
        _ => None,
    }
}

pub fn login_challenge(mut hash: Hash) -> Hash {
    use hbb_common::{
        config::Config,
        password_security::{self, ApproveMode},
    };
    hash.ryadom_auth_version = 1;
    hash.ryadom_session_version = 1;
    hash.ryadom_password_set = Config::has_permanent_password()
        && password_security::permanent_enabled()
        && password_security::approve_mode() != ApproveMode::Click;
    hash
}

pub fn request_approval(hash: &Hash, password: &mut Vec<u8>, explicit: bool) -> bool {
    if hash.ryadom_auth_version == 1 && !hash.ryadom_password_set {
        password.clear();
    }
    explicit
        || (password.is_empty() && (hash.ryadom_auth_version != 1 || !hash.ryadom_password_set))
}

pub fn pointing_event(event: &MouseEvent) -> bool {
    matches!(event.mask, 0 | 10)
        && (-1_000_000..=1_000_000).contains(&event.x)
        && (-1_000_000..=1_000_000).contains(&event.y)
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn show_pointer(id: i32, name: &str, event: &MouseEvent) {
    if !pointing_event(event) {
        return;
    }
    use crate::whiteboard::{self, Cursor, CustomEvent};
    whiteboard::ensure_ryadom_pointer(id);
    whiteboard::update_whiteboard(
        whiteboard::get_key_cursor(id),
        CustomEvent::Cursor(Cursor {
            x: event.x as f32,
            y: event.y as f32,
            argb: POINTER_ORANGE,
            btns: if event.mask == 10 { 1 } else { 0 },
            text: name.chars().filter(|c| !c.is_control()).take(60).collect(),
        }),
    );
}

pub fn peer_short_code(additions: &str) -> Option<String> {
    let value: serde_json::Value = serde_json::from_str(additions).ok()?;
    let code = value["ryadom_short_code"].as_str()?;
    super::short_code::valid(code).then(|| code.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn history_keeps_only_an_actual_nine_digit_code() {
        assert_eq!(peer_short_code(r#"{"ryadom_short_code":"123456789"}"#), Some("123456789".into()));
        for value in ["", "{}", r#"{"ryadom_short_code":"012345678"}"#, r#"{"ryadom_short_code":"ryadom-123"}"#] {
            assert_eq!(peer_short_code(value), None);
        }
    }
    #[test]
    fn automatic_software_codec_prefers_vp8_and_preserves_manual_choices() {
        use base::message_proto::{supported_decoding::PreferCodec, SupportedDecoding};
        let auto = SupportedDecoding {
            ability_vp8: 1,
            ..Default::default()
        };
        assert_eq!(
            low_latency_decoding(auto.clone()).prefer.enum_value(),
            Ok(PreferCodec::VP8)
        );
        let full_color = SupportedDecoding {
            prefer_chroma: base::message_proto::Chroma::I444.into(),
            ..auto.clone()
        };
        assert_eq!(
            low_latency_decoding(full_color).prefer.enum_value(),
            Ok(PreferCodec::Auto)
        );
        let manual = SupportedDecoding {
            prefer: PreferCodec::VP9.into(),
            ..auto
        };
        assert_eq!(
            low_latency_decoding(manual).prefer.enum_value(),
            Ok(PreferCodec::VP9)
        );
        assert_eq!(
            low_latency_decoding(SupportedDecoding::default())
                .prefer
                .enum_value(),
            Ok(PreferCodec::Auto)
        );
    }
    #[test]
    fn no_configured_password_waits_for_owner_and_ignores_old_saved_password() {
        let mut hash = Hash {
            ryadom_auth_version: 1,
            ..Default::default()
        };
        let mut password = vec![1, 2, 3];
        assert!(request_approval(&hash, &mut password, false));
        assert!(password.is_empty());
        hash.ryadom_password_set = true;
        assert!(!request_approval(&hash, &mut password, false));
        assert!(request_approval(&hash, &mut password, true));
        assert_eq!(cursor_option("show-remote-cursor", false), Some(true));
        assert_eq!(cursor_option("show-my-cursor", true), Some(true));
        assert_eq!(cursor_option("show-my-cursor", false), Some(false));
    }
    #[test]
    fn pointing_only_accepts_absolute_movement_and_visual_left_click() {
        for mask in [0, 10] {
            assert!(pointing_event(&MouseEvent {
                mask,
                x: 100,
                y: -50,
                ..Default::default()
            }));
        }
        for mask in [1, 2, 3, 4, 9, 18] {
            assert!(!pointing_event(&MouseEvent {
                mask,
                ..Default::default()
            }));
        }
        assert!(!pointing_event(&MouseEvent {
            x: i32::MAX,
            ..Default::default()
        }));
    }
}
