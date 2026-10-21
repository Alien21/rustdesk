use hbb_common::{
    anyhow::{bail, Context},
    base64::{engine::general_purpose::STANDARD, Engine as _},
    config::{Config, CONNECT_TIMEOUT, RELAY_PORT, RENDEZVOUS_PORT},
    sodiumoxide::crypto::sign,
    tcp::FramedStream,
    tokio::{
        self,
        time::{interval, Duration},
    },
    ResultType, Stream,
};
use serde_json::{json, Value};
use std::{
    net::SocketAddr,
    time::{Instant, SystemTime, UNIX_EPOCH},
};

use crate::access_transport::{self, AccessStream};

#[derive(Clone, Debug, serde_derive::Serialize, serde_derive::Deserialize)]
pub struct Invitation {
    pub id: String,
    pub expires_at: u64,
    pub server: String,
}

#[derive(Clone, Debug)]
pub struct SessionContext {
    pub uuid: String,
    pub identity: String,
    pub guest: bool,
    pub expires_at: u64,
    server: String,
    key: String,
}

#[derive(serde_derive::Deserialize)]
struct Session {
    uuid: String,
    id: String,
    expires_at: u64,
    relay_server: String,
    ticket: String,
    guest: bool,
    peer_addr: String,
    #[serde(default)]
    certificate: String,
}

fn now() -> ResultType<u64> {
    Ok(SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs())
}

pub fn is_invitation_id(id: &str) -> bool {
    id.len() == 11 && id.starts_with("P-") && id[2..].bytes().all(|c| c.is_ascii_digit())
}

fn endpoint(server: &str, port: i32) -> ResultType<String> {
    let url = if server.contains("://") {
        url::Url::parse(server)?
    } else {
        url::Url::parse(&format!("http://{server}"))?
    };
    if !url.username().is_empty() || url.password().is_some() {
        bail!("Private server endpoints must not contain credentials");
    }
    let host = url
        .host_str()
        .context("Private server hostname is missing")?;
    let base = url.port().map(i32::from).unwrap_or(port);
    let port = u16::try_from(base).context("Private server port is invalid")?;
    Ok(format!("{host}:{port}"))
}

async fn open(server: &str, key: &str, port: i32) -> ResultType<(AccessStream, SocketAddr)> {
    let address = endpoint(server, port)?;
    let stream = if let Some(proxy) = Config::get_socks() {
        FramedStream::connect(address.as_str(), None, &proxy, CONNECT_TIMEOUT).await?
    } else {
        FramedStream::new(&address, None, CONNECT_TIMEOUT).await?
    };
    let local_addr = stream.local_addr();
    let key = STANDARD
        .decode(key)
        .context("Invalid private server public key")?;
    let access =
        hbb_common::timeout(CONNECT_TIMEOUT, access_transport::connect_framed(stream, &key)).await??;
    Ok((access, local_addr))
}

fn signing_key() -> ResultType<sign::SecretKey> {
    sign::SecretKey::from_slice(&Config::get_key_pair().0)
        .context("Device signing key is unavailable")
}

fn signature(domain: &[u8], binding: &[u8], first: &[u8], last: &[u8]) -> ResultType<String> {
    let mut message =
        Vec::with_capacity(domain.len() + binding.len() + first.len() + last.len() + 1);
    message.extend_from_slice(domain);
    message.extend_from_slice(binding);
    message.extend_from_slice(first);
    message.push(0);
    message.extend_from_slice(last);
    Ok(STANDARD.encode(sign::sign_detached(&message, &signing_key()?).as_ref()))
}

async fn receive(stream: &mut AccessStream) -> ResultType<Value> {
    let response: Value =
        hbb_common::timeout(CONNECT_TIMEOUT, access_transport::recv_json(stream)).await??;
    if response["op"] == "error" {
        bail!(
            "{}",
            response["error"]
                .as_str()
                .unwrap_or("Private server request was rejected")
        );
    }
    Ok(response)
}

async fn control(server: &str, key: &str, secret: &str) -> ResultType<AccessStream> {
    if secret.is_empty() {
        bail!("Private server access key is not configured");
    }
    let (mut stream, _) = open(server, key, RENDEZVOUS_PORT).await?;
    let id = Config::get_id();
    let device_key = Config::get_key_pair().1;
    let proof = signature(
        b"rustdesk-access-auth-v1\0",
        &stream.binding(),
        id.as_bytes(),
        &device_key,
    )?;
    access_transport::send_json(
        &mut stream,
        &json!({
            "op":"auth", "access_key":secret, "id":id,
            "device_key":STANDARD.encode(&device_key), "signature":proof
        }),
    )
    .await?;
    if receive(&mut stream).await?["op"] != "ok" {
        bail!("Private server authentication was not acknowledged");
    }
    Ok(stream)
}

