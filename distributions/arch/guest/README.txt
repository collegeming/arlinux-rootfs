Arch Linux desktop (ARLinux)

The Android application supplies the Wayland compositor, input, audio and
device access. This Linux image supplies the desktop userspace on top:

- Noctalia shell (bar and panels) with the fuzzel launcher.
- kitty terminal with the Catppuccin Frappe theme, the bundled Maple Mono NF
  CN font and a fish + Tide prompt.
- Chinese locale (zh_CN.UTF-8), Asia/Shanghai time, Source Han Sans CN and
  Noto emoji fonts.
- Rime input (fcitx5) is installed; the Android-hosted IBus keyboard is the
  default input path. See the distribution README for the switch.
- Nemo file manager with "Open in Terminal".
- AI coding agents: kimi-code (kimi) and ZCode desktop, plus deepseek-harness.

Install more packages with pacman as usual; the offline bundle already
contains every desktop package.
