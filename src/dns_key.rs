use hbb_common::{
    anyhow::{anyhow, bail, Context},
    base64::{engine::general_purpose::STANDARD, Engine as _},
    config::Config,
    ResultType,
};
use serde_json::Value;
use std::{
    collections::HashMap,
    sync::Mutex,
    time::{Duration, Instant},
};

const DOH_URL: &str = "https://cloudflare-dns.com/dns-query";
const MAX_RESPONSE_BYTES: usize = 16 * 1024;
const MAX_CACHE_ENTRIES: usize = 64;
const MAX_TTL: u64 = 300;
const ERROR_TTL: u64 = 30;

struct CachedKey {
    result: Result<String, String>,
    expires: Instant,
}

lazy_static::lazy_static! {
    static ref CACHE: Mutex<HashMap<String, CachedKey>> = Mutex::new(HashMap::new());
}

pub async fn resolve(server: &str, explicit_key: &str) -> ResultType<String> {
    if !explicit_key.is_empty() {
        return Ok(explicit_key.to_owned());
    }
    let name = format!("_rustdesk.{}", hostname(server)?);
    {
        let mut cache = CACHE
            .lock()
            .map_err(|_| anyhow!("DNS key cache unavailable"))?;
        cache.retain(|_, entry| entry.expires > Instant::now());
        if let Some(entry) = cache.get(&name) {
            return entry.result.clone().map_err(|err| anyhow!(err));
        }
    }

    let result = fetch(&name).await.with_context(|| {
        format!("DNS public key discovery failed for {name}; enter Key explicitly")
    });
    let (cached_result, ttl) = match &result {
        Ok((key, ttl)) => (Ok(key.clone()), *ttl),
        Err(err) => (Err(format!("{err:#}")), ERROR_TTL),
    };
    if ttl > 0 {
        let mut cache = CACHE
            .lock()
            .map_err(|_| anyhow!("DNS key cache unavailable"))?;
        cache.retain(|_, entry| entry.expires > Instant::now());
        if cache.len() >= MAX_CACHE_ENTRIES && !cache.contains_key(&name) {
            if let Some(oldest) = cache
                .iter()
                .min_by_key(|(_, entry)| entry.expires)
                .map(|(name, _)| name.clone())
            {
                cache.remove(&oldest);
            }
        }
        cache.insert(
            name,
            CachedKey {
                result: cached_result,
                expires: Instant::now() + Duration::from_secs(ttl),
            },
        );
    }
    result.map(|(key, _)| key)
}

fn hostname(server: &str) -> ResultType<String> {
    let server = server.trim();
    let url = if server.contains("://") {
        let parsed = url::Url::parse(server)?;
        if !matches!(parsed.scheme(), "ws" | "wss") {
            bail!("DNS key discovery requires a hostname or a ws/wss server URL");
        }
        parsed
    } else {
        let parsed = url::Url::parse(&format!("https://{server}"))?;
        if parsed.path() != "/" || parsed.query().is_some() || parsed.fragment().is_some() {
            bail!("Invalid ID server hostname");
        }
        parsed
    };
    if !url.username().is_empty() || url.password().is_some() || url.port() == Some(0) {
        bail!("Invalid ID server hostname");
    }
    let host = match url.host() {
        Some(url::Host::Domain(host)) => {
            host.strip_suffix('.').unwrap_or(host).to_ascii_lowercase()
        }
        _ => bail!("DNS key discovery requires a public DNS hostname; enter Key explicitly"),
    };
    if !host.contains('.')
        || host.len() + "_rustdesk.".len() > 253
        || host.split('.').any(|label| {
            label.is_empty()
                || label.len() > 63
                || label.starts_with('-')
                || label.ends_with('-')
                || !label
                    .bytes()
                    .all(|c| c.is_ascii_alphanumeric() || c == b'-')
        })
        || host == "home.arpa"
        || host.ends_with(".home.arpa")
        || [
            "local",
            "localhost",
            "localdomain",
            "lan",
            "home",
            "internal",
            "invalid",
            "test",
            "onion",
        ]
        .iter()
        .any(|suffix| host.ends_with(&format!(".{suffix}")))
    {
        bail!("DNS key discovery requires a public DNS hostname; enter Key explicitly");
    }
    Ok(host)
}

