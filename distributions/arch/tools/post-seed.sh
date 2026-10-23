#!/usr/bin/env bash
# Import the distribution trust roots into the seed's pacman keyring. The
# Android app UID cannot create GnuPG's root-owned trust database, so it is
# generated here, before the seed is packed.
set -euo pipefail
rootfs=${1:?rootfs required}
framework=$(cd "$(dirname "$0")/../../.." && pwd)
"$framework/tools/build/seed-pacman-keyring.sh" \
    "$rootfs" archlinuxarm archlinux archlinuxcn
