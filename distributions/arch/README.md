# Arch Linux（Noctalia 桌面）for ARLinux

本仓库的内置配方 `distributions/arch` 构建 Arch Linux ARM rootfs 包，桌面外壳为 Noctalia。
预构建包发布在[本仓库 Releases](https://github.com/collegeming/arlinux-rootfs/releases)，
下载其中的 `arlinux-arch-noctalia-default.zip` 导入 ARLinux App（不要下载 GitHub 自动生成的源码归档）。

包契约与上游一致：protocol 4 bundle、框架提供的 GPU overlay、离线桌面。包内包含：

- Noctalia 桌面外壳与 fuzzel 启动器，kitty 为唯一终端，fish + Tide 提示符。
- 中文环境：`zh_CN.UTF-8`、Asia/Shanghai 时区、思源黑体 CN、Noto emoji。
- Nemo 文件管理器，附"在终端中打开"动作。
- Zen Browser 浏览器与 `paru` AUR 助手。
- AI 工具：opencode（TUI，取 `extra/opencode`）、kimi-code、ZCode 桌面版、deepseek-harness。

包源为 Arch Linux ARM 仓库（TUNA 镜像优先）与 archlinuxcn，后者提供 `rime-ice-git`、
`ttf-maplemono-nf-cn`、`deepseek-harness`。`tools/seed.sh` 把固定版本的 `archlinuxcn-keyring`
放进 seed，`tools/post-seed.sh` 导入信任根，任何仓库都不需要 `SigLevel = Never`。

## 桌面栈

ARLinux 的 Wayland 合成器运行在 Android 宿主进程内，不在 Linux 里。bundle 清单的
`compositor` 字段只接受 `anlabwc` 与 `hyprland` 两个取值（`schemas/product.schema.json`、
`tools/bundle.py`），guest 内不能再运行第二个合成器。本发行版因此声明 `hyprland` 提示，
由 Noctalia 直接驱动宿主合成器：

- `guest/desktop.sh` 先通过宿主合成器的 IPC socket 找到会话，再启动 Noctalia。Noctalia 退出后自动重启，30 秒内连续退出 5 次才放弃；每次退出状态写入 `$XDG_RUNTIME_DIR/arlinux-desktop-status.log`。
- `hyprctl` 取自签名包 `hyprland`（`guest/install-desktop.sh`），不安装 Linux 合成器本体及其 DRM 后端，只补它链接的共享库 `hyprlang`、`hyprutils`、`hyprwire`、`re2`；安装后以 `ldd` 校验无缺失库。
- 界面缩放 125%、kitty 的透明度与模糊规则都以 `hyprctl` 运行时规则下发。

## 终端与外观

kitty 使用 Catppuccin Frappe 主题、Maple Mono NF CN 字体、0.85 背景不透明度（模糊由合成器完成）
与光标拖尾；fish 配 Tide v6 提示符、fastfetch 与参考项目的 `ff-shell-stack`、`ff-sdks`。
`reef` 仅在 AUR 提供，按尽力安装处理：`conf.d/reef.fish` 在 reef 缺失时静默降级，
不让一个滚动更新的 AUR 配方拖垮镜像。

## 输入法

手机输入法通过框架提供的 IBus 通路进入 guest：`accessibility-session.sh` 发布会话总线并注册
宿主引擎 `arlinux-hosted`；`guest/desktop.sh` 启动 `ibus-wayland`（Arch 路径为 `/usr/lib/ibus/`）
并选中该引擎，Wayland 客户端（kitty、ZCode 等）由此收到提交文本。

guest 内另装了 fcitx5 + Rime-Ice 作为本地输入法，按实例启用：

```sh
printf 'fcitx5\n' > ~/.config/arlinux/input-method
# 重启桌面会话
```

## AI 工具
| 工具 | 来源 | 说明 |
| --- | --- | --- |
| opencode (TUI) | `extra/opencode` | 由 `packages/cli` 构建的 2.x CLI/TUI，随滚动源更新。 |
| kimi-code | 对应 AUR `kimi-code-bin` 2.3.1 | 固定上游 tarball + LICENSE，安装时校验 AArch64 ELF。 |
| ZCode | 对应 AUR `zcode` 3.16.2 | 固定官方 arm64 `.deb`；AUR `post_install` 的 JS 补丁被打上并校验。 |
| deepseek-harness | `archlinuxcn` | 常规包安装。 |
| OpenCode Desktop | 框架 Guest Tools | 故意不预置：`tools/seal-rootfs.py` 拒绝包快照中的 `/opt/OpenCode`，共享启动器在首次使用时安装当前 Desktop 版本。 |

ZCode 的 Electron 沙箱在 Android App UID 下无法工作，桌面入口因此带 `--no-sandbox`
（与框架对其它沙箱加载器的处理一致）。

## 浏览器

Zen Browser 取自官方 aarch64 发布包（版本固定，与 AUR `zen-browser-bin` 同源；AUR 的源码构建需要整套
Firefox 工具链，镜像不采用），入口为 `/usr/bin/zen-browser`，桌面项 `zen.desktop`。
`distribution/policies.json` 关闭应用自更新，升级随镜像进行。它与其它自带沙箱的加载器一样关闭自身沙箱：
运行时用路径映射而非内核命名空间做隔离（`docs/RUNTIME-PROTOCOL.md` 的 Security boundary），只依赖
Android 应用沙箱作为边界。

## 点按 / 触摸操作

实例没有物理键盘，桌面操作以点按为主。镜像自带一份触摸优先的 Noctalia 布局
（`guest/desktop/noctalia-arlinux.toml`，会话启动时写入 `$XDG_CONFIG_HOME/noctalia/00-arlinux.toml`；
Noctalia 按字母序合并配置目录，用户自己的 `*.toml` 在其后加载，因此用户设置优先）：

| 操作 | 点按方式 |
| --- | --- |
| 启动应用（等价 super+空格） | 顶栏最左侧启动器图标打开应用网格；底部 dock 的固定图标点一下直接启动 |
| 切换应用（等价 alt+tab） | 顶栏中间的 taskbar 点窗口图标；或点"切换窗口"按钮打开窗口切换面板 |
| 关闭应用（等价 super+Q） | 点"关闭当前窗口"按钮（`hyprctl dispatch killactive`）；taskbar 图标的中键关闭在触屏上需要双指轻点 |
| 打开终端（等价 super+T） | 点"终端"按钮 |
| 打开框架应用抽屉（Apps） | 点"应用抽屉"按钮（`guest/bin/arlinux-apps`） |
| 会话诊断 | 点"桌面诊断"按钮，在 kitty 中查看合成器状态、窗口列表、输入法与历史退出记录 |

宿主右边缘竖条的手势与发行版无关：轻点=手机键盘，双击=应用抽屉，长按=AI 语音；其余区域两指轻点=右键，两指滑动=滚动。竖条的"双击打开 Apps"只在抽屉进程还活着时生效——那个抽屉启动任意应用后会自行退出，所以镜像同时提供了上面的应用抽屉按钮。

`guest/bin/arlinux-dock` 提供 nwg-dock-hyprland 作为替代 dock：它经 `hyprctl` IPC 取窗口列表，不依赖 shell 的窗口集成，把配置里的 `[dock] enabled` 关掉后运行即可对比。

## 软件与包管理

- `paru` 随镜像保留，是用户安装 AUR 软件用的助手；`base-devel` 不随镜像，paru 按包解析构建依赖。
- `/etc/paru.conf` 设 `RemoveMake` 与 `CleanAfter`：构建完成后删除只用于构建的依赖与构建目录。
- 仓库与镜像沿用 `pacman.conf` 的设置，paru 同样生效：Arch Linux ARM 的 TUNA 优先 mirrorlist（`etc/pacman.d/mirrorlist`）与 archlinuxcn 仓库（`etc/pacman.d/archlinuxcn.conf`）。
- 提权使用实例内由框架提供的 `sudo`（bundle 载荷 `bionicx/sudo`，用法为 `sudo 命令 [参数]`），镜像内不装 Arch 的 `sudo` 包。

## 构建

```sh
echo '{"format":1,"framework":"'"$PWD"'"}' > /tmp/rootfs-config.json
sudo -E env PATH="$PATH" HOME="$HOME" ARLINUX_CACHE_DIR="$HOME/.cache/arlinux" \
  bash ./build.sh rootfs --config /tmp/rootfs-config.json \
  --distribution arch --output "$PWD/build/artifacts/rootfs/arch/default.zip"
./build.sh validate distributions/arch
./build.sh verify build/artifacts/rootfs/arch/default.zip
```

`.github/workflows/build-arch-rootfs.yml` 在 `ubuntu-24.04-arm` 上执行同一组命令：安装交叉工具链、
拉取 `taowen/gfxreconstruct` debug release 中发布的 `vulkan-capture` 产物、构建发行版并上传校验过的 bundle。
`publish_tag` 非空时，同一步把 bundle 发布为本仓库的 Release（`default.zip`、`default.json`、`SHA256SUMS`）。

## 维护

- 目录名与发行版 id 保持 `arch`：框架按该 id 处理 Mesa 覆盖层、seal 检查与 keyring 引导。
- `rootfs.lock.json` 固定 Arch Linux ARM 的 tarball 摘要；镜像重新生成 `ArchLinuxARM-aarch64-latest.tar.gz` 时刷新。
- `tools/seed.sh` 中 archlinuxcn keyring 包的版本与摘要成对更新。
- 固定下载（Catppuccin 主题、fisher、kimi-code、ZCode、Zen Browser）在 URL 旁记录 `sha256`；升级版本时两处同改，且 `guest/install-agent-tools.sh` 的 ZCode 补丁校验要对照 AUR `post_install` 重新核对、Zen 的桌面项与图标路径要对照 AUR `zen-browser-bin` 重新核对。
- `guest/build-desktop.sh` 先对包列表拍快照，再删除快照之后新增且命中构建工具清单的包，仍有残留则构建失败——镜像内不出现编译器与 AUR 脚手架。
- 设备验证（导入、首启、合成器 IPC、输入、音频）不在托管构建内；工作流变绿不能替代真机检查。
- 桌面外壳由 `guest/desktop.sh` 监督：每次退出都连同合成器状态写入 `$HOME/.cache/arlinux/desktop-diag.log`，并按下一次重启的等待时间退避，不会因连续崩溃而结束会话。
