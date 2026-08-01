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

## Phase 3 tasks (next session)

1. **Fix `snapper create-config` failing in the Calamares chroot** — warned
   during the successful install (`calamares/scripts/agave-snapper`); likely
   needs `--no-dbus`. Then verify snapper + snap-pac + grub-btrfs snapshot
   submenu on a fresh install (PLAN.md Phase 3.1).
2. **Verify all 3 kernels** (linux default, lts, zen) have initramfs + GRUB
   entries on the installed system (Phase 3.2).
3. **Test LUKS install path and manual partitioning** in UTM (Phase 3.3).
4. Then Phase 4 (NVIDIA) and Phase 5 (CI QEMU install test) per PLAN.md.

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
