# Configuration

## Overview
RSMP uses option classes to handle configuration for sites and supervisors. These classes provide:

- File-based configuration via YAML
- JSON Schema validation with descriptive errors
- Safe access to nested values using Ruby's `dig`
- Deep merging of provided values with defaults

## Option classes

- `RSMP::Site::Options` for sites
- `RSMP::Supervisor::Options` for supervisors
- `RSMP::TLC::TrafficControllerSite::Options` for TLC sites

Each class applies defaults and validates the configuration against a JSON Schema located in `lib/rsmp/options/schemas/`.

Field types and unknown keys are checked before defaults are applied. The `required_settings.json`
and `required_supervisor_settings.json` schemas then check required settings after defaults and
supervisor site inheritance are resolved:

- Every configured signal plan must have a `cycle_time`.
- Before Core 3.3.0, exactly one `main` component is required. Sites supply a default main component
  when omitted; supervisor site settings can inherit it from `default`. From Core 3.3.0, a main
  component is not used. With `core_version: "3.3.0"`, no default components are added, even if
  `components` is omitted. Configurations that allow older Core versions (including an omitted
  `core_version` or `"all"`) retain the default main component.
- A site in `server` role must have a `port`, either explicitly or from its first supervisor endpoint.
  With `supervisors: []`, the port must be explicit.

`inputs.programming: {}` is allowed and means no programmed input actions.

## Version strings

Core 3.3.0 and later use exact `MAJOR.MINOR.PATCH` version strings for both Core and SXL negotiation.

Earlier Core versions retain their historical wire formats for compatibility. In particular, the Core 3.2 release may be written as either `3.2` or `3.2.0`. The library resolves both to the `3.2.0` schema internally, but a supervisor responding to a legacy Version message uses the exact Core and SXL strings sent by the site. Ambiguous versions such as `3.1` are rejected because they do not identify one of the supported 3.1.x releases.

Configured SXL versions must use `MAJOR.MINOR.PATCH`, for example `sxls: { tlc: '1.2.0' }`.
Each SXL name maps to a version string or a non-empty, ordered list of distinct version strings.
Abbreviated versions such as `1.2` and versions with suffixes are rejected in configuration and CLI overrides.
For connections using a Core version before 3.3.0, equipment may still send legacy SXL strings such as `1.2`.
The supervisor compares their three-part equivalents against the configured version and uses the original string in its response.

The supervisor rejects a legacy Version message when the offered SXL version
does not match its effective configuration for that site, even if a schema for the offered version is available.
For example, with `tlc: '1.2.1'` configured, an offer of `1.0.15` receives `MessageNotAck` and the
connection closes. Its `rea` field identifies the requested and supported versions.
Core 3.3.0 uses the SXL response statuses described below.

## SXL hints for testing

**SXL hints and reconnect-based switching are an optional testing convention, not part of the RSMP Core specification.**
Other equipment is not expected to understand them. Hints apply only to handshakes offering Core versions
before 3.3.0. Core 3.3.0 uses its standard SXL response statuses.

A site configured with a single version string always uses that version and ignores hints.
A list enables hint handling for that SXL name:

```yaml
core_version: '3.2.2'
sxls:
  tlc: ['1.2.1', '1.0.15', '1.2.0']
```

Configure a legacy Core version explicitly. An initial rejection does not identify the selected Core version,
so hints are ignored if the request offers Core 3.3.0 or later, including mixed-version offers.

The site initially offers the first version, `1.2.1` in this example. It follows a hint only when
`MessageNotAck.oMId` refers to its outstanding initial Version request, before a Version response has been accepted.
On rejection, it closes the connection and uses the normal `intervals.reconnect` delay before reconnecting in client role.
A site in server role waits for the supervisor to reconnect.

The hint is a case-sensitive `hint:` token in `MessageNotAck.rea`. It must start at a word boundary,
so `thint:` does not count. The value must be a complete version, without extra version parts or suffixes,
and end at whitespace, a semicolon or the end of the string. For example:

