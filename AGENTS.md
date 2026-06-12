# RSMP Agent Guide

This repository contains the Ruby implementation of RSMP, the `rsmp` CLI, and vendored RSMP Core and TLC SXL JSON Schemas.

## Where Things Live

- `lib/rsmp/` contains the library, protocol logic, CLI implementation, schema handling, and converters.
- `exe/rsmp` is the executable entrypoint.
- `test/rsmp/` contains the internal `sus` test suite.
- `config/` contains example site and supervisor configuration files.
- `documentation/` contains project documentation.
- `schemas/` contains vendored Core and TLC schemas used at runtime. Do not edit these casually; update them from the source repos when possible.

## Commands

- `bundle exec sus` runs the test suite.
- `bundle exec rake test` also runs the test suite.
- `bundle exec rubocop` checks Ruby style.
- `bundle exec exe/rsmp schema generate --in path/to/sxl.yaml --out path/to/output` generates JSON Schema files from an SXL YAML file.

Always run project executables through `bundle exec` so the correct bundle is used.

## Schema Workflows

To generate JSON Schema files from an SXL YAML file:

```sh
bundle exec exe/rsmp schema generate --in ../rsmp_sxl_traffic_lights/schema/sxl.yaml --out ../rsmp_sxl_traffic_lights/schema
```

To refresh the vendored schemas in this repo from the sibling source repositories:

```sh
bundle exec rake schemas:update
```

The `schemas:update` task assumes sibling repos at `../rsmp_core` and `../rsmp_sxl_traffic_lights` by default. Pass explicit paths when needed:

```sh
bundle exec rake schemas:update[/path/to/rsmp_core,/path/to/rsmp_sxl_traffic_lights]
```

The task archives `schema/` from configured version branches in those repos, so make sure the local branches exist and are up to date before running it.

## Editing Guidance

- Follow existing Ruby, `sus`, Thor CLI, and Async patterns.
- Tests may start local sites and supervisors; they use port `13111` to avoid the default RSMP port `12111`.
- CLI tests call the Thor class directly rather than spawning a separate process.
- Keep schema converter changes aligned with `RSMP::Schema` loading and validation behavior.
- If vendored schemas change, run the relevant schema and CLI tests.

## Validation

- Run the narrowest relevant `bundle exec sus ...` command after edits, or the full `bundle exec sus` when behavior is shared.
- Run `bundle exec rubocop` for Ruby changes when practical.
- If schema source repos, branches, or dependencies are unavailable, mention which validation or schema update step was skipped and why.
