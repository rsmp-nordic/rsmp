# RSMP CLI

The `rsmp` command can run a site, run a supervisor, validate config files, generate JSON Schemas from an SXL, and print the gem version.

Use help at any level:

```console
$ rsmp help
$ rsmp help site
$ rsmp help supervisor
$ rsmp help config check
$ rsmp help schema generate
```

## Quick Examples

Run a TLC site that connects to the default supervisor endpoint, `127.0.0.1:12111`:

```console
$ rsmp site
```

Run a supervisor that listens on the default port, `12111`:

```console
$ rsmp supervisor
```

Run both with explicit config files:

```console
$ rsmp supervisor --config config/supervisor.yaml
$ rsmp site --config config/tlc.yaml
```

Run a site against a specific supervisor endpoint:

```console
$ rsmp site --supervisors 192.0.2.10:12111
```

Show raw JSON messages in the log:

```console
$ rsmp site --json
$ rsmp supervisor --json
```

Write logs to a file:

```console
$ rsmp supervisor --log log/supervisor.log
$ rsmp site --log log/site.log
```

Validate config files before starting anything:

```console
$ rsmp config check config/tlc.yaml --type tlc
$ rsmp config check config/supervisor.yaml --type supervisor
```

Generate JSON Schema files from an SXL YAML file:

```console
$ rsmp schema generate --in schemas/tlc/1.3.0/sxl.yaml --out /tmp/tlc-schema
```

## Configuration Files

Most real runs should use YAML config files. The CLI accepts `--config`, `-c`, and `--options` as aliases:

```console
$ rsmp site -c config/tlc.yaml
$ rsmp supervisor --options config/supervisor.yaml
```

CLI options override or add to settings loaded from the config file. For example, this loads `config/tlc.yaml` but changes the site id and supervisor endpoint for this run:

```console
$ rsmp site -c config/tlc.yaml --id RN+SI0420 --supervisors 127.0.0.1:13111
```

Core and SXL version overrides are command-line options.

See `documentation/configuration.md` for the YAML format.

## Commands

### `rsmp site`

Runs an RSMP site. The default site type is `tlc`, so this starts a TLC traffic controller site implementation.

```console
$ rsmp site
```

Common options:

- `--config PATH`, `-c PATH`, `--options PATH`: load site settings from a YAML file.
- `--id ID`, `-i ID`: set the site id.
- `--supervisors LIST`, `-s LIST`: set one or more supervisor endpoints.
- `--core VERSION`: set the RSMP Core version.
- `--sxls LIST`: set the SXLs announced by the site as a comma-separated `name:version` list.
- `--type tlc`, `-t tlc`: choose the site type. Currently `tlc` is the supported CLI type.
- `--log PATH`, `-l PATH`: write log output to a file.
- `--json`, `-j`: include raw JSON messages in the log.

The `--supervisors` option accepts a comma-separated list:

```console
$ rsmp site --supervisors 127.0.0.1:12111,192.0.2.10:12111
```

If the IP address is omitted, `127.0.0.1` is used:

```console
$ rsmp site --supervisors :13111
```

If the port is omitted, the configured site default is used:

```console
$ rsmp site --supervisors 127.0.0.1
```

Use `--sxls` to specify several SXLs for a site:

```console
$ rsmp site --sxls tlc:1.3.0,vms:1.0.0
```

Example with explicit core and SXL versions:

```console
$ rsmp site -c config/tlc.yaml --core 3.3.0 --sxls tlc:1.3.0
```

### `rsmp supervisor`

Runs an RSMP supervisor. By default it listens for site connections on port `12111`.

```console
$ rsmp supervisor
```

Common options:

- `--config PATH`, `-c PATH`, `--options PATH`: load supervisor settings from a YAML file.
- `--id ID`, `-i ID`: set the supervisor site id.
- `--ip ADDRESS`: set the listen address.
- `--port PORT`, `-p PORT`: set the listen port.
- `--core VERSION`: override the accepted RSMP Core version.
- `--sxls LIST`: override SXL versions as a comma-separated `name:version` list.
- `--log PATH`, `-l PATH`: write log output to a file.
- `--json`, `-j`: include raw JSON messages in the log.

Example:

```console
$ rsmp supervisor --ip 0.0.0.0 --port 13111 --core 3.3.0 --sxls tlc:1.3.0 --json
```

When `--core` or `--sxls` is used with the supervisor command, it overrides `default` and any configured `sites` entries for that run.

### `rsmp config check`

Validates one or more YAML config files without starting a site or supervisor.

```console
$ rsmp config check config/tlc.yaml
$ rsmp config check config/tlc.yaml config/supervisor.yaml
```

Options:

- `--type TYPE`, `-t TYPE`: choose the config type. Supported values are `auto`, `site`, `tlc`, and `supervisor`.

The default type is `auto`. Auto-detection works when the config shape is clear. If the CLI cannot infer the type, pass `--type` explicitly:

```console
$ rsmp config check config/tlc.yaml --type tlc
$ rsmp config check config/supervisor.yaml --type supervisor
```

Successful validation prints `OK` for each valid file. Invalid files print an error and the command exits with status `1`.

Common validation errors include:

- The file does not exist.
- The path is a directory.
- The file is not YAML.
- A setting has the wrong type.
- A config key is not allowed by the schema.

### `rsmp schema generate`

Generates JSON Schema files from an `sxl.yaml` file.

```console
$ rsmp schema generate --in schemas/tlc/1.3.0/sxl.yaml --out /tmp/tlc-schema
```

Options:

- `--in PATH`, `-i PATH`: path to the input `sxl.yaml`. Defaults to `sxl.yaml`.
- `--out PATH`, `-o PATH`: output directory. Defaults to the current directory.

The command writes the generated status, command, alarm, root schema, definitions, and `sxl_index.json` files to the output directory.

If the input file is missing, the command prints an error and exits with status `1`.

### `rsmp version`

Prints the installed `rsmp` gem version:

```console
$ rsmp version
```

## Exit Status

Commands return status `0` on success. Validation and argument errors return a non-zero status.

Long-running commands such as `rsmp site` and `rsmp supervisor` run until interrupted or until startup fails.
