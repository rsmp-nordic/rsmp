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
supervisors:
  - ip: 127.0.0.1
    port: 12111
sxl: tlc
sxl_version: "1.2.1"
components:
  main:
    TC:
log:
  json: true
```

## Example: supervisor YAML

```yaml
port: 12111
default:
  sxl: tlc
  intervals:
    timer: 0.1
    watchdog: 0.1
log:
  json: true
sites:
  TLC001:
    sxl: tlc
    sxl_version: "1.2.1"
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

Per-site configuration follows the supervisor-side site schema (`lib/rsmp/options/schemas/supervisor_site.json`). Each site entry must include an `sxl` value; if `sxl` is missing the supervisor will raise a `RSMP::ConfigurationError` on startup.

## Supervisor settings

The following lists the top-level supervisor settings and the keys available for per-site configuration under `sites`.

Top-level supervisor settings

- `port`: integer|string — TCP port the supervisor listens on (default: `12111`).
- `ip`: string — address to bind to.
- `ips`: string or array — `'all'` or a list of allowed IP addresses.
- `site_id`: string — optional site identifier for the supervisor itself.
- `max_sites`: integer — limit concurrent connected sites.
- `default`: object — default settings applied to sites that don't have a specific `sites` entry. Contains keys:
  - `sxl`: string — default SXL type for default sites (e.g. `tlc`).
  - `sxl_version`, `core_version`: strings for version hints.
  - `intervals`: object with `timer`, `watchdog` (numbers, seconds).
  - `timeouts`: object with `watchdog`, `acknowledgement` (numbers, seconds).
- `log`: object — log settings (see `log_settings` elsewhere in docs).
- `sites`: mapping — per-site settings (see below).

## Per-site settings (`sites` mapping)

Each key under `sites` is a site id (for example `TLC001`) and the value is the supervisor-side configuration for that site. These settings tell the supervisor how to handle incoming connections from that specific site (which SXL/schema to use, per-site timeouts, component layout, etc.). Per-site configuration follows the supervisor-side schema at `lib/rsmp/options/schemas/supervisor_site.json`.

If a connecting site's id is not present under `sites`, the supervisor will fall back to the `default` settings. The runtime configuration check will raise `RSMP::ConfigurationError` if a site entry is present but missing the required `sxl` key.


Common per-site keys

- `sxl` (string, required): the SXL type to use for this site (for example `tlc`). The supervisor will attempt to load the corresponding schemas for this SXL.
- `sxl_version` (string): preferred SXL version (informational; runtime version comes from the site's Version message).
- `type` (string): optional human-readable type identifier.
- `site_id` (string): explicit site identifier (if different from the mapping key).
- `supervisors` (array): list of supervisor endpoints (objects with `ip` and `port`). Useful for reverse mappings or local-site configs.
- `components` (object): component definitions (same structure as site `components`), used by the supervisor-side proxies to set up component proxies.
- `intervals` (object): per-site timer settings — `timer`, `watchdog`, `reconnect`, `after_connect` (numbers, seconds).
- `timeouts` (object): per-site timeouts — `connect`, `watchdog`, `acknowledgement` (numbers, seconds).
- `send_after_connect` (boolean): whether to send messages after connect without waiting for additional events.
- `skip_validation` (array[string]): list of message types to skip JSON schema validation for this site.
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
