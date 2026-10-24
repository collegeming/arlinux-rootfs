#!/bin/bash
# Desktop session entry point. The Android host owns the Wayland compositor
# (anhyprland for this profile), input, audio and lifecycle; this script seeds
# the instance home, joins the host compositor's IPC and runs the desktop
# shell (Noctalia) as the session's foreground process.
set -euo pipefail

seed_home() {
    local template=/usr/share/arlinux/skel-home
    [ -d "$template" ] || return 0
    mkdir -p "$HOME/.config" "$HOME/.local/share" "$HOME/.cache"
    mkdir -p "$HOME/Desktop" "$HOME/Documents" "$HOME/Downloads" "$HOME/Pictures"
    # Never overwrite user files: only fill in what is missing.
    cp -rn "$template/." "$HOME/" 2>/dev/null || true
    mkdir -p "$HOME/.config/fish/functions" "$HOME/.config/fish/conf.d"
}

seed_home

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1
mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

# Noctalia drives the host compositor over its IPC socket. A force-stopped
# Android process can leave a stale socket behind, so probe until one answers.
signature=
for _ in $(seq 1 100); do
    for socket in "$XDG_RUNTIME_DIR"/hypr/*/.socket.sock; do
        [ -S "$socket" ] || continue
        candidate="${socket%/.socket.sock}"
        candidate="${candidate##*/}"
        if HYPRLAND_INSTANCE_SIGNATURE="$candidate" timeout 1 hyprctl -j monitors >/dev/null 2>&1; then
            signature="$candidate"
            break 2
        fi
    done
    sleep 0.1
done
export HYPRLAND_INSTANCE_SIGNATURE="${signature:?Hyprland IPC socket did not appear}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"

# Phone panels are large in physical pixels, so the host default (1.0) renders
# the desktop much smaller than the device suggests. Pin the output scale at
# 125% for the selected output; the rule is idempotent and re-applied on every
# session start.
monitor_name="$(hyprctl -j monitors 2>/dev/null | jq -r '.[0].name' 2>/dev/null || true)"
if [ -n "${monitor_name:-}" ] && [ "$monitor_name" != "null" ]; then
    hyprctl keyword monitor "${monitor_name},preferred,auto,1.25" >/dev/null 2>&1 || true
fi

# The Android keyboard reaches the guest through the shared IBus engine, but
# the framework's accessibility wrapper only launches the Debian path
# (/usr/libexec/ibus-ui-gtk3). Arch ships the Wayland input-method client at
# /usr/lib/ibus/ibus-wayland, so without this the compositor had no input
# method: text-input-v3 clients (Electron, kitty) received no committed text
# while ordinary key events such as Enter still worked.
if ! pidof ibus-wayland >/dev/null 2>&1; then
    if [ -x /usr/lib/ibus/ibus-wayland ]; then
        env -u GTK_IM_MODULE -u QT_IM_MODULE /usr/lib/ibus/ibus-wayland \
            >>"$XDG_RUNTIME_DIR/ibus-wayland.log" 2>&1 &
    elif [ -x /usr/lib/ibus/ibus-ui-gtk3 ]; then
        env -u GTK_IM_MODULE -u QT_IM_MODULE GDK_BACKEND=wayland \
            /usr/lib/ibus/ibus-ui-gtk3 --enable-wayland-im \
            >>"$XDG_RUNTIME_DIR/ibus-wayland.log" 2>&1 &
    fi
fi
# Select the hosted engine explicitly. HostedInput publishes it at session
# start; selecting it again is idempotent and covers a restarted shell.
ibus engine arlinux-hosted >>"$XDG_RUNTIME_DIR/ibus-wayland.log" 2>&1 || true

# Host decorations. `hyprctl keyword` is not implemented on the host compositor,
# so runtime rules never applied; it reads its own Lua config
# (files/anhyprland/hyprland.lua) and applies changes on `hyprctl reload`. With
# no blur support its window shadows and the 1px window border render as hard
# black frames around every window — the same artefact the shell surfaces show
# from their shadows — so append the corrective block once per session and
# reload. A missing or read-only file is not fatal on other builds.
host_lua="${BIONICX_FILES:-/data/user/0/io.taowen.arlinux/files}/anhyprland/hyprland.lua"
if [ -w "$host_lua" ] && ! grep -q 'ARLinux: host decorations' "$host_lua" 2>/dev/null; then
    cat >> "$host_lua" <<'LUA'

-- ARLinux: host decorations. This compositor has no blur, so window shadows
-- render as opaque black frames and the 1px border as a light line while the
-- desktop shell is dark; the shell draws its own surfaces.
hl.config({
    decoration = { shadow = { enabled = false } },
    general = { border_size = 0 },
})
LUA
    hyprctl reload >/dev/null 2>&1 || true
fi

