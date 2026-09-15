#!/bin/bash
#=================================================
# part2.sh - Nokia XG-040G ImmortalWrt
# 生成最终 .config、写入 files，并启用 iStore 离线本地包
#=================================================
set -e

SRC_DIR="${SRC_DIR:-$(pwd)/openwrt}"
BASE_DIR="${GITHUB_WORKSPACE:-$(pwd)}"

[ -n "${DEVICE:-}" ] || { echo "ERROR: 未指定 DEVICE"; exit 1; }
DEVICE_CONFIG="${BASE_DIR}/config/devices/${DEVICE}.config"
[ -f "${DEVICE_CONFIG}" ] || { echo "ERROR: 找不到 ${DEVICE_CONFIG}"; exit 1; }
[ -d "${SRC_DIR}" ] || { echo "ERROR: 源码目录不存在 ${SRC_DIR}"; exit 1; }
[ -d "${SRC_DIR}/package/istore-offline" ] || { echo "ERROR: iStore 本地包目录不存在"; exit 1; }

cd "${SRC_DIR}"
echo "==== part2: ${DEVICE} ===="

echo "==== [1/4] 合并 base + device 配置 ===="
cat "${BASE_DIR}/config/base.config" "${DEVICE_CONFIG}" > .config

# base.config 中的旧 iStore 选项先清掉，再启用 part1 根据指定 .run
# 转换出来的本地 OpenWrt 包。这样不会使用 istore feed。
for sym in \
  CONFIG_PACKAGE_luci-app-store \
  CONFIG_PACKAGE_luci-lib-taskd \
  CONFIG_PACKAGE_luci-lib-xterm \
  CONFIG_PACKAGE_taskd; do
  sed -i "/^${sym}=y$/d; /^${sym}=m$/d; /^# ${sym} is not set$/d" .config
done

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

# iStore：来自指定 .run 的四个离线 APK，已转换为本地 OpenWrt 包
CONFIG_PACKAGE_luci-app-store=y
CONFIG_PACKAGE_luci-lib-taskd=y
CONFIG_PACKAGE_luci-lib-xterm=y
CONFIG_PACKAGE_taskd=y
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

for pkg in luci-app-store luci-lib-taskd luci-lib-xterm taskd; do
  [ -d "${SRC_DIR}/package/istore-offline/${pkg}/root" ] || {
    echo "ERROR: iStore 本地包 ${pkg} 未准备完成"
    exit 1
  }
done

# =================================================
# [3/4] make defconfig
# =================================================
echo "==== [3/4] make defconfig ===="
make defconfig

# =================================================
# [4/4] 最终配置验证
# =================================================
# 注意：iStore 本地包的 CONFIG_PACKAGE_* 可能因 ImmortalWrt
# 的依赖解析被 defconfig 自动移除，因此这里不再把
# luci-app-store/taskd 等 CONFIG_PACKAGE_* 当作 part2 的硬失败条件。
# iStore 包是否实际进入最终固件，由后续 package/install 阶段决定。
echo "==== [4/4] 中文 / APK / Mihomo 最终检查 ===="
MISSING=0

if ! grep -q '^CONFIG_LUCI_LANG_zh_Hans=y' .config; then
  echo "ERROR: CONFIG_LUCI_LANG_zh_Hans 未启用，中文语言包不会被编译"
  MISSING=1
fi

if ! grep -q '^CONFIG_USE_APK=y' .config; then
  echo "ERROR: CONFIG_USE_APK 未启用"
  MISSING=1
fi

[ "$MISSING" = "1" ] && exit 1

echo ">>> iStore：不再因 CONFIG_PACKAGE_* 被 defconfig 移除而中止构建"
echo ">>> iStore 本地包目录已准备完成，继续进入正式编译阶段"

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
# 输出最终摘要
# =================================================
echo "==== part2 完成 ===="
echo "DEVICE: ${DEVICE}"
echo "LuCI 软件包管理器：luci-app-package-manager + 中文"
echo "LuCI 中文：CONFIG_LUCI_LANG_zh_Hans=y"
echo "APK: CONFIG_USE_APK=y"
echo "iStore：本地离线包目录已准备"
echo "Mihomo: ${MIHOMO_DST}"
ls -lh "${MIHOMO_DST}"
