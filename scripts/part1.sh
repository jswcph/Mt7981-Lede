#!/bin/bash
#=================================================
# part1.sh
# ImmortalWrt 源码 + Feeds + Mihomo Meta
#=================================================
set -e

REPO_URL="${REPO_URL:-https://github.com/immortalwrt/immortalwrt}"
REPO_BRANCH="${REPO_BRANCH:-master}"
SRC_DIR="${SRC_DIR:-$(pwd)/openwrt}"

echo "==============================================="
echo "  ImmortalWrt Build Environment"
echo "==============================================="
echo "源码：${REPO_URL}"
echo "分支：${REPO_BRANCH}"

echo "==== [1/4] 安装编译依赖 ===="
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

echo "==== [2/4] 克隆 ImmortalWrt ===="
rm -rf "${SRC_DIR}"
git clone --depth=1 --single-branch --branch "${REPO_BRANCH}" \
  "${REPO_URL}" "${SRC_DIR}"
cd "${SRC_DIR}"

echo "==== [3/4] 配置第三方 Feeds ===="
cat >> feeds.conf.default <<'EOF'
src-git passwall https://github.com/Openwrt-Passwall/openwrt-passwall
src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages
src-git openclash https://github.com/vernesong/OpenClash
src-git luci_theme_argon https://github.com/jerrykuku/luci-theme-argon
src-git istore https://github.com/linkease/istore;main
EOF

# 先清理旧的 feeds 链接，再完整更新并安装所有 feeds。
# 这是 OpenWrt/ImmortalWrt 官方推荐的基础流程；后面的定向安装只用于
# 明确保证第三方包已经落到 package/feeds/，避免只更新不安装。
./scripts/feeds clean
./scripts/feeds update -a
./scripts/feeds install -a

# 第三方组件定向安装
./scripts/feeds install -d y -p luci luci-app-package-manager
./scripts/feeds install -d y -p passwall luci-app-passwall
./scripts/feeds install -d y -p passwall_packages xray-core sing-box
./scripts/feeds install -d y -p openclash luci-app-openclash
./scripts/feeds install -d y -p luci_theme_argon luci-theme-argon luci-app-argon-config

# =================================================
# iStore：完整、可验证的独立安装链
# =================================================
# 官方集成方式是：
#   feeds update istore
#   feeds install -d y -p istore luci-app-store
# 这里额外显式安装 iStore 自己的三个运行时组件，并在 defconfig 前
# 检查源码、Makefile 和依赖声明，避免问题拖到 make defconfig 才发现。
./scripts/feeds update istore
./scripts/feeds install -d y -p istore \
  luci-app-store \
  luci-lib-taskd \
  luci-lib-xterm \
  taskd

ISTORE_DIR="package/feeds/istore"
ISTORE_APP="${ISTORE_DIR}/luci-app-store"
ISTORE_TASKD="${ISTORE_DIR}/luci-lib-taskd"
ISTORE_XTERM="${ISTORE_DIR}/luci-lib-xterm"
ISTORE_TASK="${ISTORE_DIR}/taskd"

for f in \
  "${ISTORE_APP}/Makefile" \
  "${ISTORE_TASKD}/Makefile" \
  "${ISTORE_XTERM}/Makefile" \
  "${ISTORE_TASK}/Makefile"; do
  if [ ! -f "${f}" ]; then
    echo "ERROR: iStore package 未正确安装：${f}"
    exit 1
  fi
done

echo "==== iStore 源码检查 ===="
echo "luci-app-store: ${ISTORE_APP}/Makefile"
grep -E '^(LUCI_DEPENDS|LUCI_EXTRA_DEPENDS|LUCI_PKGARCH):' "${ISTORE_APP}/Makefile" || true
echo "luci-lib-taskd: ${ISTORE_TASKD}/Makefile"
grep -E '^(LUCI_DEPENDS|LUCI_EXTRA_DEPENDS|LUCI_PKGARCH):' "${ISTORE_TASKD}/Makefile" || true
echo "luci-lib-xterm: ${ISTORE_XTERM}/Makefile"
grep -E '^(LUCI_DEPENDS|LUCI_EXTRA_DEPENDS|LUCI_PKGARCH):' "${ISTORE_XTERM}/Makefile" || true
echo "taskd: ${ISTORE_TASK}/Makefile"
grep -E '^(PKG_NAME|PKG_VERSION|PKGARCH|DEPENDS):' "${ISTORE_TASK}/Makefile" || true

if ! grep -q 'LUCI_DEPENDS:.*luci-lib-taskd' "${ISTORE_APP}/Makefile"; then
  echo "ERROR: luci-app-store Makefile 未声明 luci-lib-taskd 依赖"
  exit 1
fi

echo "==== Feeds 检查通过 ===="
echo "Package Manager: package/feeds/luci/luci-app-package-manager"
echo "PassWall: package/feeds/passwall/luci-app-passwall"
echo "OpenClash: package/feeds/openclash/luci-app-openclash"
echo "Argon: package/feeds/luci_theme_argon"
echo "iStore: ${ISTORE_APP}"

echo "==== [4/4] 编译 Mihomo Meta ARM64 ===="
cd "${SRC_DIR}"
rm -rf mihomo
git clone --depth=1 --single-branch --branch Meta \
  https://github.com/MetaCubeX/mihomo.git mihomo
cd "${SRC_DIR}/mihomo"
echo "Mihomo branch: $(git branch --show-current)"
echo "Mihomo commit: $(git rev-parse --short HEAD)"
go mod download
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
  go build \
    -tags with_gvisor \
    -trimpath \
    -ldflags "-s -w" \
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
echo "Mihomo Meta：${SRC_DIR}/files/etc/openclash/core/clash_meta"
go version
