#!/bin/bash
#=================================================
# import-ruijie-x30.sh
# 将已验证的锐捷 RG-X30E / RG-X30E Pro DTS 接入 LEDE 编译树
#=================================================
set -e

SRC_DIR="${SRC_DIR:-$(pwd)/openwrt}"
BASE_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
DTS_SRC="${BASE_DIR}/target/linux/mediatek/dts"
DTS_DST="${SRC_DIR}/target/linux/mediatek/dts"
IMAGE_MK="${SRC_DIR}/target/linux/mediatek/image/filogic.mk"

case "${DEVICE:-}" in
  ruijie_rg-x30e|ruijie_rg-x30e-pro)
    ;;
  *)
    echo ">>> 当前设备不是 RG-X30E / RG-X30E Pro，跳过"
    exit 0
    ;;
esac

echo "==============================================="
echo "   导入锐捷 RG-X30E / RG-X30E Pro DTS"
echo "==============================================="

mkdir -p "${DTS_DST}"

for f in \
  mt7981b-ruijie-rg-x30-base.dtsi \
  mt7981b-ruijie-rg-x30e.dtsi \
  mt7981b-ruijie-rg-x30e.dts \
  mt7981b-ruijie-rg-x30e-pro.dtsi \
  mt7981b-ruijie-rg-x30e-pro.dts
 do
  if [ ! -f "${DTS_SRC}/${f}" ]; then
    echo "ERROR: 本仓库缺少 ${DTS_SRC}/${f}"
    exit 1
  fi
  cp -f "${DTS_SRC}/${f}" "${DTS_DST}/${f}"
  echo ">>> 已导入 ${f}"
done

#=================================================
# RG-X30E / RG-X30E Pro 镜像定义
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
  echo ">>> 已加入 filogic.mk 的两个设备定义"
fi

echo "==============================================="
echo "   RG-X30E / RG-X30E Pro 导入完成"
echo "==============================================="
