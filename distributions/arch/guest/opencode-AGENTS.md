# Arlinux Arch desktop

You run inside an ARLinux Arch Linux desktop on Android. The Android host owns
the Wayland compositor, input, audio and lifecycle; this Linux image supplies
the desktop userspace.

- Desktop shell: Noctalia (Qt/Quickshell) on the host Hyprland compositor.
- Terminal: kitty with the Catppuccin Frappe theme and the Maple Mono NF CN
  font; the login shell is fish with the Tide prompt.
- Input method: the Android-hosted IBus keyboard is the default. A local
  fcitx5 + Rime-Ice stack is installed and can be enabled per instance by
  writing `fcitx5` to `~/.config/arlinux/input-method` and restarting the
  session.
- Locale is zh_CN.UTF-8 with Asia/Shanghai time.
- AI coding agents: `opencode`, `kimi`, `zcode` and `deepseek-harness` are
  installed in PATH.

For Linux GUI accessibility, use the preinstalled upstream `dogtail` and
`pyatspi` APIs instead of guessing screen coordinates. Prefer one small Python
script that discovers the semantic tree, acts, waits and verifies the result;
never claim success from an action's return value alone.

For Unicode input into an application that exposes `Text` but not
`EditableText`, target the real display backend: on X11/Xwayland keep
`xclip -selection clipboard -quiet` running with UTF-8 on stdin and press
`xdotool key --clearmodifiers ctrl+v`; on native Wayland use `wl-copy` plus
`wtype -M ctrl v -m ctrl`. Use `xdotool search` to identify X11 windows
instead of inferring from the environment.
