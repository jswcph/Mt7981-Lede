#!/bin/bash
#=================================================
# part2.sh
# 功能：合并 通用配置 + 设备配置 生成 .config
#       写入默认系统设置覆盖目录 files/
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

echo ">>> part2.sh 执行完毕，当前编译设备：${DEVICE}"
