# 实例调试通道（SSH）

镜像里的发行版是宿主 app 的子进程，没有物理键盘，app 界面也不能执行 shell 命令。
为了在不重装 rootfs 的前提下读日志、改配置，镜像自带一个只监听回环地址的 sshd，
由 `guest/desktop.sh` 在每次会话启动时拉起（配置：`sshd_arlinux.conf`，端口 2222，
仅公钥登录，`PermitRootLogin yes`，`UsePAM no`）。

## 一次性准备：写入公钥

首次使用前，把电脑上的公钥写进实例的 `/root/.ssh/authorized_keys`（在 guest 的终端
里执行一次即可，写进 rootfs 后长期有效）：

```sh
mkdir -p /root/.ssh && chmod 700 /root/.ssh
echo 'ssh-ed25519 AAAA... 你的备注' >> /root/.ssh/authorized_keys
```

## 连接

```sh
adb forward tcp:2222 tcp:2222
ssh -p 2222 -i ~/.ssh/你的私钥 root@127.0.0.1
```

`sshd` 由 `desktop.sh` 随会话启动，会话结束后随之消失；只监听 127.0.0.1，必须借助
`adb forward` 或设备上的端口转发才能访问。会话环境（`XDG_RUNTIME_DIR`、
`HYPRLAND_INSTANCE_SIGNATURE`、`HOME` 等）不会自动带进 SSH 会话，需要跑
`hyprctl`、`noctalia msg` 时先取一份运行中会话的环境：

```sh
for p in $(pgrep -f noctalia | head -1); do
    while IFS= read -r -d '' kv; do
        case "$kv" in XDG_RUNTIME_DIR=*|HYPRLAND_INSTANCE_SIGNATURE=*|HOME=*|XDG_CONFIG_HOME=*|XDG_STATE_HOME=*|XDG_CACHE_HOME=*|PATH=*) export "$kv";; esac
    done < /proc/$p/environ
done
```

## 救援通道：socat PTY

`sshd` 起不来或密钥丢失时，可以在 guest 终端里手工开一个 PTY shell：

```sh
socat TCP-LISTEN:2323,bind=127.0.0.1,reuseaddr,fork EXEC:'/bin/bash',pty,stderr,setsid,sigint,sane
```

再 `adb forward tcp:2323 tcp:2323`，用任意 TCP 客户端连接（注意这是**无认证**的
root shell，只在回环地址上开）。若希望每次会话自动开启，创建标记文件即可：

```sh
touch ~/.arlinux-debug-socat
```

> 安全边界：这两条通道都只绑定 127.0.0.1，等价于“能连本机端口的进程”即可访问——
> 也就是设备上的其他 Android 应用（借助 `adb forward` 时才是电脑）。SSH 走公钥，
> socat 无认证，所以 socat 默认关闭、需要显式开启。

## 记录外壳被谁结束：waitid 包装

Noctalia 会以 `status=137`（SIGKILL）被单独结束，且两侧日志都没有凶手的痕迹。
`noctalia-waitid.py` 把真正的二进制包一层、用 `waitid()` 记录子进程的 `siginfo`
（退出还是被杀、信号名、`si_code`/`si_pid`），每次死亡写一行到 `/tmp/noctalia-waitid.log`，
同时进入 supervisor 的日志尾部（`$XDG_CACHE_HOME/arlinux/desktop-diag.log`）。启用方式：

```sh
mv /usr/bin/noctalia /usr/bin/noctalia.real
printf '#!/bin/bash\nexec python3 /usr/local/lib/arlinux/noctalia-waitid.py "$@"\n' > /usr/bin/noctalia
chmod 755 /usr/bin/noctalia
```

还原：`mv /usr/bin/noctalia.real /usr/bin/noctalia`。注意包装后进程名变成
`noctalia.real`，按名字找进程的工具（`pgrep -x noctalia`）会失配，请用
`pgrep -f noctalia`。
