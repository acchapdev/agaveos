# Checkpoint — 2026-08-06 · Phases 0–3 COMPLETE ✅ · debts next, then Phase 4/5

Resume point for Agave Linux development. Plan: [PLAN.md](PLAN.md). Repo:
`github.com/acchapdev/agaveos` (push via the `git@github-personal:` SSH alias;
run `gh auth status` first — must be acchapdev, never acchapm1).

> **Note on identity:** two GitHub accounts are logged in to `gh`: acchapdev
> (owns the repo) and acchapm1. Git pushes always go to the right place — the
> `origin` remote uses the `github-personal` SSH alias, and
> `ssh -T git@github-personal` authenticates as **acchapdev**. But `gh` follows
> its *active* account, and when that was acchapm1, `gh pr create` failed with
> `must be a collaborator`. Fix: `gh auth switch --user acchapdev` (done
> 2026-11-02; PR #1 was then created and merged). Check `gh auth status` at the
> start of a session — it may have been switched back.

## RESUME HERE (2026-08-06)

All Phase 3 code work is **committed** (code through `b0f05bd`; this session
added verification-record commits on top). CI is green end-to-end: packages +
ISO both succeeded on the native runner. **Phase 3 is now fully verified — all
three UTM runs passed.** Untracked in the working tree:
`docs/agave-linux-handoff-2026-08-01.md` and `img/`.

The Phase 3 verification commits were pushed to `origin/main` on 2026-11-02,
and the collector atomic-publish fix (Debt 3) landed via PR #1 (`87afbb6`).

**Run 1 (plain install) PASSED on 2026-08-06.** The user worked through every
command in [`phase3-utm-checklist.md`](phase3-utm-checklist.md) Run 1 and all
of it verified correct: GRUB shows 3 kernels defaulting to plain `linux` with
the un-doubled "Agave Linux" title, the `defaults:` block is live
(`GRUB_TOP_LEVEL` present), the systemd hook stack is in `mkinitcpio.conf`,
snapper works with a real `.snapshots` subvolume and enabled timers, the
testing collector is stripped from the installed system, and the snapshot
submenu appears after creating a snapshot. Fixes #1 (snapper `--no-dbus`),
#2 (`useSystemdHook`), #3 (collector stripping) and #4 (3 kernels + GRUB) are
now confirmed on a real install.

**Run 2 (LUKS install) PASSED on 2026-08-06 — the decisive run.** This was the
only path exercising `sd-encrypt` + `rd.luks.uuid=` + `luksbootkeyfile`, and
had `useSystemdHook` stayed false it would have produced an unbootable system.
It cold-booted to the desktop and the user confirmed all the checklist output.
Evidence in `utm-logs/archive/run2-luks-20260806-1146/`:

- All **34 jobs ran with zero ERROR lines**.
- `Configuring LUKS key file.` (25/34) reported `There are 1 LUKS partitions`
  — real work, not the Run 1 no-op — found `LUKS 2 ... on device "/dev/sda2"`
  (so `luksGeneration: luks2` took effect), and ran `luksAddKey`. That call
  took ~44 s, which is argon2 doing a genuine key enrollment.
- `crypto_keyfile.bin` was created `-rw------- root root` in the target.
- mkinitcpio logged **`-> Running build hook: [sd-encrypt]`** — the systemd
  crypt hook, NOT the legacy `encrypt` hook. This is the single most important
  line in the run; it is what fix #2 existed to produce.
- grubcfg then ran its `grep -q "^HOOKS.*systemd" /etc/mkinitcpio.conf` probe
  after initcpiocfg had already written that stack, so it emitted
  `rd.luks.uuid=` rather than `cryptdevice=` — the two halves agree.
- **The passphrase was requested exactly once** (by GRUB). That confirms the
  initramfs picked up `/crypto_keyfile.bin` instead of prompting a second
  time, i.e. the `luksbootkeyfile` module added in `c23c814` works.

The mkinitcpio `Possibly missing firmware for module:` warnings (qat_6xxx,
ast, aic94xx, bfa, qed, qla*, wd719x, xhci_pci_renesas) are stock Arch noise
for hardware the VM lacks — unrelated to any Agave change, safe to ignore.

**Run 3 (manual partitioning) PASSED on 2026-08-06.** All 35 jobs (35 not 34 —
manual partitioning adds two explicit partition-delete jobs), zero real errors,
Calamares shut down cleanly. Evidence in
`utm-logs/archive/run3-manual-20260806-1559/`:

- The subvolume layout is correct outside the erase-disk path — this was the
  whole point of the run, since `agave-snapper` depends on `@` existing. Job 11
  (`mount`) created and mounted `@`→`/`, `@home`→`/home`, `@log`→`/var/log`,
  `@pkg`→`/var/cache/pacman/pkg`, all with
  `noatime,compress=zstd:1,space_cache=v2`; ESP mounted at `/efi` with
  `fmask=0137,dmask=0027`.
- `agave-snapper` did full work here too: created the root config, applied
  retention, enabled the snapper timers and grub-btrfsd.
- snapper pre/post snapshots ran during the package transaction (`(1/1)
  Performing snapper pre snapshots` / `(6/6) ... post snapshots`), so the
  pacman hooks are live on this path.

**Beware grepping the Calamares log for `ERROR` case-insensitively** — it
matches four benign lines: two `WARNING`s whose DBus error *type names* contain
"Error", the literal `Installation finished. No error reported.`, and
grub-btrfs bug-report boilerplate. Match case-sensitively or on `[Ee]RROR:`.

## Next: clear the open debts (user's call, 2026-08-06)

Phase 3 is done. The chosen next step is **clearing the open debts** before
Phase 4 (NVIDIA) or Phase 5 (CI QEMU install test).

### Debt 1 — GPG repo signing (BLOCKED ON USER; cannot be automated)

All the plumbing already exists and is correct — this needs only the key.
`build-packages.sh` threads `AGAVE_SIGN` into `makepkg --sign`, copies `.sig`
files, and runs `repo-add --sign --verify`; `packages.yml` detects the
`AGAVE_GPG_PRIVATE_KEY` secret, imports it as the `builder` user, and degrades
to an unsigned build with a `::warning::` when it is absent (which is why every
build so far has worked). `agave-keyring` self-gates: `build-packages.sh` skips
it while `pkgbuilds/agave-keyring/keyring/agave-trusted` is empty, so the build
starts including it the moment the key exists.

Three steps, all requiring the user (private key generation + repo secret):

1. `./scripts/gen-signing-key.sh` — generates an ed25519 key in the user's real
   GPG keyring, writes the public keyring/trust files into
   `pkgbuilds/agave-keyring/keyring/` (committed), and exports the private key
   to `agave-signing-key.private.asc` (gitignored).
2. `gh secret set AGAVE_GPG_PRIVATE_KEY < agave-signing-key.private.asc`
3. Back the private key up to a password manager, then `rm -P` the local copy.

⚠️ **Step 2 failed with 403 in the past** because `gh`'s active account was
acchapm1, not the repo owner acchapdev (same cause as the old `gh workflow run`
403). With `gh auth switch --user acchapdev` it should work now, but this is
**not yet verified for secrets** — only `gh pr create` has been confirmed. Run
`gh auth status` first; if it still 403s, set the secret in the GitHub web UI.

**Only after a signed `packages.yml` run has published:** uncomment
`agave-keyring` in `iso/packages.x86_64` (~line 101). Doing it earlier breaks
the ISO build, because the package will not be in the repo yet.

### Debt 2 — stale collector debt entry — DONE (2026-08-06)

Verified and removed from Open items. `agave-cleanup` deletes both binaries,
the service unit and its `multi-user.target.wants` symlink, and Run 1 confirmed
both are absent from the installed system. Closed by `8b40ade`.

### Debt 3 — collector rewrites its log file — FIXED (untested on a live ISO)

`iso/airootfs-testing/usr/local/bin/agave-collect-logs` does `cp -f` of the
whole session log into the share every 5 s. Because the file is replaced rather
than appended to, host-side `tail -f` breaks — it re-reads from the top each
cycle and replays the same lines forever (this happened this session; a Monitor
had to be killed). It also makes mtime an unreliable liveness signal: during
Run 3 the log looked frozen at 15:27 for ~25 min while unpackfs ran, then
jumped straight to job 32. **Poll the file, do not `tail -f` it.** Fix: `publish()` in `agave-collect-logs` now writes a dot-temp file and `mv`s it over the target, skipping the rename when content is unchanged (so mtime moves only when the log grows). `tail -f` still follows the old inode — keep polling. Needs one real testing-ISO build to confirm on 9p. Writing to a
temp file and `mv`-ing atomically would fix this and is worth doing before
Phase 5 builds a CI install test on top of this collector.

## Testing-loop gotchas (learned the hard way this session)

- **Archive `utm-logs/install-logs/` before each run** — the collector
  overwrites those files, and a stale log is easy to misread as live progress.
  All three runs are archived under `utm-logs/archive/run{1,2,3}-*`.
- After Run 1 the host-side `install-logs/` came up empty even though streaming
  had worked during the run; Runs 2 and 3 streamed fine. Unexplained, low
  priority. If a stream goes quiet, check `journalctl -u agave-collect-logs` in
  the guest — but remember a quiet log during unpackfs is normal (see Debt 3).
- Testing ISO used for all three runs:
  `~/owl/mydistro/isos/agaveos-2026.08-x86_64-20260805-1927.iso` (4.2 GB,
  `AGAVE_202608`, `AGAVE_TESTING=1`).

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

## Phase 3 — COMPLETE (all six fixes verified on real installs 2026-08-06)

### The fixes, and why each was made

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

5. **LUKS keyfile** (`c23c814`) — `luksbootkeyfile` added to the sequence so an
   encrypted install does not ask for the passphrase twice. Sequence went from
   33 to 34 jobs.

### Verification status — ALL THREE RUNS PASSED (2026-08-06)

Ran against `~/owl/mydistro/isos/agaveos-2026.08-x86_64-20260805-1927.iso`
(4.2 GB, `AGAVE_202608`, `AGAVE_TESTING=1`). Logs archived under
`utm-logs/archive/run{1,2,3}-*`. Procedure:
[`phase3-utm-checklist.md`](phase3-utm-checklist.md).

| Run | Path | Result |
|-----|------|--------|
| 1 | plain (erase disk, btrfs) | ✅ 34 jobs, full checklist verified on-device |
| 2 | **LUKS** | ✅ 34 jobs, `sd-encrypt` built, one passphrase prompt |
| 3 | manual partitioning | ✅ 35 jobs, `@/@home/@log/@pkg` correct, snapper ran |

What each run proved is written up in the RESUME section above. The short
version: fixes #1–#4 confirmed by Run 1, #2 and #5 confirmed decisively by
Run 2 (the `-> Running build hook: [sd-encrypt]` line is the one that matters —
with `useSystemdHook: false` that install would have been unbootable), and the
subvolume layout confirmed outside the erase-disk path by Run 3.

**Next per PLAN.md:** clear the open debts (see RESUME above), then Phase 4
(NVIDIA) and Phase 5 (CI QEMU install test). Phase 5 is worth prioritising —
it would automate exactly the manual UTM verification this session spent hours
on, and would catch this class of regression on every push.

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
  **polling** (not `tail -f` — see Debt 3)
  `utm-logs/install-logs/calamares-session.log` for `Starting job|ERROR`,
  case-sensitively. A quiet log during `unpackfs` is normal: that job takes
  ~25 min under emulation and writes rsync progress to the terminal, not the
  log, so mtime can look frozen while the install is healthy.

## Open items / debts

- **GPG signing key not generated** — the one real blocker, and it needs the
  user. Full detail in the RESUME section above (Debt 1): plumbing is complete,
  `gh secret set` needs `gh` switched to acchapdev (see the identity note), and
  `agave-keyring` in `iso/packages.x86_64` must stay commented until a signed
  packages run has published.
- **Collector atomic publish (Debt 3) is merged but unverified on a live ISO** —
  needs one testing-ISO build + a UTM boot to confirm `mv` over the 9p share
  behaves. Host-side `tail -f` still won't follow it; keep polling.
- gh manual `workflow run` → 403 was the same wrong-active-account cause; retry
  after `gh auth switch --user acchapdev` (untested). The push-triggered
  `workflow_run` chain packages→iso works regardless.
- mkarchiso bootmode deprecation warnings (cosmetic rename someday).
- Headless QEMU driver for reference: `/tmp/qmp-drive.sh` pattern (needs
  `-device qemu-xhci -device usb-tablet` for absolute mouse).

~~Testing-ISO installs carry the log collector onto disk~~ — **CLOSED**
(`8b40ade`). `agave-cleanup` removes both binaries, the unit, and its
`multi-user.target.wants` symlink; Run 1 confirmed both are absent from the
installed system.