```text
SXL tlc version 1.2.1 requested, but only 1.0.15 supported; hint: 1.0.15
```

`hint: 1.0.15` refers to the connection's single legacy `SXL` version. The gem takes this SXL from
the first entry in its `sxls` configuration. The hinted version must use `MAJOR.MINOR.PATCH` and appear
in that entry's configured list. Named hints and rejections containing multiple `hint:` tokens are ignored.

The last allowed hinted version is retained across ordinary reconnects and later rejections.
Missing, malformed or unlisted hints leave it unchanged. Unknown message IDs, rejections of other messages,
and rejections after Version acceptance cannot change the selection. Creating a new site instance or
restarting the process restores the first configured version.

Selections are kept separately for each supervisor address and port, without modifying the configuration.
For sites in server role, selections are keyed by the supervisor's source IP because its source port changes
on reconnect. When switching versions, the connection's subscriptions and buffered messages are cleared;
the supervisor must subscribe again after reconnection.

On a supervisor, a version list means that any listed version is supported. A legacy SXL mismatch is rejected
with a hint for the first version in that list (or the single configured version). A supported offer is accepted
even if it is not the first entry. All listed versions must have schemas available locally.
Core 3.3.0 continues to report `mismatch` with a sorted `supported` list; that response does not trigger automatic switching.

For matrix testing, use a separate run with one fixed supervisor version for each matrix entry.
Wait for a matching handshake before running tests, and serialize runs sharing a physical site.
A version retained from a previous run will then be rejected with the next run's required version.

## Core 3.3.0

Preliminary Core 3.3.0 support follows `rsmp_core` branch `3.3.0` at commit
`1aa02faf82da4f47fee57c43c546c092420aa576`, including PR #318. These rules apply only
when Core 3.3.0 is selected. Earlier Core versions retain their existing behavior.

SXL responses use `ok`, `unsupported`, `mismatch` and `expected`. Only `ok` enables
an SXL, at the exact offered version. `supported` is diagnostic and does not trigger
fallback. A connection can become ready even if no SXL is accepted.

Set `use_alarms: false` in the supervisor's `default` or per-site configuration to
disable every Alarm message in both directions on a 3.3.0 connection. The default
is true.

The 3.3.0 handshake ends with ComponentList followed by a site-wide AggregatedStatus.
Readiness follows acknowledgement of that status; either MessageAck or MessageNotAck
completes this step. The initial status is mandatory even with `send_after_connect: false`.

AggregatedStatus has no `cId`, `fP` or `fS`. All false bits mean normal operation;
bits 2, 6 and 8 are always false in site messages. Site-wide conditions include all
components and active alarm priorities, including SXLs rejected on a connection.
Read received bits through `SiteProxy#site_aggregated_status` and override
`Supervisor#site_aggregated_status_changed(site_proxy)` for notifications.
For 3.3.0, call `request_aggregated_status` or `request_aggregated_status_and_collect`
without a component. A supplied component argument is ignored on the wire. Legacy
requests remain component-addressed.

Use `add_component`, `remove_component` and `ComponentBase#update_metadata` to update
the inventory. Ready 3.3.0 connections receive a complete ComponentList after a change;
disconnected connections receive the current list in their next handshake. The
supervisor preserves received ordering and retains unchanged component objects.
Component names are optional on the wire but must be nonempty strings when supplied.
The supervisor uses the component ID when a list entry omits its name, including
when a later list removes a previously supplied name.
Removing the last component is prohibited because the Core 3.3.0 schema requires a
nonempty ComponentList.

Subscription intervals use `uRt`, an integer or decimal
number represented as a string, e.g. `"2"` or `"0.5"`. Negative intervals are invalid.
Zero disables periodic updates and is valid only with `sOc: true`.
The Core source and vendored 3.3.0 schemas include this correction to the pinned baseline.
The isolated main-component requirement in `site_configuration.rst` is treated as
obsolete for 3.3.0 in favor of the component model and site-wide status definitions.

