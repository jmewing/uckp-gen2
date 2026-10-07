#!/bin/bash
cd /srv/offgridsentinel/kernel-port/linux-msm8953
exec > /srv/offgridsentinel/kernel-port/build-mainline.log 2>&1
set -o pipefail
date
echo "=== build start ==="
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image dtbs 2>&1 | tail -80
echo "=== build rc=$? ==="
ls -la arch/arm64/boot/Image arch/arm64/boot/dts/qcom/*.dtb 2>/dev/null | head
date
