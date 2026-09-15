#!/bin/bash
#=================================================
# part1.sh - ImmortalWrt Wi-Fi Router
# ImmortalWrt + Feeds + Mihomo Meta
# iStore 已彻底移除
#=================================================
set -e

REPO_URL="${REPO_URL:-https://github.com/immortalwrt/immortalwrt}"
REPO_BRANCH="${REPO_BRANCH:-openwrt-24.10}"
SRC_DIR="${SRC_DIR:-$(pwd)/openwrt}"
BASE_DIR="${GITHUB_WORKSPACE:-$(pwd)}"

echo "==============================================="
echo "  ImmortalWrt Build Environment"
echo "==============================================="
echo "源码：${REPO_URL}"
echo "分支：${REPO_BRANCH}"
echo "设备：${DEVICE:-unknown}"

echo "==== [1/5] 安装编译依赖 ===="
sudo -E apt-get -qq update
sudo -E apt-get -qq install -y \
  ack antlr3 aria2 asciidoc autoconf automake autopoint binutils bison \
  build-essential bzip2 ccache cmake cpio curl device-tree-compiler fastjar \
  flex gawk gettext gcc-multilib g++-multilib git gperf haveged help2man \
  intltool libc6-dev-i386 libelf-dev libglib2.0-dev libgmp3-dev libltdl-dev \
  libmpc-dev libmpfr-dev libncurses5-dev libncursesw5-dev libreadline-dev \
  libssl-dev libtool lrzsz mkisofs msmtp ninja-build p7zip p7zip-full patch \
  pkgconf python3 python3-pip libpython3-dev python3-ply python3-docutils \
  qtbase5-dev rsync scons squashfs-tools subversion swig texinfo unzip \
  vim wget xmlto xxd zlib1g-dev

sudo timedatectl set-timezone "Asia/Shanghai" || true

echo "==== 安装 Go ${GO_VERSION:-1.25.1} ===="
GO_VERSION="${GO_VERSION:-1.25.1}"
GO_TARBALL="go${GO_VERSION}.linux-amd64.tar.gz"
rm -f "/tmp/${GO_TARBALL}"
wget -q "https://go.dev/dl/${GO_TARBALL}" -O "/tmp/${GO_TARBALL}"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "/tmp/${GO_TARBALL}"
rm -f "/tmp/${GO_TARBALL}"
export PATH="/usr/local/go/bin:${PATH}"
command -v go
go version
if [ "$(command -v go)" != "/usr/local/go/bin/go" ]; then
  echo "ERROR: 未使用 /usr/local/go/bin/go"
  exit 1
fi

echo "==== [2/5] 克隆 ImmortalWrt ===="
rm -rf "${SRC_DIR}"
git clone --depth=1 --single-branch --branch "${REPO_BRANCH}" \
  "${REPO_URL}" "${SRC_DIR}"
cd "${SRC_DIR}"

# ImmortalWrt 24.10 的 APK 选项默认被标记为 BROKEN，因此 make defconfig
# 会无条件清掉 CONFIG_USE_APK。当前项目明确需要 APK + luci-app-package-manager，
# 所以只解除 USE_APK 这一项的 BROKEN 限制，不修改其它 Kconfig 行为。
python3 - <<'PY'
from pathlib import Path
p = Path("config/Config-build.in")
s = p.read_text()
old = '''\tconfig USE_APK\n\t\timply PACKAGE_apk-mbedtls\n\t\tbool "Use APK instead of OPKG to build distribution (BROKEN)"\n\t\tdepends on BROKEN'''
new = '''\tconfig USE_APK\n\t\timply PACKAGE_apk-mbedtls\n\t\tbool "Use APK instead of OPKG to build distribution"'''
if s.count(old) != 1:
    raise SystemExit(f"ERROR: USE_APK Kconfig 匹配数异常: {s.count(old)}")
p.write_text(s.replace(old, new, 1))
PY
echo "APK Kconfig：已解除 USE_APK 的 BROKEN 限制"

echo "==== [3/5] 调整 UBI 分区布局 ===="
case "${DEVICE:-}" in
  h3c_magic-nx30-pro)
    DTS_FILE="target/linux/mediatek/dts/mt7981b-h3c-magic-nx30-pro.dts"
    python3 - "${DTS_FILE}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
