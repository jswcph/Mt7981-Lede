#!/bin/bash
#=================================================
# import-ruijie-x30.sh
# 从锐捷 MT798X 6.6 / OpenWrt 24.10 源码移植 RG-X30E / RG-X30E Pro
# 仅复制这两个机型实际需要的 DTS/DTSI，不改变其他机型
#=================================================
set -e

SRC_DIR="${SRC_DIR:-$(pwd)/openwrt}"

RUIJIE_REPO="https://github.com/RuijieNetworksCommunity/MT798X-6.6-24.10.git"
RUIJIE_BRANCH="openwrt-24.10-6.6"
RUIJIE_TMP="${SRC_DIR}/.ruijie-x30-source"
DTS_DIR="${SRC_DIR}/target/linux/mediatek/dts"
IMAGE_MK="${SRC_DIR}/target/linux/mediatek/image/filogic.mk"

case "${DEVICE:-}" in
  ruijie_rg-x30e|ruijie_rg-x30e-pro)
    ;;
  *)
    echo ">>> 当前设备不是 RG-X30E / RG-X30E Pro，跳过锐捷 X30 DTS 移植"
    exit 0
    ;;
esac

echo "==============================================="
echo "      导入锐捷 RG-X30E / RG-X30E Pro DTS"
echo "==============================================="

echo ">>> 源码仓库: ${RUIJIE_REPO}"
echo ">>> 源码分支: ${RUIJIE_BRANCH}"

rm -rf "${RUIJIE_TMP}"

# 使用 sparse checkout，只取 dts 目录，避免下载整套源码
mkdir -p "${RUIJIE_TMP}"
cd "${RUIJIE_TMP}"
git init -q
git remote add origin "${RUIJIE_REPO}"
git config core.sparseCheckout true
printf '%s\n' 'target/linux/mediatek/dts/' > .git/info/sparse-checkout
git fetch -q --depth=1 origin "${RUIJIE_BRANCH}"
git checkout -q -B "${RUIJIE_BRANCH}" "FETCH_HEAD"

mkdir -p "${DTS_DIR}"

# RG-X30E 共用基础 DTSI + 两个机型各自的 DTS/DTSI
for f in \
  mt7981b-ruijie-rg-x30-base.dtsi \
  mt7981b-ruijie-rg-x30e.dtsi \
  mt7981b-ruijie-rg-x30e.dts \
  mt7981b-ruijie-rg-x30e-pro.dtsi \
  mt7981b-ruijie-rg-x30e-pro.dts
 do
  if [ ! -f "${RUIJIE_TMP}/target/linux/mediatek/dts/${f}" ]; then
    echo "ERROR: 锐捷源码中缺少 ${f}"
    exit 1
  fi
  cp -f "${RUIJIE_TMP}/target/linux/mediatek/dts/${f}" "${DTS_DIR}/${f}"
  echo ">>> 已导入 ${f}"
done

#=================================================
# 将 RG-X30E / RG-X30E Pro 的设备定义加入 LEDE
# 这两项来自锐捷源码的实际 image/filogic.mk 定义：
# NAND，128KiB block，2KiB page，114688KiB image size，kernel in UBI
#=================================================

if ! grep -q 'TARGET_DEVICES += ruijie_rg-x30e$' "${IMAGE_MK}"; then
cat >> "${IMAGE_MK}" <<'EOF'

define Device/ruijie_rg-x30e
  DEVICE_VENDOR := Ruijie
  DEVICE_MODEL := RG-X30E
  DEVICE_DTS := mt7981b-ruijie-rg-x30e
  DEVICE_DTS_DIR := ../dts
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 114688k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += ruijie_rg-x30e

define Device/ruijie_rg-x30e-pro
  DEVICE_VENDOR := Ruijie
  DEVICE_MODEL := RG-X30E Pro
  DEVICE_DTS := mt7981b-ruijie-rg-x30e-pro
  DEVICE_DTS_DIR := ../dts
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 114688k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += ruijie_rg-x30e-pro
EOF
  echo ">>> 已向 filogic.mk 加入 RG-X30E / RG-X30E Pro"
else
  echo ">>> filogic.mk 已存在 RG-X30E 定义，跳过重复添加"
fi

rm -rf "${RUIJIE_TMP}"

echo "==============================================="
echo "      锐捷 RG-X30E DTS 导入完成"
echo "==============================================="