Validator follow-up should cover the new Version statuses and failures, both alarm
directions, site-wide status bits and fields, final-handshake ACK/NotAck, component
changes, and accepted-SXL filtering during initial synchronization and buffer replay.

## Loading a configuration file

Use the option classes to load a YAML configuration file:

- `RSMP::Site::Options.load_file(path)`
- `RSMP::Supervisor::Options.load_file(path)`

The top-level `log` section is separated into `log_settings`. Other keys are treated as settings for the site or supervisor.

## CLI usage

Use the CLI with a config file:

- `rsmp site --config path/to/site.yaml`
- `rsmp supervisor --options path/to/supervisor.yaml`

Both `--config` and `--options` are accepted as aliases.

## Example: site YAML

```yaml
site_id: RN+SI0001
connection_role: client
supervisors:
  - ip: 127.0.0.1
    port: 12111
sxls:
  tlc: "1.3.0"
components:
  main:
    TC:
message_buffer:
  max_messages: 10000
  statuses: true
log:
  json: true
```

`connection_role` controls which side opens the TCP connection:

- `client` means the node connects to configured remote endpoints.
- `server` means the node listens for incoming connections.

Configurable connection roles are available from Core 3.3.0.

For sites, `client` is the default and uses the `supervisors` endpoint list. A site in `server` role listens on `ip` and `port` instead.

```yaml
site_id: RN+SI0001
connection_role: server
ip: 0.0.0.0
port: 12111
core_version: "3.3.0"
sxls:
  tlc: "1.3.0"
```

## Message Buffer

Sites buffer outgoing alarm and aggregated status messages while a supervisor connection is down. Status updates are buffered according to `message_buffer.statuses`, which defaults to `true`.

```yaml
message_buffer:
  max_messages: 10000
  statuses: true
```

`statuses: true` buffers all subscribed status updates during communication disruption. To buffer only selected statuses, provide selectors:

```yaml
message_buffer:
  statuses:
    - sCI: S0001
      n: signalgroupstatus
```

Use `statuses: false` or an empty list to avoid buffering status updates. Subscriptions for statuses that are not buffered are removed when the connection is lost.

The current implementation uses an in-memory buffer per supervisor connection. Buffered messages survive reconnects while the process keeps running, but are lost if the process exits, crashes, or the host loses power. The RSMP core specification requires the outgoing communication buffer to survive communication failure and power outage, so this is not yet a complete persistent buffer implementation.

## Example: supervisor YAML

```yaml
port: 12111
connection_role: server
default:
  sxls:
    tlc: "1.3.0"
  intervals:
    timer: 0.1
    watchdog: 0.1
log:
  json: true
sites:
  TLC001:
    sxls:
      tlc: "1.3.0"
    intervals:
      timer: 0.1
      watchdog: 0.1
    timeouts:
      connect: 1
      acknowledgement: 1
    components:
      main:
        TC:
```

Per-site configuration follows the supervisor-side site schema (`lib/rsmp/options/schemas/supervisor_site.json`). Each site entry can define an `sxls` map, or inherit it from `default`. The SXL name `core` is reserved for the RSMP core schema and cannot be used as an SXL key.

For supervisors, `server` is the default and listens on `ip`/`port`. A supervisor in `client` role connects out to the endpoints listed under each configured site. The outbound endpoint list uses the existing `supervisors` key in the per-site settings:

```yaml
connection_role: client
sites:
  RN+SI0001:
    core_version: "3.3.0"
    sxls:
      tlc: "1.3.0"
    supervisors:
      - ip: 127.0.0.1
        port: 12111
```

This reversed setup is used when the site listens and the supervision system initiates the connection.

## Secure RSMP

Secure RSMP is configured in YAML with a `secure` section. The implemented profile is `rsmp-secure-v1`.

