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

桌面外壳与终端共用同一套调色板：镜像内置 Catppuccin Frappe 的调色板 JSON
（`guest/desktop/palettes/catppuccin-frappe.json`，会话启动时装到
`$XDG_CONFIG_HOME/noctalia/palettes/`），`[theme]` 以 `source = "custom"` 引用它，
不需要联网、与 kitty 的配色一致（暗色模式）。`[plugins] auto_update = "none"` 关掉插件源的
后台 git 更新，Noctalia 启动后不再常驻 `git fetch` 进程。

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
| 启动应用（等价 super+空格） | 顶栏最左侧"启动器"图标打开应用网格；底部 dock 的固定项点一下直接启动 |
| 切换应用（等价 alt+tab） | 顶栏中间的 taskbar 点窗口图标；dock 上运行中的应用点一下聚焦；`guest/bin/arlinux-dock` 手动启动的 nwg-dock 同样支持 |
| 关闭应用（等价 super+Q） | 点"关闭当前窗口"按钮，或 dock 上的"关闭窗口"磁贴（走 `guest/touch/arlinux-window`，在 Lua 与经典两套派发器之间自动回退） |
| 打开终端（等价 super+T） | 点"终端"按钮 |
| 打开框架应用抽屉（Apps） | 点"应用抽屉"按钮；dock 的**第一个磁贴**就是它（固定项第一项 `arlinux-apps`） |
| 会话诊断 | 点"桌面诊断"按钮，在 kitty 中查看合成器状态、窗口列表、输入法、协议清单与历史退出记录 |

顶栏布局：**左侧**启动器、应用抽屉、终端、关闭当前窗口、桌面诊断；**中间**taskbar（运行中的窗口）；**右侧**时钟、音量、电池、控制中心。

**dock 只启用 Noctalia 自己的那个**（`[dock] enabled = true`，`launcher_position = "none"`，所以第一个磁贴就是 Apps，没有额外的网格按钮）。dock 处于**悬浮模式**：`reserve_space = false`，不向合成器申请独占区，应用窗口因此能用满整屏高度；外观上关掉全局阴影与描边（宿主合成器不画模糊，阴影会渲染成硬边黑框），大圆角、半透明、非活动图标不缩小。nwg-dock-hyprland 与 nwg-drawer 仍在镜像里但不自动启动，想对比时在终端跑 `arlinux-dock`（它只经宿主合成器 IPC 取窗口列表）。

**没有"窗口切换面板"按钮**，这是刻意的：Noctalia 的切换面板带窗口预览，预览会走 `ext-image-copy-capture` 请求窗口截图源，而宿主合成器这条路径会空指针崩溃（见下），连带整个会话退出。切换窗口请用 dock/taskbar 上的运行中应用图标。

### 已知宿主缺陷：截图会话导致整个会话崩溃

`libanhyprland.so`（宿主合成器）创建截图会话时不检查 dmabuf 主设备是否为空：

```text
#00 CLinuxDMABufV1Protocol::getMainDevice()+0
#01 CImageCopyCaptureSession::sendConstraints()+308
#02 CImageCopyCaptureSession::CImageCopyCaptureSession(...)+1200
#09 libwayland-server.so (wl_event_loop_dispatch+356)
```

触发序列（logcat，tag `anhyprland`）：任何访客进程绑定 `ext_foreign_toplevel_image_capture_source_manager_v1` /
`ext_image_copy_capture_manager_v1` 并创建会话，例如打开窗口切换面板时
`LayerSurface (namespace noctalia-window-switcher) created` → `New capture source for foreign toplevel` → 紧接着
`Fatal signal 11 (SIGSEGV) ... pid (.taowen.arlinux)`。宿主进程一死，guest 会话里的所有进程（Xwayland、shell、dock）一起退出，
表现就是"桌面时不时整个消失、shell 似乎一直在退出"。修复在宿主侧（空指针判空或干脆不暴露这两个全局协议）；
在它修好之前，本镜像不使用任何会触发截图的功能。

