#!/usr/bin/env bash
# Vendor AUR package snapshots into pkgbuilds/aur-mirrors/.
#
# Fetches the current AUR snapshot (PKGBUILD + install files + patches) for
# each package below. Re-run to refresh; review the diff before committing.
# wayle-mango and mangowm are NOT vendored — they are our own PKGBUILDs.
#
# impala, wiremix and bluetui moved from the AUR to [extra] (2026-07 check)
# and are consumed as official packages instead.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
mirrors="$repo_root/pkgbuilds/aur-mirrors"

packages='
calamares
elephant
elephant-desktopapplications
walker-bin
zen-browser-bin
adwaita-qt5
adwaita-qt6
ttf-font-awesome-5
beeper-v4-bin
scenefx0.5
'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Snapshots are addressed by PackageBase (split packages like adwaita-qt5/6
# share one base), so resolve each name first and dedupe.
bases=""
for pkg in $packages; do
  base=$(curl -fsSL --max-time 30 \
    "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$pkg" \
    | jq -r '.results[0].PackageBase // empty')
  if [ -z "$base" ]; then
    echo "error: $pkg not found in AUR" >&2
    exit 1
  fi
  case " $bases " in *" $base "*) ;; *) bases="$bases $base" ;; esac
done

for base in $bases; do
  url="https://aur.archlinux.org/cgit/aur.git/snapshot/$base.tar.gz"
  if ! curl -fsSL --max-time 60 -o "$tmp/$base.tar.gz" "$url"; then
    echo "error: failed to fetch $base from AUR" >&2
    exit 1
  fi
  rm -rf "${mirrors:?}/$base"
  tar -xzf "$tmp/$base.tar.gz" -C "$mirrors"
  ver=$(sed -n 's/^pkgver=//p' "$mirrors/$base/PKGBUILD" | head -1)
  echo "vendored $base $ver"
done
