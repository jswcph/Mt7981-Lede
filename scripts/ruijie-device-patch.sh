#!/bin/bash
set -e

SRC_DIR="${SRC_DIR:?SRC_DIR is required}"
BASE_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
DTS_DIR="${SRC_DIR}/target/linux/mediatek/dts"
IMAGE_MK="${SRC_DIR}/target/linux/mediatek/image/filogic.mk"
NETWORK_FILE="${SRC_DIR}/target/linux/mediatek/filogic/base-files/etc/board.d/02_network"

mkdir -p "${DTS_DIR}"

echo "==== 复制 Ruijie DTS 文件 ===="

# ---------- X60 107M（核心）----------
cp "${BASE_DIR}/target/linux/mediatek/dts/mt7986a-ruijie-rg-x60-base.dtsi" \
   "${DTS_DIR}/mt7986a-ruijie-rg-x60-base.dtsi"

cp "${BASE_DIR}/target/linux/mediatek/dts/mt7986a-ruijie-rg-x60-107m.dts" \
   "${DTS_DIR}/mt7986a-ruijie-rg-x60-107m.dts"

# ---------- X60 Pro ----------
cp "${BASE_DIR}/target/linux/mediatek/dts/mt7986a-ruijie-rg-x60-pro.dts" \
   "${DTS_DIR}/mt7986a-ruijie-rg-x60-pro.dts"
cp "${BASE_DIR}/target/linux/mediatek/dts/mt7986a-ruijie-rg-x60-pro.dtsi" \
   "${DTS_DIR}/mt7986a-ruijie-rg-x60-pro.dtsi"

# ---------- X30E / X30E Pro ----------
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

echo "==== 修改 image 定义 (X60 → 使用 107m DTS) ===="
python3 - "${IMAGE_MK}" <<'PY'
from pathlib import Path
p = Path(__import__('sys').argv[1])
s = p.read_text()

start = s.find('define Device/ruijie_rg-x60\n')
if start < 0:
    raise SystemExit('ruijie_rg-x60 definition not found')

end = s.find('endef\nTARGET_DEVICES += ruijie_rg-x60', start)
if end < 0:
    raise SystemExit('ruijie_rg-x60 end not found')

block = s[start:end]
block = block.replace(
    'DEVICE_DTS := mt7986a-ruijie-rg-x60\n',
    'DEVICE_DTS := mt7986a-ruijie-rg-x60-107m\n'
)
s = s[:start] + block + s[end:]
p.write_text(s)
print("DEVICE_DTS 已替换为 mt7986a-ruijie-rg-x60-107m")
PY

echo "==== 添加 X30E / X30E Pro 设备定义 ===="
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
echo "已添加 X30E / X30E Pro 设备定义"
else
  echo "X30E 设备定义已存在，跳过"
fi

echo "==== 补充网络配置匹配 ===="
if ! grep -q 'ruijie,rg-x60-107m' "${NETWORK_FILE}"; then
python3 - "${NETWORK_FILE}" <<'PY'
from pathlib import Path
p = Path(__import__('sys').argv[1])
s = p.read_text()
needle = '\truijie,rg-x60|\\\n'
if needle not in s:
    raise SystemExit('rg-x60 network case not found')
s = s.replace(needle, '\truijie,rg-x60|\\\n\truijie,rg-x60-107m|\\\n', 1)
p.write_text(s)
print("已添加 ruijie,rg-x60-107m 网络匹配")
PY
else
  echo "网络匹配已存在，跳过"
fi

echo "==== Ruijie 设备补丁完成 ===="
echo "X60-107M : mt7986a-ruijie-rg-x60-107m.dts + base.dtsi"
echo "X60-Pro  : mt7986a-ruijie-rg-x60-pro.dts + pro.dtsi"
echo "X30E     : mt7981b-ruijie-rg-x30e.dts"
echo "X30E-Pro : mt7981b-ruijie-rg-x30e-pro.dts"
