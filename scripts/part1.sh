```bash
#!/bin/bash
#=================================================
# part1.sh (精简版 + Mihomo Meta ARM64)
#=================================================
set -e

REPO_URL="${REPO_URL:-https://github.com/immortalwrt/immortalwrt}"
REPO_BRANCH="${REPO_BRANCH:-master}"
SRC_DIR="${SRC_DIR:-$(pwd)/openwrt}"

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
  golang-go \
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
  upx-ucl \
  unzip \
  vim \
  wget \
  xmlto \
  xxd \
  zlib1g-dev

sudo timedatectl set-timezone "Asia/Shanghai" || true

echo "==== [2/5] 克隆源码: ${REPO_URL} (分支: ${REPO_BRANCH}) ===="
git clone --depth=1 --single-branch --branch "${REPO_BRANCH}" "${REPO_URL}" "${SRC_DIR}"
cd "${SRC_DIR}"

echo "==== [3/5] 安全写入自定义 Feeds ===="
cat >> feeds.conf.default <<EOF
src-git passwall https://github.com/Openwrt-Passwall/openwrt-passwall
src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages
src-git openclash https://github.com/vernesong/OpenClash
src-git luci_theme_argon https://github.com/jerrykuku/luci-theme-argon
src-git luci_app_argon_config https://github.com/jerrykuku/luci-app-argon-config
EOF

#echo "==== [4/5] 添加 iStore 商店（直接放入 package 目录）===="
#rm -rf package/istore
#git clone --depth=1 -b main https://github.com/linkease/istore.git package/istore

echo "==== 准备 Mihomo Meta 核心 ===="

cd "${SRC_DIR}"

rm -rf mihomo

git clone --depth=1 \
    --branch Meta \
    https://github.com/MetaCubeX/mihomo.git \
    mihomo

echo "==== 编译 Mihomo Meta ARM64 核心 ===="

cd "${SRC_DIR}/mihomo"

go mod download

CGO_ENABLED=0 \
GOOS=linux \
GOARCH=arm64 \
go build \
    -tags with_gvisor \
    -trimpath \
    -ldflags "-s -w" \
    -o "${SRC_DIR}/clash_meta"

echo "==== 检查 Mihomo 核心 ===="

file "${SRC_DIR}/clash_meta"

"${SRC_DIR}/clash_meta" -v

echo "==== 安装 Mihomo 到 OpenClash 核心目录 ===="

mkdir -p "${SRC_DIR}/files/etc/openclash/core"

cp "${SRC_DIR}/clash_meta" \
   "${SRC_DIR}/files/etc/openclash/core/clash_meta"

chmod 0755 \
   "${SRC_DIR}/files/etc/openclash/core/clash_meta"

echo "==== Mihomo Meta 核心准备完成 ===="

echo "==== [5/5] 更新并安装所有 Feeds ===="
./scripts/feeds update -a
./scripts/feeds install -a

echo ">>> part1.sh 执行完毕，源码已就绪：${SRC_DIR}"
```
