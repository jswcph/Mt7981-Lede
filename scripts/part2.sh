#!/bin/bash
#=================================================
# part2.sh
# 功能：合并 通用配置 + 设备配置生成最终 .config
#       写入默认系统设置覆盖目录 files/
#       执行 defconfig 解析依赖
#=================================================
set -e

SRC_DIR="${SRC_DIR:-$(pwd)/openwrt}"
BASE_DIR="$GITHUB_WORKSPACE"   # 仓库根目录（本地调试可自行改成绝对路径）
[ -z "$BASE_DIR" ] && BASE_DIR="$(pwd)"

if [ -z "${DEVICE}" ]; then
  echo "错误：未指定 DEVICE 环境变量"
  exit 1
fi

DEVICE_CONFIG="${BASE_DIR}/config/devices/${DEVICE}.config"
if [ ! -f "${DEVICE_CONFIG}" ]; then
  echo "错误：找不到设备配置文件 ${DEVICE_CONFIG}"
  echo "请检查 config/devices/ 目录下是否有对应的 .config 文件"
  exit 1
fi

echo "==== 写入通用配置 + 设备配置：${DEVICE} ===="
cat "${BASE_DIR}/config/base.config" "${DEVICE_CONFIG}" > "${SRC_DIR}/.config"
echo "==== 写入默认系统设置覆盖目录 files/ ===="
rm -rf "${SRC_DIR}/files"
mkdir -p "${SRC_DIR}/files"
cp -r "${BASE_DIR}/files/." "${SRC_DIR}/files/"
find "${SRC_DIR}/files/etc/uci-defaults" -type f -exec chmod +x {} \;

#=================================================
# Ruijie RG-X60 Pro 107M DTS
# 使用用户提供的 107M 分区版本；不修改 ImmortalWrt master
# 中原有设备定义，只替换本次构建使用的 DTS 文件。
#=================================================
if [ "${DEVICE}" = "ruijie_x60-pro-107m" ]; then
  CUSTOM_DTS="${BASE_DIR}/custom/mt7986a-ruijie-rg-x60-pro-107m.dts"
  TARGET_DTS="${SRC_DIR}/target/linux/mediatek/dts/mt7986a-ruijie-rg-x60-pro.dts"

  if [ ! -f "${CUSTOM_DTS}" ]; then
    echo "错误：找不到 X60 Pro 107M DTS：${CUSTOM_DTS}"
    exit 1
  fi

  echo "==== 注入 Ruijie RG-X60 Pro 107M DTS ===="
  cp "${CUSTOM_DTS}" "${TARGET_DTS}"
  grep -A2 'partition@680000' "${TARGET_DTS}"
fi

echo "==== 写回预编译的 Mihomo Meta 核心 ===="
mkdir -p "${SRC_DIR}/files/etc/openclash/core"
if [ -f "${SRC_DIR}/clash_meta" ]; then
  cp "${SRC_DIR}/clash_meta" "${SRC_DIR}/files/etc/openclash/core/clash_meta"
  chmod 0755 "${SRC_DIR}/files/etc/openclash/core/clash_meta"
else
  echo "警告：未找到预编译的 clash_meta，跳过内核写入"
fi

echo "==== 执行 make defconfig 解析依赖 ===="
cd "${SRC_DIR}"
make defconfig

#=================================================
# Nokia XG-040G-MD/MF 无无线硬件
# make defconfig 可能根据 target/default 依赖重新选择无线组件，
# 因此在 defconfig 后再次强制关闭无线相关用户空间组件和驱动包。
#=================================================
if [[ "${DEVICE}" == nokia_xg-040g-md* || "${DEVICE}" == nokia_xg-040g-mf* ]]; then
  echo "==== Nokia XG-040G：强制关闭无线驱动/无线管理组件 ===="
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

  echo "==== 无线配置最终检查 ===="
  grep -E '^(CONFIG_PACKAGE_(wpad|wifi-scripts|wireless-regdb)|CONFIG_PACKAGE_kmod-(cfg80211|mac80211|mt76|mt7915|mt7916|mt7996))' .config || true
fi

echo ">>> part2.sh 执行完毕，当前编译设备：${DEVICE}"
