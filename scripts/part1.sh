#!/bin/bash
#=================================================
# part1.sh
# 功能：安装编译依赖、克隆源码、写入自定义插件源(feeds)、更新安装 feeds
#=================================================
set -e

REPO_URL="${REPO_URL:-https://github.com/coolsnowwolf/lede}"
REPO_BRANCH="${REPO_BRANCH:-master}"
SRC_DIR="${SRC_DIR:-$(pwd)/openwrt}"

echo "==== [1/5] 安装编译依赖 ===="
sudo -E apt-get -qq update
sudo -E apt-get -qq install -y ack antlr3 aria2 asciidoc autoconf automake autopoint binutils bison build-essential \
  bzip2 ccache cmake cpio curl device-tree-compiler fastjar flex gawk gettext gcc-multilib g++-multilib \
  git gperf haveged help2man intltool libc6-dev-i386 libelf-dev libglib2.0-dev libgmp3-dev libltdl-dev \
  libmpc-dev libmpfr-dev libncurses5-dev libncursesw5-dev libreadline-dev libssl-dev libtool lrzsz \
  mkisofs msmtp ninja-build p7zip p7zip-full patch pkgconf python3 python3-pip libpython3-dev \
  python3-ply python3-docutils qtbase5-dev rsync scons squashfs-tools subversion swig texinfo \
  upx-ucl unzip vim wget xmlto xxd zlib1g-dev
sudo timedatectl set-timezone "Asia/Shanghai" || true

echo "==== [2/5] 克隆源码: ${REPO_URL} (分支: ${REPO_BRANCH}) ===="
git clone --depth=1 --single-branch --branch "${REPO_BRANCH}" "${REPO_URL}" "${SRC_DIR}"
cd "${SRC_DIR}"

echo "==== [3/5] 写入自定义 Feeds ===="

# ---- Passwall 科学上网（需要主库 + 依赖包库两个仓库）----
sed -i '/passwall/d' feeds.conf.default
echo "src-git passwall https://github.com/Openwrt-Passwall/openwrt-passwall" >> feeds.conf.default
echo "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages" >> feeds.conf.default

# ---- OpenClash 科学上网 ----
sed -i '/openclash/d' feeds.conf.default
echo "src-git openclash https://github.com/vernesong/OpenClash" >> feeds.conf.default

# ---- Argon 主题 + 主题设置面板 ----
sed -i '/luci-theme-argon/d;/luci-app-argon-config/d' feeds.conf.default
echo "src-git luci-theme-argon https://github.com/jerrykuku/luci-theme-argon" >> feeds.conf.default
echo "src-git luci-app-argon-config https://github.com/jerrykuku/luci-app-argon-config" >> feeds.conf.default

echo "==== [4/5] 添加 iStore 商店（直接放入 package 目录）===="
rm -rf package/istore
git clone --depth=1 -b main https://github.com/linkease/istore.git package/istore

echo "==== [5/5] 更新并安装所有 Feeds ===="
./scripts/feeds update -a
./scripts/feeds install -a

echo ">>> part1.sh 执行完毕，源码已就绪：${SRC_DIR}"
