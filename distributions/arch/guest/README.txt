Arch Linux 桌面（ARLinux）

Wayland 合成器、输入、音频与设备访问由 Android 应用提供；本 Linux 镜像在上层提供桌面用户空间：

- Noctalia 桌面外壳（状态栏与面板）与 fuzzel 启动器；外壳与终端共用 Catppuccin Frappe 调色板
  （调色板随镜像内置，离线可用）。
- kitty 终端：Catppuccin Frappe 主题、内置 Maple Mono NF CN 字体、fish + Tide 提示符。
- 中文环境：zh_CN.UTF-8、Asia/Shanghai 时区、思源黑体 CN、Noto emoji。
- 已装 Rime 输入法（fcitx5）；默认输入通路是 Android 宿主的 IBus 键盘，切换方式见发行版 README。
- 点按操作：顶栏左侧是启动器/应用抽屉/终端/关闭窗口/桌面诊断，中间是运行中的窗口，右侧是时钟/音量/电池/控制中心；
  底部 dock 的第一项就是 Apps 抽屉，dock 是悬浮的（不占用应用窗口高度）。nwg-dock 也在镜像里
  （终端跑 `arlinux-dock`），但默认不启动。
- 远程操作通道：会话自带只监听 127.0.0.1:2222 的 sshd（仅公钥登录），在电脑上 `adb forward tcp:2222 tcp:2222`
  后即可 `ssh -p 2222 root@127.0.0.1`；把公钥写进实例的 `/root/.ssh/authorized_keys` 即可使用。
- Nemo 文件管理器，带"在终端中打开"。
- Zen Browser 浏览器；AUR 助手 paru 已随镜像提供（装包用 `sudo paru -S <包名>`）。
- AI 工具：opencode、kimi-code（kimi）、ZCode 桌面版、deepseek-harness。

装包用 pacman 或 paru 即可；离线包内已包含全部桌面组件。
