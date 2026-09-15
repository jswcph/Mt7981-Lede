#!/bin/bash
#=================================================
# part2.sh - ImmortalWrt MT798x
# 生成最终 .config、写入 files
# iStore 已彻底移除
#=================================================
set -e

SRC_DIR="${SRC_DIR:-$(pwd)/openwrt}"
BASE_DIR="${GITHUB_WORKSPACE:-$(pwd)}"

[ -n "${DEVICE:-}" ] || { echo "ERROR: 未指定 DEVICE"; exit 1; }
DEVICE_CONFIG="${BASE_DIR}/config/devices/${DEVICE}.config"
[ -f "${DEVICE_CONFIG}" ] || { echo "ERROR: 找不到 ${DEVICE_CONFIG}"; exit 1; }
[ -d "${SRC_DIR}" ] || { echo "ERROR: 源码目录不存在 ${SRC_DIR}"; exit 1; }

cd "${SRC_DIR}"
echo "==== part2: ${DEVICE} ===="

echo "==== [1/4] 合并 base + device 配置 ===="
cat "${BASE_DIR}/config/base.config" "${DEVICE_CONFIG}" > .config

# 明确关闭 iStore/旧 opkg 前端及其辅助组件。
# 注意：luci-app-package-manager 在 ImmortalWrt 24.10 中通过
# PKG_PROVIDES:=luci-app-opkg 提供旧包名，因此不能再把
# CONFIG_PACKAGE_luci-app-opkg 当作独立的“必须关闭”符号检查。
for sym in \
  CONFIG_PACKAGE_luci-app-store \
  CONFIG_PACKAGE_luci-lib-taskd \
  CONFIG_PACKAGE_luci-lib-xterm \
  CONFIG_PACKAGE_taskd; do
  sed -i "/^${sym}=y$/d; /^${sym}=m$/d; /^# ${sym} is not set$/d" .config
  echo "# ${sym} is not set" >> .config
done

cat >> .config <<'EOF'

# ImmortalWrt 24.10 APK package manager
CONFIG_USE_APK=y
CONFIG_PACKAGE_apk-openssl=y
# CONFIG_PACKAGE_apk-mbedtls is not set
# CONFIG_PACKAGE_opkg is not set

# LuCI package manager（APK 前端）
CONFIG_PACKAGE_luci-app-package-manager=y
CONFIG_PACKAGE_luci-i18n-package-manager-zh-cn=y

# LuCI 简体中文
CONFIG_LUCI_LANG_zh_Hans=y
EOF

# =================================================
# [2/4] 准备 files/
# =================================================
echo "==== [2/4] 准备 files/ ===="
rm -rf "${SRC_DIR}/files"
mkdir -p "${SRC_DIR}/files"
cp -a "${BASE_DIR}/files/." "${SRC_DIR}/files/"

if [ -d "${SRC_DIR}/files/etc/uci-defaults" ]; then
  find "${SRC_DIR}/files/etc/uci-defaults" -type f -exec chmod +x {} \;
fi

MIHOMO_SRC="${SRC_DIR}/clash_meta"
MIHOMO_DST="${SRC_DIR}/files/etc/openclash/core/clash_meta"
[ -f "${MIHOMO_SRC}" ] || { echo "ERROR: 找不到 ${MIHOMO_SRC}"; exit 1; }
mkdir -p "$(dirname "${MIHOMO_DST}")"
cp "${MIHOMO_SRC}" "${MIHOMO_DST}"
chmod 0755 "${MIHOMO_DST}"

# =================================================
# [3/4] make defconfig
# =================================================
echo "==== [3/4] make defconfig ===="
make defconfig

# make defconfig 会按 Kconfig 重新整理 .config。
# APK 模式必须在 defconfig 后再次固定，并清掉可能被默认值恢复的旧 opkg/iStore 项。
python3 - <<'PY'
from pathlib import Path

p = Path('.config')
lines = p.read_text().splitlines()

