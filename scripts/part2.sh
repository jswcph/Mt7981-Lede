#!/bin/bash
#=================================================
# part2.sh - Nokia XG-040G ImmortalWrt
# 生成最终 .config、写入 files，并离线预装 iStore APK
#=================================================
set -e

SRC_DIR="${SRC_DIR:-$(pwd)/openwrt}"
BASE_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
ISTORE_DIR="${SRC_DIR}/../istore-offline"

[ -n "${DEVICE:-}" ] || { echo "ERROR: 未指定 DEVICE"; exit 1; }
DEVICE_CONFIG="${BASE_DIR}/config/devices/${DEVICE}.config"
[ -f "${DEVICE_CONFIG}" ] || { echo "ERROR: 找不到 ${DEVICE_CONFIG}"; exit 1; }
[ -d "${SRC_DIR}" ] || { echo "ERROR: 源码目录不存在 ${SRC_DIR}"; exit 1; }

cd "${SRC_DIR}"
echo "==== part2: ${DEVICE} ===="

echo "==== [1/4] 合并 base + device 配置 ===="
cat "${BASE_DIR}/config/base.config" "${DEVICE_CONFIG}" > .config

# iStore 不再作为 ImmortalWrt 源码包参与 defconfig。
# base.config 中保留的旧配置在这里显式取消，避免进入源码包依赖解析。
for sym in \
  CONFIG_PACKAGE_luci-app-store \
  CONFIG_PACKAGE_luci-lib-taskd \
  CONFIG_PACKAGE_luci-lib-xterm \
  CONFIG_PACKAGE_taskd; do
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
# CONFIG_PACKAGE_luci-app-opkg is not set
# CONFIG_PACKAGE_luci-i18n-opkg-zh-cn is not set

# LuCI 简体中文
CONFIG_LUCI_LANG_zh_Hans=y
EOF

# =================================================
# [2/4] 准备 files/ 与 iStore 离线包
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

[ -d "${ISTORE_DIR}" ] || { echo "ERROR: iStore 离线目录不存在：${ISTORE_DIR}"; exit 1; }
for apk in \
  luci-app-store-0.2.0-r3.apk \
  luci-lib-taskd-1.0.25.apk \
  luci-lib-xterm-4.18.0.apk \
  taskd-1.0.3-r2.apk; do
  [ -f "${ISTORE_DIR}/${apk}" ] || { echo "ERROR: 找不到 iStore APK：${ISTORE_DIR}/${apk}"; exit 1; }
done

# =================================================
# [3/4] make defconfig
# =================================================
echo "==== [3/4] make defconfig ===="
make defconfig

# =================================================
# [3.5/4] 将 iStore APK 注入目标 rootfs
# =================================================
# 不能在 Ubuntu 构建机上直接执行 install25.sh；它是目标 OpenWrt 的运行时脚本。
# 这里使用 ImmortalWrt 的 staging_dir/host/bin/apk 工具，对一个临时 target rootfs
# 执行离线 apk add，避免首次启动时依赖网络。
echo "==== [3.5/4] 离线安装 iStore APK ===="
APK_BIN="${STAGING_DIR_HOST:-${SRC_DIR}/staging_dir/host}/bin/apk"
[ -x "${APK_BIN}" ] || { echo "ERROR: 找不到 ImmortalWrt host apk：${APK_BIN}"; exit 1; }

# 使用 OpenWrt 构建系统的 rootfs 目录；此时先建立最小目标目录。
TARGET_ROOT="${SRC_DIR}/tmp/istore-root"
rm -rf "${TARGET_ROOT}"
mkdir -p "${TARGET_ROOT}"

# 先准备 apk 所需目录。实际最终 rootfs 构建时，apk 数据库及文件会随包进入固件。
mkdir -p "${TARGET_ROOT}/etc/apk" "${TARGET_ROOT}/lib/apk/db" "${TARGET_ROOT}/var/lib/apk"

# 以 target root 为 --root，完全离线安装；--no-network 防止构建阶段意外访问网络。
"${APK_BIN}" --root "${TARGET_ROOT}" --no-network add --allow-untrusted \
  "${ISTORE_DIR}/luci-lib-xterm-4.18.0.apk" \
  "${ISTORE_DIR}/luci-lib-taskd-1.0.25.apk" \
  "${ISTORE_DIR}/taskd-1.0.3-r2.apk" \
  "${ISTORE_DIR}/luci-app-store-0.2.0-r3.apk"

# 将 APK 安装结果合并到 OpenWrt files/，并把 apk 数据库一并带入最终固件。
cp -a "${TARGET_ROOT}/." "${SRC_DIR}/files/"

# 不把下载的原始 APK 放进固件，避免浪费 NAND/ROM 空间。
rm -rf "${SRC_DIR}/files/tmp" \
       "${SRC_DIR}/files/var/cache/apk"

# =================================================
# [4/4] 最终检查
# =================================================
echo "==== [4/4] iStore / 中文 / Mihomo 最终检查 ===="
MISSING=0

# iStore 现在不是 CONFIG_PACKAGE_*，而是已注入 files/rootfs 的离线 APK 内容。
for path in \
  "${SRC_DIR}/files/usr/share/luci/menu.d/luci-app-store.json" \
  "${SRC_DIR}/files/etc/apk/world"; do
  if [ ! -e "${path}" ]; then
    echo "ERROR: iStore 离线安装结果缺少：${path}"
    MISSING=1
  fi
done

if ! grep -q '^CONFIG_LUCI_LANG_zh_Hans=y' .config; then
  echo "ERROR: CONFIG_LUCI_LANG_zh_Hans 未启用，中文语言包不会被编译"
  MISSING=1
fi

for sym in luci-app-store taskd luci-lib-taskd luci-lib-xterm; do
  if grep -q "^CONFIG_PACKAGE_${sym}=y" .config; then
    echo "ERROR: ${sym} 仍被作为源码 package 加入 .config"
    MISSING=1
  fi
done

[ "$MISSING" = "1" ] && exit 1

echo ">>> iStore 已按离线 APK 方式预装"

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
echo "iStore：离线 APK 已注入 ${SRC_DIR}/files/"
echo "Mihomo: ${MIHOMO_DST}"
ls -lh "${MIHOMO_DST}"
