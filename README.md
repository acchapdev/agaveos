# Agave Linux

Arch-based distribution shipping the Mango (dwl-based Wayland compositor) +
Wayle (GTK4 shell) desktop, installed from a live ISO via Calamares.

- **Identity:** `PRETTY_NAME="Agave Linux"`, `ID=agave`
- **Model:** Arch remix — vanilla Arch packages + small custom `[agaveos]` repo
  (EndeavourOS model)
- **ISO:** `agaveos-YYYY.MM-x86_64.iso`, offline unpackfs install (what you boot
  is what you get)
- **Filesystem:** btrfs subvolumes `@ @home @log @pkg`, snapper + snap-pac,
  zram swap, optional LUKS
- **Boot:** GRUB + grub-btrfs (snapshot submenu), UEFI and legacy BIOS
- **Kernels:** linux (default), linux-lts, linux-zen

The full design and phase plan lives in [docs/PLAN.md](docs/PLAN.md).
Desktop configuration is generated from the upstream
[owlmango](../owlmango) config tree — owlmango remains the source of truth.

## Layout

```
iso/                 archiso profile (based on releng)
calamares/           installer settings, module configs, QML branding
pkgbuilds/           [agaveos] repo packages
  agave-desktop/         skel package generated from owlmango config/
  agave-release/         os-release, branding, pacman.conf drop-in
  agave-keyring/         repo signing key
  agave-calamares-config/
  aur-mirrors/           vendored AUR PKGBUILDs (wayle-mango, mangowm, ...)
scripts/             build-packages, build-iso, gen-agave-desktop, test-iso
containers/          OrbStack/Docker x86_64 Arch build environment
.github/workflows/   packages → repo → ISO → Release; QEMU boot/install tests
```

## Building

GitHub Actions is the canonical build environment (packages → `[agaveos]` repo
→ ISO → Release). Local iteration happens in a privileged x86_64 Arch
container under OrbStack (Rosetta):

```sh
just              # list recipes
just container    # build the Arch build-container image
just shell        # privileged shell inside it (repo mounted at /work)
just packages     # build all PKGBUILDs → repo-add → sign
just iso          # mkarchiso → out/agaveos-YYYY.MM-x86_64.iso
just test-iso     # QEMU boot smoke test
```

Local x86_64 emulation is slow; CI is canonical for a reason.

## Caveats

- x86_64 only; Secure Boot is explicitly out of scope for v1.
- NVIDIA support uses `nvidia-open-dkms` (Turing or newer GPUs only).
