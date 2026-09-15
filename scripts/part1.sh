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

echo "==== [3/5] 应用已验证的 UBI 分区补丁 ===="
PATCH_DIR="${BASE_DIR}/patches"
case "${DEVICE:-}" in
  h3c_magic-nx30-pro)
    PATCH_FILE="${PATCH_DIR}/991-h3c-magic-nx30-pro-112m.patch"
    ;;
  ruijie_rg-x60)
    PATCH_FILE="${PATCH_DIR}/990-ruijie-rg-x60-107m.patch"
    ;;
  *)
    echo "ERROR: 不支持的设备：${DEVICE:-未指定}"
    exit 1
    ;;
esac

[ -f "${PATCH_FILE}" ] || { echo "ERROR: 找不到补丁 ${PATCH_FILE}"; exit 1; }

echo "使用补丁：${PATCH_FILE}"
git apply --check "${PATCH_FILE}"
git apply "${PATCH_FILE}"
echo "UBI 分区补丁应用成功"

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
echo "设备：${DEVICE:-unknown}"
echo "源码分支：${REPO_BRANCH}"
echo "UBI 补丁：${PATCH_FILE}"
echo "Mihomo Meta：${SRC_DIR}/files/etc/openclash/core/clash_meta"
go version
