#!/bin/bash
#=================================================
# part2.sh
# 功能：合并 通用配置 + 设备配置 生成 .config
#       写入默认系统设置覆盖目录 files/
#       对带 USB 口的设备追加 config/usb.config（存储/4G/CPE/USB网卡）
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

# 需要 USB 支持的设备：硬件带 USB 口（源码 filogic.mk 中带 kmod-usb3 的设备）。
# 新增带 USB 的设备时，只需要在这里加设备名。
# USB 相关的包统一维护在 config/usb.config，不要再写进各设备的 .config。
USB_DEVICES="cmcc_rax3000m cmcc_rax3000me netcore_n60-pro"
USB_CONFIG_FILE="${BASE_DIR}/config/usb.config"

ENABLE_USB_FOR_DEVICE=0
for d in ${USB_DEVICES}; do
  if [ "$d" = "${DEVICE}" ]; then
    ENABLE_USB_FOR_DEVICE=1
    break
  fi
done

if [ "${ENABLE_USB_FOR_DEVICE}" = "1" ]; then
  if [ ! -f "${USB_CONFIG_FILE}" ]; then
    echo "错误：找不到 USB 配置文件 ${USB_CONFIG_FILE}"
    exit 1
  fi
  echo "==== ${DEVICE}：追加 USB 存储/4G/CPE/USB网卡配置（config/usb.config）===="
  # 前面补一个空行，避免上一个文件末尾没有换行导致两行粘在一起
  printf '\n' >> "${SRC_DIR}/.config"
  cat "${USB_CONFIG_FILE}" >> "${SRC_DIR}/.config"
else
  echo "==== ${DEVICE}：无 USB 口，不追加 USB 配置 ===="
fi

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

#=================================================
# 校验 1：目标设备必须被 defconfig 精确选中
# 设备名写错时，defconfig 会静默丢弃该项，并回退到列表里的第一个设备
# （abt_asr3000），所以不能只检查“有没有选中设备”，必须检查是不是这一个。
#=================================================
DEVICE_SYMBOL="CONFIG_TARGET_mediatek_filogic_DEVICE_${DEVICE}"
if ! grep -qx "${DEVICE_SYMBOL}=y" .config; then
  echo "ERROR: 目标设备 ${DEVICE} 没有被选中，设备名可能与源码不一致"
  echo "defconfig 实际选中的设备："
  grep "^CONFIG_TARGET_.*_DEVICE_.*=y" .config || echo "  （无）"
  echo "请对照 target/linux/mediatek/image/filogic.mk 里的 TARGET_DEVICES 检查设备名"
  exit 1
fi

echo "==== defconfig 最终选中的设备 ===="
grep "^CONFIG_TARGET_.*_DEVICE_.*=y" .config

#=================================================
# 校验 2：USB 配置必须完整生效（缺任何一个包都直接失败）
# 符号列表直接读取 config/usb.config，不再在脚本里重复维护一份。
#=================================================
if [ "${ENABLE_USB_FOR_DEVICE}" = "1" ]; then
  echo "==== USB 配置解析结果（defconfig 后）===="
  USB_MISSING=0
  while IFS= read -r line; do
    case "${line}" in
      CONFIG_*=y) ;;
      *) continue ;;
    esac
    if grep -qx "${line}" .config; then
      echo "[USB OK]      ${line}"
    else
      echo "[USB MISSING] ${line}"
      USB_MISSING=1
    fi
  done < "${USB_CONFIG_FILE}"

  if [ "${USB_MISSING}" != "0" ]; then
    echo "ERROR: 部分 USB 配置没有生效（包名不存在或依赖不满足），请检查上面的 [USB MISSING]"
    exit 1
  fi
fi

#=================================================
# 可删除模块：精简配置最终状态核验（只读）
# 如不需要核验，删除下面这段调用，并删除 scripts/check-trim-config.sh。
# 本模块不强制关闭选项，避免破坏设备/驱动依赖。
#=================================================
echo "==== 检查内核精简项最终状态（只读）===="
bash "${BASE_DIR}/scripts/check-trim-config.sh" "${SRC_DIR}/.config"

echo ">>> part2.sh 执行完毕，当前编译设备：${DEVICE}"
