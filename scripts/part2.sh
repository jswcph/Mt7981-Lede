#!/bin/bash
set -e

SRC_DIR="${SRC_DIR:-$(pwd)/openwrt}"
BASE_DIR="${GITHUB_WORKSPACE:-$(pwd)}"

[ -n "${DEVICE:-}" ] || exit 1

DEVICE_CONFIG="${BASE_DIR}/config/devices/${DEVICE}.config"

[ -f "${DEVICE_CONFIG}" ] || exit 1
[ -d "${SRC_DIR}" ] || exit 1

cd "${SRC_DIR}"

echo "==== 合并配置 ===="

cat \
    "${BASE_DIR}/config/base.config" \
    "${DEVICE_CONFIG}" \
    > .config

echo "==== 写入 files ===="

mkdir -p "${SRC_DIR}/files"
cp -a "${BASE_DIR}/files/." "${SRC_DIR}/files/"

find "${SRC_DIR}/files/etc/uci-defaults" \
    -type f \
    -exec chmod +x {} \; 2>/dev/null || true

echo "==== 写入 Mihomo Meta ===="

MIHOMO_SRC="${SRC_DIR}/clash_meta"
MIHOMO_DST="${SRC_DIR}/files/etc/openclash/core/clash_meta"

[ -f "${MIHOMO_SRC}" ] || {
    echo "ERROR: 找不到 clash_meta"
    exit 1
}

mkdir -p "$(dirname "${MIHOMO_DST}")"
cp "${MIHOMO_SRC}" "${MIHOMO_DST}"
chmod 0755 "${MIHOMO_DST}"

echo "==== make defconfig ===="

make defconfig

echo "==== 最终关键配置 ===="

grep -E \
'^CONFIG_(TARGET_|USE_APK|PACKAGE_luci-(mod-network|mod-status|mod-system|app-package-manager)|LUCI_LANG_zh_Hans)' \
.config || true