For step-by-step credential provisioning, configuration, validation, and run commands, see [Using Secure RSMP](secure.md). This section is the detailed configuration and protocol reference.

Profile status:

| Profile | Status | Handshake | Data AEAD | Notes |
| --- | --- | --- | --- | --- |
| `rsmp-secure-v1` | Implemented profile | EDHOC method 0, cipher suite 4 | COSE_Encrypt0 with ChaCha20-Poly1305 | Uses deterministic CBOR, exact pinned CCS credentials, four-message initial EDHOC, and mandatory traffic-key renewal limits. |

The secure layer is independent of the RSMP site/supervisor role:

- `connection_role` decides which TCP side connects and therefore which EDHOC role is used.
- RSMP site/supervisor identity is still checked through the normal RSMP `Version` exchange.
- The initial encrypted `Version` exchange follows the RSMP application roles, not the EDHOC roles. A site or site-to-site follower sends first even when it is the EDHOC responder.

The security boundary is the pair of credential-authenticated endpoints that terminate the EDHOC/COSE session. TCP proxies, VPN gateways, and similar intermediaries can remain outside that boundary when they forward Secure RSMP frames unchanged. A gateway that decrypts, translates, inspects plaintext, or re-encrypts frames terminates the secure channel and is an explicit trusted endpoint; protection across that gateway requires a separate Secure RSMP session on each side.

Use `secure.enabled: true` on an outgoing side to initiate secure connections. Use `secure.required: true` on a listening side to reject non-secure inbound connections.

Mode selection is fail closed and is not negotiated in band. An outgoing endpoint with `secure.enabled: true` attempts Secure RSMP on every connection and never retries a failed secure handshake as legacy RSMP. A listener with `secure.required: true` interprets every accepted connection as Secure RSMP and closes legacy or malformed input. `secure.enabled: true` without `secure.required: true` is rejected on a listening endpoint because it would otherwise leave the listener in legacy mode.

Secure paths are resolved relative to the YAML config file, not the current working directory. If paths are omitted, Secure RSMP uses conventions:

- A site with `site_id: RN+SI0001` uses `secure/RN+SI0001.private.key` and `secure/RN+SI0001.cred`.
- A supervisor uses `secure/supervisor.private.key` and `secure/supervisor.cred`.
- A site endpoint with `secure.id: supervisor` trusts `secure/supervisor.cred`.
- A supervisor with `secure.required: true` trusts every configured site by convention, e.g. `sites.RN+SI0001` uses `secure/RN+SI0001.cred`.

The endpoint `secure.id` is the expected peer credential subject and conventional file prefix. For example, `id: supervisor-a` means the peer credential is `secure/supervisor-a.cred` unless an explicit path is provided.

`private_key` is the local raw 64-byte Ed25519 signing key: a 32-byte private seed followed by its 32-byte public key. `credential` is the exact deterministic-CBOR CCS credential pinned by the profile. It contains a non-empty subject and an Ed25519 COSE_Key whose 16-byte KID is derived from the public key. No separate public-key file or self-signed envelope is used.

On POSIX systems, the private-key file must deny all group and other access;
owner-only modes such as `0600` and `0400` are accepted. Insecure permissions
fail startup.

Trust comes from provisioning the complete peer `.cred` file through an authenticated process. EDHOC proves possession of its corresponding private key. Authorization then maps the authenticated credential subject to the expected RSMP identity, site or supervisor role, and permitted Core versions.

Use `core_versions` on a peer `secure` entry to restrict the encrypted RSMP `Version` selection. The authenticated identity and selected Core version are sealed for the connection; a later `Version` change is rejected.

`log_decrypted_payloads` is a local boolean policy setting and defaults to
`false`. With the default, Secure RSMP log entries retain only redacted message
metadata and never retain message attributes, identifiers, JSON, or
payload-derived exceptions. Set it to `true` only for an explicit development
or diagnostic need. When enabled, the normal archive retains decrypted
`Message` objects and JSON logging can emit complete plaintext payloads.

