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

## Supervisor settings

The following lists the top-level supervisor settings and the keys available for per-site configuration under `sites`.

Top-level supervisor settings

- `port`: integer|string - TCP port the supervisor listens on (default: `12111`).
- `ip`: string - address to bind to.
- `connection_role`: string - `server` to listen for sites, or `client` to connect to configured site endpoints (default: `server`).
- `ips`: string or array - `'all'` or a list of allowed IP addresses.
- `site_id`: string - optional site identifier for the supervisor itself.
- `max_sites`: integer - limit concurrent connected sites.
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
- `supervisors` (array): supervisor endpoints used when `connection_role` is `client`.
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