async fn fetch(name: &str) -> ResultType<(String, u64)> {
    let mut builder = reqwest::Client::builder()
        .use_rustls_tls()
        .https_only(true)
        .redirect(reqwest::redirect::Policy::none())
        .connect_timeout(Duration::from_secs(5))
        .timeout(Duration::from_secs(10))
        .no_proxy();
    if let Some(config) = Config::get_socks() {
        let address = if config.proxy.contains("://") {
            config.proxy
        } else {
            format!("socks5h://{}", config.proxy)
        };
        let mut proxy = reqwest::Proxy::all(address).context("Invalid configured DNS proxy")?;
        if !config.username.is_empty() && !config.password.is_empty() {
            proxy = proxy.basic_auth(&config.username, &config.password);
        }
        builder = builder.proxy(proxy);
    }
    let mut response = builder
        .build()?
        .get(DOH_URL)
        .header(reqwest::header::ACCEPT, "application/dns-json")
        .query(&[
            ("name", name),
            ("type", "TXT"),
            ("do", "true"),
            ("cd", "false"),
        ])
        .send()
        .await?
        .error_for_status()?;
    if !response.status().is_success() {
        bail!("DNS resolver redirected the request");
    }
    if response
        .content_length()
        .map_or(false, |length| length > MAX_RESPONSE_BYTES as u64)
    {
        bail!("DNS response exceeds the size limit");
    }
    let age = response
        .headers()
        .get(reqwest::header::AGE)
        .map(|value| {
            value
                .to_str()
                .context("Invalid DNS HTTP age")?
                .parse::<u64>()
                .context("Invalid DNS HTTP age")
        })
        .transpose()?
        .unwrap_or(0);
    let mut body = Vec::new();
    while let Some(chunk) = response.chunk().await? {
        if chunk.len() > MAX_RESPONSE_BYTES - body.len() {
            bail!("DNS response exceeds the size limit");
        }
        body.extend_from_slice(&chunk);
    }
    let (key, ttl) = validate_response(name, &serde_json::from_slice(&body)?)?;
    Ok((key, ttl.saturating_sub(age)))
}

fn same_name(a: &str, b: &str) -> bool {
    a.strip_suffix('.')
        .unwrap_or(a)
        .eq_ignore_ascii_case(b.strip_suffix('.').unwrap_or(b))
}

fn validate_response(name: &str, response: &Value) -> ResultType<(String, u64)> {
    if response["Status"].as_u64() != Some(0)
        || response["AD"].as_bool() != Some(true)
        || response["CD"].as_bool() != Some(false)
        || response["TC"].as_bool() != Some(false)
    {
        bail!("DNS response was not authenticated with DNSSEC");
    }
    let questions = response["Question"]
        .as_array()
        .context("DNS question missing")?;
    if questions.len() != 1
        || questions[0]["type"].as_u64() != Some(16)
        || !questions[0]["name"]
            .as_str()
            .map_or(false, |value| same_name(value, name))
    {
        bail!("DNS response does not match the requested TXT record");
    }
    let answers = response["Answer"]
        .as_array()
        .context("No DNS public key record found")?;
    let mut key = None;
    let mut ttl = MAX_TTL;
    for answer in answers {
        if answer["type"].as_u64() != Some(16)
            || !answer["name"]
                .as_str()
                .map_or(false, |value| same_name(value, name))
        {
            continue;
        }
        let value = decode_txt(answer["data"].as_str().context("Invalid DNS TXT value")?)?;
        let candidate = parse_record(&value)?;
        if key.as_ref().map_or(false, |key| key != &candidate) {
            bail!("DNS public key record is ambiguous");
        }
        key = Some(candidate);
        ttl = ttl.min(answer["TTL"].as_u64().context("Invalid DNS record TTL")?);
    }
    Ok((key.context("No DNS public key record found")?, ttl))
}

fn parse_record(record: &str) -> ResultType<String> {
    let mut fields = record.split(';').map(str::trim);
    if fields.next() != Some("v=1") {
        bail!("Unsupported DNS public key record; expected v=1;key=<public key>");
    }
    let key = fields
        .next()
        .and_then(|field| field.strip_prefix("key="))
        .context("DNS public key record has no key")?;
    if fields.next().is_some()
        || STANDARD
            .decode(key)
            .context("Invalid DNS public key encoding")?
            .len()
            != 32
    {
        bail!("Invalid DNS public key; expected a base64 encoded 32 byte public key");
    }
    Ok(key.to_owned())
}

