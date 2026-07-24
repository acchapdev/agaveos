#!/usr/bin/env bash
# QEMU smoke test for the newest ISO in out/. On the Mac host this is a TCG
# (unaccelerated) boot check; CI runs the full KVM boot + unattended-install
# harness (Phase 5). Boots UEFI by default; pass `bios` for the BIOS path.
#
#   scripts/test-iso.sh [uefi|bios] [--headless]
#
# --headless routes the display to none and the serial console to stdout,
# useful for logging the boot without a window.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
mode=uefi
# shellcheck disable=SC2054  # the comma is inside a single QEMU arg, not a separator
display=(-display 'default,show-cursor=on')

for arg in "$@"; do
  case "$arg" in
    uefi|bios) mode=$arg ;;
    --headless) display=(-nographic) ;;
    *) echo "usage: $0 [uefi|bios] [--headless]" >&2; exit 2 ;;
  esac
done

iso=$(/bin/ls -t "$repo_root"/out/agaveos-*.iso 2>/dev/null | head -1 || true)
[ -n "$iso" ] || { echo "error: no ISO in out/ — run 'just iso' first" >&2; exit 1; }
command -v qemu-system-x86_64 >/dev/null || {
  echo "error: qemu-system-x86_64 not found (brew install qemu)" >&2; exit 1; }

qemu=(qemu-system-x86_64
  -m 4G -smp 4
  -drive "media=cdrom,file=$iso,readonly=on"
  -boot d
  -device virtio-vga-gl -device qemu-xhci -device usb-tablet
  "${display[@]}")

if [ "$mode" = uefi ]; then
  ovmf_code=$(/bin/ls \
    /opt/homebrew/share/qemu/edk2-x86_64-code.fd \
    /usr/share/qemu/edk2-x86_64-code.fd \
    /usr/share/edk2/x64/OVMF_CODE.4m.fd 2>/dev/null | head -1 || true)
  [ -n "$ovmf_code" ] || { echo "error: OVMF firmware not found for UEFI boot" >&2; exit 1; }
  qemu+=(-drive "if=pflash,format=raw,readonly=on,file=$ovmf_code")
  echo "booting $iso (UEFI, TCG)"
else
  echo "booting $iso (BIOS, TCG)"
fi

exec "${qemu[@]}"
