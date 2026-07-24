# Agave Linux build environment: x86_64 Arch with archiso + packaging tools.
# Run privileged (mkarchiso needs loop devices); under OrbStack this runs
# via Rosetta on Apple Silicon. The same image is used by CI.
FROM --platform=linux/amd64 archlinux:latest

# pacman's seccomp download sandbox breaks under Rosetta emulation
# ("error restricting syscalls via seccomp: 22"); disable it in-container.
RUN sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf

RUN pacman -Syu --noconfirm --needed \
      base-devel git archiso grub dosfstools mtools rsync jq \
      pacman-contrib devtools namcap rustup \
      cmake nasm go \
    && pacman -Scc --noconfirm
# cmake + nasm + go: build deps of aws-lc-sys (rustls crypto backend, pulled
# in by wayle-mango via reqwest). aws-lc-sys builds its bundled C crypto
# library reliably on NATIVE x86_64 but not under Rosetta/QEMU emulation, so
# wayle-mango is a CI-only build (docs/PLAN.md "CI is canonical"); these tools
# are here so the same image builds it on native x86_64 CI runners.

# makepkg refuses to run as root; builds happen as this user.
RUN useradd -m -G wheel builder \
    && echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder \
    && chmod 440 /etc/sudoers.d/builder

# Rust toolchain for wayle-mango builds
RUN sudo -u builder rustup default stable

WORKDIR /work
