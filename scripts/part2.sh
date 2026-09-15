#!/bin/bash
#=================================================
# part2.sh
# 功能：合并 通用配置 + 设备配置生成最终 .config
#       写入 files/
#       执行 defconfig 解析依赖
#=================================================
set -e

SRC_DIR="${SRC_DIR:-$(pwd)/openwrt}"
BASE_DIR="$GITHUB_WORKSPACE"
[ -z "$BASE_DIR" ] && BASE_DIR="$(pwd)"

if [ -z "${DEVICE}" ]; then
  echo "错误：未指定 DEVICE 环境变量"
  exit 1
fi

DEVICE_CONFIG="${BASE_DIR}/config/devices/${DEVICE}.config"
if [ ! -f "${DEVICE_CONFIG}" ]; then
  echo "错误：找不到设备配置文件 ${DEVICE_CONFIG}"
  exit 1
fi

echo "==== [1/3] 写入通用配置 + 设备配置：${DEVICE} ===="
cat "${BASE_DIR}/config/base.config" "${DEVICE_CONFIG}" > "${SRC_DIR}/.config"

echo "==== [2/3] 写入 files/ ===="
rm -rf "${SRC_DIR}/files"
mkdir -p "${SRC_DIR}/files"
cp -r "${BASE_DIR}/files/." "${SRC_DIR}/files/"
find "${SRC_DIR}/files/etc/uci-defaults" -type f -exec chmod +x {} \; 2>/dev/null || true

# Mihomo Meta 是预编译 ARM64 核心，不通过 OpenClash feed 编译。
mkdir -p "${SRC_DIR}/files/etc/openclash/core"
if [ -f "${SRC_DIR}/clash_meta" ]; then
  cp "${SRC_DIR}/clash_meta" "${SRC_DIR}/files/etc/openclash/core/clash_meta"
  chmod 0755 "${SRC_DIR}/files/etc/openclash/core/clash_meta"
else
  echo "警告：未找到预编译的 clash_meta"
fi

echo "==== [3/3] 执行 make defconfig 并检查最终选择 ===="
cd "${SRC_DIR}"
make defconfig

# 目标固件只允许 PassWall 的 Xray + SingBox。
# Shadowsocks-Rust 会触发 Rust/Cargo 工具链，明确禁止进入最终配置。
if grep -E '^CONFIG_(PACKAGE_.*shadowsocks.*rust|PACKAGE_.*rust|.*PASSWALL.*Shadowsocks_Rust).*=[ym]' .config >/tmp/rust-selected.txt 2>/dev/null; then
  echo "ERROR: 检测到 Rust / Shadowsocks-Rust 被最终 Kconfig 选中："
  cat /tmp/rust-selected.txt
  exit 1
fi

for required in \
  CONFIG_PACKAGE_luci-app-passwall=y \
  CONFIG_PACKAGE_xray-core=y \
  CONFIG_PACKAGE_sing-box=y \
  CONFIG_PACKAGE_luci-app-openclash=y \
  CONFIG_PACKAGE_luci-app-store=y; do
  grep -qx "$required" .config || {
    echo "ERROR: 缺少必须的配置：$required"
    exit 1
  }
done

if [ ! -x "files/etc/openclash/core/clash_meta" ]; then
  echo "ERROR: files/etc/openclash/core/clash_meta 不存在或不可执行"
  exit 1
fi

echo ">>> PassWall：Xray + SingBox"
echo ">>> OpenClash：Mihomo Meta（预编译 ARM64）"
echo ">>> iStore：luci-app-store"
echo ">>> 未检测到 Rust / Shadowsocks-Rust"
echo ">>> part2.sh 执行完毕，当前编译设备：${DEVICE}"
