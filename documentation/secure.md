# Using Secure RSMP

This guide explains how to configure and run the `rsmp` gem with the `rsmp-secure-v1` transport. It focuses on setup and operation. For the complete setting reference and protocol details, see [Configuration: Secure RSMP](configuration.md#secure-rsmp).

Secure mode protects the connection between the two RSMP endpoints. Before the normal RSMP connection sequence, the endpoints authenticate provisioned credentials with EDHOC and establish fresh session keys. The normal `Version`, `ComponentList`, status, command, alarm, and watchdog messages are then carried inside encrypted CBOR/COSE frames. Rekeying is automatic.

## Connection roles

The endpoint opening the TCP connection initiates Secure RSMP. The listener requires it:

| TCP role | Secure setting |
| --- | --- |
| Endpoint opening the connection | `secure.enabled: true` |
| Endpoint accepting the connection | `secure.required: true` |

The usual arrangement is a site connecting to a listening supervisor:

| Endpoint | Default TCP role | Secure setting |
| --- | --- | --- |
| Site | Client | `secure.enabled: true` |
| Supervisor | Server | `secure.required: true` |

Secure mode is not negotiated and never falls back to legacy RSMP. Both endpoints must be configured before they connect.

## Quick local example

The repository contains matching secure site and supervisor configurations in `config/tlc.yaml` and `config/supervisor.yaml`.

Generate the stable sample credentials used by those files:

```console
$ bundle exec rsmp secure generate
```

Validate both configurations:

```console
$ bundle exec rsmp config check config/tlc.yaml --type tlc
OK
$ bundle exec rsmp config check config/supervisor.yaml --type supervisor
OK
```

Start the supervisor in one terminal:

```console
$ bundle exec rsmp supervisor --config config/supervisor.yaml --json
```

Start the site in another:

```console
$ bundle exec rsmp site --config config/tlc.yaml --json
```

The logs identify the `rsmp-secure-v1` profile, report the authenticated peer when the secure handshake completes, and then show the normal RSMP connection sequence. Application messages are logged after decryption when JSON logging is enabled.

The no-argument generator uses public test-vector identities so this example is repeatable. Never use those sample private keys with real equipment or in production.

## Generate endpoint identities

For a real deployment, generate a fresh identity for each endpoint. The identity passed with `--id` must match the identity that endpoint uses in the secure configuration.

Generate a site identity:

```console
$ bundle exec rsmp secure generate --out config/secure --id RN+SI0001
```

Generate a supervisor identity:

```console
$ bundle exec rsmp secure generate --out config/secure --id supervisor
```

Each command creates two files:

| File | Used by | Handling |
| --- | --- | --- |
| `<id>.private.key` | The endpoint that owns the identity | Keep secret and readable only by that endpoint |
| `<id>.cred` | The owner and every peer that trusts it | Provision through an authenticated process |

The `.cred` file contains the identity and public key. There is no separate `.pub` file and no `public_key` configuration setting.

The generator creates the output directory if needed and refuses to overwrite existing files unless `--force` is used. Avoid overwriting active credentials as an ad hoc rotation procedure: stage the new key pair, authenticate and provision the new `.cred` file to the peer, and coordinate activation and reconnection.

When the endpoints run on separate systems:

1. Keep the site's private key and own credential on the site.
2. Copy only the site's `.cred` file to the supervisor's trust store.
3. Keep the supervisor's private key and own credential on the supervisor.
4. Copy only the supervisor's `.cred` file to the site's trust store.

## Configure a site that connects to a supervisor

The site needs its own private key and credential at the top-level `secure` setting. Its supervisor endpoint pins the supervisor credential.

```yaml
site_id: RN+SI0001
core_version: '3.3.0'
supervisors:
  - ip: 192.0.2.10
    port: 12111
    secure:
      id: supervisor
      credential: secure/supervisor.cred
      core_versions: ['3.3.0']
secure:
  enabled: true
  profile: rsmp-secure-v1
  private_key: secure/RN+SI0001.private.key
  credential: secure/RN+SI0001.cred
sxls:
  tlc: '1.3.0'
components:
  main:
    TC:
```

In this example:

- `site_id` must match the subject in `RN+SI0001.cred`.
- Endpoint `secure.id` is the expected subject in the supervisor credential.
- `core_versions` is optional. When present, it restricts the Core versions that peer is authorized to use.
- Secure file paths are relative to the YAML file, so a config in `config/` resolves `secure/...` below `config/secure/`.

If the supervisor's RSMP `supervisorId` differs from its credential subject, configure both values:

```yaml
supervisors:
  - ip: 192.0.2.10
    port: 12111
    secure:
      id: supervisor-credential
      supervisor_id: operational-supervisor-id
      credential: secure/supervisor-credential.cred
```

## Configure a supervisor that accepts sites

The supervisor listener needs its own private key and credential. Each configured site is a trusted peer when `secure.required` is true. Explicit credential paths make that trust relationship visible:

```yaml
port: 12111
secure:
  required: true
  profile: rsmp-secure-v1
  id: supervisor
  private_key: secure/supervisor.private.key
  credential: secure/supervisor.cred
default:
  sxls:
    tlc: '1.3.0'
sites:
  RN+SI0001:
    sxls:
      tlc: '1.3.0'
    secure:
      credential: secure/RN+SI0001.cred
      core_versions: ['3.3.0']
```

The `sites` mapping key, the subject in the pinned site credential, and the site's RSMP `siteId` must agree. Add every site that is permitted to authenticate. A secure-required listener does not accept an unconfigured credential merely because its signature is valid.

## Conventional and explicit paths

The explicit paths in the preceding examples can be omitted when the files use the standard names in a `secure/` directory next to the YAML file:

- Site `RN+SI0001` uses `secure/RN+SI0001.private.key` and `secure/RN+SI0001.cred`.
- A supervisor uses `secure/supervisor.private.key` and `secure/supervisor.cred` by default.
- A site endpoint with `secure.id: supervisor` trusts `secure/supervisor.cred`.
- A secure-required supervisor trusts configured site `RN+SI0001` through `secure/RN+SI0001.cred`.

Use explicit paths when credentials live elsewhere or their filenames do not follow these conventions. Absolute paths are also accepted.

## Reverse connection roles

Core 3.3 permits the connection direction to be reversed. The security rule remains based on TCP role, not RSMP site/supervisor role:

- A listening site uses `connection_role: server` and `secure.required: true`.
- A supervisor connecting to sites uses `connection_role: client` and `secure.enabled: true`.

Trusted supervisors remain in the site's `supervisors` list. For an outbound supervisor, each site entry needs its endpoint under `supervisors` and a `secure` peer marker or explicit credential. See the [connection-role examples](configuration.md#secure-rsmp) for the complete YAML shapes.

## Validate and run configurations

Validate the YAML shape before starting either endpoint:

```console
$ bundle exec rsmp config check config/site-secure.yaml --type tlc
$ bundle exec rsmp config check config/supervisor-secure.yaml --type supervisor
```

The `config check` command catches unknown properties, invalid types, unsupported profiles, and basic secure bounds. Starting the endpoint performs the remaining operational checks before it opens a listener or starts an outgoing connection:

- required local and peer credential files;
- exact credential encoding and key sizes;
- the local private-key/credential match;
- credential subjects and derived key identifiers; and
- secure timeout and rekey bounds.

Invalid secure material fails startup before the listener opens or the outgoing connection starts.

Run the endpoints with the same commands used for legacy RSMP. Secure mode comes entirely from the YAML configuration:

```console
$ bundle exec rsmp supervisor --config config/supervisor-secure.yaml --json
$ bundle exec rsmp site --config config/site-secure.yaml --json
```

## Use secure configuration from Ruby

Loading through the options classes preserves config-file-relative credential paths and performs schema validation:

```ruby
require 'rsmp'

options = RSMP::TLC::TrafficControllerSite::Options.load_file('config/site-secure.yaml')
Async do
  site = RSMP::TLC::TrafficControllerSite.new(
    site_settings: options.to_h,
    log_settings: options.log_settings
  )
  site.start
  site.wait
end
```

For a supervisor:

```ruby
require 'rsmp'

options = RSMP::Supervisor::Options.load_file('config/supervisor-secure.yaml')
Async do
  supervisor = RSMP::Supervisor.new(
    supervisor_settings: options.to_h,
    log_settings: options.log_settings
  )
  supervisor.start
  supervisor.wait
end
```

When constructing settings directly instead of loading YAML, use absolute credential paths. Loading YAML through an options class is recommended for operational configurations.

## Operational behavior

- Every new TCP connection performs a new EDHOC handshake and creates a new secure session.
- Traffic-key renewal happens automatically according to the configured limits. Applications do not need to initiate routine rekeying.
- The authenticated credential identity and selected Core version cannot change within a connection.
- A second RSMP `Version` message on an established connection is rejected.
- Authentication, authorization, framing, replay, or rekey failures close the connection; there is no plaintext retry.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| `public_key` is rejected as an additional property | Remove it and configure the complete peer `.cred` file. |
| A credential path is not found | Paths are relative to the YAML file; check the filename or use an absolute path. |
| The private key does not match the local credential | Restore or regenerate the matching pair. |
| A peer credential is missing | Add the peer endpoint credential on a site, or configure the site credential under the supervisor's `sites` entry. |
| The credential identity is not authorized | Check `site_id`, the supervisor endpoint `id`, optional `supervisor_id`, and credential subjects. |
| Core-version authorization fails | Check the peer entry's optional `core_versions` list. |
| A secure handshake receives invalid data | Confirm that the connector uses `enabled`, the listener uses `required`, and neither endpoint is sending legacy JSON. |
| A handshake times out | Check reachability, both peer credentials, endpoint resource load, and the logs on both sides. |

## Further reference

- [Configuration: Secure RSMP](configuration.md#secure-rsmp) describes all settings and protocol constraints.
- [RSMP CLI](cli.md#rsmp-secure-generate) documents credential-generation options.
- [`config/secure/README.md`](../config/secure/README.md) describes the sample credential directory.
- [`schemas/secure/`](../schemas/secure/) contains the CDDL structure reference.
