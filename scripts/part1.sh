#!/bin/bash
#=================================================
# part1.sh
# LEDE + PassWall + OpenClash + Mihomo Meta
#=================================================
set -e

REPO_URL="${REPO_URL:-https://github.com/coolsnowwolf/lede}"
REPO_BRANCH="${REPO_BRANCH:-master}"
SRC_DIR="${SRC_DIR:-$(pwd)/openwrt}"

echo "==============================================="
echo "      LEDE Build Environment"
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
# [2/5] 克隆 LEDE仓库
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

echo ">>> LEDE 源码目录:"
echo "${SRC_DIR}"


#=================================================
# 按机型应用 DTS 分区补丁（ubi 扩容）
# 只有 DEVICE 匹配才执行，其他机型直接跳过，互不影响
# 全部按内容检索替换，不依赖 patches/ 目录
#=================================================

echo "==== 设备专属分区补丁检查: ${DEVICE:-未指定} ===="

case "${DEVICE:-}" in

  #---------------- Ruijie RG-X60 Pro: ubi 63M -> 107M ----------------
  ruijie_rg-x60-pro)
    RUIJIE_X60_PRO_DTS="${SRC_DIR}/target/linux/mediatek/dts/mt7986a-ruijie-rg-x60-pro.dts"
    if [ ! -f "${RUIJIE_X60_PRO_DTS}" ]; then
      echo "ERROR: 找不到 ${RUIJIE_X60_PRO_DTS}"
      exit 1
    fi
    echo "==== 补丁：扩大 Ruijie RG-X60 Pro 的 ubi 分区 ===="

    # 按 label 定位 ubi，改大小为 0x6b00000 (107MiB)
    perl -0pi -e 's/(label = "ubi";\s*reg = <0x680000 )0x[0-9a-fA-F]+(>;)/${1}0x6b00000${2}/' "${RUIJIE_X60_PRO_DTS}"

    echo ">>> 补丁后的分区信息："
    grep -n -E 'partition@|label =|reg = <0x' "${RUIJIE_X60_PRO_DTS}"

    grep -q 'reg = <0x680000 0x6b00000>;' "${RUIJIE_X60_PRO_DTS}" \
      || { echo "ERROR: Ruijie ubi 补丁未生效"; exit 1; }
    echo ">>> Ruijie RG-X60 Pro 107M 补丁应用成功"
    ;;

  #---------------- H3C Magic NX30 Pro: ubi 扩容 112M ----------------
  h3c_magic-nx30-pro)
    NX30_DTS="${SRC_DIR}/target/linux/mediatek/dts/mt7981b-h3c-magic-nx30-pro.dts"
    export NX30_UBI_SIZE="0x7000000"   # 112MiB，如需其他大小改这里

    if [ ! -f "${NX30_DTS}" ]; then
      echo "ERROR: 找不到 ${NX30_DTS}"
      exit 1
    fi
    echo "==== 补丁：H3C Magic NX30 Pro ubi 扩容到 ${NX30_UBI_SIZE} ===="

    # 按 label 定位 ubi，改大小
    perl -0pi -e 's/(label = "ubi";\s*reg = <0x0*580000 )0x[0-9a-fA-F]+(>;)/$1$ENV{NX30_UBI_SIZE}$2/' "${NX30_DTS}"

    # 按 label 删除 ubi 后面的 4 个分区（含前面的注释）
    perl -0pi -e 's/(?:[ \t]*\/\*[^*]*\*\/[ \t]*\n)?[ \t]*partition\@[0-9a-fA-F]+ \{\s*label = "(?:pdt_data|pdt_data_1|exp|plugin)";.*?\};\n//gs' "${NX30_DTS}"

    echo ">>> 补丁后的分区信息："
    grep -n -E 'partition@|label =|reg = <0x' "${NX30_DTS}"

    grep -q "reg = <0x0*580000 ${NX30_UBI_SIZE}>;" "${NX30_DTS}" \
      || { echo "ERROR: NX30 Pro ubi 大小未修改成功"; exit 1; }
    if grep -q -E 'label = "(pdt_data|pdt_data_1|exp|plugin)"' "${NX30_DTS}"; then
      echo "ERROR: NX30 Pro 多余分区未删除干净"; exit 1
    fi
    echo ">>> NX30 Pro ubi 扩容完成"
    ;;

  #---------------- Nokia EA0326GMP: ubi 扩容 ----------------
  # 分区表：删除 Aos-net / bvasPlugin，ubi 改为 0x980000 / 0x7680000
  nokia_ea0326gmp)
    NOKIA_DTS="$(find "${SRC_DIR}/target/linux/mediatek" -type f -name '*nokia-ea0326gmp*.dts' 2>/dev/null | head -n1)"
    if [ -z "${NOKIA_DTS}" ] || [ ! -f "${NOKIA_DTS}" ]; then
      echo "ERROR: 找不到 Nokia EA0326GMP 的 DTS"
      exit 1
    fi
    echo "==== 补丁：Nokia EA0326GMP ubi  扩容 ===="
    echo ">>> DTS: ${NOKIA_DTS}"

    # 1) 按 label 删除 Aos-net / bvasPlugin 分区
    perl -0pi -e 's/[ \t]*partition\@[0-9a-fA-F]+ \{\s*label = "(?:Aos-net|bvasPlugin)";.*?\};\n(?:[ \t]*\n)?//gs' "${NOKIA_DTS}"

    # 2) 按 label 改写 ubi：节点名、compatible、reg
    perl -0pi -e 's/partition\@[0-9a-fA-F]+ \{(\s*)(?:compatible = "linux,ubi";\s*)?label = "ubi";(\s*)reg = <[^>]*>;/partition\@980000 {$1compatible = "linux,ubi";$1label = "ubi";$2reg = <0x980000 0x7680000>;/' "${NOKIA_DTS}"

    echo ">>> 补丁后的分区信息："
    grep -n -E 'partition@|label =|compatible = "linux,ubi"|reg = <0x' "${NOKIA_DTS}"

    grep -q 'reg = <0x980000 0x7680000>;' "${NOKIA_DTS}" \
      || { echo "ERROR: Nokia ubi 大小未修改成功"; exit 1; }
    grep -q 'compatible = "linux,ubi";' "${NOKIA_DTS}" \
      || { echo "ERROR: Nokia ubi 缺少 compatible"; exit 1; }
    if grep -q -E 'label = "(Aos-net|bvasPlugin)"' "${NOKIA_DTS}"; then
      echo "ERROR: Aos-net/bvasPlugin 未删除干净"; exit 1
    fi
    [ "$(grep -c 'partition@980000' "${NOKIA_DTS}")" -eq 1 ] \
      || { echo "ERROR: partition@980000 节点数量不是 1"; exit 1; }
    echo ">>> Nokia EA0326GMP ubi 扩容完成"
    ;;

  #---------------- 其他机型：不做任何分区补丁 ----------------
  *)
    echo ">>> ${DEVICE:-未指定} 无分区补丁，跳过"
    ;;
esac
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

echo ">>> 自定义 Feeds:"
echo "    PassWall"
echo "    PassWall Packages"
echo "    OpenClash"
echo "    Argon Theme"

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

cd "${SRC_DIR}"

./scripts/feeds update -a

./scripts/feeds install -a

echo "==== 查找 Argon 源码目录 ===="

find "${SRC_DIR}/package" \
     "${SRC_DIR}/feeds" \
     -maxdepth 5 \
     -type d \
     -iname "*argon*" \
     2>/dev/null || true
#=================================================
# 完成
#=================================================

echo "==============================================="
echo "       part1.sh 执行完毕"
echo "==============================================="

echo ">>> LEDE 源码:"
echo "${SRC_DIR}"

echo ">>> Mihomo 核心:"
echo "${SRC_DIR}/files/etc/openclash/core/clash_meta"

echo ">>> Go:"
go version

echo ">>> part1.sh 完成"