# Input method: the Android-hosted IBus keyboard is the default path (the
# session bus and engine come from accessibility-session.sh). Dropping
# `fcitx5` into ~/.config/arlinux/input-method switches this session to the
# locally installed fcitx5 + Rime-Ice stack instead.
if [ -f "$HOME/.config/arlinux/input-method" ] && grep -qx 'fcitx5' "$HOME/.config/arlinux/input-method"; then
    export GTK_IM_MODULE=fcitx5 QT_IM_MODULE=fcitx5 XMODIFIERS=@im=fcitx5 SDL_IM_MODULE=fcitx5 GLFW_IM_MODULE=fcitx
    fcitx5 -d --replace >"$XDG_RUNTIME_DIR/fcitx5.log" 2>&1 || true
fi

# Export the resolved session state for launchers that rejoin this session.
export -p > "$XDG_RUNTIME_DIR/arlinux-session.env" 2>/dev/null || true

# Touch-first shell layout. Noctalia merges every *.toml in its config
# directory alphabetically, so the image's file loads first and the user's own
# files (config.toml, …) still win.
install -d "$XDG_CONFIG_HOME/noctalia"
install -Dm644 /usr/share/arlinux/noctalia/00-arlinux.toml "$XDG_CONFIG_HOME/noctalia/00-arlinux.toml"
# The Catppuccin Frappe palette ships with the image so the shell keeps the
# kitty theme offline; the config file above selects it by name.
install -d "$XDG_CONFIG_HOME/noctalia/palettes"
install -Dm644 "/usr/share/arlinux/noctalia/palettes/Catppuccin Frappe.json" \
    "$XDG_CONFIG_HOME/noctalia/palettes/Catppuccin Frappe.json"
# The framework's Apps entry uses an Adwaita symbolic icon that renders as a
# dark glyph on the dock; this entry (same stem, user data dir) replaces it
# with the colored grid icon from the image.
install -d "$XDG_DATA_HOME/applications"
install -Dm644 /usr/share/arlinux/arlinux-apps.desktop "$XDG_DATA_HOME/applications/arlinux-apps.desktop"

log="$XDG_RUNTIME_DIR/noctalia.log"
status_log="$XDG_RUNTIME_DIR/arlinux-desktop-status.log"
diag_dir="$XDG_CACHE_HOME/arlinux"
diag_log="$diag_dir/desktop-diag.log"
mkdir -p "$diag_dir"
printf '%s session start: %s, %s\n' "$(date -Is)" \
    "$(pacman -Q noctalia 2>/dev/null || echo 'noctalia unknown')" \
    "$(hyprctl -j monitors 2>/dev/null | jq -c '[.[] | {name, width, height, refreshRate, scale}]' 2>/dev/null || echo 'monitors unknown')" \
    >> "$diag_log" 2>/dev/null || true

# Debug / automation channel, loopback only. The instance has no physical
# keyboard and the app UI cannot run shell commands, so the image starts a
# key-only sshd each session (client recipe in guest/debug/README.md); the
# unauthenticated socat PTY shell on 2323 is the rescue path and stays off
# until the user opts in with ~/.arlinux-debug-socat.
if [ -x /usr/bin/sshd ] && ! pgrep -x sshd >/dev/null 2>&1; then
    mkdir -p /run/sshd /var/empty
    [ -s /etc/ssh/ssh_host_ed25519_key ] || ssh-keygen -A >/dev/null 2>&1
    if /usr/bin/sshd -f /etc/ssh/sshd_arlinux.conf -E /var/log/sshd.log 2>/dev/null; then
        printf '%s debug channel: sshd listening on 127.0.0.1:2222\n' "$(date -Is)" >> "$diag_log"
    else
        printf '%s debug channel: sshd failed to start (see /var/log/sshd.log)\n' "$(date -Is)" >> "$diag_log"
    fi
fi
if [ -f "$HOME/.arlinux-debug-socat" ] && command -v socat >/dev/null 2>&1 && ! pgrep -f "TCP-LISTEN:2323" >/dev/null 2>&1; then
    socat TCP-LISTEN:2323,bind=127.0.0.1,reuseaddr,fork EXEC:'/bin/bash',pty,stderr,setsid,sigint,sane \
        >"$XDG_RUNTIME_DIR/socat.log" 2>&1 &
    printf '%s debug channel: socat PTY shell on 127.0.0.1:2323\n' "$(date -Is)" >> "$diag_log"
fi

# The host re-applies its own monitor rule when Android changes the display
# refresh rate, which resets the output scale to 1.0. Re-check once the shell
# is up, re-apply the 125% rule, and keep the evidence in the diagnostics log.
(
    sleep 15
    current="$(hyprctl -j monitors 2>/dev/null | jq -r '.[0].scale' 2>/dev/null || true)"
    if [ -n "${current:-}" ] && [ "$current" != "1.25" ] && [ "$current" != "null" ]; then
        hyprctl keyword monitor "${monitor_name},preferred,auto,1.25" >/dev/null 2>&1 || true
        printf '%s scale was %s; re-applied 1.25\n' "$(date -Is)" "$current" >> "$diag_log"
    fi
) &

