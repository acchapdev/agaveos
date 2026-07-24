# Agave Linux — Arch-based distro with graphical installer

## Context

`owlmango` (~/owl/mydistro/owlmango) is a working per-user dotfiles installer for the
Mango (dwl-based Wayland compositor) + Wayle (GTK4 shell) desktop on existing Arch
systems. The goal now is a real distribution: a bootable live ISO with a graphical
installer that produces a fully configured Agave Linux system from bare metal.
`/Users/acchapm1/owl/mydistro/owlman-arch` is the new, empty monorepo for this.

All design decisions below were resolved interactively (grill-me session, 2026-07-23).

## Decisions (locked)

| Branch | Decision |
|---|---|
| Scope | Arch **remix ISO** — vanilla Arch packages + small custom repo (EndeavourOS model) |
| Installer | **Calamares** (YAML config + Python modules + QML branding) |
| Install mode | **Offline unpackfs** — live squashfs is copied to disk; what you boot is what you get |
| Live session | Boots the real **Mango+Wayle desktop**, Calamares auto-launched; "safe graphics" boot entry as fallback |
| Custom repo | **[agaveos]** pacman repo, CI-built on GitHub Actions, served from a rolling GitHub Release; GPG-signed |
| Config delivery | **`agave-desktop` skel package** generated from owlmango's config tree (`/etc/skel/.config/...` + system bits) |
| Filesystem | **btrfs** subvolumes `@ @home @log @pkg` + **snapper + snap-pac** + zram swap; LUKS as Calamares checkbox |
| Bootloader | **GRUB + grub-btrfs** (snapshot boot submenu), UEFI **and** legacy BIOS |
| Kernels | **linux (default) + linux-lts + linux-zen**, all with initramfs + GRUB entries |
| GPU | Mesa baked in (AMD/Intel); **nvidia-open-dkms** for all 3 kernels + hardware-detect enable service (Turing+ only, documented) |
| Build env | **GitHub Actions = canonical** (packages → repo → ISO → Release); local iteration in OrbStack x86_64 (Rosetta) privileged Arch container |
| Testing | **CI QEMU/KVM**: boot test (UEFI+BIOS) + unattended Calamares install + reboot-to-greetd assertion; metal checklist on spare x86_64 machine before releases |
| Identity | `PRETTY_NAME="Agave Linux"`, `ID=agave`, repo `[agaveos]`, ISO `agaveos-YYYY.MM-x86_64.iso` (naming split is intentional, per user) |
| Layout | **Monorepo** in `owlman-arch/` |

Defaults adopted without ceremony: live user `agave` with greetd autologin; Calamares
cleanup step strips installer + live-only artifacts from the target; versioning
`YYYY.MM`; x86_64 only; Secure Boot explicitly out of scope for v1.

## Monorepo layout (`owlman-arch/`)

```
agave/
├── iso/                      # archiso profile (based on releng)
│   ├── profiledef.sh         # ISO name/label agaveos-YYYY.MM, bootmodes (BIOS+UEFI)
│   ├── packages.x86_64       # everything in the squashfs (see package inventory)
│   ├── pacman.conf           # official repos + [agaveos]
│   ├── airootfs/             # overlay: greetd autologin, live user, os-release,
│   │                         #   Calamares autostart, safe-graphics tweaks
│   ├── grub/ syslinux/ efiboot/   # boot menus incl. "safe graphics" entry
├── calamares/
│   ├── settings.conf         # module sequence
│   ├── modules/*.conf        # partition (btrfs subvols), users, grubcfg, unpackfs,
│   │                         #   shellprocess jobs (snapper setup, nvidia enable, cleanup)
│   └── branding/agave/       # QML slideshow, logos, colors
├── pkgbuilds/
│   ├── agave-desktop/        # skel package generated from owlmango config/
│   ├── agave-release/        # os-release, branding, wallpapers, pacman.conf drop-in
│   ├── agave-calamares-config/
│   ├── agave-keyring/        # repo signing key
│   └── aur-mirrors/          # calamares, mangowm, wayle-mango (NEW PKGBUILD),
│                             #   elephant, elephant-desktopapplications, walker-bin,
│                             #   zen-browser-bin, adwaita-qt5/6, qgnomeplatform-qt5/6,
│                             #   ttf-font-awesome-5, impala, wiremix, bluetui, beeper-v4-bin
├── scripts/
│   ├── build-packages.sh     # makepkg loop → repo-add → sign
│   ├── build-iso.sh          # mkarchiso wrapper (same script locally + CI)
│   ├── gen-agave-desktop.sh  # owlmango config/ → agave-desktop package tree
│   └── test-iso.sh           # QEMU boot + unattended install harness
├── .github/workflows/
│   ├── packages.yml          # PKGBUILDs → [agaveos] repo on rolling "repo" Release
│   ├── iso.yml               # mkarchiso in Arch container → ISO artifact/Release
│   └── test.yml              # KVM QEMU: boot UEFI+BIOS, autoinstall, assert greetd
└── justfile                  # default recipe first (user convention): build, test, clean
```

## Implementation phases