fn decode_txt(value: &str) -> ResultType<String> {
    let bytes = value.as_bytes();
    let mut index = 0;
    let mut decoded = Vec::new();
    let mut segments = 0;
    while index < bytes.len() {
        if bytes[index].is_ascii_whitespace() {
            index += 1;
            continue;
        }
        if bytes[index] != b'"' {
            bail!("Invalid quoted DNS TXT record");
        }
        segments += 1;
        index += 1;
        loop {
            let byte = *bytes.get(index).context("Unterminated DNS TXT record")?;
            index += 1;
            match byte {
                b'"' => break,
                b'\\' => {
                    let escaped = *bytes.get(index).context("Incomplete DNS TXT escape")?;
                    if escaped.is_ascii_digit() {
                        let digits = bytes
                            .get(index..index + 3)
                            .context("Invalid DNS TXT escape")?;
                        if !digits.iter().all(u8::is_ascii_digit) {
                            bail!("Invalid DNS TXT escape");
                        }
                        let code = u16::from(digits[0] - b'0') * 100
                            + u16::from(digits[1] - b'0') * 10
                            + u16::from(digits[2] - b'0');
                        decoded.push(u8::try_from(code).context("Invalid DNS TXT escape")?);
                        index += 3;
                    } else {
                        decoded.push(escaped);
                        index += 1;
                    }
                }
                _ => decoded.push(byte),
            }
        }
    }
    if segments == 0 {
        bail!("Empty DNS TXT record");
    }
    Ok(String::from_utf8(decoded)?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn response(key: &[u8]) -> Value {
        json!({
            "Status": 0, "AD": true, "CD": false, "TC": false,
            "Question": [{"name": "_rustdesk.example.com.", "type": 16}],
            "Answer": [{"name": "_rustdesk.example.com.", "type": 16, "TTL": 600,
                "data": format!("\"v=1;key={}\"", STANDARD.encode(key))}]
        })
    }

    #[test]
    fn normalizes_public_server_names_and_rejects_local_addresses() {
        assert_eq!(hostname("Example.COM.:21116").unwrap(), "example.com");
        assert_eq!(
            hostname("wss://BÜCHER.de:443/ws").unwrap(),
            "xn--bcher-kva.de"
        );
        for server in [
            "127.0.0.1:21116",
            "[::1]:21116",
            "localhost",
            "server.lan",
            "server.home.arpa",
            "bad..example.com",
            "https://example.com",
            "name@example.com",
        ] {
            assert!(hostname(server).is_err(), "{server}");
        }
    }

    #[test]
    fn joins_txt_segments_and_dns_escapes_without_joining_records() {
        let key = STANDARD.encode([7u8; 32]);
        let quoted = format!(r#""v=\049;" "key={key}""#);
        assert_eq!(parse_record(&decode_txt(&quoted).unwrap()).unwrap(), key);
        for value in [r#""v=1"garbage"#, r#""unterminated"#, r#""\999""#] {
            assert!(decode_txt(value).is_err());
        }
    }

    #[test]
    fn requires_authenticated_untruncated_matching_dns_response() {
        let valid = response(&[7; 32]);
        assert_eq!(
            validate_response("_rustdesk.example.com", &valid)
                .unwrap()
                .1,
            300
        );
        for (field, value) in [
            ("AD", json!(false)),
            ("CD", json!(true)),
            ("TC", json!(true)),
            ("Status", json!(2)),
        ] {
            let mut invalid = valid.clone();
            invalid[field] = value;
            assert!(validate_response("_rustdesk.example.com", &invalid).is_err());
        }
        let mut invalid = valid.clone();
        invalid["Question"][0]["name"] = json!("_rustdesk.attacker.com.");
        assert!(validate_response("_rustdesk.example.com", &invalid).is_err());
        let mut invalid = valid;
        invalid["Answer"][0]["name"] = json!("_rustdesk.attacker.com.");
        assert!(validate_response("_rustdesk.example.com", &invalid).is_err());
    }

    #[test]
    fn rejects_invalid_or_ambiguous_keys_and_respects_zero_ttl() {
        let mut valid = response(&[7; 32]);
        valid["Answer"][0]["TTL"] = json!(0);
        assert_eq!(
            validate_response("_rustdesk.example.com", &valid)
                .unwrap()
                .1,
            0
        );
        assert!(validate_response("_rustdesk.example.com", &response(&[7; 31])).is_err());
        let different = response(&[8; 32])["Answer"][0].clone();
        valid["Answer"].as_array_mut().unwrap().push(different);
        assert!(validate_response("_rustdesk.example.com", &valid).is_err());
        assert!(parse_record("v=1;key=not-base64").is_err());
        assert!(parse_record(&format!("v=2;key={}", STANDARD.encode([7; 32]))).is_err());
    }

    #[tokio::test]
    async fn explicit_key_bypasses_discovery_and_is_returned_unchanged() {
        assert_eq!(
            resolve("not a valid hostname", " configured key ")
                .await
                .unwrap(),
            " configured key "
        );
    }
}
