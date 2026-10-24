#!/bin/sh
# Build-only package preparation in a disposable ARM64 instance. Never a
# consumer entry point: the sealed offline desktop is what devices import.
set -eu
root=/
guest=/usr/lib/arlinux/guest

# pacman's GnuPG agent inherits this process's stdout/stderr. Close it before
# returning so the host can observe the completed package stage.
trap 'gpgconf --homedir "$root/etc/pacman.d/gnupg" --kill all >/dev/null 2>&1 || true' EXIT

if [ ! -s "$root/etc/machine-id" ]; then
    chmod u+w "$root/etc/machine-id"
    tr -d '-' < /proc/sys/kernel/random/uuid > "$root/etc/machine-id"
    chmod 444 "$root/etc/machine-id"
fi

# libalpm canonicalizes these paths inside libc, so supply real paths. The
# Android app UID cannot switch to the ALPM user and the tested kernel has no
# Landlock, hence DisableSandboxFilesystem and no DownloadUser.
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

# Android supplies identity and service management. Keep package scriptlets and
# desktop cache hooks, but omit Linux boot/service-account operations.
mkdir -p "$root/etc/pacman.d/hooks"
for hook in 20-systemd-sysusers.hook 21-systemd-tmpfiles.hook \
            10-openssh-mark-sshd-for-restart.hook \
            60-mkinitcpio-remove.hook 90-mkinitcpio-install.hook; do
    ln -sfn /dev/null "$root/etc/pacman.d/hooks/$hook"
done
[ -f "$root/etc/pacman.d/gnupg/arlinux-populated" ] || {
    echo 'Bundle is missing its prebuilt pacman trust database' >&2; exit 1;
}

# archlinuxcn carries rime-ice, the Maple Mono font and deepseek-harness. Its
# keyring was extracted into the seed and imported by tools/post-seed.sh, so
# the repository is signature-verified from the first transaction.
if ! grep -q '^\[archlinuxcn\]$' "$root/etc/pacman.conf"; then
    printf '\n' >> "$root/etc/pacman.conf"
    cat "$guest/archlinuxcn.conf" >> "$root/etc/pacman.conf"
fi

# pacman 7 preflights every transaction against the recorded mount table and
# matches its cachedir and every target path to a mount point. This disposable
# chroot lives inside the runner's filesystem, so the namespace mount table
# describes host paths instead of the chroot's, pacman logs "could not
# determine cachedir mount point" and then refuses the transaction as "not
# enough free disk space" even though the disk has >100 GiB free. Record the
# single mount that is true for every path in this tree; the symlink to
# /proc/self/mounts is restored before the image is sealed.
diagnose_mount_table() {
    echo '--> [diag] mount table (first 20 lines):' >&2
    head -20 /proc/self/mounts >&2 2>/dev/null || true
    ls -l /etc/mtab >&2 2>/dev/null || true
    df -h / >&2 2>/dev/null || true
}
rm -f /etc/mtab
printf 'none / none rw 0 0\n' > /etc/mtab

# Replace the seed's libc before anything else links against it, then restart
# the package stage at a fresh process boundary (the runner retries on 75).
runtime_epoch=$root/var/lib/arlinux/runtime-epoch-1
if [ ! -f "$runtime_epoch" ]; then
    echo 'ARLINUX:Updating the base runtime...'
    if ! pacman -Syy --needed --noconfirm glibc coreutils bash pacman; then
        diagnose_mount_table
        exit 1
    fi
    mkdir -p "$(dirname "$runtime_epoch")"
    : > "$runtime_epoch"
    exit 75
fi

# The Android GPU overlay owns the Mesa providers; install its matching pacman
# package before any repository mesa can be pulled in by the desktop packages.
/bin/sh /usr/lib/arlinux/install-mesa-arch.sh

# Desktop package set. Grouped the same way as the reference builder: core
# clients, Qt/Quickshell stack, input method, fonts, files and AI agents.
set -- \
    kitty fish fastfetch neovim nemo gvfs wl-clipboard wtype xclip xdotool \
    fuzzel noctalia quickshell qt6-declarative qt6-svg qt6-wayland qt6-multimedia \
    qt6-5compat qt6-imageformats inotify-tools hyprutils hyprwire hyprlang re2 \
    fcitx5 fcitx5-rime fcitx5-gtk fcitx5-qt fcitx5-configtool rime-ice-git \
    ttf-maplemono-nf-cn adobe-source-han-sans-cn-fonts noto-fonts noto-fonts-emoji \
    ttf-dejavu fontconfig \
    deepseek-harness opencode ripgrep \
    curl ca-certificates xorg-xrdb dbus dbus-glib at-spi2-core ibus python-dbus python-atspi \
    python-gobject python-pip mpg123 patch wayland libx11 libxcb libxxf86vm \
    gtk3 gtk4 libnotify nss libxss libxtst libsecret xdg-utils xdg-terminal-exec \
    alsa-plugins libpulse cups libdrm pango cairo jq socat imagemagick \
    bash-completion procps-ng tzdata unzip libarchive tar xz git cinnamon-translations \
    binutils file perl \
    libxext libxshmfence libglvnd vulkan-icd-loader libxrandr libxfixes libxrender \
    libxdamage xcb-util xcb-util-keysyms xcb-util-wm xcb-util-renderutil xcb-util-cursor
if ! pacman -Q "$@" >/dev/null 2>&1; then
    echo 'ARLINUX:Updating Arch Linux ARM and installing the desktop components...'
    if ! pacman -Syyu --needed --noconfirm "$@"; then
        diagnose_mount_table
        exit 1
    fi
