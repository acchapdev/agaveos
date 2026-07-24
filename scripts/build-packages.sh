#!/usr/bin/env bash
# Build every [agaveos] package and assemble the pacman repo in repo/.
#
# Runs INSIDE the x86_64 Arch build container (as root) — locally via
# `just packages`, in CI via .github/workflows/packages.yml. Builds happen
# under the unprivileged `builder` user in its home (bind-mounted /work may
# not be writable by builder), artifacts are collected into /work/repo.
#
# Environment:
#   OWLMANGO_DIR   owlmango checkout (default: /work/../owlmango, CI: ./owlmango)
#   BUILD_ONLY     space-separated subset of package dirs to build (iteration)
#   AGAVE_SIGN     1 to GPG-sign packages + repo db (requires the signing key
#                  in builder's gpg; CI imports it from a secret)
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
repo_out="$repo_root/repo"
db_name='agaveos'
builder_home=$(getent passwd builder | cut -d: -f6)

[ -n "$builder_home" ] || { echo "error: no builder user (run inside the build container)" >&2; exit 1; }

log() { printf '\n==> %s\n' "$*"; }

# Build order matters: a package that is a build/runtime dependency of a later
# one must come first — each built package is pacman -U'd immediately (below)
# so subsequent --syncdeps builds resolve it. scenefx0.5 -> mangowm;
# calamares -> agave-calamares-config.
packages=(
  agave-release
  agave-keyring
  agave-desktop
  aur-mirrors/scenefx0.5
  aur-mirrors/mangowm
  aur-mirrors/wayle-mango
  aur-mirrors/calamares
  agave-calamares-config
  aur-mirrors/elephant
  aur-mirrors/elephant-desktopapplications
  aur-mirrors/walker-bin
  aur-mirrors/zen-browser-bin
  aur-mirrors/adwaita-qt
  aur-mirrors/qgnomeplatform
  aur-mirrors/font-awesome-5
  aur-mirrors/beeper-v4-bin
)
if [ -n "${BUILD_ONLY:-}" ]; then
  read -r -a packages <<< "$BUILD_ONLY"
fi

log "refreshing base system"
pacman -Syu --noconfirm

# --- generated package inputs ----------------------------------------------
if [ -d "${OWLMANGO_DIR:-$repo_root/../owlmango}/config" ]; then
  log "generating agave-desktop payload from owlmango"
  "$repo_root/scripts/gen-agave-desktop.sh"
else
  echo "warning: owlmango not found — reusing existing agave-desktop payload tarball" >&2
  [ -f "$repo_root/pkgbuilds/agave-desktop/agave-desktop-payload.tar.gz" ] || {
    echo "error: no agave-desktop payload; set OWLMANGO_DIR" >&2; exit 1; }
fi

log "packing calamares config"
tar -czf "$repo_root/pkgbuilds/agave-calamares-config/calamares-config.tar.gz" \
  -C "$repo_root/calamares" .

# --- build loop ------------------------------------------------------------
mkdir -p "$repo_out"
pkgdest="$builder_home/pkgdest"
install -d -o builder "$pkgdest"

failed=()
for rel in "${packages[@]}"; do
  name=$(basename "$rel")
  src="$repo_root/pkgbuilds/$rel"
  [ -d "$src" ] || { echo "error: unknown package dir $rel" >&2; exit 1; }

  if [ "$name" = agave-keyring ] && [ ! -s "$src/keyring/agave-trusted" ]; then
    echo "warning: skipping agave-keyring (no key yet — scripts/gen-signing-key.sh)" >&2
    continue
  fi

  log "building $name"
  build_dir="$builder_home/build/$name"
  rm -rf "$build_dir"
  mkdir -p "$builder_home/build"
  cp -a "$src" "$build_dir"
  chown -R builder "$build_dir"

  makepkg_args=(--syncdeps --noconfirm --force --cleanbuild)
  [ "${AGAVE_SIGN:-0}" = 1 ] && makepkg_args+=(--sign)
  if sudo -u builder env PKGDEST="$pkgdest" \
       sh -c "cd '$build_dir' && makepkg ${makepkg_args[*]}"; then
    # Install every package this PKGBUILD produced into the (throwaway) build
    # container so later --syncdeps builds resolve local inter-package deps:
    #   scenefx0.5 -> mangowm ; calamares -> agave-calamares-config ;
    #   elephant -> walker-bin ; etc. --packagelist handles split packages
    #   (adwaita-qt5/6); --asdeps keeps them non-explicit. Non-fatal on error.
    while IFS= read -r built; do
      [ -e "$built" ] || continue
      pacman -U --noconfirm --asdeps "$built" 2>/dev/null || true
    done < <(sudo -u builder env PKGDEST="$pkgdest" \
               sh -c "cd '$build_dir' && makepkg --packagelist" 2>/dev/null)
  else
    failed+=("$name")
    echo "ERROR: $name failed to build" >&2
  fi
done

# --- assemble repo ---------------------------------------------------------
log "assembling [$db_name] repo"
cp "$pkgdest"/*.pkg.tar.zst "$repo_out"/ 2>/dev/null || true
[ "${AGAVE_SIGN:-0}" = 1 ] && cp "$pkgdest"/*.pkg.tar.zst.sig "$repo_out"/ 2>/dev/null || true

shopt -s nullglob
pkgs=("$repo_out"/*.pkg.tar.zst)
if [ ${#pkgs[@]} -gt 0 ]; then
  repo_add_args=()
  [ "${AGAVE_SIGN:-0}" = 1 ] && repo_add_args+=(--sign --verify)
  # repo-add also runs as builder so --sign finds the imported key.
  chown -R builder "$repo_out"
  sudo -u builder repo-add "${repo_add_args[@]}" "$repo_out/$db_name.db.tar.gz" "${pkgs[@]}"
fi

log "repo contents"
/bin/ls -la "$repo_out"

if [ ${#failed[@]} -gt 0 ]; then
  printf '\nFAILED packages: %s\n' "${failed[*]}" >&2
  exit 1
fi
log "all packages built"
