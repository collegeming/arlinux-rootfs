# Arch Linux (Niri-style desktop) for ARLinux

This distribution replaces the upstream `taowen/arlinux-arch` recipe in this
fork. It keeps the same contract (protocol 4 bundle, framework-owned GPU
overlays, offline desktop) and changes the desktop content:

- Noctalia shell + fuzzel launcher, kitty only terminal, fish + Tide prompt.
- Chinese locale (zh_CN.UTF-8), Asia/Shanghai time, Source Han Sans CN and
  Noto emoji fonts, Rime input (fcitx5 + rime-ice) next to the Android-hosted
  IBus engine.
- Nemo file manager with an "Open in Terminal" action.
- AI agents: opencode (TUI 2.x from `extra`), kimi-code, ZCode desktop and
  deepseek-harness.

Package sources are the Arch Linux ARM repositories (TUNA mirror first) plus
archlinuxcn for `rime-ice-git`, `ttf-maplemono-nf-cn` and `deepseek-harness`.
`tools/seed.sh` copies the pinned `archlinuxcn-keyring` into the seed and
`tools/post-seed.sh` imports the trust root, so no repository ever needs a
`SigLevel = Never` bootstrap.

## Why there is no niri compositor here

ARLinux is not a container runtime: the Android host supplies the Wayland
compositor (anlabwc or anhyprland) and the bundle manifest only accepts those
two hints (`schemas/product.schema.json`, `tools/bundle.py`). A second Linux
compositor cannot run inside the guest. This recipe therefore declares the
`hyprland` hint and provides the same desktop experience on top of it:

- Noctalia runs as the shell; it drives the host compositor over its IPC
  socket, which `guest/desktop.sh` discovers before starting it.
- `hyprctl` is extracted from the signed `hyprland` package without installing
  the Linux compositor or its DRM backend, the same pattern the upstream
  Omarchy distribution uses.
- The kitty transparency/blur rule that the reference desktop implemented with
  a niri window rule is applied as a runtime `hyprctl` window rule.

If a future host embeds niri, only `product.json` and `guest/desktop.sh` need
to change.

## Terminal look

kitty with the Catppuccin Frappe theme, the Maple Mono NF CN font, 0.85
background opacity (blur is compositor-side), cursor trail, and fish with the
Tide v6 prompt, fastfetch, and the reference desktop's `ff-shell-stack` /
`ff-sdks` helpers. The `reef` bash-compatibility layer is AUR-only and is
installed best-effort: a rolling AUR recipe must never break the image, and
`conf.d/reef.fish` degrades silently when reef is absent.

## Input method

The Android-hosted IBus keyboard is the default path (the framework publishes
the session bus and engine in `accessibility-session.sh`). The local
fcitx5 + Rime-Ice stack is installed, configured with Rime as the default
group, and can be enabled per instance:

```sh
printf 'fcitx5\n' > ~/.config/arlinux/input-method
# restart the desktop session
```

## AI agents

| Tool | Source | Notes |
| --- | --- | --- |
| opencode (TUI) | `extra/opencode` | The 2.x CLI/TUI built from `packages/cli`; the rolling repo version is used. |
| kimi-code | mirrors AUR `kimi-code-bin` 2.3.1 | Pinned upstream tarball + LICENSE, converted to an AArch64 ELF check. |
| ZCode | mirrors AUR `zcode` 3.16.2 | Pinned official arm64 `.deb`; the AUR `post_install` JS patch is applied and gated. |
| deepseek-harness | `archlinuxcn` | Regular package install. |
| OpenCode Desktop | framework Guest Tools | Deliberately not baked in: `tools/seal-rootfs.py` rejects `/opt/OpenCode` in the package snapshot and the shared launcher installs the current Desktop build on first use. |

ZCode's Electron sandbox cannot work under the Android app UID, so its desktop
entry runs with `--no-sandbox` (the same trade-off the framework documents for
other sandboxed loaders).

## Build

```sh
echo '{"format":1,"framework":"'"$PWD"'"}' > /tmp/rootfs-config.json
sudo -E env PATH="$PATH" HOME="$HOME" ARLINUX_CACHE_DIR="$HOME/.cache/arlinux" \
  bash ./build.sh rootfs --config /tmp/rootfs-config.json \
  --distribution arch --output "$PWD/build/artifacts/rootfs/arch/default.zip"
./build.sh validate distributions/arch
./build.sh verify build/artifacts/rootfs/arch/default.zip
```

`.github/workflows/build-arch-rootfs.yml` runs the same commands on
`ubuntu-24.04-arm`: it installs the cross toolchain, fetches the published
`vulkan-capture` product from `taowen/gfxreconstruct`'s debug release, builds
the distribution and uploads the verified bundle.

## Maintenance

- `rootfs.lock.json` pins the Arch Linux ARM tarball. Refresh the digest when
  the mirror regenerates `ArchLinuxARM-aarch64-latest.tar.gz`.
- The archlinuxcn keyring package in `tools/seed.sh` carries its own version
  and digest; refresh both together.
- Pinned downloads (Catppuccin theme, fisher, kimi-code, ZCode) record
  `sha256` next to their URL. Version bumps must update both, and the ZCode
  patch gate in `guest/install-agent-tools.sh` must be re-checked against the
  AUR `post_install` hook.
- `guest/build-desktop.sh` removes every package installed after its baseline
  snapshot that matches the build-tool list and fails the build if anything
  remains, so the sealed image ships no compiler or AUR scaffolding.
- Device testing (import, first boot, compositor IPC, input, audio) is not part
  of the hosted build; a green workflow does not replace a real device check.
