#!/usr/bin/env bash
# Build the Agave Linux live ISO with mkarchiso. Runs inside the privileged
# x86_64 Arch build container. Placeholder until Phase 1 fills iso/ with the
# archiso profile (docs/PLAN.md).
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)

[ -f "$repo_root/iso/profiledef.sh" ] || {
  echo "error: iso/ archiso profile not implemented yet (Phase 1)" >&2
  exit 1
}

mkdir -p "$repo_root/out" "$repo_root/work"
mkarchiso -v -w "$repo_root/work" -o "$repo_root/out" "$repo_root/iso"
