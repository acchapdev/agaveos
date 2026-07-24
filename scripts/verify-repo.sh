#!/usr/bin/env bash
# Verify the freshly built repo/ is a usable pacman repository: point a clean
# pacman root at it, sync, and install agave-desktop + agave-release.
# Runs inside the Arch build container after build-packages.sh.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
repo_out="$repo_root/repo"

[ -f "$repo_out/agaveos.db.tar.gz" ] || { echo "error: no repo db in $repo_out" >&2; exit 1; }

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/root/var/lib/pacman" "$sandbox/etc" "$sandbox/cache"

cat > "$sandbox/etc/pacman.conf" << EOF
[options]
Architecture = x86_64
# Signature checking is exercised in CI once the keyring secret is set;
# local/unsigned iteration verifies structure only.
SigLevel = Never

[agaveos]
Server = file://$repo_out
EOF

pacman --config "$sandbox/etc/pacman.conf" --root "$sandbox/root" -Sy
pacman --config "$sandbox/etc/pacman.conf" --root "$sandbox/root" \
  --noconfirm --cachedir "$sandbox/cache" -S --dbonly agave-release agave-desktop

echo "OK: [agaveos] repo syncs and resolves agave-release + agave-desktop"