### Phase 0 — Package infrastructure (the foundation everything sits on)
1. Scaffold monorepo, justfile, OrbStack build container recipe (x86_64 Arch, privileged).
2. Write `gen-agave-desktop.sh`: transform `owlmango/config/` → `/etc/skel/.config/{mango,wayle,ghostty,fish,...}` + system files (greetd config launching Mango, `host.conf` handling). owlmango remains upstream source of truth.
3. **New PKGBUILD for wayle-mango** (currently `cargo install` in owlmango — biggest single packaging task). Pin mangowm to a commit (reproducibility) rather than raw `-git`.
4. Vendor/adapt remaining AUR PKGBUILDs; add `agave-release`, `agave-keyring`, `agave-calamares-config`.
5. `packages.yml` CI: build all in Arch container, `repo-add`, GPG-sign (key in GH secrets), publish to rolling `repo` Release. Verify `pacman -Sy` against it from a clean container.

### Phase 1 — Live ISO boots the desktop
1. archiso profile from `releng`, add `[agaveos]` to build pacman.conf, fill `packages.x86_64` (3 kernels, Mesa, full owlmango GUI/CLI set, calamares).
2. airootfs overlay: `agave` live user, greetd autologin → Mango session, os-release, boot menus with safe-graphics entry (`nomodeset` + software rendering env).
3. **Milestone: ISO boots to a working Mango+Wayle desktop in QEMU** (local OrbStack build, `qemu-system-x86_64` TCG smoke on the Mac).

### Phase 2 — Calamares installs it
1. Calamares config: welcome → locale → keyboard → partition (btrfs subvol layout, LUKS checkbox, erase/manual) → users → summary → unpackfs → fstab → users/locale jobs → grubcfg/bootloader → shellprocess(cleanup) → finished.
2. Cleanup job: remove calamares, live user, autologin, ISO-only services from target.
3. Branding QML (minimal but not default-blue; Agave palette to match Adwaita Pastel Dark).
4. **Milestone: full install in QEMU; installed system boots via GRUB to greetd → Mango with skel configs for the created user.**

### Phase 3 — Disk features complete
1. Snapper + snap-pac configured on target (shellprocess or baked into `agave-desktop`/`agave-release` post-install); grub-btrfs snapshot submenu; zram-generator.
2. Verify all 3 kernels get initramfs + GRUB entries, `linux` default.
3. Test LUKS path and manual partitioning path in QEMU.

### Phase 4 — NVIDIA + hardening
1. `nvidia-open-dkms` + headers for all 3 kernels in squashfs; detect service (pciid match) enables modules + `nvidia_drm.modeset=1` on live boot and on installed system; document Turing+ requirement.
2. Safe-graphics entry validated (forces software rendering, still reaches installer).

### Phase 5 — CI pipeline end-to-end
1. `iso.yml`: mkarchiso in privileged Arch container on ubuntu runner; artifact upload; tagged builds → GitHub Release with checksums.
2. `test.yml` (KVM available on GH runners): boot ISO UEFI + BIOS, wait for live session marker; run unattended Calamares install onto virtual disk; reboot; assert greetd/Mango reached. Gate releases on green.

### Phase 6 — Metal validation + first release
1. Ventoy USB; spare-machine checklist: UEFI boot, BIOS boot, Wi-Fi, GPU/compositor, backlight, suspend, full install, snapshot rollback drill (`snapper rollback` → boot snapshot from GRUB).
2. Cut `agaveos-YYYY.MM-x86_64.iso` release. README with install docs + NVIDIA/Secure Boot caveats.

## Key reuse

- `owlmango/config/**` — entire desktop configuration (mango, wayle, ghostty, fish, ssh) becomes `agave-desktop` input; don't fork it, generate from it.
- `owlmango/config/packages/arch/{cli,gui}/*.txt` — seed for `iso/packages.x86_64` and the AUR-mirror list.
- `owlmango/test/` Docker patterns — model for package-build and repo-sanity containers.
- Upstream references while building: EndeavourOS `iso-next` + `calamares` config repos, CachyOS `archiso` (both are the canonical examples of exactly this architecture).

## Verification

- **Per phase**: the milestone lines above, each demonstrable in QEMU.
- **Repo**: clean Arch container `pacman -Sy && pacman -S agave-desktop` from the hosted [agaveos] repo, signature verified.
- **End-to-end (CI, every ISO)**: boot UEFI → live desktop → unattended install → reboot → greetd+Mango up; repeat boot leg for BIOS.
- **Pre-release (manual, metal)**: Phase 6 checklist including snapshot-rollback drill and LUKS install.

## Risks / open items

- **wayle-mango packaging** is net-new work (Rust build, vendored crates for offline makepkg) — scheduled first deliberately.
- Mango+Wayle on unknown GPUs is the biggest first-impression risk — mitigated by safe-graphics entry, three kernels, and metal testing; not eliminable.
- Rosetta-emulated local builds are slow; CI is canonical for a reason.
- ISO size with 3 kernels + full desktop: expect ~3GB; acceptable, monitor.
- Secure Boot: out of scope v1, document loudly.
