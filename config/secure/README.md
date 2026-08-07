Secure RSMP sample credentials
==============================

The sample configurations refer to credentials in this directory. Generated
key and credential files are intentionally ignored by Git.

Generate the repeatable sample site and supervisor identities with:

```sh
bundle exec rsmp secure generate
```

Generate a fresh identity with:

```sh
bundle exec rsmp secure generate --id RN+SI0002
```

Each identity consists of two files:

- `<id>.private.key`: a 64-byte Ed25519 seed-plus-public-key value. Keep it
  secret.
- `<id>.cred`: the exact deterministic-CBOR CCS credential pinned by
  `rsmp-secure-v1`. It contains the identity, public key, and derived 16-byte
  KID and is provisioned as the peer trust object.

No separate `.pub` file or self-signed credential envelope is used. Trusting a
`.cred` file means pinning the complete identity and public key it contains.

When paths are omitted, Secure RSMP uses these conventions:

- Site `RN+SI0001` uses `secure/RN+SI0001.private.key` and
  `secure/RN+SI0001.cred`.
- The default supervisor uses `secure/supervisor.private.key` and
  `secure/supervisor.cred`.
- A secure-required supervisor trusts site `RN+SI0001` through
  `secure/RN+SI0001.cred`.
- A site endpoint with `secure.id: supervisor` trusts
  `secure/supervisor.cred`.

Use `secure.enabled: true` on the endpoint opening the TCP connection and
`secure.required: true` on the listener. Secure handshake failure never falls
back to legacy RSMP.

The no-argument command uses stable test-vector keys for repeatable local
examples. Use freshly generated or hardware-backed keys in deployment and
provision, rotate, revoke, back up, and audit credentials through an
authenticated operational process.
