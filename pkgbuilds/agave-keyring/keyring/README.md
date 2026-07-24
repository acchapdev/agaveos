# Agave Linux signing keyring

Generate the repo signing key once with `scripts/gen-signing-key.sh`, which
exports into this directory:

- `agave.gpg` — public keyring (committed)
- `agave-trusted` — `<fingerprint>:4:` trust line (committed)
- `agave-revoked` — revoked fingerprints, empty initially (committed)

The **private** key is exported to a local file the script prints; store it as
the `AGAVE_GPG_PRIVATE_KEY` GitHub Actions secret (and back it up somewhere
safe), then delete the local copy. It must never be committed.
