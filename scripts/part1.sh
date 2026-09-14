#!/bin/bash
#=================================================
# part1.sh
# ImmortalWrt 源码 + Feeds + Mihomo Meta
#
# 原则：
#   1. ImmortalWrt master 使用 APK 包管理体系
#   2. iStore 按官方方式单独处理，只安装 luci-app-store
#   3. Feeds 只注册/安装本项目实际需要的软件包
#   4. 不在这里处理 .config，配置统一交给 part2.sh
#=================================================
set -e

REPO_URL="${REPO_URL:-https://github.com/immortalwrt/immortalwrt}"
REPO_BRANCH="${REPO_BRANCH:-master}"
SRC_DIR="${SRC_DIR:-$(pwd)/openwrt}"

#=================================================
# [1/4] 编译环境
#=================================================
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

#=================================================
# Go：Mihomo Meta 编译使用独立 Go
#=================================================
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

#=================================================
# [2/4] 获取 ImmortalWrt 源码
#=================================================
echo "==== [2/4] 克隆 ImmortalWrt ===="
rm -rf "${SRC_DIR}"
git clone --depth=1 --single-branch --branch "${REPO_BRANCH}" \
  "${REPO_URL}" "${SRC_DIR}"
cd "${SRC_DIR}"

#=================================================
# [3/4] Feeds
#
# iStore 是这里最重要的特殊项：
# 官方集成方式就是注册 istore -> update istore ->
# install luci-app-store，而不是把旧 opkg/iStore 配置混进 .config。
#=================================================
echo "==== [3/4] 配置第三方 Feeds ===="
cat >> feeds.conf.default <<'EOF'
src-git passwall https://github.com/Openwrt-Passwall/openwrt-passwall
src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages
src-git openclash https://github.com/vernesong/OpenClash
src-git luci_theme_argon https://github.com/jerrykuku/luci-theme-argon
src-git istore https://github.com/linkease/istore;main
EOF

# 一次更新全部 feeds，避免重复 update。
./scripts/feeds update -a

# 只安装本项目实际使用的第三方 LuCI / 软件包。
# 不执行 feeds install -a，避免把整套第三方 feed 无差别挂进源码树。
./scripts/feeds install -d y -p passwall luci-app-passwall
./scripts/feeds install -d y -p passwall_packages xray-core sing-box
./scripts/feeds install -d y -p openclash luci-app-openclash
./scripts/feeds install -d y -p luci_theme_argon luci-theme-argon luci-app-argon-config

# iStore：严格按照官方方式安装 luci-app-store。
./scripts/feeds install -d y -p istore luci-app-store

# iStore 必须真正进入 feeds/package 链接树，否则后面的 defconfig 无法识别。
if [ ! -f "package/feeds/istore/luci-app-store/Makefile" ]; then
  echo "ERROR: iStore Feed 已更新，但 luci-app-store Makefile 不存在"
  echo "请检查 istore feed 是否成功安装"
  exit 1
fi

echo "==== Feeds 检查通过 ===="
echo "iStore: package/feeds/istore/luci-app-store/Makefile"
echo "PassWall: package/feeds/passwall/luci-app-passwall"
echo "OpenClash: package/feeds/openclash/luci-app-openclash"
echo "Argon: package/feeds/luci_theme_argon"

#=================================================
# [4/4] 编译 Mihomo Meta ARM64
#=================================================
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

#=================================================
# 完成
#=================================================
echo "==============================================="
echo "  part1.sh 完成"
echo "==============================================="
echo "ImmortalWrt：${SRC_DIR}"
echo "Mihomo Meta：${SRC_DIR}/files/etc/openclash/core/clash_meta"
go version
