# Checkpoint — updated 2026-08-01: PHASE 2 COMPLETE ✅

**Milestone reached:** full Calamares install in UTM succeeded (all 33 jobs,
`completion: succeeded`), and the installed system cold-boots without the ISO:
GRUB → greetd → autologin `alan` → Mango+Wayle desktop, clean rendering, zero
compositor errors (verified in the installed system's own journal — evidence in
`milestones/`). Next: **Phase 3** (snapper verification — note
`snapper create-config` warned during install and needs fixing; 3-kernel GRUB
entries; LUKS + manual-partition test paths), per PLAN.md.

New open items from Phase 2 testing:
- `snapper create-config` fails in the chroot (warning, non-blocking) — fix in
  Phase 3 (likely needs dbus or `--no-dbus` flag).
- Testing-only log collector survives onto systems installed from TESTING ISOs
  (harmless; final ISOs never contain it; optionally strip in agave-cleanup).

---

# Original checkpoint — 2026-07-31

Resume point for Agave Linux development. Plan: [PLAN.md](PLAN.md). Repo:
`github.com/acchapdev/agaveos` (push via `git@github-personal:...` SSH alias).

## Where we are

**Phase 0 (package infra) — DONE.** All packages build; `[agaveos]` repo
publishes to the rolling GitHub Release via `packages.yml` CI and verifies
against a clean pacman. wayle-mango's aws-lc link failure was makepkg **LTO**
(`options=('!lto')` is the fix). qgnomeplatform dropped (broken vs Qt 6.11;
qt5ct/qt6ct+adwaita-qt cover theming; skel rewrites `QT_QPA_PLATFORMTHEME` to
`qt6ct`).

**Phase 1 (live ISO) — DONE + verified.** ISO boots (UEFI systemd-boot + BIOS
syslinux, branded menus incl. safe-graphics) → greetd autologin `agave` → Mango
+ Wayle desktop (screenshot: `screenshots/phase1-mango-wayle-desktop.png`).
Key fixes en route: firstboot masked + `machine-id=uninitialized`;
`agave-session` auto-sets `WLR_RENDERER_ALLOW_SOFTWARE=1` when no
`/dev/dri/renderD*` (VMs); ISO must build in a native-fs work dir
(`AGAVE_WORK`, default `/var/tmp/agave-iso-work`) not the macOS bind mount.
`iso.yml` CI builds the ISO from the repo release (artifact verified).

**Phase 2 (Calamares) — ~95%, one rebuild + retest from done.** Full config in
`calamares/` (btrfs `@ @home @log @pkg`, offline unpackfs, users, GRUB,
branding + QML slideshow). Manual UTM install testing (huge help) found and we
fixed, in order:
1. `squashfs-tools` missing from ISO → unpackfs "unsquashfs not found".
2. archiso presets on target → mkinitcpio failed; shellprocess
   `agave-mkinitcpio-presets` now writes stock presets.
3. Kernels absent from target `/boot` (archiso strips them from the squashfs)
   → same job now copies `vmlinuz-{linux,-lts,-zen}` from
   `/run/archiso/bootmnt/agave/boot/x86_64` (runs `dontChroot: true`, `${ROOT}`).
4. **Last found bug (fix committed d83552e, NOT yet in a built ISO):** the
   `packages` job removed `agave-calamares-config` *before*
   `shellprocess@snapper`/`@cleanup` ran → exit 127. Sequence now runs
   `packages` after the shellprocess jobs.

In the last UTM run everything through GRUB install succeeded (jobs 1–29/33);
only snapper/cleanup failed due to bug 4.

## Next steps (in order)

1. `just container` is NOT needed daily; image `agave-build` exists. Rebuild the
   **testing ISO** with the sequence fix — last attempt failed on transient
   mirror "Broken pipe" errors; just re-run:
   `docker run --rm --privileged --platform linux/amd64 -e AGAVE_TESTING=1 -v ~/owl/mydistro:/mydistro -w /mydistro/agavelinux agave-build scripts/build-iso.sh`
2. ISOs stage to `~/owl/mydistro/isos/` (NOT the iCloud-synced Desktop; NEVER
   overwrite an ISO a running VM is using — `AGAVE_STAGE_DIR` timestamping in
   build-iso.sh handles this automatically, and `just iso` sets it) and
   re-run the manual UTM install (erase disk). Expect all 33 jobs to pass.
3. Reboot the VM without the ISO → verify GRUB → greetd → autologin as the
   created user → Mango desktop. **That completes the Phase 2 milestone.**
4. Debug why `agave-collect-logs.service` didn't start on the testing ISO
   (unit + wants symlink are in the squashfs but `journalctl -u` was empty; the
   manual mirror loop in ghostty works as a workaround — see below).
5. Then Phase 3 (snapper verification, 3-kernel GRUB entries, LUKS + manual
   partition paths) per PLAN.md.

## UTM testing setup (working)

- VM: QEMU x86_64 emulate, UEFI, ≥4 GB RAM; ISOs in `~/owl/mydistro/isos/`;
  ~100 GB disk.
- VirtFS share (mode VirtFS, path `…/agavelinux/utm-logs`, 9p tag `share`) —
  verified working.
- **Log setup is one command now** (ghostty: Cmd+Return; input captured by VM):
  `sudo agave-logs-setup` — mounts the share, starts/repairs the collector
  service, falls back to an inline mirror loop, prints diagnostics if the 9p
  device is missing. (`sudo bash /usr/local/bin/agave-logs-setup` if the exec
  bit is missing.) On testing ISO v3+ the collector service also starts
  automatically at boot (203/EXEC crash-loop fixed — mkarchiso strips exec
  bits; unit now invokes via bash).
- Launch installer manually: `calamares-launch &`.
- Logs appear on host at `utm-logs/install-logs/`; watch with a Monitor on
  `calamares-session.log` grepping `Starting job|ERROR`.

## Open items / debts

- GPG signing key not generated (`scripts/gen-signing-key.sh`; secret
  `AGAVE_GPG_PRIVATE_KEY`; re-enable `agave-keyring` in `packages.x86_64` after).
- `agave-collect-logs` service didn't auto-start (see next steps #4).
- gh manual `workflow run` returns 403 (token scope); `workflow_run` auto-chain
  packages→iso works on push.
- Old QEMU headless harness: `/tmp/qmp-drive.sh` (click/type/shot via QMP);
  needs `-device qemu-xhci -device usb-tablet` for abs mouse.
- mkarchiso deprecation warnings: bootmode names (`bios.syslinux.mbr` →
  `bios.syslinux` etc.) — cosmetic, tidy later.
