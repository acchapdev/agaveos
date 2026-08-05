# Checkpoint — 2026-08-01 · Phases 0–2 COMPLETE ✅ · Next: Phase 3

Resume point for Agave Linux development. Plan: [PLAN.md](PLAN.md). Repo:
`github.com/acchapdev/agaveos` (push via the `git@github-personal:` SSH alias;
run `gh auth status` first — must be acchapdev, never acchapm1).

## Proven working (do not re-verify)

- **Phase 0** — all packages build; `[agaveos]` repo publishes via packages.yml
  CI to the rolling "repo" Release and verifies against clean pacman.
  wayle-mango needs `options=('!lto')` (makepkg LTO corrupts aws-lc-sys).
- **Phase 1** — live ISO boots (UEFI systemd-boot + BIOS syslinux, branded
  menus, safe-graphics entry) into the Mango+Wayle desktop; software-rendering
  fallback for VMs. CI iso.yml builds the ISO from the repo release.
- **Phase 2** — full Calamares install in UTM: all 33 jobs, then cold boot of
  the installed system → GRUB → greetd → autologin created user → desktop,
  zero compositor errors. Evidence: `milestones/`. Milestone commit `ceaea50`.

Key architecture decisions that must survive refactors:
- greetd (live AND installed) launches **`/usr/lib/agave/session`** (ships in
  agave-desktop): safe-graphics flag → pixman; no `/dev/dri/renderD*` →
  `WLR_RENDERER_ALLOW_SOFTWARE=1`; under software rendering writes a managed
  `animations=0` block into `~/.config/mango/host.conf` (frozen animations
  break click hit-testing at ~1 fps).
- Calamares sequence: the `packages` removal job MUST run after
  `shellprocess@snapper`/`@cleanup` (it deletes agave-calamares-config, which
  ships those scripts).
- `shellprocess@mkinitcpio` (dontChroot, `${ROOT}`) copies vmlinuz-* from the
  live medium (archiso strips kernels from the squashfs) and writes stock
  presets before initcpio runs.
- owlmango (`~/owl/mydistro/owlmango`) stays upstream source of truth;
  regenerate the desktop payload with `scripts/gen-agave-desktop.sh`.

## Phase 3 progress

### Done in code, verified in containers — needs a UTM install to confirm

1. **snapper in the chroot — FIXED** (`5cbaac3`). Root cause was not a guess:
   reproduced in a pacstrapped btrfs chroot, `create-config` died with
   `Failure (org.freedesktop.DBus.Error.FileNotFound)` — snapper's CLI talks to
   snapperd over DBus and there is no DBus in the Calamares chroot. `--no-dbus`
   is now used for **every** snapper call (set-config was failing the same way,
   silently, because errors went to `/dev/null`). Verified end-to-end in a real
   chroot: `SUBVOLUME="/"`, retention applied, `.snapshots` created as a real
   subvolume, snapper timers + grub-btrfsd enabled, and re-running is
   idempotent. The script now logs snapper's actual error instead of hiding it.
2. **initramfs hook stack — FIXED** (`5cbaac3`), a latent bug found while
   preparing the LUKS test. `initcpiocfg.conf` had `useSystemdHook: false`
   while the ISO ships `HOOKS=(base systemd … sd-vconsole …)`. initcpiocfg
   *replaces* the hook list wholesale, so every install was silently downgraded
   to the udev/keymap stack — and a LUKS install would have gotten the classic
   `encrypt` hook, which cannot work in a systemd-hook initramfs (unbootable).
   Phase 2 never caught it because only unencrypted installs were tested.
   Now `true`: confirmed the target has `systemd-cat` (which gates the flag)
   and the `sd-encrypt`/`sd-vconsole` hooks, and that the resulting hook set
   really builds (`mkinitcpio -p linux` succeeds; the image contains
   `systemd-cryptsetup`). This also fixes grubcfg *by construction* — grubcfg
   greps the target's `mkinitcpio.conf` for a systemd hook to choose between
   `rd.luks.uuid=` and `cryptdevice=`, and initcpiocfg runs before it.
3. **Testing log collector no longer lands on installs** (`8b40ade`) — closes
   a listed debt; no-op on final ISOs.

