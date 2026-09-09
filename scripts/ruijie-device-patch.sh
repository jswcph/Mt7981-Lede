#!/bin/bash
set -e

SRC_DIR="${SRC_DIR:?SRC_DIR is required}"
BASE_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
DTS_DIR="${SRC_DIR}/target/linux/mediatek/dts"
IMAGE_MK="${SRC_DIR}/target/linux/mediatek/image/filogic.mk"
NETWORK_FILE="${SRC_DIR}/target/linux/mediatek/filogic/base-files/etc/board.d/02_network"

mkdir -p "${DTS_DIR}"

# X60 / X60 Pro: 使用 107M DTS。ImmortalWrt master 已有原生设备定义，
# 这里只把 X60 的 DTS 指向 107M 版本；X60 Pro 直接覆盖同名 DTS。
cp "${BASE_DIR}/target/linux/mediatek/dts/mt7986a-ruijie-rg-x60-107m.dts" \
   "${DTS_DIR}/mt7986a-ruijie-rg-x60-107m.dts"
cp "${BASE_DIR}/target/linux/mediatek/dts/mt7986a-ruijie-rg-x60-pro.dts" \
   "${DTS_DIR}/mt7986a-ruijie-rg-x60-pro.dts"
cp "${BASE_DIR}/target/linux/mediatek/dts/mt7986a-ruijie-ubi-107m.dtsi" \
   "${DTS_DIR}/mt7986a-ruijie-ubi-107m.dtsi"

# X30E / X30E Pro 的 DTS 与 DTSI 依赖来自 RuijieNetworksCommunity。
cp "${BASE_DIR}/target/linux/mediatek/dts/mt7981b-ruijie-rg-x30-base.dtsi" \
   "${DTS_DIR}/mt7981b-ruijie-rg-x30-base.dtsi"
cp "${BASE_DIR}/target/linux/mediatek/dts/mt7981b-ruijie-rg-x30e.dtsi" \
   "${DTS_DIR}/mt7981b-ruijie-rg-x30e.dtsi"
cp "${BASE_DIR}/target/linux/mediatek/dts/mt7981b-ruijie-rg-x30e.dts" \
   "${DTS_DIR}/mt7981b-ruijie-rg-x30e.dts"
cp "${BASE_DIR}/target/linux/mediatek/dts/mt7981b-ruijie-rg-x30e-pro.dtsi" \
   "${DTS_DIR}/mt7981b-ruijie-rg-x30e-pro.dtsi"
cp "${BASE_DIR}/target/linux/mediatek/dts/mt7981b-ruijie-rg-x30e-pro.dts" \
   "${DTS_DIR}/mt7981b-ruijie-rg-x30e-pro.dts"

# X60 107M：使用已有 ruijie_rg-x60 image 定义，只替换 DTS。
python3 - "${IMAGE_MK}" <<'PY'
from pathlib import Path
p = Path(__import__('sys').argv[1])
s = p.read_text()
s2 = s.replace(
    'define Device/ruijie_rg-x60\n',
    'define Device/ruijie_rg-x60\n',
    1
)
# 精确替换该设备定义内部的 DTS，不影响其它设备。
start = s2.find('define Device/ruijie_rg-x60\n')
if start < 0:
    raise SystemExit('ruijie_rg-x60 definition not found')
end = s2.find('endef\nTARGET_DEVICES += ruijie_rg-x60', start)
if end < 0:
    raise SystemExit('ruijie_rg-x60 end not found')
block = s2[start:end]
block = block.replace('DEVICE_DTS := mt7986a-ruijie-rg-x60\n',
                      'DEVICE_DTS := mt7986a-ruijie-rg-x60-107m\n')
s2 = s2[:start] + block + s2[end:]
p.write_text(s2)
PY

# X30E / X30E Pro 的 image 定义。两者都使用 NAND UBI，DTS 中的 ubi 分区为 0x6F80000。
if ! grep -q 'define Device/ruijie_rg-x30e$' "${IMAGE_MK}"; then
cat >> "${IMAGE_MK}" <<'EOF'

define Device/ruijie_rg-x30e
  DEVICE_VENDOR := Ruijie
  DEVICE_MODEL := RG-X30E
  DEVICE_DTS := mt7981b-ruijie-rg-x30e
  DEVICE_DTS_DIR := ../dts
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_IN_UBI := 1
  IMAGE_SIZE := 114688k
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
  KERNEL_IN_UBI := 1
  IMAGE_SIZE := 114688k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += ruijie_rg-x30e-pro
EOF
fi

# X60 107M DTS 使用独立 compatible，因此补充网络初始化匹配。
if ! grep -q 'ruijie,rg-x60-107m' "${NETWORK_FILE}"; then
python3 - "${NETWORK_FILE}" <<'PY'
from pathlib import Path
p=Path(__import__('sys').argv[1])
s=p.read_text()
needle='\truijie,rg-x60|\\\n'
if needle not in s:
    raise SystemExit('rg-x60 network case not found')
s=s.replace(needle, '\truijie,rg-x60|\\\n\truijie,rg-x60-107m|\\\n', 1)
p.write_text(s)
PY
fi

echo '==== Ruijie DTS / image patch 完成 ===='
echo 'X60  : mt7986a-ruijie-rg-x60-107m.dts'
echo 'X60P : mt7986a-ruijie-rg-x60-pro.dts'
echo 'X30E : mt7981b-ruijie-rg-x30e.dts'
echo 'X30EP: mt7981b-ruijie-rg-x30e-pro.dts'