Secure-required listeners automatically rate-limit repeated failed handshakes
per remote address. Running `Site` and `Supervisor` objects also expose
`revoke_secure_credential!` and `restore_secure_credential!` for process-local
emergency revocation; see [Using Secure RSMP](secure.md#rate-limiting-and-runtime-revocation).

When secure mode is active, startup validates deterministic credential encoding, exact CCS shape, derived KIDs, key lengths, the local private-key/credential match, configured subjects, and duplicate peer identities or KIDs. Invalid material fails startup before a listener opens or an outgoing connection starts.

The two authenticated credential subjects are mandatory exporter-context inputs, ordered by EDHOC initiator and responder role. The exact deterministic-CBOR context is passed to RFC 9528 `EDHOC_Exporter` with private-use label `32768` and retained in the downstream HKDF-SHA-256 schedule. The RSMP identity and Core version are learned from encrypted RSMP messages and checked against local authorization policy.

Encrypted RSMP data and rekey-control frames use untagged `COSE_Encrypt0` with protected algorithm `24` (ChaCha20/Poly1305). The COSE Partial IV carries the per-epoch message index, while the outer frame carries the epoch and frame type used for key selection and dispatch.

CDDL schemas for Secure RSMP v1 CBOR structures are available in `schemas/secure/`.
They document the implemented frame, credential, exporter-context, HKDF-info, and AAD shapes,
and the development test suite validates representative generated CBOR structures against them.
The Ruby runtime does not load them for validation.

Example site connecting securely to a supervisor:

```yaml
site_id: RN+SI0001
supervisors:
  - ip: 127.0.0.1
    port: 12111
    secure:
      id: supervisor
secure:
  enabled: true
  profile: rsmp-secure-v1
  log_decrypted_payloads: false
sxls:
  tlc: "1.3.0"
```

With the example above, the site uses `secure/RN+SI0001.private.key` and `secure/RN+SI0001.cred`, and trusts the supervisor through the pinned `secure/supervisor.cred`.

Example supervisor accepting secure sites:

```yaml
port: 12111
secure:
  required: true
  profile: rsmp-secure-v1
  log_decrypted_payloads: false
default:
  sxls:
    tlc: "1.3.0"
sites:
  RN+SI0001:
    sxls:
      tlc: "1.3.0"
  RN+SI0002:
    sxls:
      tlc: "1.3.0"
```

Because `secure.required` is true, both configured sites are trusted by convention. No `secure: {}` marker is needed under each site.

Use explicit paths when the file names do not follow the conventions:

```yaml
sites:
  RN+SI0001:
    sxls:
      tlc: "1.3.0"
    secure:
      credential: secure/custom-site.cred
      core_versions: ["3.3.0"]
```

A site can also listen for supervisor connections. In that case `secure.required` is on the site, and trusted supervisors stay in the existing `supervisors` list:

```yaml
site_id: RN+SI0001
connection_role: server
port: 12111
secure:
  required: true
supervisors:
  - ip: 127.0.0.1
    port: 12111
    secure:
      id: supervisor-a
  - ip: 127.0.0.1
    port: 12112
    secure:
      id: supervisor-b
```

A supervisor can also connect out to listening sites. In that case `secure.enabled` is on the supervisor, and each site entry opts into secure peer resolution:

```yaml
connection_role: client
secure:
  enabled: true
sites:
  RN+SI0001:
    sxls:
      tlc: "1.3.0"
    secure: {}
    supervisors:
      - ip: 127.0.0.1
        port: 12111
  RN+SI0002:
    sxls:
      tlc: "1.3.0"
    secure: {}
    supervisors:
      - ip: 127.0.0.1
        port: 12112
```

Here the supervisor uses its conventional local identity, and each site peer uses the site id as the file prefix. The `secure: {}` marker is used because the supervisor is initiating outbound secure connections; `secure.required` only implies all configured site peers for inbound supervisor listeners.

The same site-listener and supervisor-client implementation supports direct
site-to-site communication. Instantiate or run the follower as a site in server
role and the leader as a supervisor in client role. Set the leader's top-level
`site_id` and `secure.id` to its site identity, and pin that credential as the
follower's supervisor-role peer. Pin the follower credential under the leader's
`sites` entry. The leader is the TCP/EDHOC initiator, while the follower remains
the sender of the first Version message. See the “Direct site-to-site
connections” section in `documentation/secure.md` for complete YAML examples.

Traffic-key renewal is mandatory. It retains the authenticated credential subjects, authorization context, and session id, but derives fresh directional traffic keys and increments a non-wrapping unsigned 64-bit epoch. Every configured limit must be at or below the profile maximum:

```yaml
secure:
  rekey_after_messages: 1000000
  rekey_after_bytes: 68719476736
  rekey_after_seconds: 7200
  rekey_timeout: 2
```

The limits apply per direction and epoch. They cannot be disabled. `rekey_after_messages` must be between 3 and 1,000,000. `rekey_after_bytes` must leave space for two maximum-sized control frames and cannot exceed 64 GiB. `rekey_after_seconds` cannot exceed 7,200 seconds and must exceed the fixed two-second rekey timeout. `rekey_timeout` is exactly 2 seconds.

The original EDHOC initiator starts each rekey. The responder sends an encrypted request when its limit is due. Application data pauses while renewal is required or active. The responder's final acknowledgement is protected by the pending new-epoch keys, so the initiator installs the new channel only after authenticating possession of those keys.

Each direction also has an absolute 4,294,967,295-frame index space per epoch because the COSE Partial IV is 32 bits. The configured one-million-frame maximum and reserved control space ensure renewal happens much earlier. A frame index or epoch never wraps; exhaustion closes the connection.

Secure RSMP derives the traffic secret, directional keys, nonce prefixes, and
initial session id using full HKDF-SHA-256 (Extract followed by Expand). Each
derivation uses an empty salt and a deterministic-CBOR map as the exact HKDF
`info` value. Rekeying derives fresh traffic keys and nonce prefixes from the
new EDHOC exporter material, while retaining the session id for the lifetime of
the Secure RSMP connection.

Generate local Secure RSMP v1 credentials with:

```console
$ rsmp secure generate
$ rsmp secure generate --id RN+SI0002
```

The generated files use the same v1 credential format as secure mode. See `config/secure/README.md` for details.

## Supervisor settings

The following lists the top-level supervisor settings and the keys available for per-site configuration under `sites`.

Top-level supervisor settings

- `port`: integer|string - TCP port the supervisor listens on (default: `12111`).
- `ip`: string - address to bind to.
- `connection_role`: string - `server` to listen for sites, or `client` to connect to configured site endpoints (default: `server`).
- `ips`: string or array - `'all'` or a list of allowed IP addresses.
- `site_id`: string - optional site identifier for the supervisor itself.
- `max_sites`: integer - limit concurrent connected sites.
- `secure`: object - Secure RSMP settings. Use `required: true` for secure inbound listeners or `enabled: true` for supervisor-initiated outbound connections.
- `default`: object - default settings applied to sites that don't have a specific `sites` entry. Contains keys:
  - `sxls`: object - default SXL versions for default sites, for example `{ "tlc": "1.3.0" }`.
  - `core_version`: string for the accepted RSMP Core version.
  - `intervals`: object with `timer`, `watchdog` (numbers, seconds).
  - `timeouts`: object with `watchdog`, `acknowledgement` (numbers, seconds).
- `log`: object - log settings (see `log_settings` elsewhere in docs).
- `sites`: mapping - per-site settings (see below).

## Per-site settings (`sites` mapping)

Each key under `sites` is a site id (for example `TLC001`) and the value is the supervisor-side configuration for that site. These settings tell the supervisor how to handle incoming connections from that specific site (which SXL/schema to use, per-site timeouts, component layout, etc.). Per-site configuration follows the supervisor-side schema at `lib/rsmp/options/schemas/supervisor_site.json`.

If a connecting site's id is not present under `sites`, the supervisor will fall back to the `default` settings. The runtime configuration check will raise `RSMP::ConfigurationError` if neither the site entry nor the default settings provide usable SXL information.


Common per-site keys

- `sxls` (object): SXL versions to use for this site, keyed by SXL name, for example `tlc: "1.3.0"`. The supervisor will attempt to load the corresponding schemas for these SXLs.
- `core_version` (string): accepted RSMP Core version for this site.
- `type` (string): optional human-readable type identifier.
- `site_id` (string): explicit site identifier (if different from the mapping key).
- `supervisors` (array): list of supervisor endpoints (objects with `ip` and `port`). Useful for reverse mappings or local-site configs.
- `secure` (object): Secure RSMP peer settings for this site. Use `credential` for an explicit pinned CCS file, or omit it to use `secure/<site_id>.cred` by convention. `core_versions` optionally restricts the authorized encrypted Core-version selection.
- `components` (object): component definitions (same structure as site `components`), used by the supervisor-side proxies to set up component proxies.
- `intervals` (object): per-site timer settings - `timer`, `watchdog`, `reconnect`, `after_connect` (numbers, seconds).
- `timeouts` (object): per-site timeouts - `connect`, `watchdog`, `acknowledgement` (numbers, seconds).
- `send_after_connect` (boolean): whether to send messages after connect without waiting for additional events.
- `skip_validation` (array[string]): list of message types to skip JSON schema validation for this site.
- `security_codes` (object): map of security code levels to secrets.

## Site settings

The following lists the top-level site settings.

- `site_id` (string): site identifier sent in the Version message.
- `type` (string): optional site type.
- `connection_role` (string): `client` to connect to supervisors, or `server` to listen for supervisor connections (default: `client`).
- `ip` (string): bind address when `connection_role` is `server` (default: `0.0.0.0`).
- `port` (integer|string): listen port when `connection_role` is `server`. If omitted, it defaults to the first configured supervisor port.
- `supervisors` (array): supervisor endpoints used when `connection_role` is `client`. Each endpoint may include secure peer settings with `id`, `credential`, and optional `core_versions`.
- `secure` (object): Secure RSMP local settings. Use `enabled: true` for outgoing secure connections or `required: true` for secure inbound listeners.
- `sxls` (object): SXL versions used by the site, keyed by SXL name.
- `core_version` (string): RSMP Core version to use.
- `intervals` (object): timer settings - `timer`, `watchdog`, `reconnect`.
- `timeouts` (object): timeout settings - `watchdog`, `acknowledgement`.
- `send_after_connect` (boolean): whether to send messages after connect without waiting for additional events.
- `message_buffer` (object): outgoing message buffer settings.
- `components` (object): component definitions.
- `security_codes` (object): map of security code levels to secrets.

### TLC-specific settings

TLC-specific settings are used when a site uses the `tlc` SXL and include:

- `startup_sequence` (string): expected startup sequence for the traffic controller.
- `signal_plans` (object): signal plan definitions and timing information.
- `inputs` (object): input definitions for the controller.
- `live_output` (string|null): optional live output destination.

See `lib/rsmp/options/schemas/traffic_controller_site.json` for the full schema and examples.

## Validation

Invalid configurations raise `RSMP::ConfigurationError` with details about the failing path. The CLI prints these errors when loading config files.

Errors include the failing JSON pointer and helpful type hints, for example:

- `/supervisors: value at \`/supervisors\` is not an array (expected array, got string)`

## Defaults and overrides

Configuration values override defaults via deep merge. A notable exception is `components.main`, which replaces the default component list when provided.
