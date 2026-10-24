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

# Supervise the desktop shell. A single `exec noctalia` turns any shell exit
# (crash, low-memory kill, or a host teardown of just the shell) into a
# permanently black surface with no way back. Restart it instead, keep the
# current log, and record every exit status for diagnosis. The rapid-restart
# guard stops a crash loop from draining the battery.
log="$XDG_RUNTIME_DIR/noctalia.log"
status_log="$XDG_RUNTIME_DIR/arlinux-desktop-status.log"
attempt=0
while :; do
    : > "$log"
    started=$(date +%s)
    noctalia >>"$log" 2>&1 &
    shell_pid=$!
    status=0
    wait "$shell_pid" || status=$?
    ended=$(date +%s)
    {
        printf '%s noctalia exited status=%s after %ss\n' \
            "$(date -Is)" "$status" "$((ended - started))"
        tail -n 60 "$log"
    } >> "$status_log" 2>/dev/null || true
    if [ $((ended - started)) -ge 30 ]; then
        attempt=0
    else
        attempt=$((attempt + 1))
    fi
    if [ "$attempt" -ge 5 ]; then
        echo "[arlinux] noctalia exited ${attempt} times in a row; giving up" >&2
        exit 1
    fi
    sleep 2
done
