#!/bin/bash
#=================================================
# part2.sh
# 功能：合并 通用配置 + 设备配置 生成 .config
#       写入默认系统设置覆盖目录 files/
#       对需要 USB 的设备自动启用 USB 存储/NAS/串口/网卡模块
#       执行 defconfig 解析依赖
#=================================================
set -e

SRC_DIR="${SRC_DIR:-$(pwd)/openwrt}"
BASE_DIR="$GITHUB_WORKSPACE"   # 仓库根目录（本地调试可自行改成绝对路径）
[ -z "$BASE_DIR" ] && BASE_DIR="$(pwd)"

if [ -z "${DEVICE}" ]; then
  echo "错误：未指定 DEVICE 环境变量（例如 export DEVICE=h3c_magic-nx30-pro）"
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

# 不再依赖独立 USB Job 的 ENABLE_USB_MODULES 环境变量。
# 统一构建时，根据当前 matrix 设备自动决定是否加入 USB 相关包。
case "${DEVICE}" in
  cmcc_rax3000m|cmcc_rax3000me|netcore_n60-pro)
    echo "==== ${DEVICE}：自动启用 USB 存储/NAS/串口/网卡模块 ===="
    cat >> "${SRC_DIR}/.config" <<'USB_CONFIG'
CONFIG_USB_SUPPORT=y
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-usb-storage-extras=y
CONFIG_PACKAGE_kmod-usb-storage-uas=y
CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_kmod-fs-vfat=y
CONFIG_PACKAGE_kmod-fs-exfat=y
CONFIG_PACKAGE_kmod-nls-cp437=y
CONFIG_PACKAGE_kmod-nls-iso8859-1=y
CONFIG_PACKAGE_kmod-nls-utf8=y
CONFIG_PACKAGE_block-mount=y
CONFIG_PACKAGE_kmod-usb-serial=y
CONFIG_PACKAGE_kmod-usb-serial-option=y
CONFIG_PACKAGE_kmod-usb-serial-wwan=y
CONFIG_PACKAGE_kmod-usb-net=y
CONFIG_PACKAGE_kmod-usb-net-cdc-ether=y
CONFIG_PACKAGE_kmod-usb-net-rndis=y
USB_CONFIG
    ENABLE_USB_FOR_DEVICE=1
    ;;
  *)
    echo "==== ${DEVICE}：不额外添加 USB 专用模块 ===="
    ENABLE_USB_FOR_DEVICE=0
    ;;
esac

echo "==== 写入默认系统设置覆盖目录 files/ ===="
rm -rf "${SRC_DIR}/files"
mkdir -p "${SRC_DIR}/files"
cp -r "${BASE_DIR}/files/." "${SRC_DIR}/files/"
# 确保首次开机脚本有执行权限（git 有时不保留执行位）
find "${SRC_DIR}/files/etc/uci-defaults" -type f -exec chmod +x {} \;

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

if ! grep -q "^CONFIG_TARGET_mediatek_filogic_DEVICE_.*=y" .config; then
  echo "ERROR: 没有选中任何设备，设备名可能写错"
  exit 1
fi

echo "==== defconfig 最终选中的 Filogic 设备 ===="
grep "^CONFIG_TARGET_mediatek_filogic_DEVICE_.*=y" .config

if [ "${ENABLE_USB_FOR_DEVICE:-0}" = "1" ]; then
  echo "==== USB 配置解析结果（defconfig 后）===="
  USB_SYMBOLS=(
    CONFIG_USB_SUPPORT
    CONFIG_PACKAGE_kmod-usb-storage
    CONFIG_PACKAGE_kmod-usb-storage-extras
    CONFIG_PACKAGE_kmod-usb-storage-uas
    CONFIG_PACKAGE_kmod-fs-ext4
    CONFIG_PACKAGE_kmod-fs-vfat
    CONFIG_PACKAGE_kmod-fs-exfat
    CONFIG_PACKAGE_kmod-nls-cp437
    CONFIG_PACKAGE_kmod-nls-iso8859-1
    CONFIG_PACKAGE_kmod-nls-utf8
    CONFIG_PACKAGE_block-mount
    CONFIG_PACKAGE_kmod-usb-serial
    CONFIG_PACKAGE_kmod-usb-serial-option
    CONFIG_PACKAGE_kmod-usb-serial-wwan
    CONFIG_PACKAGE_kmod-usb-net
    CONFIG_PACKAGE_kmod-usb-net-cdc-ether
    CONFIG_PACKAGE_kmod-usb-net-rndis
  )
  for symbol in "${USB_SYMBOLS[@]}"; do
    if grep -qx "${symbol}=y" .config; then
      echo "[USB OK] ${symbol}=y"
    else
      echo "[USB WARN] ${symbol} 未解析为 y（可能上游无此选项或依赖不满足）"
    fi
  done
fi

#=================================================
# 可删除模块：精简配置最终状态核验（只读）
# 如不需要核验，删除下面这段调用，并删除 scripts/check-trim-config.sh。
# 本模块不强制关闭选项，避免破坏设备/驱动依赖。
#=================================================
echo "==== 检查内核精简项最终状态（只读）===="
bash "${BASE_DIR}/scripts/check-trim-config.sh" "${SRC_DIR}/.config"

echo ">>> part2.sh 执行完毕，当前编译设备：${DEVICE}"
