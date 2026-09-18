#!/bin/bash
#=================================================
# part1.sh
# ImmortalWrt + RG-X30E / RG-X30E Pro
# PassWall + OpenClash + Mihomo Meta
#=================================================
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/immortalwrt/immortalwrt}"
REPO_BRANCH="${REPO_BRANCH:-master}"
SRC_DIR="${SRC_DIR:-$(pwd)/openwrt}"

printf '%s\n' '==== [1/4] 安装编译依赖 ===='
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
sudo timedatectl set-timezone Asia/Shanghai || true

printf '%s\n' '==== 安装 Go 编译环境 ===='
GO_VERSION="1.25.1"
GO_TARBALL="go${GO_VERSION}.linux-amd64.tar.gz"
wget -q "https://go.dev/dl/${GO_TARBALL}" -O "/tmp/${GO_TARBALL}"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "/tmp/${GO_TARBALL}"
rm -f "/tmp/${GO_TARBALL}"
export PATH="/usr/local/go/bin:${PATH}"
test "$(command -v go)" = /usr/local/go/bin/go
go version

printf '%s\n' "==== [2/4] 克隆源码：${REPO_URL} (${REPO_BRANCH}) ===="
case "${DEVICE:-}" in
  ruijie_rg-x30e|ruijie_rg-x30e-pro) ;;
  *) echo "ERROR: 本分支仅允许 ruijie_rg-x30e 或 ruijie_rg-x30e-pro，收到：${DEVICE:-未指定}"; exit 1 ;;
esac
rm -rf "${SRC_DIR}"
git clone --depth=1 --single-branch --branch "${REPO_BRANCH}" "${REPO_URL}" "${SRC_DIR}"
cd "${SRC_DIR}"

# 上游 RuijieNetworksCommunity 源码已维护 RG-X30E / RG-X30E Pro 的
# filogic.mk 设备定义；这里不再重复追加定义，也不应用 X60/H3C 补丁。
# 自定义 DTS 若确需覆盖，应与上游 DEVICE_DTS 名称和设备树内容逐项核对后再启用。
echo "==== 设备范围确认：${DEVICE}；跳过无关设备补丁和重复 Device 定义 ===="

printf '%s\n' '==== [3/4] 写入自定义 Feeds ===='
for feed in \
  'src-git passwall https://github.com/Openwrt-Passwall/openwrt-passwall' \
  'src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages' \
  'src-git openclash https://github.com/vernesong/OpenClash' \
  'src-git luci_theme_argon https://github.com/jerrykuku/luci-theme-argon'; do
  grep -Fqx "$feed" feeds.conf.default || echo "$feed" >> feeds.conf.default
done

printf '%s\n' '==== [4/4] 准备 Mihomo Meta 核心 ===='
cd "${SRC_DIR}"
rm -rf mihomo
git clone --depth=1 --single-branch --branch Meta https://github.com/MetaCubeX/mihomo.git mihomo
cd "${SRC_DIR}/mihomo"
go mod download
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -tags with_gvisor -trimpath -ldflags '-s -w' -o "${SRC_DIR}/clash_meta"
test -f "${SRC_DIR}/clash_meta"
file "${SRC_DIR}/clash_meta" | grep -E 'ARM aarch64|ARM64' >/dev/null
mkdir -p "${SRC_DIR}/files/etc/openclash/core"
install -m 0755 "${SRC_DIR}/clash_meta" "${SRC_DIR}/files/etc/openclash/core/clash_meta"

cd "${SRC_DIR}"
./scripts/feeds update -a
./scripts/feeds install -a
find "${SRC_DIR}/package" "${SRC_DIR}/feeds" -maxdepth 5 -type d -iname '*argon*' 2>/dev/null || true
echo '==== part1.sh 执行完毕 ===='