old_reg = "\t\t\t\treg = <0x0580000 0x4000000>;"
new_reg = "\t\t\t\treg = <0x0580000 0x7000000>;"
if text.count(old_reg) != 1:
    raise SystemExit(f"ERROR: NX30 Pro 原始 UBI reg 匹配数异常: {text.count(old_reg)}")
text = text.replace(old_reg, new_reg, 1)
old_partitions = r'''\n\t\t\t/\* yaffs partition \*/\n\t\t\tpartition@4580000 \{\n\t\t\t\tlabel = "pdt_data";\n\t\t\t\treg = <0x4580000 0x0600000>;\n\t\t\t\tread-only;\n\t\t\t\};\n\n\t\t\t/\* yaffs partition \*/\n\t\t\tpartition@4b80000 \{\n\t\t\t\tlabel = "pdt_data_1";\n\t\t\t\treg = <0x4b80000 0x0600000>;\n\t\t\t\tread-only;\n\t\t\t\};\n\n\t\t\tpartition@5180000 \{\n\t\t\t\tlabel = "exp";\n\t\t\t\treg = <0x5180000 0x0100000>;\n\t\t\t\tread-only;\n\t\t\t\};\n\n\t\t\tpartition@5280000 \{\n\t\t\t\tlabel = "plugin";\n\t\t\t\treg = <0x5280000 0x2580000>;\n\t\t\t\tread-only;\n\t\t\t\};'''
text, removed = re.subn(old_partitions, "", text, count=1)
if removed != 1:
    raise SystemExit(f"ERROR: NX30 Pro 旧分区块删除失败，匹配数: {removed}")
if text.count(new_reg) != 1:
    raise SystemExit(f"ERROR: NX30 Pro 新 UBI reg 验证失败: {text.count(new_reg)}")
for label in ("pdt_data", "pdt_data_1", 'label = "exp"', 'label = "plugin"'):
    if label in text:
        raise SystemExit(f"ERROR: NX30 Pro 旧分区仍存在: {label}")
path.write_text(text)
PY
    echo "NX30 Pro UBI: 0x0580000 + 0x7000000"
    ;;
  ruijie_rg-x60)
    DTS_FILE="target/linux/mediatek/dts/mt7986a-ruijie-rg-x60.dtsi"
    python3 - "${DTS_FILE}" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text()
old = "\t\t\t\treg = <0x680000 0x3f00000>;"
new = "\t\t\t\treg = <0x680000 0x6b00000>;"
if text.count(old) != 1:
    raise SystemExit(f"ERROR: X60 原始 UBI reg 匹配数异常: {text.count(old)}")
text = text.replace(old, new, 1)
if text.count(new) != 1:
    raise SystemExit(f"ERROR: X60 新 UBI reg 验证失败: {text.count(new)}")
path.write_text(text)
PY
    echo "X60 UBI: 0x680000 + 0x6b00000"
    ;;
  *)
    echo "ERROR: 不支持的设备：${DEVICE:-未指定}"
    exit 1
    ;;
esac

echo "UBI 分区布局调整成功"
echo "===== UBI 分区验证 ====="
case "${DEVICE:-}" in
  h3c_magic-nx30-pro)
    grep -n 'reg = <0x0580000 0x7000000>;' "${DTS_FILE}"
    ! grep -qE 'label = "(pdt_data|pdt_data_1|exp|plugin)";' "${DTS_FILE}"
    ;;
  ruijie_rg-x60)
    grep -n 'reg = <0x680000 0x6b00000>;' "${DTS_FILE}"
    ;;
esac

echo "==== [4/5] 配置第三方 Feeds ===="
cat >> feeds.conf.default <<'EOF'
src-git passwall https://github.com/Openwrt-Passwall/openwrt-passwall
src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages
src-git openclash https://github.com/vernesong/OpenClash
src-git luci_theme_argon https://github.com/jerrykuku/luci-theme-argon
EOF

./scripts/feeds clean
./scripts/feeds update -a
./scripts/feeds install -a

