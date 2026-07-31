#!/usr/bin/env bash
# Generate the agave-desktop package payload from the owlmango config tree.
#
# owlmango (../owlmango by default) is the upstream source of truth for the
# Mango + Wayle desktop configuration; this script transforms its per-user
# symlink-based install into a static package tree:
#
#   payload/etc/skel/.config/...        per-user desktop + CLI configs
#   payload/etc/skel/.ssh/config        generic ssh client config
#   payload/etc/...                     system config (iwd, networkd)
#   payload/usr/share/wayland-sessions/ mango session entry
#   payload/usr/share/agave/greetd/     greetd templates (greeter/autologin);
#                                       the greetd package owns /etc/greetd/
#                                       config.toml, so the live ISO overlay
#                                       and Calamares install these instead
#
# Deliberately NOT imported from owlmango (personal / dev-machine material):
#   config/git             user identity
#   config/opencode, zed   personal editors/tools
#   config/zellij          app not in the package set
#   config/dnsmasq.d       .test dev resolver
#   config/systemd/resolved.conf.d  points DNS at that dev resolver
#   config/ssh/sshd_config.d        server login policy
#   config/security/faillock.conf   pam owns the path; policy is personal
#   config/packages        owlmango install metadata (seeds iso/packages.x86_64)
#   bin/, local/share      personal helper scripts and webapp entries
#
# The result is tarred to agave-desktop-payload.tar.gz next to the PKGBUILD.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
owlmango=${OWLMANGO_DIR:-$repo_root/../owlmango}
pkgdir="$repo_root/pkgbuilds/agave-desktop"
payload="$pkgdir/payload"

[ -d "$owlmango/config" ] || {
  echo "error: owlmango config tree not found at $owlmango (set OWLMANGO_DIR)" >&2
  exit 1
}

log() { printf '%s\n' "$*"; }

# Portable `install -D`: BSD install (macOS host) has no -D.
inst() { # inst <mode> <src> <dst>
  mkdir -p "$(dirname "$3")"
  install -m "$1" "$2" "$3"
}

rm -rf "$payload"
skel="$payload/etc/skel"
mkdir -p "$skel/.config"

# --- per-user configs -> /etc/skel/.config/ --------------------------------
# Mirrors the link_dir/link_gui_dir set in owlmango install/stages/10-user.sh.
skel_dirs='
bat bluetui btop elephant environment.d fish fzf ghostty gtk-4.0 htop
impala mango nvim qt5ct qt6ct swayidle swaylock theme upower uwsm walker
wayle wiremix wireplumber xdg-desktop-portal
'
for d in $skel_dirs; do
  src="$owlmango/config/$d"
  [ -d "$src" ] || { log "skip $d (not in owlmango)"; continue; }
  rsync -a "$src/" "$skel/.config/$d/"
done

# Agave ships qt5ct/qt6ct + adwaita-qt for Qt theming, not qgnomeplatform
# (archived upstream, broken against current Qt). owlmango's mango config sets
# QT_QPA_PLATFORMTHEME=gnome (the qgnomeplatform theme); rewrite it to qt6ct so
# Qt apps are themed by the platform theme we actually install.
mango_conf="$skel/.config/mango/config.conf"
if [ -f "$mango_conf" ]; then
  # Portable in-place edit (BSD sed -i differs from GNU); rewrite via temp file.
  sed 's/^env=QT_QPA_PLATFORMTHEME,gnome$/env=QT_QPA_PLATFORMTHEME,qt6ct/' \
    "$mango_conf" > "$mango_conf.tmp" && mv "$mango_conf.tmp" "$mango_conf"
fi

# systemd user units + helper scripts (units use %h-relative paths)
mkdir -p "$skel/.config/systemd/user"
rsync -a "$owlmango/config/systemd/user/" "$skel/.config/systemd/user/"

