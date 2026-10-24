Arch Linux 桌面（ARLinux）

Wayland 合成器、输入、音频与设备访问由 Android 应用提供；本 Linux 镜像在上层提供桌面用户空间：

- Noctalia 桌面外壳（状态栏与面板）与 fuzzel 启动器。
- kitty 终端：Catppuccin Frappe 主题、内置 Maple Mono NF CN 字体、fish + Tide 提示符。
- 中文环境：zh_CN.UTF-8、Asia/Shanghai 时区、思源黑体 CN、Noto emoji。
- 已装 Rime 输入法（fcitx5）；默认输入通路是 Android 宿主的 IBus 键盘，切换方式见发行版 README。
- 点按操作：顶栏的启动器/taskbar/终端/关闭窗口/切换窗口/应用抽屉/桌面诊断按钮，底部 dock 放常用应用。
- Nemo 文件管理器，带"在终端中打开"。
- Zen Browser 浏览器；AUR 助手 paru 已随镜像提供（装包用 `sudo paru -S <包名>`）。
- AI 工具：opencode、kimi-code（kimi）、ZCode 桌面版、deepseek-harness。

装包用 pacman 或 paru 即可；离线包内已包含全部桌面组件。
