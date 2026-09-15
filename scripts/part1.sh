#!/bin/bash
#=================================================
# part1.sh
# ImmortalWrt 源码 + Feeds + iStore 离线 APK + Mihomo Meta
#=================================================
set -e

REPO_URL="${REPO_URL:-https://github.com/immortalwrt/immortalwrt}"
REPO_BRANCH="${REPO_BRANCH:-master}"
SRC_DIR="${SRC_DIR:-$(pwd)/openwrt}"

ISTORE_RUN_URL="https://github.com/wkccd/CloudRunFilesBuilder/releases/download/2026-06-18/25-luci-app-store-0.2.0-r3_all.run"
ISTORE_RUN="${SRC_DIR}/../25-luci-app-store-0.2.0-r3_all.run"
ISTORE_DIR="${SRC_DIR}/../istore-offline"
ISTORE_PACKAGE_DIR="${SRC_DIR}/package/istore-offline"


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
EOF

./scripts/feeds clean
./scripts/feeds update -a
./scripts/feeds install -a

# 第三方组件定向安装
./scripts/feeds install -d y -p luci luci-app-package-manager
./scripts/feeds install -d y -p passwall luci-app-passwall
./scripts/feeds install -d y -p passwall_packages xray-core sing-box
./scripts/feeds install -d y -p openclash luci-app-openclash
./scripts/feeds install -d y -p luci_theme_argon luci-theme-argon luci-app-argon-config

echo "==== Feeds 检查通过 ===="
echo "Package Manager: package/feeds/luci/luci-app-package-manager"
echo "PassWall: package/feeds/passwall/luci-app-passwall"
echo "OpenClash: package/feeds/openclash/luci-app-openclash"
echo "Argon: package/feeds/luci_theme_argon"

echo "==== 下载并解包 iStore 离线安装包 ===="
rm -rf "${ISTORE_DIR}" "${ISTORE_PACKAGE_DIR}"
mkdir -p "${ISTORE_DIR}" "${ISTORE_PACKAGE_DIR}"
wget -q --show-progress "${ISTORE_RUN_URL}" -O "${ISTORE_RUN}"
chmod 0755 "${ISTORE_RUN}"

# Makeself 只解包，不执行 install25.sh。
if ! "${ISTORE_RUN}" --noexec --target "${ISTORE_DIR}" >/tmp/istore-extract.log 2>&1; then
  echo "ERROR: iStore .run 解包失败"
  cat /tmp/istore-extract.log
  exit 1
fi

for apk in \
  luci-app-store-0.2.0-r3.apk \
  luci-lib-taskd-1.0.25.apk \
  luci-lib-xterm-4.18.0.apk \
  taskd-1.0.3-r2.apk; do
  if [ ! -f "${ISTORE_DIR}/${apk}" ]; then
    echo "ERROR: iStore 离线包缺少 ${apk}"
    find "${ISTORE_DIR}" -maxdepth 2 -type f -print
    exit 1
  fi
done

# APK v3 使用 apk-tools 提取。这里仅提取 payload，不执行目标 OpenWrt 的安装脚本。
command -v docker >/dev/null 2>&1 || { echo "ERROR: 构建机没有 Docker，无法提取 APK v3 包"; exit 1; }

extract_apk() {
  local apk="$1"
  local pkg="$2"
  local out="${ISTORE_PACKAGE_DIR}/${pkg}/root"
  mkdir -p "${out}"
  docker run --rm \
    -v "${ISTORE_DIR}:/input:ro" \
    -v "${out}:/output" \
    alpine:latest \
    apk extract --allow-untrusted --destination /output "/input/${apk}"
  [ -n "$(find "${out}" -mindepth 1 -print -quit)" ] || {
    echo "ERROR: ${pkg} APK 提取后为空"
    exit 1
  }
}

extract_apk luci-app-store-0.2.0-r3.apk luci-app-store
extract_apk luci-lib-taskd-1.0.25.apk luci-lib-taskd
extract_apk luci-lib-xterm-4.18.0.apk luci-lib-xterm
extract_apk taskd-1.0.3-r2.apk taskd

# 每个离线 APK 单独转换为 OpenWrt 本地 package。
# 这样它们会走 ImmortalWrt 正常的 package/install 阶段，首次开机无需联网。
cat > "${ISTORE_PACKAGE_DIR}/luci-app-store/Makefile" <<'EOF'
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/package.mk

PKG_NAME:=luci-app-store
PKG_VERSION:=0.2.0-r3
PKG_RELEASE:=1
PKGARCH:=all

define Package/luci-app-store
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=Applications
  TITLE:=LuCI based iStore
  DEPENDS:=+curl +tar +libuci-lua +mount-utils +luci-lib-taskd +apk +luci-compat
endef

define Package/luci-app-store/install
	$(CP) ./root/* $(1)/
endef

$(eval $(call BuildPackage,luci-app-store))
EOF

cat > "${ISTORE_PACKAGE_DIR}/luci-lib-taskd/Makefile" <<'EOF'
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/package.mk

PKG_NAME:=luci-lib-taskd
PKG_VERSION:=1.0.25
PKG_RELEASE:=1
PKGARCH:=all

define Package/luci-lib-taskd
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=Libraries
  TITLE:=LuCI taskd library
  DEPENDS:=+taskd +luci-lib-xterm +luci-lua-runtime
endef

define Package/luci-lib-taskd/install
	$(CP) ./root/* $(1)/
endef

$(eval $(call BuildPackage,luci-lib-taskd))
EOF

cat > "${ISTORE_PACKAGE_DIR}/luci-lib-xterm/Makefile" <<'EOF'
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/package.mk

PKG_NAME:=luci-lib-xterm
PKG_VERSION:=4.18.0
PKG_RELEASE:=1
PKGARCH:=all

define Package/luci-lib-xterm
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=Libraries
  TITLE:=LuCI xterm library
endef

define Package/luci-lib-xterm/install
	$(CP) ./root/* $(1)/
endef

$(eval $(call BuildPackage,luci-lib-xterm))
EOF

cat > "${ISTORE_PACKAGE_DIR}/taskd/Makefile" <<'EOF'
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/package.mk

PKG_NAME:=taskd
PKG_VERSION:=1.0.3-r2
PKG_RELEASE:=1

define Package/taskd
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=taskd
endef

define Package/taskd/install
	$(CP) ./root/* $(1)/
endef

$(eval $(call BuildPackage,taskd))
EOF

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
echo "iStore 本地包：${ISTORE_PACKAGE_DIR}"
echo "Mihomo Meta：${SRC_DIR}/files/etc/openclash/core/clash_meta"
go version