async fn rpc(server: &str, key: &str, secret: &str, request: Value) -> ResultType<Value> {
    let mut stream = control(server, key, secret).await?;
    access_transport::send_json(&mut stream, &request).await?;
    receive(&mut stream).await
}

async fn ui_rpc(request: Value) -> ResultType<Value> {
    let server = Config::get_rendezvous_server();
    let secret = crate::access_config::connection_secret_for(&server).await?;
    let key = crate::get_key_with_dns(crate::is_server()).await?;
    rpc(&server, &key, &secret, request).await
}

pub async fn create_invitation(minutes: u32) -> ResultType<Invitation> {
    if !crate::access_config::invitations_enabled() {
        bail!("Guest invitations are disabled");
    }
    let response = ui_rpc(json!({"op":"create_invitation", "minutes":minutes})).await?;
    parse_invitation(response)?.context("The server did not create an invitation")
}

fn parse_invitation(response: Value) -> ResultType<Option<Invitation>> {
    if response["op"] != "invitation" {
        bail!("Invalid invitation response");
    }
    let id = response["id"]
        .as_str()
        .context("Invitation ID is missing")?;
    if id.is_empty() {
        return Ok(None);
    }
    if !is_invitation_id(id) {
        bail!("Invalid invitation ID");
    }
    Ok(Some(Invitation {
        id: id.to_owned(),
        expires_at: response["expires_at"]
            .as_u64()
            .context("Invitation expiry is missing")?,
        server: Config::get_rendezvous_server(),
    }))
}

pub async fn current_invitation() -> ResultType<Option<Invitation>> {
    parse_invitation(ui_rpc(json!({"op":"invitation_status"})).await?)
}

pub async fn revoke_invitation() -> ResultType<()> {
    ui_rpc(json!({"op":"revoke_invitation", "id":""})).await?;
    Ok(())
}

pub async fn validate_admission(context: &SessionContext) -> ResultType<()> {
    if !crate::access_config::configured() {
        bail!("Private server access configuration changed");
    }
    let secret = crate::access_config::connection_secret_for(&context.server).await?;
    if secret.is_empty() {
        bail!("Private server access key is not configured");
    }
    if !context.guest {
        return Ok(());
    }
    if !crate::access_config::invitations_enabled() || now()? >= context.expires_at {
        bail!("Guest invitation expired or was revoked");
    }
    let response = rpc(
        &context.server,
        &context.key,
        &secret,
        json!({"op":"validate_invitation", "id":context.identity, "uuid":context.uuid}),
    )
    .await?;
    if response["op"] != "valid"
        || response["valid"] != true
        || !crate::access_config::invitations_enabled()
        || now()? >= context.expires_at
    {
        bail!("Guest invitation expired or was revoked");
    }
    Ok(())
}

async fn relay(session: &Session, key: &str, secret: &str, role: &str) -> ResultType<Stream> {
    if session.uuid.is_empty() || session.ticket.is_empty() {
        bail!("Private relay session is missing its authorization ticket");
    }
    let (mut stream, local_addr) = open(&session.relay_server, key, RELAY_PORT).await?;
    let proof = signature(
        b"rustdesk-access-relay-v1\0",
        &stream.binding(),
        role.as_bytes(),
        session.ticket.as_bytes(),
    )?;
    access_transport::send_json(
        &mut stream,
        &json!({
            "op":"relay", "access_key":secret, "ticket":session.ticket,
            "role":role, "signature":proof
        }),
    )
    .await?;
    if receive(&mut stream).await?["op"] != "ok" {
        bail!("Private relay authorization was not acknowledged");
    }
    Ok(Stream::Tcp(FramedStream::from(stream, local_addr)))
}

pub async fn connect_owned(
    server: &str,
    target: &str,
    key: &str,
    secret: &str,
) -> ResultType<(Stream, Vec<u8>)> {
    let response = rpc(server, key, secret, json!({"op":"connect", "id":target})).await?;
    if response["op"] != "session" {
        bail!("Invalid private server connection response");
    }
    let session: Session = serde_json::from_value(response)?;
    if session.id != target || (session.guest && !is_invitation_id(target)) {
        bail!("Private server returned a different target identity");
    }
    let certificate = STANDARD
        .decode(&session.certificate)
        .context("Private target certificate is invalid")?;
    if certificate.is_empty() {
        bail!("Private target certificate is missing");
    }
    Ok((
        relay(&session, key, secret, "controller").await?,
        certificate,
    ))
}

