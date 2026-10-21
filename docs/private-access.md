# Private server access and temporary invitations

Use the same **Private key** access secret in the modified client and in both modified server processes. This is independent of the public Key field and the server signing private key. See the server's docs/private-access.md for ACCESS_KEY and relay configuration. Private control and relay share the existing TCP ports 21116 and 21117 through a framed upgrade; no additional private ports are opened. The online query remains on TCP 21115.

## Client settings

In Settings → Network → ID/Relay server, enter the custom ID server and optionally its public Key. When Key is empty, native clients can discover it from the DNSSEC-validated TXT record described in [DNS public key discovery](dns-public-key.md).

The new Private key field is visible while entering a replacement. After saving, it displays exactly twenty dots, regardless of the stored secret's length. Clicking the saved mask starts replacement; the clear icon removes it. Leaving the field unchanged keeps the existing secret.

The secret is stored encrypted in a separate machine-bound configuration file. It is bound to the ID server authority, including the port. Neither the ordinary options/export nor the UI status API returns the stored secret. Changing the ID server does not send a previous server's secret to the new server. Re-enter the access secret when changing servers.

Enable **Enable guest invitations** and choose **Invitation validity (minutes)**, from 1 to 1440 minutes (default 10). Saving these settings restarts the private host registration and invalidates its previous invitations. Existing accepted sessions continue.

## Mixed clients and public access

Update hbbs and hbbr together and preserve their signing keys and peer database. Existing unmodified PCs can keep their ID server, relay and public Key settings. They may register as targets for PSK-authenticated controllers; registration alone does not grant general relay access. Online status combines live legacy registrations and authenticated host-control channels.

| Controller | Target | Admission |
| --- | --- | --- |
| PSK client | Registered legacy client | Target's normal password/approval |
| PSK client | PSK client | Target's normal password/approval |
| Public client | PSK client's real ID | Only while that device allows public connections |
| Public client | PSK client's P invitation | Only with a valid invitation |
| Public client | Legacy client | Rejected |

**Allow clients without the private key to connect to this device** is off by default. The authenticated host registration sets this policy for that device. With it enabled, any public controller with the correct public server Key may connect to the real ID, including through ID@server?key=...; it does not identify a list of known PCs. Password/manual approval and other security settings still apply. With it disabled, public callers need a valid P invitation. Turning it off blocks new admission, including pending requests; accepted sessions continue. P invitations remain independent of the switch.

Older local services leave this new switch disabled and require an update. Changing servers or clearing the private secret resets public access to off. Private ID ownership and legacy public keys are pinned on the server; converting a private ID to a legacy target or replacing a pinned key requires deliberate server administration.

Clipboard server-configuration import/export transfers only host, relay, API and public Key. It never transfers plaintext, encrypted or masked Private key values. Unknown secret/private_key/access_key fields do not change the stored secret or its editing state. Invitation settings and public-access policy stay outside this format.

## Inviting a guest

The **Invite guest** button below the one-time password creates an invitation and opens a read-only connection field with a copy icon:

`P-254785236@rustdesk.example.com?key=PUBLIC_SERVER_KEY`

The guest pastes this whole value into RustDesk's remote ID field. It has no rustdesk:// prefix. The public key is ordinary Base64, matching the stock connection-field parser; do not percent-encode it. Only the short numeric alias changes between invitations. An updated client with DNS discovery can also receive just `P-254785236@rustdesk.example.com`.

The address never includes the private access secret or a password. The owner's existing password/manual approval policy still applies. One invitation per device is active; creating another replaces it. **Revoke invitation** rejects pending/new admission.

The server allocates the P- namespace and checks for collisions with stored device IDs and active invitations. Stock clients use the existing rendezvous/relay protocol for the alias. Legacy target registrations remain supported, while public-to-public relay pairing is rejected. Public access to a PSK real ID follows its separate per-device policy.

Expiration is checked again immediately before guest authorization, against both the alias and the issued session UUID. A prompt left open past expiration cannot be accepted afterward. Accepted sessions may continue after expiration/revocation; reconnecting requires a current invitation.

## First-version limits and validation

Protected owned sessions use the relay. Authenticated control and tunnels use the existing TCP 21116/21117 listeners, even when public signaling is behind a WebSocket proxy. Native clients support this feature; Flutter Web has an explicit unsupported fallback.

Earlier automated checks covered the exact native access modules, credential/UI isolation, authenticated transport, signed guest identity, relay pairing, invitation admission and continued transfer after expiry. Results for the new mixed-mode build and full GUI sessions must be recorded separately; protocol and package checks do not replace installation and device testing.

## Regression surface

Existing paths changed only where required: src/client.rs selects authenticated owned connections; src/rendezvous_mediator.rs selects the private host control channel; src/server.rs carries/signs per-session aliases; src/server/connection.rs validates login identity and final admission. src/ipc.rs and src/flutter_ffi.rs expose the dedicated write-only settings/invitation API. The settings dialog and desktop home page add the requested controls; the web bridge reports unsupported native-only functionality. Existing direct-IP paths and paths without a configured access secret retain their original behavior.

The separate DNS commit also changes src/common.rs (central key lookup and API proxy), src/ui_session_interface.rs (key lookup before ordinary sessions), and key lookup in src/client.rs, src/server.rs, and src/rendezvous_mediator.rs. Manual keys and the built-in public-server key retain priority; direct-IP and explicit other-server sessions bypass discovery for the local configured server.

The mixed-mode changes stay in src/access_config.rs, src/server_access.rs and the existing server-access settings widget: these store the explicit opt-in, publish it at registration, distinguish public real-ID sessions and recheck local/server admission before authorization. The server's rendezvous/relay paths and peer ownership records enforce the permitted endpoint roles. Without ACCESS_KEY, the original server registration and relay paths remain unchanged. Windows UAC, Unlock PIN and local IPC process authentication are unchanged; the existing JSON API carries the new setting without FFI code generation.
