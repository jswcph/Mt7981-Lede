#!/bin/bash
#=================================================
# generate-release-notes.sh
# 功能：生成本次 Release 的说明文档 RELEASE_NOTES.md
#=================================================
set -e

DATE_STR=$(date +'%Y-%m-%d %H:%M')

cat > RELEASE_NOTES.md << EOF
## OpenWrt 固件自动构建

编译时间：${DATE_STR}（北京时间）

### 支持机型
- Nokia XG-040G-MD
- Nokia XG-040G-MD UBI
- Nokia XG-040G-MF
- Nokia XG-040G-MF UBI
- Ruijie RG-X60 Pro 107M UBI

### 内置插件
- Passwall（科学上网）
- OpenClash（科学上网）
- Argon 主题及主题设置面板
- USB 2.0 / USB 3.0
- USB 存储 / UAS
- USB 转 RJ45 网卡驱动
- Samba4 NAS

### 默认参数
| 项目 | 值 |
|------|------|
| 主机名 | OpenWrt |
| 默认密码 | password |
| LAN 地址 | 192.168.6.1 |
| 默认语言 | 简体中文 |
| 默认主题 | Argon |

> Nokia 与 Ruijie 固件请务必确认设备型号、Flash 分区布局和对应 U-Boot 后再刷写。本 Release 中的 Ruijie RG-X60 Pro 版本使用 107M UBI 分区布局。
EOF

echo "RELEASE_NOTES.md 生成完毕"
