#!/usr/bin/env bash
# Build the Agave Linux live ISO with mkarchiso. Runs inside the privileged
# x86_64 Arch build container (`just iso`, or CI). Expects the [agaveos]
# packages to be built first (scripts/build-packages.sh -> repo/).
#
# Environment:
#   AGAVE_SIGN   1 if repo/ is GPG-signed (uses SigLevel Required for agaveos);
#                default 0 -> the profile's TrustAll line is kept as-is.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
iso_dir="$repo_root/iso"
repo_out="$repo_root/repo"
# mkarchiso's work dir must be on a real Linux filesystem: writing the airootfs
# (setcap, the version file, snapper hooks) fails on a bind-mounted macOS volume
# under OrbStack. Default to an in-container path locally; CI (native Linux)
# can point AGAVE_WORK back at repo_root/work. out/ stays on the repo so the
# ISO artifact is accessible from the host.
work="${AGAVE_WORK:-/var/tmp/agave-iso-work}"
out="$repo_root/out"

command -v mkarchiso >/dev/null || { echo "error: mkarchiso not found (run inside the build container)" >&2; exit 1; }
[ -f "$iso_dir/profiledef.sh" ] || { echo "error: $iso_dir/profiledef.sh missing" >&2; exit 1; }

# The [agaveos] packages must exist locally; the profile pacman.conf points at
# file:///work/repo, so ensure that path resolves to our repo_out.
if [ ! -f "$repo_out/agaveos.db.tar.gz" ]; then
  echo "error: no [agaveos] repo at $repo_out — run scripts/build-packages.sh first" >&2
  exit 1
fi

# mkarchiso reads the profile's pacman.conf with the build host's pacman.d,
# so make sure a mirrorlist exists (containers ship one via pacman-mirrorlist).
if [ ! -s /etc/pacman.d/mirrorlist ]; then
  echo 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' > /etc/pacman.d/mirrorlist
fi

# Refresh keyrings so official + agave packages verify during squashfs build.
pacman-key --init >/dev/null 2>&1 || true
pacman-key --populate archlinux >/dev/null 2>&1 || true
if [ -f "$repo_root/pkgbuilds/agave-keyring/keyring/agave.gpg" ]; then
  pacman-key --add "$repo_root/pkgbuilds/agave-keyring/keyring/agave.gpg" >/dev/null 2>&1 || true
  awk -F: '{print $1}' "$repo_root/pkgbuilds/agave-keyring/keyring/agave-trusted" 2>/dev/null \
    | while read -r fpr; do [ -n "$fpr" ] && pacman-key --lsign-key "$fpr" >/dev/null 2>&1 || true; done
fi

rm -rf "$work"
mkdir -p "$out" "$work"

# The profile's pacman.conf points [agaveos] at file:///work/repo as a
# placeholder. Generate a build-time copy pointing at the actual repo path
# (which differs between local runs and CI) and pass it with mkarchiso -C, so
# there is no dependency on a fixed mount point.
build_pacman_conf="$work/pacman.conf"
sed "s#^Server = file:///work/repo#Server = file://$repo_out#" \
  "$iso_dir/pacman.conf" > "$build_pacman_conf"
if ! grep -q "Server = file://$repo_out" "$build_pacman_conf"; then
  echo "error: failed to rewrite [agaveos] Server line in pacman.conf" >&2
  exit 1
fi

echo "==> building Agave Linux ISO (repo: $repo_out)"
mkarchiso -v -C "$build_pacman_conf" -w "$work" -o "$out" "$iso_dir"

echo "==> ISO built:"
/bin/ls -lh "$out"/*.iso
