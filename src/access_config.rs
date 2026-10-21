use hbb_common::{anyhow, config::Config, password_security, ResultType};
use serde_derive::{Deserialize, Serialize};
use std::{fmt, fs, sync::Mutex};

pub const IPC_CAPABILITY: &str = "server-access-v1";

static STORE_LOCK: Mutex<()> = Mutex::new(());

#[derive(Default, Serialize, Deserialize)]
struct Stored {
    server: String,
    secret: Vec<u8>,
    enabled: bool,
    minutes: u32,
}

#[derive(Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum UiRequest {
    Status,
    Save {
        server: String,
        secret: Option<String>,
        clear: bool,
        enabled: bool,
        minutes: u32,
    },
    Create,
    Revoke,
}

#[derive(Serialize, Deserialize, Clone)]
pub enum IpcRequest {
    Ui(String),
    Credentials(String),
    Reply(String),
}

impl fmt::Debug for IpcRequest {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("ServerAccess(<redacted>)")
    }
}

fn server() -> String {
    crate::get_custom_rendezvous_server(Config::get_option("custom-rendezvous-server"))
}

fn same_server(a: &str, b: &str) -> bool {
    fn authority(value: &str) -> Option<(String, u16)> {
        if value.trim().is_empty() {
            return None;
        }
        let value = value.trim();
        let url = url::Url::parse(&if value.contains("://") {
            value.to_owned()
        } else {
            format!("tcp://{value}")
        })
        .ok()?;
        if !url.username().is_empty() || url.password().is_some() {
            return None;
        }
        Some((
            url.host_str()?.trim_end_matches('.').to_ascii_lowercase(),
            url.port().unwrap_or(21116),
        ))
    }
    match (authority(a), authority(b)) {
        (Some(a), Some(b)) => a == b,
        (None, None) => a.trim().is_empty() && b.trim().is_empty(),
        _ => false,
    }
}

fn load() -> ResultType<Stored> {
    let path = Config::file().with_extension("access.json");
    match fs::read(path) {
        Ok(data) => Ok(serde_json::from_slice(&data)?),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(Stored {
            minutes: 10,
            ..Default::default()
        }),
        Err(err) => Err(err.into()),
    }
}

pub fn configured() -> bool {
    match load() {
        Ok(value) => same_server(&value.server, &server()) && !value.secret.is_empty(),
        Err(_) => true,
    }
}

pub fn secret() -> ResultType<String> {
    let value = load()?;
    if !same_server(&value.server, &server()) || value.secret.is_empty() {
        return Ok(String::new());
    }
    decrypt_secret(&value.secret)
}

fn decrypt_secret(ciphertext: &[u8]) -> ResultType<String> {
    let data = password_security::symmetric_crypt(ciphertext, false).map_err(|_| {
        anyhow::anyhow!("Private key could not be decrypted; enter it again in network settings")
    })?;
    Ok(String::from_utf8(data)?)
}

pub fn invitations_enabled() -> bool {
    load()
        .map(|v| same_server(&v.server, &server()) && !v.secret.is_empty() && v.enabled)
        .unwrap_or(false)
}

pub fn invitation_minutes() -> u32 {
    load().map(|v| v.minutes.clamp(1, 1440)).unwrap_or(10)
}

