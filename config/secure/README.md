Secure RSMP sample credentials
==============================

The sample Secure RSMP configs refer to credential files in this directory, but
the generated credential files themselves are intentionally ignored by git.

Generate local Secure RSMP v1 credentials with:

```sh
bundle exec rsmp secure generate
```

Generate an additional fresh identity for another site with:

```sh
bundle exec rsmp secure generate --id RN+SI0002
```

Secure RSMP fills in conventional file paths when they are omitted:

- A site with `site_id: RN+SI0001` uses `secure/RN+SI0001.private.key` and `secure/RN+SI0001.cred`.
- A supervisor uses `secure/supervisor.private.key` and `secure/supervisor.cred`.
- A secure-required supervisor trusts each configured site by convention, e.g. `sites.RN+SI0001` uses `secure/RN+SI0001.pub` and `secure/RN+SI0001.cred`.
- A site supervisor endpoint with `secure.id: supervisor` trusts `secure/supervisor.pub` and `secure/supervisor.cred`.

Use `secure.enabled: true` only for the endpoint that opens the TCP connection,
and `secure.required: true` for the endpoint that listens. Secure handshake
failure never causes an automatic retry using legacy RSMP. A listening endpoint
configured only with `secure.enabled: true` is rejected as ambiguous.

These files are generated as `rsmp-secure-v1` credentials. Without `--id`, the
command uses stable sample keys from the local `edhoc` gem test vector and is
intended only for repeatable local examples. With
`--id`, the command generates a fresh Ed25519 key and signed deterministic-CBOR
credential bundle using the id as the file prefix.

Generated credentials use the same v1 format as secure mode. Before deployment,
protect private keys and run the generated public keys and credential bundles
through your commissioning, backup, rotation, and trust-approval process.

Generate v1 bundles with:

```sh
bundle exec rsmp secure generate
```

The sample configs use:

- `RN+SI0001.private.key`, `RN+SI0001.pub`, `RN+SI0001.cred` for the sample site side.
- `supervisor.private.key`, `supervisor.pub`, `supervisor.cred` for the sample supervisor side.
