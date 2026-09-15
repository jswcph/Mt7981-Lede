#!/bin/bash
#=================================================
# part2.sh - Nokia XG-040G ImmortalWrt
# 生成最终 .config、写入 files
# iStore 已彻底移除
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

echo "==== [1/4] 合并 base + device 配置 ===="
cat "${BASE_DIR}/config/base.config" "${DEVICE_CONFIG}" > .config

# 明确彻底关闭 iStore/旧 OPKG，避免历史配置残留。
for sym in \
  CONFIG_PACKAGE_luci-app-store \
  CONFIG_PACKAGE_luci-lib-taskd \
  CONFIG_PACKAGE_luci-lib-xterm \
  CONFIG_PACKAGE_taskd \
  CONFIG_PACKAGE_luci-app-opkg \
  CONFIG_PACKAGE_luci-i18n-opkg-zh-cn; do
  sed -i "/^${sym}=y$/d; /^${sym}=m$/d; /^# ${sym} is not set$/d" .config
  echo "# ${sym} is not set" >> .config
done

cat >> .config <<'EOF'

# ImmortalWrt master / APK package manager
CONFIG_USE_APK=y
CONFIG_PACKAGE_apk-openssl=y
# CONFIG_PACKAGE_opkg is not set

# LuCI package manager
CONFIG_PACKAGE_luci-app-package-manager=y
CONFIG_PACKAGE_luci-i18n-package-manager-zh-cn=y

# LuCI 简体中文
CONFIG_LUCI_LANG_zh_Hans=y
EOF

# =================================================
# [2/4] 准备 files/
# =================================================
echo "==== [2/4] 准备 files/ ===="
rm -rf "${SRC_DIR}/files"
mkdir -p "${SRC_DIR}/files"
cp -a "${BASE_DIR}/files/." "${SRC_DIR}/files/"

if [ -d "${SRC_DIR}/files/etc/uci-defaults" ]; then
  find "${SRC_DIR}/files/etc/uci-defaults" -type f -exec chmod +x {} \;
fi

MIHOMO_SRC="${SRC_DIR}/clash_meta"
MIHOMO_DST="${SRC_DIR}/files/etc/openclash/core/clash_meta"
[ -f "${MIHOMO_SRC}" ] || { echo "ERROR: 找不到 ${MIHOMO_SRC}"; exit 1; }
mkdir -p "$(dirname "${MIHOMO_DST}")"
cp "${MIHOMO_SRC}" "${MIHOMO_DST}"
chmod 0755 "${MIHOMO_DST}"

# =================================================
# [3/4] make defconfig
# =================================================
echo "==== [3/4] make defconfig ===="
make defconfig

# =================================================
# [4/4] 最终配置验证
# =================================================
echo "==== [4/4] 最终配置检查 ===="
MISSING=0

check_y() {
  if grep -q "^$1=y$" .config; then
    echo "OK: $1=y"
  else
    echo "ERROR: $1 未进入最终 .config"
    MISSING=1
  fi
}

check_disabled() {
  if grep -q "^# $1 is not set$" .config; then
    echo "OK: $1 disabled"
  else
    echo "ERROR: $1 没有被关闭"
    MISSING=1
  fi
}

check_y CONFIG_USE_APK
check_y CONFIG_PACKAGE_apk-openssl
check_y CONFIG_PACKAGE_luci-app-package-manager
check_y CONFIG_PACKAGE_luci-i18n-package-manager-zh-cn
check_y CONFIG_LUCI_LANG_zh_Hans

check_disabled CONFIG_PACKAGE_luci-app-store
check_disabled CONFIG_PACKAGE_luci-lib-taskd
check_disabled CONFIG_PACKAGE_luci-lib-xterm
check_disabled CONFIG_PACKAGE_taskd
check_disabled CONFIG_PACKAGE_luci-app-opkg
check_disabled CONFIG_PACKAGE_luci-i18n-opkg-zh-cn

[ "$MISSING" = "1" ] && exit 1

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

echo "==== part2 完成 ===="
echo "DEVICE: ${DEVICE}"
echo "LuCI 软件包管理器：luci-app-package-manager + 中文"
echo "LuCI 中文：CONFIG_LUCI_LANG_zh_Hans=y"
echo "APK: CONFIG_USE_APK=y"
echo "iStore：已彻底移除"
echo "Mihomo: ${MIHOMO_DST}"
ls -lh "${MIHOMO_DST}"
