#!/usr/bin/env bash
# QEMU smoke test for the newest ISO in out/. On the Mac host this is a TCG
# (unaccelerated) boot check; CI runs the full KVM boot + unattended-install
# harness. Placeholder until Phase 1 produces an ISO (docs/PLAN.md).
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
iso=$(/bin/ls -t "$repo_root"/out/agaveos-*.iso 2>/dev/null | head -1 || true)

[ -n "$iso" ] || { echo "error: no ISO in out/ — run 'just iso' first" >&2; exit 1; }
command -v qemu-system-x86_64 >/dev/null || {
  echo "error: qemu-system-x86_64 not found (brew install qemu)" >&2; exit 1; }

echo "booting $iso (UEFI, TCG)"
exec qemu-system-x86_64 \
  -m 4G -smp 4 \
  -drive "media=cdrom,file=$iso,readonly=on" \
  -boot d \
  -display default,show-cursor=on