会话启动时 `wayland-info` 的协议清单写入 `$XDG_RUNTIME_DIR/arlinux-protocols.log`；其中 `zwlr_foreign_toplevel_manager_v1`、
`ext_foreign_toplevel_list_v1`、`hyprland_toplevel_mapping_manager_v1` 决定 shell 侧 taskbar 与 dock 能否列出窗口，
`ext_image_copy_capture_*` 出现在清单里说明宿主仍然会崩。shell 的每次退出都会写一行到 logcat（`arlinux-guest` 标签），
便于在没有 adb 访问实例文件的情况下定位。

### 会话被宿主系统的内存管理结束（非崩溃）

设备内存吃紧时，MIUI 的内存清理会直接结束整个 guest 会话进程组。logcat 里的证据链：

```text
I/ActivityManager: Killing 28637:io.taowen.arlinux:guest/u0a318 (adj 705): umms1_normal_mem_pressure
I/libc: kill: send 9 to pid 28637 / kill: send 9 to pid -28637
I/ActivityManager: Process PhantomProcessRecord {... 28670:28637:libarlinux_exec.so ...} died   # 同一毫秒整组消失
```

`io.taowen.arlinux:guest` 是框架为 guest 单独注册的 Android 进程，不在前台时带 `adj 705`，
属于 MIUI 内存清理的候选；被清理时其中的 sshd、shell、所有应用一起消失，桌面表现为"整个桌面不见了"。
app 进程本身还活着，但不会自动重启会话（要重新打开发行版）。缓解手段（设备侧，与镜像无关）：

- 系统设置 → 应用管理 → ARLinux → 省电策略改为**无限制**，并在最近任务里**锁定**该应用；
- 控制 guest 的内存占用：ZCode 桌面版（Electron，常驻 1 GB 量级）与大型构建同时跑时最容易触发；
- `dumpsys meminfo io.taowen.arlinux` 可看 app 侧内存，guest 内 `free -m`、`ps -eo rss` 可看总量。

### 外壳被单独结束（SIGKILL）

Noctalia 进程会以 `status=137`（SIGKILL）单独退出，间隔从几秒到几分钟不等（实测 0–559 秒），
`desktop.sh` 立即重启它，症状只是 bar/dock 重绘一次。已排除：内核 OOM（宿主 `/proc/vmstat`
的 `oom_kill` 计数不变，mimd cgroup 的 `oom_kill`/`failcnt` 也不动）、Android/MIUI 的 AM 清理
（logcat 里没有对应的 `kill:`、`Killing` 或 phantom 记录）、宿主合成器（它结束客户端会走自己的
IPC 路径）、以及设备侧观测活动（空转数分钟后仍会复现）。`plugins.auto_update = "none"` 也不是
触发条件：关掉后仍然复现。

剩下的解释只有两类，都恰好不会留下日志：guest 命名空间内的某个进程发信号（guest 用自己的
glibc，`kill()` 不进 MIUI 的插桩日志），或宿主侧原生守护进程绕过 libc 直接发信号（`tgkill`/
pidfd）。值得注意的是 MIUI 的 SSRU 一直把该 uid 标为 `restricter=1`（受限应用），而每次被杀
的都是 uid 里 CPU/内存占用最大的 guest 进程。因此设备侧的首选缓解是系统设置里把 ARLinux 的
省电策略改成**无限制**并锁定最近任务；继续取证用 `guest/debug/README.md` 里的 `waitid` 包装
（能判定"内核还是用户态"，但不能点名发送方——这一点需要宿主侧的 trace/audit 权限）。

## 调试与自动化通道（SSH）

实例没有物理键盘，app 界面也不能执行 shell 命令。镜像自带一个只监听 `127.0.0.1` 的 sshd
（`guest/debug/sshd_arlinux.conf`，端口 2222，仅公钥登录，`UsePAM no`），由 `desktop.sh`
在每次会话启动时拉起；配合 `adb forward` 就能在电脑上操作实例，改配置、读日志都不用重装 rootfs：

```sh
adb forward tcp:2222 tcp:2222
ssh -p 2222 root@127.0.0.1          # 公钥先写进实例的 /root/.ssh/authorized_keys
```

SSH 会话不会继承桌面会话的环境变量，跑 `hyprctl`、`noctalia msg` 前要先从运行中的进程取一份
（`guest/debug/README.md` 里有一行式做法）。`socat` 的 PTY shell（端口 2323，无认证）是救援通道，
默认关闭，`touch ~/.arlinux-debug-socat` 后随会话开启。

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
