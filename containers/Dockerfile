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
    && pacman -Scc --noconfirm

# makepkg refuses to run as root; builds happen as this user.
RUN useradd -m -G wheel builder \
    && echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder \
    && chmod 440 /etc/sudoers.d/builder

# Rust toolchain for wayle-mango builds
RUN sudo -u builder rustup default stable

WORKDIR /work
