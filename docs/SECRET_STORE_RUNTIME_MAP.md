# SecretStore Runtime Mapping (P5.M2.E2)

This note aligns `src/secret_store.ml` with `coq/theories/Clawq/SecretStore.v`.

## Runtime path split

- Plaintext (`"value"`): returned unchanged.
- Env indirection (`"$ENV_VAR"`, but not `$ENC:`): resolve from environment, else passthrough.
- Encrypted (`"$ENC:..."`) with `encrypt_secrets = false`: passthrough.
- Encrypted with `encrypt_secrets = true` and missing master key: passthrough.
- Encrypted with `encrypt_secrets = true` and present master key:
  - decrypt success -> plaintext
  - decrypt failure -> passthrough

These branches are modeled in `resolve_secret_runtime` and proved via:

- `resolve_secret_runtime_missing_master_key`
- `resolve_secret_runtime_decrypt_failure`
- `resolve_secret_runtime_decrypt_success`

## Config rewrite preservation

- `encrypt_provider_key_avoids_double_encryption`: existing `$ENC:` values remain unchanged.
- `encrypt_provider_key_preserves_env_refs`: `$ENV` references are never encrypted.

## Trusted boundaries

- AES-GCM, base64, nonce framing, and key derivation are abstract/trusted.
- The end-to-end `encrypt_decrypt_identity` theorem is kept as an axiom in this model due to abstract framing/string primitives.
