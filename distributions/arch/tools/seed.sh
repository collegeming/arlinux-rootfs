#!/usr/bin/env bash
# Seed the Arch Linux ARM rootfs. Runs as the regular build user on the Linux
# builder; it never executes ARM64 code. Package configuration that needs a
# live pacman runs later in guest/build-desktop.sh.
set -euo pipefail
product="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:?rootfs output required}"
cache_root="${ARLINUX_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/arlinux}"
cache="${ARLINUX_DOWNLOAD_CACHE:-$cache_root/downloads}"
mkdir -p "$cache" "$out"
python3 - "$product" "$cache" <<'PY'
import hashlib, json, pathlib, subprocess, sys
p, cache = map(pathlib.Path, sys.argv[1:]); lock = json.loads((p / 'rootfs.lock.json').read_text())
archive = cache / ('rootfs-' + lock['sha256'] + '.tar.gz')
if not archive.is_file():
    partial = archive.with_suffix('.part')
    subprocess.run(['curl', '-fL', '--retry', '2', lock['url'], '-o', str(partial)], check=True)
    partial.replace(archive)
with archive.open('rb') as source:
    actual = hashlib.file_digest(source, 'sha256').hexdigest()
if actual != lock['sha256']:
    raise SystemExit('Rootfs hash changed; review and update rootfs.lock.json before building')
PY
archive="$(python3 -c 'import json,sys; x=json.load(open(sys.argv[1])); print(sys.argv[2]+"/rootfs-"+x["sha256"]+".tar.gz")' "$product/rootfs.lock.json" "$cache")"
tar --delay-directory-restore --no-same-owner --exclude=./dev --exclude=./proc --exclude=./sys \
    --exclude=./boot --exclude=./usr/lib/modules -xzf "$archive" -C "$out"
cp "$product/guest/mirrorlist" "$out/etc/pacman.d/mirrorlist"

# Pre-pin the archlinuxcn trust root while no ARM64 code runs. tools/post-seed.sh
# then imports archlinuxarm, archlinux and archlinuxcn into the seed's pacman
# keyring, so package preparation never bootstraps an unsigned repository and
# never needs a SigLevel override.
cn=archlinuxcn-keyring-20260505-1-any.pkg.tar.zst
cn_sha=f8ed39c21babdf8fccfc36f603bc6d99c808332238d7e5297714a0f1f624e17a
if [[ ! -f "$cache/$cn" ]]; then
    curl -fL --retry 2 "https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/aarch64/$cn" -o "$cache/$cn.part"
    mv "$cache/$cn.part" "$cache/$cn"
fi
echo "$cn_sha  $cache/$cn" | sha256sum -c -
tar --zstd -xf "$cache/$cn" -C "$out" \
    usr/share/pacman/keyrings/archlinuxcn.gpg \
    usr/share/pacman/keyrings/archlinuxcn-trusted \
    usr/share/pacman/keyrings/archlinuxcn-revoked

# pacman.conf preparation. Repository signatures stay required; only locally
# built packages (the ARLinux Mesa provider installed later with pacman -U) may
# be unsigned. Parallel downloads keep the hosted package stage short.
python3 - "$out" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1]) / 'etc/pacman.conf'
text = path.read_text()
if not re.search(r'^\s*ParallelDownloads\s*=', text, re.M):
    text = text.replace('[options]\n', '[options]\nParallelDownloads = 8\n', 1)
if not re.search(r'^\s*LocalFileSigLevel\s*=', text, re.M):
    text = text.replace('[options]\n', '[options]\nLocalFileSigLevel = Optional\n', 1)
else:
    text = re.sub(r'^\s*LocalFileSigLevel\s*=.*$', 'LocalFileSigLevel = Optional', text, flags=re.M)
path.write_text(text)
PY

# Android supplies the kernel: drop the bare-metal firmware payload and the
# kernel/firmware package records before any package scriptlet can run.
python3 - "$out" <<'PY'
import pathlib, shutil, sys
root = pathlib.Path(sys.argv[1])
shutil.rmtree(root / 'usr/lib/firmware', ignore_errors=True)
local = root / 'var/lib/pacman/local'
if local.is_dir():
    for package in local.iterdir():
        desc = package / 'desc'
        if not desc.is_file():
            continue
        lines = desc.read_text(errors='replace').splitlines()
        try:
            name = lines[lines.index('%NAME%') + 1]
        except (ValueError, IndexError):
            continue
        if name == 'linux-aarch64' or name == 'linux-firmware' or name.startswith('linux-firmware-'):
            shutil.rmtree(package)
PY
