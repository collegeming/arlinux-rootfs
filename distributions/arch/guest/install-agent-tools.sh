#!/bin/sh
# Pinned AI coding agents for the offline desktop.
#
#   kimi-code  mirrors AUR kimi-code-bin 2.3.1  -> /usr/bin/kimi
#   zcode      mirrors AUR zcode 3.16.2          -> /opt/ZCode + /usr/bin/zcode
#
# opencode (the 2.x coding agent) and deepseek-harness are regular Arch
# packages and are installed from the repositories in build-desktop.sh. The
# OpenCode Desktop launcher stays framework-owned: it resolves and installs the
# current Desktop build on first use, which is independent of this CLI.
set -eu
root=/

fetch_verified() { # url sha256 destination
    curl -fL --retry 5 --retry-delay 3 --retry-all-errors --connect-timeout 20 --max-time 600 \
        -o "$3" "$1"
    printf '%s  %s\n' "$2" "$3" | sha256sum -c -
}

require_aarch64_elf() { # path
    file "$1" | grep -Eq 'ELF 64-bit LSB.*(ARM aarch64|AArch64)'
    readelf -h "$1" | grep -Eq 'Machine:[[:space:]]+AArch64'
    readelf -l "$1" | grep -Fq 'Requesting program interpreter: /lib/ld-linux-aarch64.so.1'
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# --- kimi-code (AUR kimi-code-bin 2.3.1 payload) -------------------------
# Bun-compiled glibc binary; the upstream asset name is version-independent,
# so the local name carries the version like the AUR recipe does.
kimi_url='https://github.com/MoonshotAI/kimi-code/releases/download/%40moonshot-ai/kimi-code%402.3.1/kimi-code-linux-arm64.tar.gz'
kimi_sha=6ef2af316d3b7fe28313bbd6aa3fdc0e5943e43958cbf7f6a564e48acec355f0
kimi_license_url='https://raw.githubusercontent.com/MoonshotAI/kimi-code/%40moonshot-ai%2Fkimi-code%402.3.1/LICENSE'
kimi_license_sha=23cc68e17992e0b512ae2e80afc5787d7d8e0fbfbdb4fff54ec0245508fa400e
echo 'ARLINUX:Installing kimi-code (kimi-code-bin 2.3.1)...'
fetch_verified "$kimi_url" "$kimi_sha" "$work/kimi.tar.gz"
mkdir -p "$work/kimi"
tar -xzf "$work/kimi.tar.gz" -C "$work/kimi" --no-same-owner --no-same-permissions
test -f "$work/kimi/kimi" && [ ! -L "$work/kimi/kimi" ]
require_aarch64_elf "$work/kimi/kimi"
install -Dm755 "$work/kimi/kimi" /usr/bin/kimi
fetch_verified "$kimi_license_url" "$kimi_license_sha" "$work/kimi-LICENSE"
install -Dm644 "$work/kimi-LICENSE" /usr/share/licenses/kimi-code-bin/LICENSE
command -v kimi >/dev/null

# --- zcode (AUR zcode 3.16.2 payload) -----------------------------------
# The official Electron release is repacked here exactly like the AUR recipe:
# /opt/ZCode plus an /usr/bin/zcode symlink and the Chromium licenses. The
# bundled JS patch from the AUR post_install hook is applied afterwards.
zcode_ver=3.16.2
zcode_url="https://cdn-zcode.z.ai/zcode/electron/releases/${zcode_ver}/linux-arm64/ZCode-${zcode_ver}-linux-arm64.deb"
zcode_sha=35bc72a8b9316703eca135f336e486a39740c9a3344423ead2e2038502c17cf0
echo "ARLINUX:Installing ZCode desktop ${zcode_ver}..."
fetch_verified "$zcode_url" "$zcode_sha" "$work/zcode.deb"
mkdir -p "$work/deb"
bsdtar -C "$work/deb" -xf "$work/zcode.deb"
bsdtar -C "$work/deb" -xf "$work/deb/data.tar.xz"
test -d "$work/deb/opt/ZCode"
install -d /opt /usr/share/licenses/zcode
cp -a "$work/deb/opt/ZCode" /opt/
ln -sfn /opt/ZCode/zcode /usr/bin/zcode
chmod 0755 /opt/ZCode/chrome-sandbox
cp -a "$work/deb/usr/share/icons" /usr/share/
install -Dm644 "$work/deb/opt/ZCode/LICENSE.electron.txt" \
    /usr/share/licenses/zcode/LICENSE.electron.txt
install -Dm644 "$work/deb/opt/ZCode/LICENSES.chromium.html" \
    /usr/share/licenses/zcode/LICENSES.chromium.html
# Electron's SUID/user-namespace sandbox cannot work under the Android app
# UID, the same limitation the framework documents for other sandboxed
# loaders, so the desktop entry disables it explicitly.
cat > /usr/share/applications/zcode.desktop <<'DESKTOP'
[Desktop Entry]
Name=ZCode
Comment=ZCode desktop app
Exec=/usr/bin/zcode --no-sandbox %U
TryExec=/usr/bin/zcode
Icon=zcode
Terminal=false
Type=Application
Categories=Development;IDE;
MimeType=x-scheme-handler/zcode;
StartupNotify=true
StartupWMClass=ZCode
DESKTOP

# The AUR post_install hook patches the bundled Responses client against
# missing `annotations` arrays. Kept verbatim so this image behaves exactly
# like a `pacman -U zcode` installation; a version bump must re-check it.
bundle=/opt/ZCode/resources/glm/zcode.cjs
if [ -f "$bundle" ]; then
    perl -0pi -e '
    my $marker = q{part&&part.type==="output_text"&&!Array.isArray(part.annotations)};
    next if index($_, $marker) >= 0;

    my $id = qr/[A-Za-z_\$][A-Za-z0-9_\$]*/;
    my $pattern = qr/let ($id)=await ($id)\.text\(\),($id)=await ($id)\(\{text:\1,schema:($id)\}\),($id)=($id)\(\2\);if\(!\3\.success\)throw new ($id)\(\{message:"Invalid JSON response"/;

    if (my @match = /$pattern/) {
      my ($body, $response, $parsed, $parser, $schema, $headers, $header_parser, $error_class) = @match;
      my $patched_text = "(()=>{try{let o=JSON.parse($body);if(Array.isArray(o?.output)){let changed=!1;for(let item of o.output){let content=item?.content;if(!Array.isArray(content))continue;for(let part of content){if(part&&part.type===" . q{"output_text"} . "&&!Array.isArray(part.annotations)){part.annotations=[];changed=!0}}}if(changed)return JSON.stringify(o)}}catch{}return $body})()";
      my $replacement = "let $body=await $response.text(),$parsed=await $parser({text:$patched_text,schema:$schema}),$headers=$header_parser($response);if(!$parsed.success)throw new $error_class({message:" . q{"Invalid JSON response"};
      s/$pattern/$replacement/;
    }
    ' "$bundle" || true
    grep -Fq 'part.type==="output_text"&&!Array.isArray(part.annotations)' "$bundle" || {
        echo 'ERROR: the bundled zcode Responses client no longer matches the AUR patch' >&2
        echo 'Re-check the AUR zcode post_install hook when bumping zcode_ver.' >&2
        exit 1
    }
fi
test -x /usr/bin/zcode
echo '--> [agents] kimi-code and ZCode installed'
