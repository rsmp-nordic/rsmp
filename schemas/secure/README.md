# Secure RSMP CDDL schemas

This directory contains the normative structural CDDL for `rsmp-secure-v1`.
It covers:

- four-message initial EDHOC frames and the generic EDHOC error frame;
- encrypted RSMP data and rekey frames;
- untagged RFC 9052 `COSE_Encrypt0` with ChaCha20/Poly1305;
- responder rekey requests, EDHOC rekey messages, new-key acknowledgement,
  and the generic rekey error;
- exact deterministic-CBOR CCS credentials with Ed25519 COSE keys;
- exporter-context and HKDF info maps; and
- COSE external AAD and `Enc_structure`.

Run the conformance checks with:

```console
$ bundle exec sus test/rsmp/secure_cddl_spec.rb
```

The Ruby runtime performs explicit semantic and cryptographic validation. CDDL
does not by itself enforce deterministic encoding, exact derived KIDs, trust or
authorization policy, EDHOC transcript validity, frame ordering, replay
rejection, mandatory renewal thresholds, or secret erasure.

Every protected direction has an independent 32-bit Partial IV index beginning
at 1 in each epoch. The profile renews keys at no more than 1,000,000 protected
frames, 64 GiB of ciphertext, or two hours per direction and epoch. The outer
epoch is an unsigned 64-bit value beginning at 0. Neither value may wrap.

The exporter context binds the exact profile and both authenticated credential
subjects in EDHOC initiator/responder order. Private-use exporter label `32768`
produces 32 bytes of material, followed by the deterministic-CBOR-bound
HKDF-SHA-256 schedule described in the normative specification.

The main schema is `rsmp-secure-v1.cddl`.
