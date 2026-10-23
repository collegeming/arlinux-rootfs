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

# Replace the seed's libc before anything else links against it, then restart
# the package stage at a fresh process boundary (the runner retries on 75).
runtime_epoch=$root/var/lib/arlinux/runtime-epoch-1
if [ ! -f "$runtime_epoch" ]; then
    echo 'ARLINUX:Updating the base runtime...'
    pacman -Syy --needed --noconfirm glibc coreutils bash pacman
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
    qt6-5compat qt6-imageformats inotify-tools hyprutils hyprwire hyprlang \
    fcitx5 fcitx5-rime fcitx5-gtk fcitx5-qt fcitx5-configtool rime-ice-git \
    ttf-maplemono-nf-cn adobe-source-han-sans-cn-fonts noto-fonts noto-fonts-emoji \
    ttf-dejavu fontconfig \
    deepseek-harness opencode ripgrep \
    curl ca-certificates xorg-xrdb dbus at-spi2-core ibus python-dbus python-atspi \
    python-gobject python-pip mpg123 patch wayland libx11 libxcb libxxf86vm \
    gtk3 gtk4 libnotify nss libxss libxtst libsecret xdg-utils xdg-terminal-exec \
    alsa-plugins libpulse cups libdrm pango cairo jq socat imagemagick \
    bash-completion procps-ng tzdata unzip libarchive tar xz git cinnamon-translations \
    binutils file perl
if ! pacman -Q "$@" >/dev/null 2>&1; then
    echo 'ARLINUX:Updating Arch Linux ARM and installing the desktop components...'
    pacman -Syyu --needed --noconfirm "$@"
fi

# Every package later than this snapshot is build-only scaffolding; the
# cleanup step below removes it again so the sealed image stays a desktop.
pacman -Qq | sort > /tmp/arlinux-packages-before

/bin/sh "$guest/install-desktop.sh"
/bin/sh "$guest/install-agent-tools.sh"

# Remove the build-only toolchain (reef's AUR build, zcode's perl patch, the
# mirrored agent packages' helpers). Only packages added by this run are
# touched, and the result is a hard gate, mirroring the reference builder.
build_tool_re='^(autoconf|automake|bison|ccache|clang([0-9]+)?|cmake|cpio|debugedit|elfutils|fakeroot|flex|gcc|gdb|gdb-common|gettext|groff|guile|libtool|lld([0-9]+)?|llvm[0-9]+|m4|make|meson|ninja|paru|pkgconf|python-build|python-calver|python-editables|python-fastjsonschema|python-flit-core|python-hatchling|python-installer|python-mako|python-markupsafe|python-packaging|python-pathspec|python-platformdirs|python-pluggy|python-pyproject-hooks|python-pypa-build|python-setuptools|python-tomli|python-trove-classifiers|python-typing_extensions|python-validate-pyproject|python-wheel|rust|rustup|sudo|texinfo|which)$'
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
remaining="$(comm -13 /tmp/arlinux-packages-before /tmp/arlinux-packages-after | grep -E "$build_tool_re" || true)"
if [ -n "$remaining" ]; then
    echo "ERROR: build-only packages remain in the desktop: $remaining" >&2
    exit 1
fi
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

# PulseAudio clients connect to the host socket; the Android app owns audio.
mkdir -p "$root/etc/pulse/client.conf.d" "$root/etc/alsa/conf.d"
printf 'default-server = unix:%s/runtime/pulse-native\nautospawn = no\nenable-shm = no\n' \
    "$BIONICX_FILES" > "$root/etc/pulse/client.conf.d/arlinux.conf"
cat > "$root/etc/alsa/conf.d/99-arlinux-pulse.conf" <<'ALSA'
pcm.!default { type pulse }
ctl.!default { type pulse }
ALSA

# Distribution note for the shared OpenCode integration (TUI and Desktop both
# read it through the Guest Tools launcher).
mkdir -p "$root/etc/arlinux"
cp "$guest/opencode-AGENTS.md" "$root/etc/arlinux/opencode-AGENTS.md"

# Download caches must not reach snapshot.tar: the seal drops var/cache from
# the final image anyway, and several gigabytes of packages would otherwise be
# archived, copied and discarded on every build.
pacman -Scc --noconfirm >/dev/null 2>&1 || true
rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/* /tmp/ghostty-pkg /tmp/aurlog

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
pacman -Q deepseek-harness >/dev/null
mkdir -p /usr/share/arlinux
pacman -Q | awk '{print $1 "\t" $2}' > /usr/share/arlinux/packages.tsv
printf '%s\n' 'arch' > /usr/share/arlinux/offline-distribution
printf '1\n' > /usr/share/arlinux/offline-desktop
