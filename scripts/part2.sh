#!/bin/bash
#=================================================
# part2.sh - Nokia XG-040G ImmortalWrt
# 合并配置、写入 files、准备 Mihomo、解析最终 .config
#=================================================
set -e

SRC_DIR="${SRC_DIR:-$(pwd)/openwrt}"
BASE_DIR="${GITHUB_WORKSPACE:-$(pwd)}"

[ -n "${DEVICE:-}" ] || { echo "ERROR: 未指定 DEVICE"; exit 1; }
DEVICE_CONFIG="${BASE_DIR}/config/devices/${DEVICE}.config"
[ -f "${DEVICE_CONFIG}" ] || { echo "ERROR: 找不到 ${DEVICE_CONFIG}"; exit 1; }
[ -d "${SRC_DIR}" ] || { echo "ERROR: 源码目录不存在 ${SRC_DIR}"; exit 1; }

cd "${SRC_DIR}"
echo "==== part2: ${DEVICE} ===="

echo "==== [1/3] 合并 base + device 配置 ===="
cat "${BASE_DIR}/config/base.config" "${DEVICE_CONFIG}" > .config

# =================================================
# [2/3] 准备 files/
# =================================================
echo "==== [2/3] 准备 files/ ===="
mkdir -p "${SRC_DIR}/files"
cp -a "${BASE_DIR}/files/." "${SRC_DIR}/files/"

if [ -d "${SRC_DIR}/files/etc/uci-defaults" ]; then
  find "${SRC_DIR}/files/etc/uci-defaults" -type f -exec chmod +x {} \;
fi

# =================================================
# Mihomo Meta
# =================================================
echo "==== 准备 Mihomo Meta ===="
MIHOMO_SRC="${SRC_DIR}/clash_meta"
MIHOMO_DST="${SRC_DIR}/files/etc/openclash/core/clash_meta"
[ -f "${MIHOMO_SRC}" ] || { echo "ERROR: 找不到 ${MIHOMO_SRC}"; exit 1; }
mkdir -p "$(dirname "${MIHOMO_DST}")"
cp "${MIHOMO_SRC}" "${MIHOMO_DST}"
chmod 0755 "${MIHOMO_DST}"

# =================================================
# Nokia XG-040G 无 Wi-Fi 硬件，因此关闭无线组件
# 仅修改最终配置，不影响 files/
# =================================================
echo "==== Nokia XG-040G：关闭无硬件 Wi-Fi 组件 ===="
if [[ "${DEVICE}" == nokia_xg-040g-md* || "${DEVICE}" == nokia_xg-040g-mf* ]]; then
  for sym in \
    CONFIG_PACKAGE_wpad-openssl \
    CONFIG_PACKAGE_wifi-scripts \
    CONFIG_PACKAGE_wireless-regdb \
    CONFIG_PACKAGE_kmod-cfg80211 \
    CONFIG_PACKAGE_kmod-mac80211 \
    CONFIG_PACKAGE_kmod-mt76 \
    CONFIG_PACKAGE_kmod-mt76-core \
    CONFIG_PACKAGE_kmod-mt76-connac \
    CONFIG_PACKAGE_kmod-mt7915e \
    CONFIG_PACKAGE_kmod-mt7916 \
    CONFIG_PACKAGE_kmod-mt7996 \
    CONFIG_PACKAGE_kmod-mt7996-firmware; do
    sed -i "/^${sym}=y$/d; /^${sym}=m$/d; /^# ${sym} is not set$/d" .config
    echo "# ${sym} is not set" >> .config
  done
fi

# =================================================
# [3/3] 只做一次 defconfig
# =================================================
echo "==== [3/3] make defconfig ===="
make defconfig

echo "==== DEFCONFIG 后关键配置 ===="
grep -E '^CONFIG_PACKAGE_luci-(mod-network|mod-status|mod-system)=' .config || true
grep -E '^CONFIG_(USE_APK|PACKAGE_apk-openssl|PACKAGE_luci-app-package-manager|PACKAGE_luci-i18n-package-manager-zh-cn|LUCI_LANG_zh_Hans)=' .config || true
grep -E '^CONFIG_PACKAGE_(luci-app-store|luci-lib-taskd|luci-lib-xterm|taskd|luci-app-opkg|luci-i18n-opkg-zh-cn)=' .config || true

echo "==== part2 完成 ===="
echo "DEVICE: ${DEVICE}"
echo "LuCI：标准 Network / Status / System 模块"
echo "LuCI 软件包管理器：luci-app-package-manager + 中文"
echo "APK：CONFIG_USE_APK=y"
echo "iStore：未选中"
echo "Mihomo: ${MIHOMO_DST}"
ls -lh "${MIHOMO_DST}"