fn save(
    server: String,
    secret: Option<String>,
    clear: bool,
    enabled: bool,
    minutes: u32,
) -> ResultType<()> {
    anyhow::ensure!(
        (1..=1440).contains(&minutes),
        "Invitation validity must be between 1 and 1440 minutes"
    );
    anyhow::ensure!(
        !server.trim().is_empty() || (secret.is_none() && !enabled),
        "Enter an ID server before a private key"
    );
    anyhow::ensure!(
        same_server(&server, &self::server()),
        "Save the ID server before the private key"
    );
    let _guard = STORE_LOCK.lock().unwrap();
    let mut value = load()?;
    if clear || !same_server(&server, &value.server) {
        value.secret.clear();
    }
    if let Some(secret) = secret {
        anyhow::ensure!(
            !secret.is_empty() && secret.len() <= 1024,
            "Private key must contain 1 to 1024 bytes"
        );
        value.secret = password_security::symmetric_crypt(secret.as_bytes(), true)
            .map_err(|_| anyhow::anyhow!("Private key could not be encrypted"))?;
    }
    anyhow::ensure!(
        !enabled || !value.secret.is_empty(),
        "Enter a private key before enabling guest invitations"
    );
    value.server = server;
    value.enabled = enabled;
    value.minutes = minutes;
    let path = Config::file().with_extension("access.json");
    let temporary = path.with_extension("access.tmp");
    let data = serde_json::to_vec(&value)?;
    use std::io::Write;
    let mut options = fs::OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options.open(&temporary)?;
    file.write_all(&data)?;
    file.sync_all()?;
    drop(file);
    fs::rename(&temporary, path)?;
    Ok(())
}

async fn dispatch(request: UiRequest) -> ResultType<serde_json::Value> {
    match request {
        UiRequest::Status => Ok(
            serde_json::json!({"available": true, "has_secret": configured(), "enabled": invitations_enabled(), "minutes": invitation_minutes()}),
        ),
        UiRequest::Save {
            server,
            secret,
            clear,
            enabled,
            minutes,
        } => {
            save(server, secret, clear, enabled, minutes)?;
            #[cfg(not(target_os = "ios"))]
            crate::rendezvous_mediator::RendezvousMediator::restart();
            Ok(serde_json::json!({}))
        }
        UiRequest::Create => {
            anyhow::ensure!(invitations_enabled(), "Guest invitations are disabled");
            let key = crate::get_key_with_dns(true).await?;
            anyhow::ensure!(
                !key.is_empty(),
                "The public server key is required for guest invitations"
            );
            let invitation = crate::server_access::create_invitation(invitation_minutes()).await?;
            let data = serde_json::to_value(invitation)?;
            let id = data
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| anyhow::anyhow!("Invitation ID is missing"))?;
            Ok(
                serde_json::json!({"address": format!("{}@{}?key={}", id, server(), key), "invitation": data}),
            )
        }
        UiRequest::Revoke => {
            crate::server_access::revoke_invitation().await?;
            Ok(serde_json::json!({}))
        }
    }
}

pub async fn handle(request: IpcRequest) -> IpcRequest {
    let result: ResultType<serde_json::Value> = match request {
        IpcRequest::Credentials(target) => {
            scoped_secret(&target).map(|v| serde_json::json!({"secret": v}))
        }
        IpcRequest::Ui(json) => match serde_json::from_str::<UiRequest>(&json) {
            Ok(request) => dispatch(request).await,
            Err(err) => Err(err.into()),
        },
        IpcRequest::Reply(_) => Err(anyhow::anyhow!("Invalid server access request")),
    };
    IpcRequest::Reply(match result {
        Ok(value) => serde_json::json!({"ok": true, "value": value}).to_string(),
        Err(err) => serde_json::json!({"ok": false, "error": err.to_string()}).to_string(),
    })
}

async fn request(request: IpcRequest) -> ResultType<serde_json::Value> {
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    let reply = {
        let mut connection = match crate::ipc::connect(1000, "").await {
            Ok(connection) => connection,
            Err(_) => return unsupported_service(&request, configured(), &server()),
        };
        // Older services understand Config queries and reply None for unknown names.
        if connection
            .send(&crate::ipc::Data::Config((IPC_CAPABILITY.to_owned(), None)))
            .await
            .is_err()
        {
            return unsupported_service(&request, configured(), &server());
        }
        let supported = matches!(
            connection.next_timeout(2_000).await,
            Ok(Some(crate::ipc::Data::Config((name, Some(version)))))
                if name == IPC_CAPABILITY && version == "1"
        );
        if !supported {
            return unsupported_service(&request, configured(), &server());
        }
        connection
            .send(&crate::ipc::Data::ServerAccess(request))
            .await?;
        match connection.next_timeout(15_000).await? {
            Some(crate::ipc::Data::ServerAccess(IpcRequest::Reply(json))) => json,
            _ => anyhow::bail!("Server access service did not reply"),
        }
    };
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let reply = match handle(request).await {
        IpcRequest::Reply(json) => json,
        _ => anyhow::bail!("Invalid server access reply"),
    };
    let reply: serde_json::Value = serde_json::from_str(&reply)?;
    anyhow::ensure!(
        reply.get("ok").and_then(|v| v.as_bool()) == Some(true),
        "{}",
        reply
            .get("error")
            .and_then(|v| v.as_str())
            .unwrap_or("Server access request failed")
    );
    Ok(reply.get("value").cloned().unwrap_or_default())
}

