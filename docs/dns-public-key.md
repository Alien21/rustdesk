# Public server key discovery through DNS

Native RustDesk clients can discover a self-hosted server's public key when
the `Key` setting is empty. An explicit key, including a key in
`ID@server?key=...`, always takes precedence and does not make a DNS request.
The default public RustDesk servers continue to use their built-in key.

Publish the contents of the server's `id_ed25519.pub` as a TXT record:

```dns
_rustdesk.rustdesk.example.com. 300 IN TXT "v=1;key=BASE64_PUBLIC_KEY"
```

The key must decode to a 32-byte Ed25519 public key. Keep the server's private
`id_ed25519` file private. Publish a single key at this name; different keys in
multiple records are rejected. DNS TXT character strings within one record
are concatenated, so the record may be split into quoted chunks by a DNS
provider. CNAME indirection is not supported.

Enable DNSSEC for the zone, including its delegation. Discovery queries
Cloudflare's `https://cloudflare-dns.com/dns-query` over validated HTTPS and
requires the resolver's authenticated-data (`AD`) flag. The client trusts
that resolver's DNSSEC validation; it does not validate DNSSEC signatures
locally. The query discloses the server hostname to Cloudflare, but contains
no RustDesk peer ID, password or private key. Configured proxies are used.

For example, either of these configurations can use the record above:

* ID server `rustdesk.example.com`, with an empty `Key` setting.
* A connection to `123456789@rustdesk.example.com` without a `key` argument.

Ports and `ws://`/`wss://` server URLs do not change the DNS record name.
Internationalized domain names use their DNS/IDNA form. IP addresses,
private DNS names and unsigned DNS zones require an explicit key. A public
resolver cannot see internal or split-horizon DNS records.

A missing, unsigned, ambiguous or invalid record, or an unavailable resolver,
causes discovery to fail with an error. It does not fall back to an empty
key or to the built-in public-server key. Explicit key connections retain
their existing behavior. Discovery does not change the existing peer
handshake or its legacy compatibility behavior.

Discovered keys are cached in memory for at most the DNS TTL, capped at five
minutes; failures are cached for 30 seconds. They are not saved into network
settings or the per-peer explicit key. Previously saved explicit keys must
be cleared before that peer can use DNS discovery or DNS key rotation.

This feature requires the updated native client. It does not add DNS key
discovery to older public RustDesk releases or to the separate web client.
Continue to include `?key=...` when sharing an address with those clients.