# Enablement symlinks, faithful to 10-user.sh (`systemctl --user enable` on
# every shipped unit, keyed by each unit's WantedBy=).
unit_dir="$skel/.config/systemd/user"
for unit in "$unit_dir"/*.service; do
  [ -f "$unit" ] || continue
  target=$(sed -n 's/^WantedBy=//p' "$unit" | head -1)
  [ -n "$target" ] || continue
  mkdir -p "$unit_dir/$target.wants"
  ln -sfn "../$(basename "$unit")" "$unit_dir/$target.wants/$(basename "$unit")"
done
# gcr-ssh-agent handles SSH_AUTH_SOCK; its unit ships with gcr.
mkdir -p "$unit_dir/sockets.target.wants"
ln -sfn /usr/lib/systemd/user/gcr-ssh-agent.socket \
  "$unit_dir/sockets.target.wants/gcr-ssh-agent.socket"
# Mask socket activation; the keyring runs via our wrapper service instead.
ln -sfn /dev/null "$unit_dir/gnome-keyring-daemon.socket"

# Machine-specific Mango overrides, sourced by config.conf via source-optional.
# owlmango seeds this at install time; the skel copy plays that role here.
cat > "$skel/.config/mango/host.conf" << 'EOF'
# Host-specific Mango configuration for this machine.
# Example monitor rule:
#   monitorrule=eDP-1,0.55,1,tile,0,1.0,0,0,1920,1080,60.0
EOF

# --- ssh client config -> /etc/skel/.ssh/ ----------------------------------
if [ -f "$owlmango/config/ssh/config" ]; then
  mkdir -p "$skel/.ssh"
  install -m 600 "$owlmango/config/ssh/config" "$skel/.ssh/config"
  chmod 700 "$skel/.ssh"
fi

# --- system configuration --------------------------------------------------
# iwd manages Wi-Fi (impala TUI); EnableNetworkConfiguration gives it DHCP.
inst 644 "$owlmango/config/iwd/main.conf" "$payload/etc/iwd/main.conf"
# Generic DHCP for wired interfaces via systemd-networkd.
inst 644 "$owlmango/config/systemd/network/20-wired.network" \
  "$payload/etc/systemd/network/20-wired.network"

# Note: no wayland-sessions entry here — mango's own meson install ships
# /usr/share/wayland-sessions/mango.desktop (checked at the pinned commit).

# --- session launcher -> /usr/lib/agave/session ----------------------------
# Canonical Mango launcher used by greetd on BOTH the live ISO and installed
# systems. Handles the safe-graphics boot flag, auto-allows software rendering
# when no GPU render node exists (VMs, broken KMS — wlroots aborts otherwise),
# and disables Mango's animations under software rendering (at ~1 fps the
# open/tile animations freeze mid-transform and clicks miss the drawn window).
mkdir -p "$payload/usr/lib/agave"
cat > "$payload/usr/lib/agave/session" << 'EOF'
#!/usr/bin/env bash
# Agave Linux Mango session launcher (invoked by greetd).
set -u

softmode=0
if grep -qw 'agave.safegraphics=1' /proc/cmdline 2>/dev/null; then
  # Explicit safe-graphics boot entry: force the pixman software renderer.
  export WLR_RENDERER=pixman
  export WLR_RENDERER_ALLOW_SOFTWARE=1
  export LIBGL_ALWAYS_SOFTWARE=1
  export WLR_NO_HARDWARE_CURSORS=1
  softmode=1
elif ! ls /dev/dri/renderD* >/dev/null 2>&1; then
  # No rendering-capable GPU: allow wlroots' software fallback.
  export WLR_RENDERER_ALLOW_SOFTWARE=1
  export WLR_NO_HARDWARE_CURSORS=1
  softmode=1
fi

# Manage an animations override in the per-user host.conf (sourced last by
# mango's config.conf): off under software rendering, restored on real GPUs.
hostconf="$HOME/.config/mango/host.conf"
if mkdir -p "${hostconf%/*}" 2>/dev/null; then
  touch "$hostconf" 2>/dev/null
  if [ -w "$hostconf" ]; then
    sed -i '/# agave-managed software-rendering BEGIN/,/# agave-managed software-rendering END/d' "$hostconf" 2>/dev/null
    if [ "$softmode" = 1 ]; then
      {
        echo '# agave-managed software-rendering BEGIN'
        echo 'animations=0'
        echo 'layer_animations=0'
        echo '# agave-managed software-rendering END'
      } >> "$hostconf"
    fi
  fi
fi

exec mango
EOF
chmod 755 "$payload/usr/lib/agave/session"

# --- greetd templates -> /usr/share/agave/greetd/ --------------------------
# config-autologin.toml keeps owlmango's _USER_ placeholder; the live ISO
# substitutes `agave`, Calamares substitutes the created user when autologin
# is selected. config-greeter.toml is the installed-system default. Both launch
# Mango through /usr/lib/agave/session (graphics fallback, animation handling).
mkdir -p "$payload/usr/share/agave/greetd"
sed 's|command = "mango"|command = "/usr/lib/agave/session"|' \
  "$owlmango/config/greetd/config.toml" \
  > "$payload/usr/share/agave/greetd/config-autologin.toml"
chmod 644 "$payload/usr/share/agave/greetd/config-autologin.toml"
if ! grep -q '/usr/lib/agave/session' \
     "$payload/usr/share/agave/greetd/config-autologin.toml"; then
  echo "error: failed to point the autologin greetd template at the session launcher" >&2
  exit 1
fi
cat > "$payload/usr/share/agave/greetd/config-greeter.toml" << 'EOF'
# Agave Linux greetd configuration: console greeter launching Mango.
# Installed to /etc/greetd/config.toml by the Calamares users job unless
# the user selected autologin (then config-autologin.toml is used).

[terminal]
vt = 1

[default_session]
command = "agreety --cmd /usr/lib/agave/session"
user = "greeter"
EOF

# --- package it ------------------------------------------------------------
tar -czf "$pkgdir/agave-desktop-payload.tar.gz" -C "$payload" etc usr

log ""
log "payload: $payload"
log "tarball: $pkgdir/agave-desktop-payload.tar.gz"
find "$payload" -type f | wc -l | awk '{print "files:  " $1}'
