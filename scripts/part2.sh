#!/bin/bash
set -e
SRC_DIR="${SRC_DIR:-$(pwd)/openwrt}"
BASE_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
if [ -z "${DEVICE:-}" ]; then echo "错误：未指定 DEVICE"; exit 1; fi
DEVICE_CONFIG="${BASE_DIR}/config/devices/${DEVICE}.config"
[ -f "${DEVICE_CONFIG}" ] || { echo "错误：找不到设备配置 ${DEVICE_CONFIG}"; exit 1; }
echo "==== 写入通用配置 + 设备配置：${DEVICE} ===="
cat "${BASE_DIR}/config/base.config" "${DEVICE_CONFIG}" > "${SRC_DIR}/.config"
USB_DEVICES="cmcc_rax3000m cmcc_rax3000me netcore_n60-pro cudy_tr3000-v1-ubootmod"
USB_CONFIG_FILE="${BASE_DIR}/config/usb.config"
ENABLE_USB_FOR_DEVICE=0
for d in ${USB_DEVICES}; do
  if [ "$d" = "${DEVICE}" ]; then ENABLE_USB_FOR_DEVICE=1; break; fi
done
if [ "${ENABLE_USB_FOR_DEVICE}" = "1" ]; then
  [ -f "${USB_CONFIG_FILE}" ] || { echo "错误：找不到 USB 配置"; exit 1; }
  printf '\n' >> "${SRC_DIR}/.config"
  cat "${USB_CONFIG_FILE}" >> "${SRC_DIR}/.config"
fi
echo "==== 写入默认系统设置覆盖目录 files/ ===="
rm -rf "${SRC_DIR}/files"; mkdir -p "${SRC_DIR}/files"
cp -r "${BASE_DIR}/files/." "${SRC_DIR}/files/"
find "${SRC_DIR}/files/etc/uci-defaults" -type f -exec chmod +x {} \;
if [ "${DEVICE}" = "h3c_magic-nx30-pro-ubootmod" ] || [ "${DEVICE}" = "mobipromo_cm520-79f" ]; then
  echo "==== ${DEVICE}：跳过 Mihomo Meta 核心写入 ===="
else
  if [ -f "${SRC_DIR}/clash_meta" ]; then
    mkdir -p "${SRC_DIR}/files/etc/openclash/core"
    cp "${SRC_DIR}/clash_meta" "${SRC_DIR}/files/etc/openclash/core/clash_meta"
    chmod 0755 "${SRC_DIR}/files/etc/openclash/core/clash_meta"
  fi
fi
cd "${SRC_DIR}"
make defconfig
case "${DEVICE}" in
  h3c_magic-nx30-pro-ubootmod) DEVICE_SYMBOL="CONFIG_TARGET_mediatek_filogic_DEVICE_h3c_magic-nx30-pro" ;;
  mobipromo_cm520-79f) DEVICE_SYMBOL="CONFIG_TARGET_ipq40xx_generic_DEVICE_mobipromo_cm520-79f" ;;
  *) DEVICE_SYMBOL="CONFIG_TARGET_mediatek_filogic_DEVICE_${DEVICE}" ;;
esac
grep -qx "${DEVICE_SYMBOL}=y" .config || {
  echo "ERROR: 目标设备 ${DEVICE} 没有被选中，期望 ${DEVICE_SYMBOL}=y"
  grep "^CONFIG_TARGET_.*DEVICE_.*=y" .config || true
  exit 1
}
echo "==== defconfig 最终选中的设备 ===="
grep "^CONFIG_TARGET_.*DEVICE_.*=y" .config
if [ "${DEVICE}" = "mobipromo_cm520-79f" ]; then
  grep -qx 'CONFIG_PACKAGE_kmod-usb-ledtrig-usbport=y' .config || {
    echo "ERROR: kmod-usb-ledtrig-usbport 未进入最终配置"; exit 1;
  }
fi
if [ "${ENABLE_USB_FOR_DEVICE}" = "1" ]; then
  USB_MISSING=0
  while IFS= read -r line; do
    case "$line" in CONFIG_*=y) ;; *) continue ;; esac
    grep -qx "$line" .config || { echo "[USB MISSING] $line"; USB_MISSING=1; }
  done < "${USB_CONFIG_FILE}"
  [ "$USB_MISSING" = "0" ] || { echo "ERROR: USB 配置未完整生效"; exit 1; }
fi
bash "${BASE_DIR}/scripts/check-trim-config.sh" "${SRC_DIR}/.config"
echo ">>> part2.sh 执行完毕：${DEVICE}"