forced = {
    'CONFIG_USE_APK': 'CONFIG_USE_APK=y',
    'CONFIG_PACKAGE_apk-openssl': 'CONFIG_PACKAGE_apk-openssl=y',
    'CONFIG_PACKAGE_apk-mbedtls': '# CONFIG_PACKAGE_apk-mbedtls is not set',
    'CONFIG_PACKAGE_opkg': '# CONFIG_PACKAGE_opkg is not set',
    'CONFIG_PACKAGE_luci-app-package-manager': 'CONFIG_PACKAGE_luci-app-package-manager=y',
    'CONFIG_PACKAGE_luci-i18n-package-manager-zh-cn': 'CONFIG_PACKAGE_luci-i18n-package-manager-zh-cn=y',
    'CONFIG_LUCI_LANG_zh_Hans': 'CONFIG_LUCI_LANG_zh_Hans=y',
    'CONFIG_PACKAGE_luci-app-store': '# CONFIG_PACKAGE_luci-app-store is not set',
    'CONFIG_PACKAGE_luci-lib-taskd': '# CONFIG_PACKAGE_luci-lib-taskd is not set',
    'CONFIG_PACKAGE_luci-lib-xterm': '# CONFIG_PACKAGE_luci-lib-xterm is not set',
    'CONFIG_PACKAGE_taskd': '# CONFIG_PACKAGE_taskd is not set',
}

out = []
seen = set()
for line in lines:
    key = None
    if line.startswith('CONFIG_') and '=' in line:
        key = line.split('=', 1)[0]
    elif line.startswith('# CONFIG_ is not set'):
        key = line[2:].split(' is not set', 1)[0]
    if key in forced:
        if key not in seen:
            out.append(forced[key])
            seen.add(key)
    else:
        out.append(line)

for key, line in forced.items():
    if key not in seen:
        out.append(line)

p.write_text('\n'.join(out) + '\n')
PY

# =================================================
# [4/4] 最终配置验证
# =================================================
echo "==== [4/4] 最终配置检查 ===="
MISSING=0

check_y() {
  if grep -q "^$1=y$" .config; then
    echo "OK: $1=y"
  else
    echo "ERROR: $1 未进入最终 .config"
    MISSING=1
  fi
}

check_disabled() {
  if grep -q "^# $1 is not set$" .config; then
    echo "OK: $1 disabled"
  else
    echo "ERROR: $1 没有被关闭"
    MISSING=1
  fi
}

check_y CONFIG_USE_APK
check_y CONFIG_PACKAGE_apk-openssl
check_y CONFIG_PACKAGE_luci-app-package-manager
check_y CONFIG_PACKAGE_luci-i18n-package-manager-zh-cn
check_y CONFIG_LUCI_LANG_zh_Hans

check_disabled CONFIG_PACKAGE_apk-mbedtls
check_disabled CONFIG_PACKAGE_opkg
check_disabled CONFIG_PACKAGE_luci-app-store
check_disabled CONFIG_PACKAGE_luci-lib-taskd
check_disabled CONFIG_PACKAGE_luci-lib-xterm
check_disabled CONFIG_PACKAGE_taskd

# luci-app-package-manager 的 Makefile 声明 PKG_PROVIDES:=luci-app-opkg，
# 因此不能要求 CONFIG_PACKAGE_luci-app-opkg 同时出现“not set”。
# 这里改为检查旧的 opkg 软件包本体已关闭。
if grep -q '^CONFIG_PACKAGE_luci-app-opkg=' .config; then
  echo "ERROR: CONFIG_PACKAGE_luci-app-opkg 不应被显式选中"
  MISSING=1
else
  echo "OK: CONFIG_PACKAGE_luci-app-opkg 未被显式选中（由 package-manager 提供虚拟包名）"
fi

check_disabled CONFIG_PACKAGE_luci-i18n-opkg-zh-cn

[ "$MISSING" = "1" ] && exit 1

echo "==== ${DEVICE}：关闭无硬件 Wi-Fi 组件 ===="
if [[ "${DEVICE}" == h3c_magic-nx30-pro || "${DEVICE}" == ruijie_rg-x60* ]]; then
  :
fi

echo "==== part2 完成 ===="
echo "DEVICE: ${DEVICE}"
echo "LuCI 软件包管理器：luci-app-package-manager + 中文"
echo "LuCI 中文：CONFIG_LUCI_LANG_zh_Hans=y"
echo "APK: CONFIG_USE_APK=y + apk-openssl"
echo "iStore：已彻底移除"
echo "Mihomo: ${MIHOMO_DST}"
ls -lh "${MIHOMO_DST}"