# What the host compositor exposes decides which shell features can work: the
# Noctalia taskbar and dock build their window lists from the foreign-toplevel
# protocols, not from hyprctl. Record the full list once per session and mirror
# the tracked ones to logcat: the guest log files sit inside the app's data
# directory, so logcat is the only channel a device report can carry them.
logcat_note() { # level tag message...
    arlinux-logcat "$@" 2>/dev/null || true
}
if command -v wayland-info >/dev/null 2>&1; then
    protocols_log="$XDG_RUNTIME_DIR/arlinux-protocols.log"
    wayland-info > "$protocols_log" 2>&1 || true
    tracked='zwlr_foreign_toplevel_manager_v1 ext_foreign_toplevel_list_v1 hyprland_toplevel_mapping_manager_v1 zwlr_layer_shell_v1 zwp_virtual_keyboard_manager_v1 zwp_text_input_manager_v3'
    summary=''
    for protocol in $tracked; do
        if grep -q "$protocol" "$protocols_log" 2>/dev/null; then
            summary="$summary $protocol"
        fi
    done
    summary="${summary:- none of the tracked ones}"
    printf '[arlinux] compositor protocols:%s\n' "$summary" >&2
    logcat_note info arlinux-guest "compositor protocols:$summary"
fi

# Seed the pins of the optional second dock (guest/bin/arlinux-dock). The dock
# itself stays off until it is started: the Noctalia dock is the one in use.
cache="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$cache"
if [ ! -e "$cache/nwg-dock-pinned" ] && [ -f /usr/share/arlinux/nwg-dock-pinned ]; then
    cp /usr/share/arlinux/nwg-dock-pinned "$cache/nwg-dock-pinned"
fi

# Supervise the desktop shell. The shell is the session's only window-manager
# surface, so it is never left dead: every exit is recorded with its status,
# its runtime and the compositor state at that moment, and the shell is
# restarted with a growing pause instead of ending the session. Exiting here is
# what a device shows as "the desktop died and stayed black".
record_exit() { # status started ended
    local status="$1" started="$2" ended="$3" uptime windows scale last
    uptime=$((ended - started))
    {
        printf '%s noctalia exited status=%s after=%ss\n' "$(date -Is)" "$status" "$uptime"
        printf '  compositor: %s\n' "${HYPRLAND_INSTANCE_SIGNATURE:-none}"
        hyprctl -j monitors 2>/dev/null | jq -c '[.[] | {name, width, height, refreshRate, scale}]' 2>/dev/null | sed 's/^/  monitors: /'
        hyprctl -j clients 2>/dev/null | jq -c 'length' 2>/dev/null | sed 's/^/  windows: /'
        ibus engine 2>/dev/null | sed 's/^/  ibus engine: /'
        tail -n 60 "$log" 2>/dev/null | sed 's/^/  log: /'
    } >> "$diag_log" 2>/dev/null || true
    # One logcat line per exit: the shell log file is unreachable from adb, and
    # a session that dies with a stack trace still leaves this behind.
    windows="$(hyprctl -j clients 2>/dev/null | jq -c 'length' 2>/dev/null || echo '?')"
    scale="$(hyprctl -j monitors 2>/dev/null | jq -r '.[0].scale' 2>/dev/null || echo '?')"
    last="$(tail -n 1 "$log" 2>/dev/null)"
    logcat_note warn arlinux-guest \
        "noctalia exited status=$status after=${uptime}s windows=$windows scale=$scale last=${last:-none}"
}

attempt=0
while :; do
    : > "$log"
    started=$(date +%s)
    noctalia >>"$log" 2>&1 &
    shell_pid=$!
    status=0
    wait "$shell_pid" || status=$?
    ended=$(date +%s)
    # stderr reaches the host session log, which is the only place a device-side
    # black screen can be diagnosed without access to the instance directory.
    printf '[arlinux] noctalia exited status=%s after %ss\n' \
        "$status" "$((ended - started))" >&2
    {
        printf '%s noctalia exited status=%s after %ss\n' \
            "$(date -Is)" "$status" "$((ended - started))"
        tail -n 60 "$log"
    } >> "$status_log" 2>/dev/null || true
    record_exit "$status" "$started" "$ended"
    if [ $((ended - started)) -ge 30 ]; then
        attempt=0
    else
        attempt=$((attempt + 1))
    fi
    # Back off so a crash loop cannot spin, but keep the session alive: the
    # diagnostics button on the bar shows the recorded exits.
    delay=$((attempt * 3))
    [ "$delay" -gt 30 ] && delay=30
    sleep "$delay"
done
