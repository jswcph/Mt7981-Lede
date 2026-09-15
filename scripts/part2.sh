#!/bin/bash
#=================================================
# part2.sh - Nokia XG-040G ImmortalWrt
# 生成最终 .config、写入 files，并对第三方包做最终配置验证
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

cat >> .config <<'EOF'

# ImmortalWrt master / APK package manager
CONFIG_USE_APK=y
CONFIG_PACKAGE_apk-openssl=y
# CONFIG_PACKAGE_opkg is not set

# LuCI package manager
CONFIG_PACKAGE_luci-app-package-manager=y
CONFIG_PACKAGE_luci-i18n-package-manager-zh-cn=y
# CONFIG_PACKAGE_luci-app-opkg is not set
# CONFIG_PACKAGE_luci-i18n-opkg-zh-cn is not set

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
# [4/4] 最终 .config 验证
# =================================================
echo "==== 最终核心软件包检查 ===="

MISSING=0
for sym in luci-app-store taskd luci-lib-taskd; do
  if ! grep -q "^CONFIG_PACKAGE_${sym}=y" .config; then
    echo "ERROR: ${sym} 未进入最终配置（依赖未满足，已被 defconfig 丢弃）"
    MISSING=1
  fi
done

if ! grep -q '^CONFIG_LUCI_LANG_zh_Hans=y' .config; then
  echo "ERROR: CONFIG_LUCI_LANG_zh_Hans 未启用，中文语言包不会被编译"
  MISSING=1
fi

[ "$MISSING" = "1" ] && exit 1
echo ">>> 核心软件包与中文支持检查通过"

if [[ "${DEVICE}" == nokia_xg-040g-md* || "${DEVICE}" == nokia_xg-040g-mf* ]]; then
  echo "==== Nokia XG-040G：关闭无硬件 Wi-Fi 组件 ===="
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
# 输出最终摘要
# =================================================
echo "==== part2 完成 ===="
echo "DEVICE: ${DEVICE}"
echo "LuCI 软件包管理器：luci-app-package-manager + 中文"
echo "LuCI 中文：CONFIG_LUCI_LANG_zh_Hans=y"
echo "APK: CONFIG_USE_APK=y"
echo "Mihomo: ${MIHOMO_DST}"
ls -lh "${MIHOMO_DST}"
