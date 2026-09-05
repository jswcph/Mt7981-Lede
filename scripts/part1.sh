#!/bin/bash
#=================================================
# part1.sh
# ImmortalWrt + PassWall + OpenClash + Mihomo Meta
#=================================================
set -e

REPO_URL="${REPO_URL:-https://github.com/immortalwrt/immortalwrt}"
REPO_BRANCH="${REPO_BRANCH:-master}"
SRC_DIR="${SRC_DIR:-$(pwd)/openwrt}"

echo "==============================================="
echo "       ImmortalWrt Build Environment"
echo "==============================================="

#=================================================
# [1/5] 安装编译依赖
#=================================================

echo "==== [1/5] 安装编译依赖 ===="

sudo -E apt-get -qq update

sudo -E apt-get -qq install -y \
  ack \
  antlr3 \
  aria2 \
  asciidoc \
  autoconf \
  automake \
  autopoint \
  binutils \
  bison \
  build-essential \
  bzip2 \
  ccache \
  cmake \
  cpio \
  curl \
  device-tree-compiler \
  fastjar \
  flex \
  gawk \
  gettext \
  gcc-multilib \
  g++-multilib \
  git \
  gperf \
  haveged \
  help2man \
  intltool \
  libc6-dev-i386 \
  libelf-dev \
  libglib2.0-dev \
  libgmp3-dev \
  libltdl-dev \
  libmpc-dev \
  libmpfr-dev \
  libncurses5-dev \
  libncursesw5-dev \
  libreadline-dev \
  libssl-dev \
  libtool \
  lrzsz \
  mkisofs \
  msmtp \
  ninja-build \
  p7zip \
  p7zip-full \
  patch \
  pkgconf \
  python3 \
  python3-pip \
  libpython3-dev \
  python3-ply \
  python3-docutils \
  qtbase5-dev \
  rsync \
  scons \
  squashfs-tools \
  subversion \
  swig \
  texinfo \
  unzip \
  vim \
  wget \
  xmlto \
  xxd \
  zlib1g-dev

sudo timedatectl set-timezone "Asia/Shanghai" || true


#=================================================
# 安装独立 Go 环境
# 不使用 Ubuntu 自带的旧版 Go
#=================================================

echo "==== 安装 Go 编译环境 ===="

GO_VERSION="1.25.1"
GO_TARBALL="go${GO_VERSION}.linux-amd64.tar.gz"
GO_URL="https://go.dev/dl/${GO_TARBALL}"

echo ">>> Go 版本: ${GO_VERSION}"

rm -f "/tmp/${GO_TARBALL}"

wget -q \
  "${GO_URL}" \
  -O "/tmp/${GO_TARBALL}"

sudo rm -rf /usr/local/go

sudo tar \
  -C /usr/local \
  -xzf "/tmp/${GO_TARBALL}"

rm -f "/tmp/${GO_TARBALL}"

export PATH="/usr/local/go/bin:${PATH}"

echo "==== 检查 Go 环境 ===="

echo ">>> Go 路径:"
which go

echo ">>> Go 版本:"
go version

GO_BIN="$(which go)"

if [ "${GO_BIN}" != "/usr/local/go/bin/go" ]; then
    echo "ERROR: 当前使用的不是 /usr/local/go/bin/go"
    echo "当前 Go: ${GO_BIN}"
    exit 1
fi

echo ">>> Go 环境检查通过"


#=================================================
# [2/5] 克隆 ImmortalWrt
#=================================================

echo "==== [2/5] 克隆源码: ${REPO_URL} ===="
echo "==== 分支: ${REPO_BRANCH} ===="

rm -rf "${SRC_DIR}"

git clone \
  --depth=1 \
  --single-branch \
  --branch "${REPO_BRANCH}" \
  "${REPO_URL}" \
  "${SRC_DIR}"

cd "${SRC_DIR}"

echo ">>> ImmortalWrt 源码目录:"
echo "${SRC_DIR}"


#=================================================
# [3/5] 写入自定义 Feeds
#=================================================

echo "==== [3/5] 安全写入自定义 Feeds ===="

cat >> feeds.conf.default <<EOF
src-git passwall https://github.com/Openwrt-Passwall/openwrt-passwall
src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages
src-git openclash https://github.com/vernesong/OpenClash
src-git luci_theme_argon https://github.com/jerrykuku/luci-theme-argon
src-git luci_app_argon_config https://github.com/jerrykuku/luci-app-argon-config
EOF

