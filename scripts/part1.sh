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
  ack antlr3 aria2 asciidoc autoconf automake autopoint binutils bison \
  build-essential bzip2 ccache cmake cpio curl device-tree-compiler fastjar \
  flex gawk gettext gcc-multilib g++-multilib git gperf haveged help2man \
  intltool libc6-dev-i386 libelf-dev libglib2.0-dev libgmp3-dev libltdl-dev \
  libmpc-dev libmpfr-dev libncurses5-dev libncursesw5-dev libreadline-dev \
  libssl-dev libtool lrzsz mkisofs msmtp ninja-build p7zip p7zip-full patch \
  pkgconf python3 python3-pip libpython3-dev python3-ply python3-docutils \
  qtbase5-dev rsync scons squashfs-tools subversion swig texinfo unzip vim \
  wget xmlto xxd zlib1g-dev

sudo timedatectl set-timezone "Asia/Shanghai" || true

#=================================================
# 独立 Go 环境
#=================================================

echo "==== 安装 Go 编译环境 ===="

GO_VERSION="1.25.1"
GO_TARBALL="go${GO_VERSION}.linux-amd64.tar.gz"
GO_URL="https://go.dev/dl/${GO_TARBALL}"

rm -f "/tmp/${GO_TARBALL}"
wget -q "${GO_URL}" -O "/tmp/${GO_TARBALL}"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "/tmp/${GO_TARBALL}"
rm -f "/tmp/${GO_TARBALL}"
export PATH="/usr/local/go/bin:${PATH}"

which go
go version
GO_BIN="$(which go)"
if [ "${GO_BIN}" != "/usr/local/go/bin/go" ]; then
    echo "ERROR: 当前使用的不是 /usr/local/go/bin/go"
    echo "当前 Go: ${GO_BIN}"
    exit 1
fi

#=================================================
# [2/5] 克隆 ImmortalWrt
#=================================================

echo "==== [2/5] 克隆源码: ${REPO_URL} ===="
echo "==== 分支: ${REPO_BRANCH} ===="

rm -rf "${SRC_DIR}"
git clone --depth=1 --single-branch --branch "${REPO_BRANCH}" "${REPO_URL}" "${SRC_DIR}"
cd "${SRC_DIR}"

#=================================================
# 锐捷 RG-X60 107MiB UBI 分区补丁
#=================================================
# 上游文件：target/linux/mediatek/dts/mt7986a-ruijie-rg-x60.dtsi
# 只在选择 RG-X60 时应用，避免影响其他机型。
#=================================================

if [ "${DEVICE:-}" = "ruijie_rg-x60" ]; then
    PATCH_FILE="${GITHUB_WORKSPACE}/patches/990-ruijie-rg-x60-107m.patch"

    echo "==== 应用 Ruijie RG-X60 107MiB UBI 分区补丁 ===="

    if [ ! -f "${PATCH_FILE}" ]; then
        echo "ERROR: 找不到补丁文件：${PATCH_FILE}"
        exit 1
    fi

    patch -p1 --forward < "${PATCH_FILE}"

    echo "==== 检查 RG-X60 UBI 分区 ===="
    grep -n -A3 -B1 'partition@680000' \
      "${SRC_DIR}/target/linux/mediatek/dts/mt7986a-ruijie-rg-x60.dtsi"

    grep -q 'reg = <0x680000 0x6b00000>;' \
      "${SRC_DIR}/target/linux/mediatek/dts/mt7986a-ruijie-rg-x60.dtsi"

    echo ">>> RG-X60 107MiB UBI 分区补丁验证通过"
else
    echo "==== 当前设备 ${DEVICE:-未指定}，不应用 RG-X60 分区补丁 ===="
fi

#=================================================
# [3/5] 写入自定义 Feeds
#=================================================

echo "==== [3/5] 安全写入自定义 Feeds ===="

cat >> feeds.conf.default <<EOF
src-git passwall https://github.com/Openwrt-Passwall/openwrt-passwall
src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages
src-git openclash https://github.com/vernesong/OpenClash
src-git luci_theme_argon https://github.com/jerrykuku/luci-theme-argon
EOF

#=================================================
# [4/5] 编译 Mihomo Meta ARM64
#=================================================

echo "==== [4/5] 准备 Mihomo Meta 核心 ===="

cd "${SRC_DIR}"
rm -rf mihomo

git clone --depth=1 --single-branch --branch Meta \
  https://github.com/MetaCubeX/mihomo.git mihomo

cd "${SRC_DIR}/mihomo"
go mod download

CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
go build \
  -tags with_gvisor \
  -trimpath \
  -ldflags "-s -w" \
  -o "${SRC_DIR}/clash_meta"

if [ ! -f "${SRC_DIR}/clash_meta" ]; then
    echo "ERROR: Mihomo 编译失败，找不到 clash_meta"
    exit 1
fi

file "${SRC_DIR}/clash_meta"
if ! file "${SRC_DIR}/clash_meta" | grep -E "ARM aarch64|ARM64" >/dev/null 2>&1; then
    echo "ERROR: clash_meta 不是 ARM64/aarch64 可执行文件"
    exit 1
fi

mkdir -p "${SRC_DIR}/files/etc/openclash/core"
cp "${SRC_DIR}/clash_meta" "${SRC_DIR}/files/etc/openclash/core/clash_meta"
chmod 0755 "${SRC_DIR}/files/etc/openclash/core/clash_meta"

#=================================================
# [5/5] 更新并安装所有 Feeds
#=================================================

echo "==== [5/5] 更新并安装所有 Feeds ===="

cd "${SRC_DIR}"
./scripts/feeds update -a
./scripts/feeds install -a

find "${SRC_DIR}/package" "${SRC_DIR}/feeds" \
     -maxdepth 5 -type d -iname "*argon*" 2>/dev/null || true

echo "==============================================="
echo "       part1.sh 执行完毕"
echo "==============================================="
