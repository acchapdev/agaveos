#!/usr/bin/env bash
# shellcheck disable=SC2034
# Agave Linux archiso profile (based on releng). Boots the real Mango + Wayle
# desktop with greetd autologin and auto-launches Calamares (docs/PLAN.md
# Phase 1). Offline unpackfs install — what you boot is what gets copied.

iso_name="agaveos"
iso_label="AGAVE_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Agave Linux <https://github.com/acchapm1/agavelinux>"
iso_application="Agave Linux Live/Install medium"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m)"
install_dir="agave"
buildmodes=('iso')
# BIOS via syslinux; UEFI via systemd-boot. (mkarchiso rejects grub + systemd-
# boot on the same ESP — systemd-boot is the primary UEFI loader; the grub/
# loopback.cfg still serves USB-loopback boots.)
bootmodes=('bios.syslinux.mbr'
           'bios.syslinux.eltorito'
           'uefi-x64.systemd-boot.esp'
           'uefi-x64.systemd-boot.eltorito')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
# zstd (vs releng's xz) — the offline install copies this squashfs to disk, so
# faster decompression at install time matters more than a few % of ISO size.
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '18' '-b' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/etc/sudoers.d"]="0:0:750"
  ["/usr/local/bin/agave-live-setup"]="0:0:755"
  ["/usr/local/bin/agave-session"]="0:0:755"
)