./scripts/feeds install -d y -p luci luci-app-package-manager
./scripts/feeds install -d y -p passwall luci-app-passwall
./scripts/feeds install -d y -p passwall_packages xray-core sing-box
./scripts/feeds install -d y -p openclash luci-app-openclash
./scripts/feeds install -d y -p luci_theme_argon luci-theme-argon luci-app-argon-config

for pkg in xray-core sing-box; do
  if [ ! -f "package/feeds/passwall_packages/${pkg}/Makefile" ]; then
    if [ ! -f "feeds/passwall_packages/${pkg}/Makefile" ]; then
      echo "ERROR: PassWall packages 源码缺失：feeds/passwall_packages/${pkg}/Makefile"
      exit 1
    fi
    mkdir -p package/feeds/passwall_packages
    ln -sfn "../../../feeds/passwall_packages/${pkg}" "package/feeds/passwall_packages/${pkg}"
  fi
done

if [ ! -f "package/feeds/passwall/luci-app-passwall/Makefile" ]; then
  if [ ! -f "feeds/passwall/luci-app-passwall/Makefile" ]; then
    echo "ERROR: PassWall 源码缺失：feeds/passwall/luci-app-passwall/Makefile"
    exit 1
  fi
  mkdir -p package/feeds/passwall
  ln -sfn ../../../feeds/passwall/luci-app-passwall package/feeds/passwall/luci-app-passwall
fi

if [ ! -f "package/feeds/openclash/luci-app-openclash/Makefile" ]; then
  if [ ! -f "feeds/openclash/luci-app-openclash/Makefile" ]; then
    echo "ERROR: OpenClash 源码缺失：feeds/openclash/luci-app-openclash/Makefile"
    exit 1
  fi
  mkdir -p package/feeds/openclash
  ln -sfn ../../../feeds/openclash/luci-app-openclash package/feeds/openclash/luci-app-openclash
fi

echo "==== Feeds 检查 ===="
for path in \
  "package/feeds/luci/luci-app-package-manager/Makefile" \
  "package/feeds/passwall/luci-app-passwall/Makefile" \
  "package/feeds/passwall_packages/xray-core/Makefile" \
  "package/feeds/passwall_packages/sing-box/Makefile" \
  "package/feeds/openclash/luci-app-openclash/Makefile"; do
  if [ ! -f "$path" ]; then
    echo "ERROR: 缺少 $path"
    exit 1
  fi
done

echo "Package Manager: OK"
echo "PassWall: OK"
echo "Xray: OK"
echo "Sing-box: OK"
echo "OpenClash: OK"
echo "Argon: OK"

echo "==== [5/5] 编译 Mihomo Meta ARM64 ===="
rm -rf mihomo
git clone --depth=1 --single-branch --branch Meta \
  https://github.com/MetaCubeX/mihomo.git mihomo
cd "${SRC_DIR}/mihomo"
echo "Mihomo branch: $(git branch --show-current)"
echo "Mihomo commit: $(git rev-parse --short HEAD)"
go mod download
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
  go build -tags with_gvisor -trimpath -ldflags "-s -w" \
  -o "${SRC_DIR}/clash_meta"

if [ ! -f "${SRC_DIR}/clash_meta" ]; then
  echo "ERROR: Mihomo Meta 编译失败"
  exit 1
fi
if ! file "${SRC_DIR}/clash_meta" | grep -E "ARM aarch64|ARM64" >/dev/null 2>&1; then
  echo "ERROR: clash_meta 不是 ARM64/aarch64 ELF"
  file "${SRC_DIR}/clash_meta"
  exit 1
fi

mkdir -p "${SRC_DIR}/files/etc/openclash/core"
cp "${SRC_DIR}/clash_meta" "${SRC_DIR}/files/etc/openclash/core/clash_meta"
chmod 0755 "${SRC_DIR}/files/etc/openclash/core/clash_meta"

echo "==============================================="
echo "  part1.sh 完成"
echo "==============================================="
echo "ImmortalWrt：${SRC_DIR}"
echo "设备：${DEVICE:-unknown}"
echo "源码分支：${REPO_BRANCH}"
echo "UBI 分区：已直接修改上游 DTS/DTSI"
echo "Mihomo Meta：${SRC_DIR}/files/etc/openclash/core/clash_meta"
go version
