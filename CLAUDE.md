# Agave Linux (agaveos)

> Arch-based distro remix: live ISO + Calamares installer shipping the Mango
> (dwl-based Wayland compositor) + Wayle (GTK4 shell) desktop.

## Read these first

- **`docs/PLAN.md`** — the locked design and phase plan. All major decisions
  (remix model, offline unpackfs install, btrfs layout, CI-canonical builds)
  were settled there; don't relitigate them.
- **`docs/CHECKPOINT.md`** — current status, next tasks, proven-working
  architecture, and the UTM test loop. **Always update it at session end.**
- `../owlmango/` (github.com/acchapm1/owlmango) is the **upstream source of
  truth for all desktop configuration**. Never fork or edit its content here —
  regenerate the desktop payload with `scripts/gen-agave-desktop.sh`.

## Tech stack

- Arch Linux packaging (PKGBUILD/makepkg, pacman repo via `repo-add`)
- archiso (`mkarchiso`, releng-derived profile in `iso/`)
- Calamares 3.4 installer (YAML modules + shellprocess bash jobs + QML branding)
- Bash scripts (shellcheck-clean, `-S warning`), `just`, GitHub Actions CI
- Local builds: Docker image `agave-build` under OrbStack (x86_64 via Rosetta)

## Directory structure

```
iso/                 archiso profile: profiledef.sh, packages.x86_64,
                     airootfs/ (live overlay), boot menus (grub/syslinux/efiboot)
iso/airootfs-testing/  testing-only overlay (log collector) — merged into the
                     ISO ONLY when AGAVE_TESTING=1; never in final ISOs
calamares/           installer: settings.conf, modules/*.conf, scripts/
                     (agave-cleanup, agave-snapper, agave-mkinitcpio-presets),
                     branding/agave/
pkgbuilds/           [agaveos] repo packages; aur-mirrors/ holds vendored AUR
                     PKGBUILDs (refresh with scripts/vendor-aur.sh)
scripts/             build-packages.sh, build-iso.sh, gen-agave-desktop.sh,
                     vendor-aur.sh, verify-repo.sh, test-iso.sh, gen-signing-key.sh
containers/          Dockerfile for the agave-build image
.github/workflows/   packages.yml (repo → rolling Release), iso.yml (ISO)
docs/                PLAN.md, CHECKPOINT.md, milestones/, screenshots/
```

Build artifacts (`out/`, `work/`, `repo/`, payload tarballs) are gitignored.
ISOs are staged to `~/owl/mydistro/isos/` — **never the Desktop** (iCloud).

## Build & run

CI (GitHub Actions, native x86_64) is canonical. Local iteration:

```sh
just              # list recipes
just container    # build the agave-build image
just packages     # all PKGBUILDs → repo-add → repo/
just iso          # mkarchiso → out/ + timestamped copy in ~/owl/mydistro/isos/
just test-iso     # QEMU (TCG) boot smoke test on the host
```

Direct invocations (subset builds, testing ISO):

```sh
docker run --rm --privileged --platform linux/amd64 \
  -e BUILD_ONLY="agave-desktop aur-mirrors/calamares" \
  -v ~/owl/mydistro:/mydistro -w /mydistro/agavelinux \
  agave-build scripts/build-packages.sh

docker run --rm --privileged --platform linux/amd64 \
  -e AGAVE_TESTING=1 -e AGAVE_STAGE_DIR=/mydistro/isos \
  -v ~/owl/mydistro:/mydistro -w /mydistro/agavelinux \
  agave-build scripts/build-iso.sh
```

## Testing

- `scripts/verify-repo.sh` — clean-pacman sync + install from `repo/` (run in
  the container; CI runs it after every package build).
- ISO smoke: `just test-iso` (UEFI via OVMF, add `bios` for legacy).
- Full install verification: UTM VM (QEMU x86_64 emulate, UEFI, ≥4 GB RAM) —
  the VirtFS log loop is documented in `docs/CHECKPOINT.md`. Install logs
  stream to `utm-logs/` (gitignored).
- Everything is emulated locally (slow); real speed only on native x86_64/CI.

## Hard-won constraints (violating these re-breaks fixed bugs)

- **wayle-mango**: keep `options=('!lto')` — makepkg LTO corrupts the
  aws-lc-sys static crypto lib (undefined `aws_lc_*` at link).
- **Calamares sequence**: `packages` (removal) must stay AFTER
  `shellprocess@snapper`/`@cleanup` — it deletes agave-calamares-config, which
  ships those scripts.
- **greetd launches `/usr/lib/agave/session`** everywhere (live + installed);
  it owns the safe-graphics/no-GPU software-rendering fallback and disables
  Mango animations under software rendering. Don't point greetd at `mango`
  directly.
- **mkarchiso strips exec bits** from airootfs overlay files; executables must
  be listed in `profiledef.sh` `file_permissions` (a listed-but-missing file
  fails the build) — testing-overlay units invoke scripts via `bash` instead.
- archiso strips kernels from the squashfs; the `shellprocess@mkinitcpio` job
  copies `vmlinuz-*` into the target and writes stock presets — keep it before
  `initcpiocfg`/`initcpio`.
- The ISO work dir must be a native Linux fs (`AGAVE_WORK`, default
  `/var/tmp/agave-iso-work`) — bind-mounted macOS paths break setcap/xattrs.
- Under Rosetta: pacman needs `DisableSandbox` (in the Dockerfile);
  `libfakeroot internal error` messages during makepkg are cosmetic.

## Conventions

- Every justfile starts with a `default` recipe running `@just --list`.
- Shell scripts pass `shellcheck -S warning`; portable across macOS host and
  Linux container (no GNU-only `install -D`, `sed -i` without suffix, etc.).
- Calamares/branding YAML validated with `yq` before committing.
- Versioning is `YYYY.MM`; ISO name `agaveos-YYYY.MM-x86_64.iso`; distro
  `ID=agave`, repo `[agaveos]` (naming split is intentional).
- Commit messages explain the why; bugs found in testing get the root cause in
  the message.

## Deployment

- Push to `main` → `packages.yml` builds all packages on a native runner,
  verifies the repo, publishes to the rolling `repo` GitHub Release →
  `iso.yml` chains via workflow_run and uploads the ISO artifact (`agave-iso`).
- Repo signing is not yet enabled (`scripts/gen-signing-key.sh` +
  `AGAVE_GPG_PRIVATE_KEY` secret; then re-enable `agave-keyring` in
  `iso/packages.x86_64`).
- Version-tag pushes (`v*`) attach the ISO + checksum to a GitHub Release.
