# Secure RSMP CDDL Schemas

This directory contains CDDL schemas for the implemented Secure RSMP v1 CBOR
structures.

The schemas are documentation and conformance artifacts. The development test
suite uses the `cddl` gem to validate representative generated CBOR structures
against them. The Ruby runtime does not load or validate against them; it uses
explicit Ruby validation for deterministic CBOR, credential bundles, secure
frames, replay state, and cryptographic checks.

Run the conformance check with:

```console
$ bundle exec sus test/rsmp/secure_cddl_spec.rb
```

The main schema is:

- `rsmp-secure-v1.cddl`

It describes:

- Secure RSMP `edhoc`, `data`, and `rekey` frames.
- Untagged RFC 9052 `COSE_Encrypt0` objects used by encrypted frames.
- Encrypted rekey plaintext.
- Signed Secure RSMP credential bundles.
- COSE Key shape used by Ed25519 credentials.
- CCS-style EDHOC credential bytes.
- RSMP exporter context and HKDF info maps.
- COSE external AAD maps and the resulting RFC 9052 `Enc_structure`.

Encrypted `data` and `rekey` frames carry an untagged `COSE_Encrypt0` object.
Its protected header contains only algorithm `24` (ChaCha20/Poly1305), and its
unprotected header contains the minimal one-to-four-byte Partial IV used as the
per-epoch frame index. The outer frame supplies the epoch and frame family;
the RSMP session binding is supplied as COSE external AAD.

Secure RSMP derives traffic material with full HKDF-SHA-256 (Extract followed
by Expand), an empty salt, and the deterministic-CBOR `hkdf-info` map as the
exact `info` byte string. The session id is derived during the initial
handshake and remains stable when traffic keys are renewed on the same
connection.

The exporter context always includes the authenticated credential-bundle ids
in EDHOC initiator/responder order. Both ids are mandatory, non-empty CBOR text
strings. RSMP Core version and optional login authorization are established
later inside encrypted RSMP messages; they are not plaintext EDHOC-frame hints
or pre-handshake exporter-context fields.

Rekey completes with a responder `rekey_ack` encrypted under the new epoch
keys after the responder authenticates EDHOC message 3. The initiator prepares
its pending channel before sending message 3, then authenticates the
acknowledgement before installing that channel locally. Successful rekey thus
confirms both state installation and possession of the newly derived traffic
keys without a separate commit message.

CDDL describes structure and CBOR types. Implementations must still perform
semantic checks such as deterministic-CBOR validation, signature verification,
credential authorization, EDHOC transcript validation, replay rejection, and
matching the EDHOC credential to the COSE key.