#[cfg(not(target_os = "ios"))]
async fn serve_session(
    server: crate::server::ServerPtr,
    host: String,
    key: String,
    secret: String,
    session: Session,
) -> ResultType<()> {
    if session.guest {
        if !is_invitation_id(&session.id)
            || !crate::access_config::invitations_enabled()
            || now()? >= session.expires_at
        {
            bail!("Guest invitation is not active");
        }
    } else if session.id != Config::get_id() {
        bail!("Private session targets a different device");
    }
    let peer_addr = session
        .peer_addr
        .parse()
        .context("Invalid private session peer address")?;
    let stream = relay(&session, &key, &secret, "host").await?;
    let context = SessionContext {
        uuid: session.uuid,
        identity: session.id,
        guest: session.guest,
        expires_at: session.expires_at,
        server: host,
        key,
    };
    crate::server::create_tcp_connection(
        server,
        stream,
        peer_addr,
        true,
        crate::server::ConnectionMeta {
            server_access: Some(context),
            ..Default::default()
        },
    )
    .await
}

#[cfg(not(target_os = "ios"))]
pub async fn run_host(
    server: crate::server::ServerPtr,
    host: String,
    restart: &std::sync::atomic::AtomicBool,
) -> ResultType<()> {
    let secret = crate::access_config::connection_secret_for(&host).await?;
    let key = crate::get_key_with_dns(true).await?;
    let started = Instant::now();
    let mut stream = control(&host, &key, &secret).await?;
    access_transport::send_json(&mut stream, &json!({"op":"register"})).await?;
    if receive(&mut stream).await?["op"] != "registered" {
        bail!("Private host registration was not acknowledged");
    }
    Config::set_key_confirmed(true);
    Config::update_latency(&host, started.elapsed().as_micros().max(1) as i64);
    let (mut reader, mut writer) = tokio::io::split(stream);
    let mut heartbeat = interval(Duration::from_secs(5));
    loop {
        let mut incoming = Box::pin(tokio::time::timeout(
            Duration::from_secs(20),
            access_transport::recv_json::<_, Value>(&mut reader),
        ));
        let response = loop {
            tokio::select! {
                response = &mut incoming => break response??,
                _ = heartbeat.tick() => {
                    if restart.load(std::sync::atomic::Ordering::SeqCst)
                        || !crate::access_config::configured()
                        || crate::access_config::connection_secret_for(&host).await? != secret {
                        return Ok(());
                    }
                    access_transport::send_json(&mut writer, &json!({"op":"ping"})).await?;
                }
            }
        };
        drop(incoming);
        match response["op"].as_str() {
            Some("session") => {
                let session: Session = serde_json::from_value(response)?;
                let (server, host, key, secret) =
                    (server.clone(), host.clone(), key.clone(), secret.clone());
                tokio::spawn(async move {
                    if let Err(err) = serve_session(server, host, key, secret, session).await {
                        hbb_common::throttled_log!(
                            Duration::from_secs(30),
                            warn,
                            "Private session rejected: {}",
                            err
                        );
                    }
                });
            }
            Some("pong") => {}
            Some("error") => bail!(
                "{}",
                response["error"]
                    .as_str()
                    .unwrap_or("Private host control failed")
            ),
            _ => bail!("Invalid private host control message"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invitation_ids_require_the_reserved_prefix_and_nine_digits() {
        assert!(is_invitation_id("P-123456789"));
        for id in [
            "123456789",
            "P-12345678",
            "P-1234567890",
            "p-123456789",
            "P-12345678x",
        ] {
            assert!(!is_invitation_id(id), "{id}");
        }
    }

    #[test]
    fn private_endpoints_use_the_existing_server_port() {
        assert_eq!(endpoint("example.com", RELAY_PORT).unwrap(), "example.com:21117");
        assert_eq!(endpoint("example.com:32116", RENDEZVOUS_PORT).unwrap(), "example.com:32116");
        assert_eq!(
            endpoint("example.com", RENDEZVOUS_PORT).unwrap(),
            "example.com:21116"
        );
        assert_eq!(
            endpoint("example.com:21117", RELAY_PORT).unwrap(),
            "example.com:21117"
        );
        assert_eq!(
            endpoint("wss://example.com/ws", RENDEZVOUS_PORT).unwrap(),
            "example.com:21116"
        );
        assert_eq!(endpoint("example.com:65535", RENDEZVOUS_PORT).unwrap(), "example.com:65535");
        assert!(endpoint("example.com:65536", RENDEZVOUS_PORT).is_err());
        assert!(endpoint("http://name:secret@example.com", RENDEZVOUS_PORT).is_err());
    }
}
