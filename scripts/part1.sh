#!/bin/bash
#=================================================
# part1.sh
# ImmortalWrt + PassWall(Xray/SingBox) + OpenClash(Mihomo) + iStore
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

#=================================================
# 锐捷 RG-X60 / RG-X60 Pro 107MiB UBI 分区补丁：保留
#=================================================
if [ "${DEVICE:-}" = "ruijie_rg-x60" ] || [ "${DEVICE:-}" = "ruijie_rg-x60-pro" ]; then
    PATCH_FILE="${GITHUB_WORKSPACE}/patches/990-ruijie-rg-x60-107m.patch"
    echo "==== 应用 Ruijie RG-X60 / X60 Pro 107MiB UBI 分区补丁 ===="
    [ -f "${PATCH_FILE}" ] || { echo "ERROR: 找不到补丁文件：${PATCH_FILE}"; exit 1; }
    patch -p1 --forward < "${PATCH_FILE}"
    grep -q 'reg = <0x680000 0x6b00000>;' "${SRC_DIR}/target/linux/mediatek/dts/mt7986a-ruijie-rg-x60.dtsi"
    echo ">>> RG-X60 / X60 Pro 107MiB UBI 分区补丁验证通过"
else
    echo "==== 当前设备 ${DEVICE:-未指定}，不应用 RG-X60 分区补丁 ===="
fi

#=================================================
# H3C Magic NX30 Pro 112MiB UBI 分区补丁：保留
#=================================================
if [ "${DEVICE:-}" = "h3c_magic-nx30-pro" ]; then
    PATCH_FILE="${GITHUB_WORKSPACE}/patches/991-h3c-magic-nx30-pro-112m.patch"
    echo "==== 应用 H3C Magic NX30 Pro 112MiB UBI 分区补丁 ===="
    [ -f "${PATCH_FILE}" ] || { echo "ERROR: 找不到补丁文件：${PATCH_FILE}"; exit 1; }
    patch -p1 --forward < "${PATCH_FILE}"
    NX30_DTS="${SRC_DIR}/target/linux/mediatek/dts/mt7981b-h3c-magic-nx30-pro.dts"
    grep -n -A6 -B1 'partition@580000' "${NX30_DTS}"
    grep -q 'reg = <0x0580000 0x7000000>;' "${NX30_DTS}"
    ! grep -q 'label = "pdt_data"' "${NX30_DTS}"
    ! grep -q 'label = "pdt_data_1"' "${NX30_DTS}"
    ! grep -q 'label = "exp"' "${NX30_DTS}"
    ! grep -q 'label = "plugin"' "${NX30_DTS}"
    echo ">>> H3C Magic NX30 Pro 112MiB UBI 分区补丁验证通过"
else
    echo "==== 当前设备 ${DEVICE:-未指定}，不应用 NX30 Pro 112MiB 分区补丁 ===="
fi

echo "==== [3/5] 只安装必要 Feeds ===="
cat >> feeds.conf.default <<'EOF'
src-git passwall https://github.com/Openwrt-Passwall/openwrt-passwall
src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages
src-git openclash https://github.com/vernesong/OpenClash
EOF

./scripts/feeds clean
./scripts/feeds update passwall passwall_packages openclash
./scripts/feeds install -d y -p passwall luci-app-passwall
./scripts/feeds install -d y -p passwall_packages xray-core sing-box
./scripts/feeds install -d y -p openclash luci-app-openclash

echo "==== 不安装无关 Feeds 包：不再执行 feeds install -a ===="

echo "==== [4/5] 准备 iStore 离线包 ===="
rm -rf "${ISTORE_DIR}" "${ISTORE_PACKAGE_DIR}"
mkdir -p "${ISTORE_DIR}" "${ISTORE_PACKAGE_DIR}"
wget -q --show-progress "${ISTORE_RUN_URL}" -O "${ISTORE_RUN}"
chmod 0755 "${ISTORE_RUN}"

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

command -v docker >/dev/null 2>&1 || { echo "ERROR: 构建机没有 Docker，无法提取 iStore APK v3"; exit 1; }

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

echo "==== [5/5] 编译 Mihomo Meta ARM64 ===="
cd "${SRC_DIR}"
rm -rf mihomo
git clone --depth=1 --single-branch --branch Meta \
  https://github.com/MetaCubeX/mihomo.git mihomo
cd "${SRC_DIR}/mihomo"
go mod download
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
  go build -tags with_gvisor -trimpath -ldflags "-s -w" \
  -o "${SRC_DIR}/clash_meta"

[ -f "${SRC_DIR}/clash_meta" ] || { echo "ERROR: Mihomo Meta 编译失败"; exit 1; }
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
echo "PassWall：仅 Xray + SingBox"
echo "OpenClash：Mihomo Meta"
echo "iStore：${ISTORE_PACKAGE_DIR}"