fi

# Every package later than this snapshot is build-only scaffolding; the
# cleanup step below removes it again so the sealed image stays a desktop.
pacman -Qq | sort > /tmp/arlinux-packages-before

/bin/sh "$guest/install-desktop.sh"
/bin/sh "$guest/install-agent-tools.sh"

# Remove the build-only toolchain (reef's AUR build, zcode's perl patch, the
# mirrored agent packages' helpers). Only packages added by this run are
# touched, so a pre-existing tool never disappears from the seed. paru is not
# in this list: the AUR helper is content, not scaffolding.
build_tool_re='^(autoconf|automake|base-devel|bison|ccache|clang([0-9]+)?|cmake|cpio|debugedit|elfutils|fakeroot|flex|gcc|gdb|gdb-common|gettext|groff|guile|libtool|lld([0-9]+)?|llvm[0-9]+|m4|make|meson|ninja|pkgconf|rust|rustup|sudo|texinfo|which)$'
# The hard gate covers the compiler and AUR scaffolding only: other build
# helpers may legitimately remain as dependencies of packages the desktop
# keeps (python-setuptools for pip, for example), and failing on those would
# break the image for a reason that does not affect its content.
critical_tool_re='^(ccache|cargo|clang([0-9]+)?|cmake|fakeroot|gcc|llvm[0-9]+|make|meson|ninja|rust|rustup|sudo)$'
iteration=0
while [ "$iteration" -lt 6 ]; do
    iteration=$((iteration + 1))
    pacman -Qq | sort > /tmp/arlinux-packages-after
    comm -13 /tmp/arlinux-packages-before /tmp/arlinux-packages-after \
        | grep -E "$build_tool_re" > /tmp/arlinux-build-only || true
    [ -s /tmp/arlinux-build-only ] || break
    # shellcheck disable=SC2046
    pacman -Rns --noconfirm $(cat /tmp/arlinux-build-only) 2>/dev/null || true
done
pacman -Qq | sort > /tmp/arlinux-packages-after
remaining="$(comm -13 /tmp/arlinux-packages-before /tmp/arlinux-packages-after | grep -E "$critical_tool_re" || true)"
if [ -n "$remaining" ]; then
    echo "ERROR: build-only packages remain in the desktop: $remaining" >&2
    exit 1
fi
leftover="$(comm -13 /tmp/arlinux-packages-before /tmp/arlinux-packages-after | grep -E "$build_tool_re" || true)"
[ -z "$leftover" ] || echo "--> [cleanup] kept as dependencies: $leftover"
rm -f /tmp/arlinux-packages-before /tmp/arlinux-packages-after /tmp/arlinux-build-only
echo '--> [cleanup] build-only toolchain removed'

# Desktop automation and online speech support, matching the other ARLinux
# desktops; Dogtail is not packaged by Arch, so both come from PyPI.
if ! python3 -c 'import dogtail, edge_tts' >/dev/null 2>&1; then
    echo 'ARLINUX:Installing desktop automation and online speech support...'
    python3 -m pip install --break-system-packages --no-cache-dir \
        'dogtail==1.0.5' 'edge-tts==7.2.8'
fi
python3 -c 'import dogtail, edge_tts, pyatspi'

# The PulseAudio client and ALSA defaults depend on the runtime socket path
# (BIONICX_FILES), which only exists on the device, so guest/first-boot.sh
# writes them per instance.

# Distribution note for the shared OpenCode integration (TUI and Desktop both
# read it through the Guest Tools launcher).
mkdir -p "$root/etc/arlinux"
cp "$guest/opencode-AGENTS.md" "$root/etc/arlinux/opencode-AGENTS.md"

# Download caches must not reach snapshot.tar: the seal drops var/cache from
# the final image anyway, and several gigabytes of packages would otherwise be
# archived, copied and discarded on every build.
pacman -Scc --noconfirm >/dev/null 2>&1 || true
rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/* /tmp/ghostty-pkg /tmp/aurlog

# Restore the image's own mount table: devices must see /proc/self/mounts.
rm -f /etc/mtab
ln -s ../proc/self/mounts /etc/mtab
test -L /etc/mtab

# Completion receipt: the seal step verifies these files, not a second
# inventory of the packages above.
python3 -c 'import dogtail, edge_tts, pyatspi'
test -x /usr/bin/noctalia
test -x /usr/bin/quickshell
test -x /usr/bin/kitty
test -x /usr/bin/fish
test -x /usr/bin/nemo
test -x /usr/bin/hyprctl
test -x /usr/bin/opencode
test -x /usr/bin/kimi
test -x /usr/bin/zcode
test -x /usr/bin/zen-browser
pacman -Q deepseek-harness >/dev/null
pacman -Q paru >/dev/null
# Zen Browser links libraries the desktop set provides; the cleanup above runs
# first, so this gate sees the sealed package set rather than the build chroot.
if ldd /opt/zen-browser/zen-bin 2>/dev/null | grep -q 'not found'; then
    echo 'ERROR: Zen Browser has unresolved libraries:' >&2
    ldd /opt/zen-browser/zen-bin | grep 'not found' >&2
    exit 1
fi
mkdir -p /usr/share/arlinux
pacman -Q | awk '{print $1 "\t" $2}' > /usr/share/arlinux/packages.tsv
printf '%s\n' 'arch' > /usr/share/arlinux/offline-distribution
printf '1\n' > /usr/share/arlinux/offline-desktop
