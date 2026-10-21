# Private server access and temporary invitations

Use the same **Private key** access secret in the modified client and in both modified server processes. This is independent of the public Key field and the server signing private key. See the server's docs/private-access.md for ACCESS_KEY, relay configuration, and the additional TCP ports (21120 and 21121 by default).

## Client settings

In Settings → Network → ID/Relay server, enter the custom ID server and optionally its public Key. When Key is empty, native clients can discover it from the DNSSEC-validated TXT record described in [DNS public key discovery](dns-public-key.md).

The new Private key field is visible while entering a replacement. After saving, it displays exactly twenty dots, regardless of the stored secret's length. Clicking the saved mask starts replacement; the clear icon removes it. Leaving the field unchanged keeps the existing secret.

The secret is stored encrypted in a separate machine-bound configuration file. It is bound to the ID server authority, including the port. Neither the ordinary options/export nor the UI status API returns the stored secret. Changing the ID server does not send a previous server's secret to the new server. Re-enter the access secret when changing servers.

Enable **Enable guest invitations** and choose **Invitation validity (minutes)**, from 1 to 1440 minutes (default 10). Saving these settings restarts the private host registration and invalidates its previous invitations. Existing accepted sessions continue.

## Inviting a guest

The **Invite guest** button below the one-time password creates an invitation and opens a read-only connection field with a copy icon:

`P-254785236@rustdesk.example.com?key=PUBLIC_SERVER_KEY`

The guest pastes this whole value into RustDesk's remote ID field. It has no rustdesk:// prefix. The public key is ordinary Base64, matching the stock connection-field parser; do not percent-encode it. Only the short numeric alias changes between invitations. An updated client with DNS discovery can also receive just `P-254785236@rustdesk.example.com`.

The address never includes the private access secret or a password. The owner's existing password/manual approval policy still applies. One invitation per device is active; creating another replaces it. **Revoke invitation** rejects pending/new admission.

The server allocates the P- namespace and checks for collisions with stored device IDs and active invitations. Stock clients can use the existing rendezvous/relay protocol for the alias, while anonymous registrations, true-ID connections, and public-to-public relay pairing are rejected in protected mode.

Expiration is checked again immediately before guest authorization, against both the alias and the issued session UUID. A prompt left open past expiration cannot be accepted afterward. Accepted sessions may continue after expiration/revocation; reconnecting requires a current invitation.

## First-version limits and validation

Protected owned sessions use the relay. The additional authenticated control/tunnel use TCP, even when the normal public server is behind a WebSocket proxy. Native clients support this feature; Flutter Web has an explicit unsupported fallback.

Automated checks compile the exact native access modules against the pinned hbb_common and cover credential/UI isolation, authenticated transport, signed guest identity, relay pairing, invitation admission, and continued transfer after expiry. Full Flutter application builds and a live session with an installed stock GUI client are still separate smoke tests; protocol-level tests do not replace that device check.

## Regression surface

Existing paths changed only where required: src/client.rs selects authenticated owned connections; src/rendezvous_mediator.rs selects the private host control channel; src/server.rs carries/signs per-session aliases; src/server/connection.rs validates login identity and final admission. src/ipc.rs and src/flutter_ffi.rs expose the dedicated write-only settings/invitation API. The settings dialog and desktop home page add the requested controls; the web bridge reports unsupported native-only functionality. Existing direct-IP paths and paths without a configured access secret retain their original behavior.

The separate DNS commit also changes src/common.rs (central key lookup and API proxy), src/ui_session_interface.rs (key lookup before ordinary sessions), and key lookup in src/client.rs, src/server.rs, and src/rendezvous_mediator.rs. Manual keys and the built-in public-server key retain priority; direct-IP and explicit other-server sessions bypass discovery for the local configured server.