fn unsupported_service(
    request: &IpcRequest,
    private_configured: bool,
    current_server: &str,
) -> ResultType<serde_json::Value> {
    match request {
        IpcRequest::Credentials(target) if !private_configured || !same_server(target, current_server) => Ok(serde_json::json!({"secret": ""})),
        IpcRequest::Ui(json) if matches!(serde_json::from_str::<UiRequest>(json), Ok(UiRequest::Status)) => {
            Ok(serde_json::json!({"available": false, "has_secret": false, "enabled": false, "minutes": 10}))
        }
        _ => anyhow::bail!("Install or restart the updated RustDesk client service to use private keys and guest invitations"),
    }
}

fn scoped_secret(target: &str) -> ResultType<String> {
    if !same_server(target, &server()) {
        return Ok(String::new());
    }
    let value = load()?;
    if value.secret.is_empty() || !same_server(&value.server, target) {
        return Ok(String::new());
    }
    decrypt_secret(&value.secret)
}

pub async fn connection_secret() -> ResultType<String> {
    connection_secret_for(&server()).await
}

pub async fn connection_secret_for(target: &str) -> ResultType<String> {
    #[cfg(any(target_os = "android", target_os = "ios"))]
    return scoped_secret(target);
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    {
        if crate::is_server() {
            return scoped_secret(target);
        }
        let value = request(IpcRequest::Credentials(target.to_owned())).await?;
        Ok(value
            .get("secret")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_owned())
    }
}

pub async fn ui_request(json: String) -> String {
    // UI commands deliberately have no credential-reading operation.
    let result = match serde_json::from_str::<UiRequest>(&json) {
        Ok(_) => request(IpcRequest::Ui(json)).await,
        Err(err) => Err(err.into()),
    };
    match result {
        Ok(value) => serde_json::json!({"ok": true, "value": value}).to_string(),
        Err(err) => serde_json::json!({"ok": false, "error": err.to_string()}).to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn credential_scope_compares_authority_and_effective_port() {
        assert!(same_server("Example.com.", "example.com:21116"));
        assert!(!same_server("example.com", "other.example.com"));
        assert!(!same_server("example.com:21116", "example.com:21117"));
        assert!(!same_server("example.com", "user@example.com"));
    }

    #[test]
    fn ui_cannot_read_credentials_and_ipc_debug_is_redacted() {
        assert!(serde_json::from_str::<UiRequest>(r#"{"action":"credentials"}"#).is_err());
        let request = IpcRequest::Ui("sensitive value".into());
        assert_eq!(format!("{request:?}"), "ServerAccess(<redacted>)");
    }
    #[test]
    fn old_service_preserves_regular_connections_and_reports_feature_availability() {
        assert_eq!(unsupported_service(&IpcRequest::Credentials("example.com".into()), false, "example.com").unwrap()["secret"], "");
        assert!(unsupported_service(&IpcRequest::Credentials("example.com".into()), true, "example.com").is_err());
        assert_eq!(unsupported_service(&IpcRequest::Credentials("other.example.com".into()), true, "example.com").unwrap()["secret"], "");
        assert_eq!(unsupported_service(&IpcRequest::Ui(r#"{"action":"status"}"#.into()), false, "example.com").unwrap()["available"], false);
        assert!(unsupported_service(&IpcRequest::Ui(r#"{"action":"create"}"#.into()), false, "example.com").unwrap_err().to_string().contains("updated RustDesk client service"));
    }

}
