# Agave Linux — build entry points
# CI (GitHub Actions) is canonical; these recipes drive the same scripts
# inside a privileged x86_64 Arch container (OrbStack/Rosetta) locally.

image := 'agave-build'
version := `date +%Y.%m`
platform := 'linux/amd64'

# Default: list available recipes
default:
  @just --list

# Build the x86_64 Arch build-container image
container:
  docker build --platform {{platform}} -t {{image}} containers/

# Privileged interactive shell in the build container, repo mounted at /work
shell: container
  docker run --rm -it --privileged --platform {{platform}} \
    -v "{{justfile_directory()}}:/work" -w /work {{image}} bash

# Regenerate the agave-desktop package tree from owlmango (runs on the host)
gen-desktop:
  scripts/gen-agave-desktop.sh

# Build all PKGBUILDs and assemble the [agaveos] repo (inside the container)
packages: container
  docker run --rm --privileged --platform {{platform}} \
    -v "{{justfile_directory()}}:/work" -w /work {{image}} \
    scripts/build-packages.sh

# Build the live ISO with mkarchiso (inside the container)
iso: container
  docker run --rm --privileged --platform {{platform}} \
    -v "{{justfile_directory()}}:/work" -w /work {{image}} \
    scripts/build-iso.sh

# QEMU boot smoke test against the newest ISO in out/ (runs on the host)
test-iso:
  scripts/test-iso.sh

# Remove build artifacts
clean:
  rm -rf out work repo
  find pkgbuilds -type d \( -name src -o -name pkg \) -prune -exec rm -rf {} +
