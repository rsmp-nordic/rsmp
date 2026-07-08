Secure RSMP development credentials
===================================

The sample Secure RSMP configs refer to credential files in this directory, but
the generated credential files themselves are intentionally ignored by git.

Generate local development credentials with:

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

These files are generated from the EDHOC suite0 test vector used by the local
`edhoc` gem unless `--id` is used. With `--id`, the command generates a fresh
Ed25519 key and self-signed development credential using the id as the file
prefix. They are suitable for local prototype testing only. Do not use these
keys or credentials for deployment.

The default implemented Secure RSMP profile is currently `rsmp-secure-suite0-dev`.
`rsmp-secure-suite4-dev` is also implemented for testing EDHOC cipher suite 4
with these development credential files. The planned normative profile is
`rsmp-secure-v1`, which will use EDHOC cipher suite 4 and a CBOR/COSE key bundle
instead of these development credential files.

The sample configs use:

- `RN+SI0001.private.key`, `RN+SI0001.pub`, `RN+SI0001.cred` for the sample site side.
- `supervisor.private.key`, `supervisor.pub`, `supervisor.cred` for the sample supervisor side.