echo ">>> 自定义 Feeds:"
echo "    PassWall"
echo "    PassWall Packages"
echo "    OpenClash"
echo "    Argon Theme"
echo "    Argon Config"


#=================================================
# iStore 已禁用
#=================================================

#echo "==== 添加 iStore 商店 ===="
#rm -rf package/istore
#git clone --depth=1 -b main https://github.com/linkease/istore.git package/istore


#=================================================
# [4/5] 编译 Mihomo Meta ARM64
#=================================================

echo "==== [4/5] 准备 Mihomo Meta 核心 ===="

cd "${SRC_DIR}"

rm -rf mihomo

echo ">>> 克隆 Mihomo Meta 分支"

git clone \
  --depth=1 \
  --single-branch \
  --branch Meta \
  https://github.com/MetaCubeX/mihomo.git \
  mihomo

echo ">>> Mihomo Meta 源码准备完成"

cd "${SRC_DIR}/mihomo"

echo ">>> Mihomo Git 分支:"
git branch --show-current

echo ">>> Mihomo Commit:"
git rev-parse --short HEAD


#=================================================
# Mihomo Go 依赖
#=================================================

echo "==== 下载 Mihomo Go 依赖 ===="

go mod download


#=================================================
# 编译 Mihomo
#
# AX3000T:
#   CPU: MT7981
#   Architecture: ARM64 / AArch64
#
# 输出:
#   ${SRC_DIR}/clash_meta
#=================================================

echo "==== 编译 Mihomo Meta ARM64 核心 ===="

CGO_ENABLED=0 \
GOOS=linux \
GOARCH=arm64 \
go build \
  -tags with_gvisor \
  -trimpath \
  -ldflags "-s -w" \
  -o "${SRC_DIR}/clash_meta"


#=================================================
# 检查编译结果
#=================================================

echo "==== 检查 Mihomo 核心 ===="

if [ ! -f "${SRC_DIR}/clash_meta" ]; then
    echo "ERROR: Mihomo 编译失败，找不到 clash_meta"
    exit 1
fi

echo ">>> 文件信息:"
file "${SRC_DIR}/clash_meta"

echo ">>> 文件大小:"
ls -lh "${SRC_DIR}/clash_meta"

echo ">>> 检查 ARM64 ELF 架构:"

if ! file "${SRC_DIR}/clash_meta" | grep -E "ARM aarch64|ARM64" >/dev/null 2>&1; then
    echo "ERROR: clash_meta 不是 ARM64/aarch64 可执行文件"
    exit 1
fi

echo ">>> Mihomo ARM64 核心编译成功"
echo ">>> 当前 GitHub Runner 是 x86_64"
echo ">>> 不在 Runner 上执行 ARM64 clash_meta"


#=================================================
# 安装到 OpenClash 核心目录
#=================================================

echo "==== 安装 Mihomo 到 OpenClash 核心目录 ===="

mkdir -p \
  "${SRC_DIR}/files/etc/openclash/core"

cp \
  "${SRC_DIR}/clash_meta" \
  "${SRC_DIR}/files/etc/openclash/core/clash_meta"

chmod 0755 \
  "${SRC_DIR}/files/etc/openclash/core/clash_meta"


#=================================================
# 检查 OpenClash Meta 核心
#=================================================

echo "==== 检查 OpenClash Meta 核心 ===="

if [ ! -f "${SRC_DIR}/files/etc/openclash/core/clash_meta" ]; then
    echo "ERROR: OpenClash Meta 核心安装失败"
    exit 1
fi

echo ">>> OpenClash Meta 核心:"
ls -lh \
  "${SRC_DIR}/files/etc/openclash/core/clash_meta"

echo ">>> 核心架构:"
file \
  "${SRC_DIR}/files/etc/openclash/core/clash_meta"

echo "==== Mihomo Meta 核心准备完成 ===="


#=================================================
# [5/5] 更新并安装所有 Feeds
#=================================================

echo "==== [5/5] 更新并安装所有 Feeds ===="

./scripts/feeds update -a

./scripts/feeds install -a


#=================================================
# 完成
#=================================================

echo "==============================================="
echo "       part1.sh 执行完毕"
echo "==============================================="

echo ">>> ImmortalWrt 源码:"
echo "${SRC_DIR}"

echo ">>> Mihomo 核心:"
echo "${SRC_DIR}/files/etc/openclash/core/clash_meta"

echo ">>> Go:"
go version

echo ">>> part1.sh 完成"