4. **3 kernels + GRUB — FIXED** (`821026e`). Both halves now proven in
   containers. ISO side: all three `vmlinuz-*` exist at
   `/run/archiso/bootmnt/agave/boot/x86_64`, all three `pkgbase` files are in
   the squashfs, and `agave-mkinitcpio-presets` copies every kernel and writes
   correct stock presets (checked against the real ISO). GRUB side: running
   `grub-mkconfig` on a real btrfs root with all three kernels produced an
   entry per kernel with fallbacks and `rootflags=subvol=@` — but exposed two
   bugs, both fixed:
   - the default entry booted **linux-zen**, because `10_linux` reverse-version
     -sorts. Fixed with `GRUB_TOP_LEVEL=/boot/vmlinuz-linux`.
   - **the whole `defaults:` block in grubcfg.conf was dead config.** Calamares
     only applies it when `/etc/default/grub` does not exist — and the grub
     package always ships it. So the target kept stock Arch's `GRUB_DEFAULT=0`,
     `GRUB_TIMEOUT`, and a commented-out `GRUB_DISABLE_SUBMENU`; only
     `GRUB_CMDLINE_LINUX_DEFAULT`/`GRUB_DISTRIBUTOR` (written unconditionally)
     ever took effect. Fixed with `always_use_defaults: true`. **Do not set
     this back to false** — it silently reverts every GRUB default.
   - Menu also read "Agave Linux **Linux**" (GRUB appends "Linux" to
     `GRUB_DISTRIBUTOR`, which comes from branding's `bootloaderEntryName`, not
     from `defaults`). `bootloaderEntryName` is now `"Agave"`.

### Still to verify (needs the user's UTM loop)

**→ Run [`phase3-utm-checklist.md`](phase3-utm-checklist.md)** — three runs
(plain / LUKS / manual partitioning) with the exact verification commands and
expected output for each fix.

5. Confirm the above on a real install: snapper config present + `.snapshots`
   subvolume + timers, a GRUB menu with all 3 kernels defaulting to `linux`,
   and the snapshot submenu appearing after a snapshot exists.
6. **LUKS + manual partitioning** in UTM (Phase 3.3). Config analysis says this
   should now work: `luksGeneration: luks2`, `allowManualPartitioning: true`,
   and because the ESP mounts at `/efi` (no `/boot` partition) Calamares sets
   `GRUB_ENABLE_CRYPTODISK=y` automatically and emits `rd.luks.uuid=` to match
   the now-correct `sd-encrypt` hook. Untested on real hardware.
7. Then Phase 4 (NVIDIA) and Phase 5 (CI QEMU install test) per PLAN.md.

Note: `GRUB_DEFAULT: "saved"` is set without `GRUB_SAVEDEFAULT`. Calamares only
downgrades `saved` on btrfs when `GRUB_SAVEDEFAULT` is present, so nothing
breaks — `saved` falls back to the first entry, which `GRUB_TOP_LEVEL` now
makes `linux`. Left as-is.

## Build & test quick reference

- Local builds run in the `agave-build` docker image (OrbStack, x86_64/Rosetta;
  context `orbstack`). Packages:
  `docker run --rm --privileged --platform linux/amd64 -e BUILD_ONLY="<dirs>" -v ~/owl/mydistro:/mydistro -w /mydistro/agavelinux agave-build scripts/build-packages.sh`
- Testing ISO (auto-staged, timestamped):
  `docker run --rm --privileged --platform linux/amd64 -e AGAVE_TESTING=1 -e AGAVE_STAGE_DIR=/mydistro/isos -v ~/owl/mydistro:/mydistro -w /mydistro/agavelinux agave-build scripts/build-iso.sh`
- **ISOs live in `~/owl/mydistro/isos/`** — never the iCloud-synced Desktop;
  never overwrite an ISO a running VM has open (timestamping handles this).
- UTM test loop: VM = QEMU x86_64 emulate, UEFI, ≥4 GB RAM, ~100 GB disk;
  VirtFS share (tag `share`) → host `utm-logs/`; the log collector auto-starts
  on testing ISOs; `sudo agave-logs-setup` in ghostty (Cmd+Return) repairs it;
  installer relaunch: `calamares-launch &`. Watch installs from the host by
  grepping `utm-logs/install-logs/calamares-session.log` for
  `Starting job|ERROR`.

## Open items / debts

- GPG signing key not generated (`scripts/gen-signing-key.sh`, secret
  `AGAVE_GPG_PRIVATE_KEY`; re-enable `agave-keyring` in packages.x86_64 after).
- Testing-ISO installs carry the log collector onto disk (harmless, testing
  only) — optionally strip in `agave-cleanup`.
- gh manual `workflow run` → 403 (token scope); push-triggered
  `workflow_run` chain packages→iso works.
- mkarchiso bootmode deprecation warnings (cosmetic rename someday).
- Headless QEMU driver for reference: `/tmp/qmp-drive.sh` pattern (needs
  `-device qemu-xhci -device usb-tablet` for absolute mouse).
