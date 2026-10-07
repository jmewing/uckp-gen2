#!/bin/bash
cd /srv/offgridsentinel/kernel-port/linux-msm8953
exec > /srv/offgridsentinel/kernel-port/build-mainline.log 2>&1
set -o pipefail
date
echo "=== CLEAN rebuild start (make clean, keep .config) ==="
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- clean >/dev/null 2>&1
echo "clean rc=$?  ($(date))"
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image dtbs 2>&1 | tail -60
echo "=== build rc=$? ==="
ls -la arch/arm64/boot/Image arch/arm64/boot/dts/qcom/msm8953-ubiquiti-uck.dtb 2>/dev/null
date
echo "=== CLEAN REBUILD DONE ==="
