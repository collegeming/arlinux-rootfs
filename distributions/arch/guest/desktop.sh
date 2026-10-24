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

# Kitty translucency needs compositor-side blur, matching the reference
# desktop's terminal look. Runtime keywords only; the host configuration
# itself is never rewritten, and failures are non-fatal on other builds.
hyprctl keyword windowrulev2 "opacity 0.90 0.85,class:^(kitty)$" >/dev/null 2>&1 || true
hyprctl keyword windowrulev2 "blur,class:^(kitty)$" >/dev/null 2>&1 || true

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

log="$XDG_RUNTIME_DIR/noctalia.log"
status_log="$XDG_RUNTIME_DIR/arlinux-desktop-status.log"
diag_dir="$XDG_CACHE_HOME/arlinux"
diag_log="$diag_dir/desktop-diag.log"
mkdir -p "$diag_dir"
printf '%s session start: %s, %s\n' "$(date -Is)" \
    "$(pacman -Q noctalia 2>/dev/null || echo 'noctalia unknown')" \
    "$(hyprctl -j monitors 2>/dev/null | jq -c '[.[] | {name, width, height, refreshRate, scale}]' 2>/dev/null || echo 'monitors unknown')" \
    >> "$diag_log" 2>/dev/null || true

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

# Supervise the desktop shell. The shell is the session's only window-manager
# surface, so it is never left dead: every exit is recorded with its status,
# its runtime and the compositor state at that moment, and the shell is
# restarted with a growing pause instead of ending the session. Exiting here is
# what a device shows as "the desktop died and stayed black".
record_exit() { # status started ended
    local status="$1" started="$2" ended="$3" uptime
    uptime=$((ended - started))
    {
        printf '%s noctalia exited status=%s after=%ss\n' "$(date -Is)" "$status" "$uptime"
        printf '  compositor: %s\n' "${HYPRLAND_INSTANCE_SIGNATURE:-none}"
        hyprctl -j monitors 2>/dev/null | jq -c '[.[] | {name, width, height, refreshRate, scale}]' 2>/dev/null | sed 's/^/  monitors: /'
        hyprctl -j clients 2>/dev/null | jq -c 'length' 2>/dev/null | sed 's/^/  windows: /'
        ibus engine 2>/dev/null | sed 's/^/  ibus engine: /'
        tail -n 60 "$log" 2>/dev/null | sed 's/^/  log: /'
    } >> "$diag_log" 2>/dev/null || true
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
