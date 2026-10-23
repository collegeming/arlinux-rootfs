#!/bin/sh
# Per-instance first boot. Runs on the device as the Android app UID: only
# device-local state is written here, never packages.
set -eu
root=/

trap 'gpgconf --homedir "$root/etc/pacman.d/gnupg" --kill all >/dev/null 2>&1 || true' EXIT

if [ ! -s "$root/etc/machine-id" ]; then
    chmod u+w "$root/etc/machine-id"
    tr -d '-' < /proc/sys/kernel/random/uuid > "$root/etc/machine-id"
    chmod 444 "$root/etc/machine-id"
fi

# libalpm canonicalizes these paths inside libc, so supply real app paths; the
# Android UID cannot switch to the ALPM user and the kernel has no Landlock.
mkdir -p "$root/etc/pacman.d/gnupg" "$root/var/lib/pacman" "$root/var/cache/pacman/pkg" "$root/var/log"
cat > "$root/etc/pacman.d/arlinux.conf" <<EOF
RootDir = $root
DBPath = $root/var/lib/pacman
CacheDir = $root/var/cache/pacman/pkg
LogFile = $root/var/log/pacman.log
GPGDir = $root/etc/pacman.d/gnupg
HookDir = $root/etc/pacman.d/hooks
DisableSandboxFilesystem
EOF
if ! grep -q '^Include = /etc/pacman.d/arlinux.conf$' "$root/etc/pacman.conf"; then
    sed -i '/^\[options\]/a Include = /etc/pacman.d/arlinux.conf' "$root/etc/pacman.conf"
fi
sed -i '/^DownloadUser[[:space:]]*=/d' "$root/etc/pacman.conf"
mkdir -p "$root/etc/ld.so.conf.d"
ldconfig

# Boot-only package hooks stay neutered on the device as well.
mkdir -p "$root/etc/pacman.d/hooks"
for hook in 20-systemd-sysusers.hook 21-systemd-tmpfiles.hook \
            10-openssh-mark-sshd-for-restart.hook \
            60-mkinitcpio-remove.hook 90-mkinitcpio-install.hook; do
    ln -sfn /dev/null "$root/etc/pacman.d/hooks/$hook"
done
[ -f "$root/etc/pacman.d/gnupg/arlinux-populated" ] || {
    echo 'Bundle is missing its prebuilt pacman trust database' >&2; exit 1;
}
[ -f /usr/share/arlinux/offline-desktop ] || {
    echo 'Incomplete desktop bundle: import a prepared offline distribution ZIP.' >&2
    exit 1
}

# Seed the per-instance home from the image template, without overwriting
# anything the user already changed.
template=/usr/share/arlinux/skel-home
if [ -d "$template" ] && [ -n "${HOME:-}" ]; then
    mkdir -p "$HOME/.config" "$HOME/.local/share" "$HOME/.cache"
    mkdir -p "$HOME/Desktop" "$HOME/Documents" "$HOME/Downloads" "$HOME/Pictures"
    cp -rn "$template/." "$HOME/" 2>/dev/null || true
fi

# PulseAudio clients connect to the host socket; the Android app owns audio.
mkdir -p "$root/etc/pulse/client.conf.d" "$root/etc/alsa/conf.d"
printf 'default-server = unix:%s/runtime/pulse-native\nautospawn = no\nenable-shm = no\n' \
    "$BIONICX_FILES" > "$root/etc/pulse/client.conf.d/arlinux.conf"
cat > "$root/etc/alsa/conf.d/99-arlinux-pulse.conf" <<'ALSA'
pcm.!default { type pulse }
ctl.!default { type pulse }
ALSA
