#!/usr/bin/env bash
# Generate the [agaveos] repo signing key and export the keyring package
# inputs. Run once on a trusted machine; see pkgbuilds/agave-keyring/keyring/
# README.md for where each artifact goes.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
keyring_dir="$repo_root/pkgbuilds/agave-keyring/keyring"
uid='Agave Linux Build Key <brochapman@gmail.com>'

command -v gpg >/dev/null || { echo "error: gpg not found" >&2; exit 1; }

if [ -f "$keyring_dir/agave-trusted" ] && [ -s "$keyring_dir/agave-trusted" ]; then
  echo "error: keyring already exists at $keyring_dir — refusing to overwrite" >&2
  exit 1
fi

gpg --batch --quick-generate-key "$uid" ed25519 sign never

fpr=$(gpg --list-keys --with-colons "$uid" | awk -F: '/^fpr:/ {print $10; exit}')
[ -n "$fpr" ] || { echo "error: could not determine fingerprint" >&2; exit 1; }

mkdir -p "$keyring_dir"
gpg --export "$fpr" > "$keyring_dir/agave.gpg"
printf '%s:4:\n' "$fpr" > "$keyring_dir/agave-trusted"
: > "$keyring_dir/agave-revoked"

private="$repo_root/agave-signing-key.private.asc"
gpg --export-secret-keys --armor "$fpr" > "$private"
chmod 600 "$private"

cat << EOF

Key generated: $fpr

Committed to the repo (public):
  $keyring_dir/agave.gpg
  $keyring_dir/agave-trusted
  $keyring_dir/agave-revoked

PRIVATE key exported to:
  $private

Next steps:
  1. gh secret set AGAVE_GPG_PRIVATE_KEY < $private
  2. Back the private key up somewhere safe (password manager).
  3. shred/delete $private — do NOT commit it (gitignored as *.asc).
EOF
