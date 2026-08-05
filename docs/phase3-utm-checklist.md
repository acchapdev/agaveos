# Phase 3 — UTM verification checklist

Everything below was fixed and verified in containers this session, but **none
of it has run on a real install**. This checklist is what turns that into
Phase 3 being genuinely done. Commits: `5cbaac3`, `8b40ade`, `821026e`,
`c23c814`.

VM: QEMU x86_64 (emulate), UEFI, ≥4 GB RAM, ~100 GB disk, VirtFS tag `share`
→ host `utm-logs/`. Archive any previous `utm-logs/install-logs/` before
starting (the log file is overwritten between runs).

---

## Run 1 — plain install (erase disk, btrfs, no encryption)

The regression check: this is the path Phase 2 already proved, re-run because
the initramfs hook stack changed underneath it.

1. Boot the testing ISO → live desktop.
2. Install: erase disk, btrfs, create a user. Watch from the host with
   `grep -E "Starting job|ERROR" utm-logs/install-logs/calamares-session.log`.
3. Expect **zero** job failures. `luksbootkeyfile` runs but is a no-op
   ("Nothing to do for LUKS" / "No root partition").
4. Reboot into the installed system, then verify:

```sh
# --- GRUB: 3 kernels, linux is the default, name not doubled -------------
sudo grep -E "^menuentry|^\s+menuentry" /boot/grub/grub.cfg
#  expect: top-level "Agave Linux"  (NOT "Agave Linux Linux")
#  expect: linux, linux-lts, linux-zen each with a (fallback initramfs) twin
sudo grep -m1 -A6 "^menuentry" /boot/grub/grub.cfg | grep "linux\s*/"
#  expect: /@/boot/vmlinuz-linux   (NOT vmlinuz-linux-zen)
uname -r          # expect the plain arch kernel, not -zen / -lts

# --- the defaults block is no longer dead config -------------------------
grep -E "GRUB_TIMEOUT|GRUB_DEFAULT|GRUB_TOP_LEVEL|GRUB_DISABLE_SUBMENU" /etc/default/grub
#  expect GRUB_TOP_LEVEL present and GRUB_DEFAULT='saved' — if these are
#  missing, always_use_defaults regressed to false

# --- initramfs: systemd hook stack --------------------------------------
grep ^HOOKS /etc/mkinitcpio.conf     # expect systemd + sd-vconsole, NOT udev/keymap
ls /boot/initramfs-*.img             # expect 6: 3 kernels x (default + fallback)

# --- snapper (the Phase 3.1 fix) ----------------------------------------
sudo snapper -c root list            # must NOT error
grep SUBVOLUME /etc/snapper/configs/root        # expect "/"
sudo btrfs subvolume show /.snapshots | head -3 # expect a real subvolume
systemctl is-enabled snapper-timeline.timer snapper-cleanup.timer grub-btrfsd
grep SNAPPER_CONFIGS /etc/conf.d/snapper        # expect "root"

# --- the testing collector must be gone ---------------------------------
ls /usr/local/bin/agave-collect-logs /usr/local/bin/agave-logs-setup 2>&1
#  expect: No such file or directory (both)

# --- snapshot submenu ----------------------------------------------------
sudo snapper -c root create -d "checklist test"
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo grep -ic "snapshot" /boot/grub/grub.cfg    # expect > 0
```

5. Reboot once more and confirm the GRUB snapshot submenu is visible and the
   system still boots.

## Run 2 — LUKS install (the path that has never been tested)

Fixes #2 and #4 exist entirely for this run. If `useSystemdHook` had stayed
false, this install would produce an **unbootable** system — so a successful
boot here is the real proof.

1. Fresh VM/disk. Install with **encryption enabled** (erase disk + LUKS
   passphrase). Use a passphrase you can type on the VM's keymap.
2. Watch the log for `luksbootkeyfile` — it should now actually do work
   ("There are 1 LUKS partitions"), not skip.
3. Reboot. **You should be asked for the passphrase exactly once** (by GRUB).
   If you are asked a second time, `/crypto_keyfile.bin` was not picked up.
4. Then verify:

```sh
grep ^HOOKS /etc/mkinitcpio.conf         # expect sd-encrypt, NOT encrypt
grep ^FILES /etc/mkinitcpio.conf         # expect /crypto_keyfile.bin
grep -E "GRUB_ENABLE_CRYPTODISK|rd.luks" /etc/default/grub
#  expect GRUB_ENABLE_CRYPTODISK=y and rd.luks.uuid= in the cmdline
#  (NOT cryptdevice= — that would mean grubcfg and the hook disagree)
sudo ls -l /crypto_keyfile.bin           # expect root-only perms
lsblk -f                                 # expect crypto_LUKS + btrfs inside
sudo snapper -c root list                # snapper still works on encrypted root
```

**If it fails to boot**, capture the initramfs emergency-shell message — the
distinguishing symptom is `encrypt` vs `sd-encrypt` disagreeing with the
kernel cmdline (`cryptdevice=` vs `rd.luks.uuid=`).

## Run 3 — manual partitioning

Confirms the `@`/`@home`/`@log`/`@pkg` subvolume layout is applied outside the
erase-disk path (`agave-snapper` depends on `@`).

1. Manual partitioning: ESP at `/efi` (≥512 MiB, fat32) + btrfs root at `/`.
2. After install:

```sh
sudo btrfs subvolume list /     # expect @, @home, @log, @pkg
findmnt -no OPTIONS /           # expect subvol=/@ , compress=zstd:1, noatime
findmnt /var/log /var/cache/pacman/pkg
sudo snapper -c root list       # expect the config to exist on this path too
```

---

## Reporting back

For each run, the useful evidence is: the Calamares job list (any ERROR
lines), whether the system cold-boots to the desktop, and the command output
above. Screenshots of the GRUB menu are worth having for runs 1 and 2 — the
entry titles are themselves two of the fixes.
