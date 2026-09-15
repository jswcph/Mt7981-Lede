#!/bin/bash
#=================================================
# generate-release-notes.sh
# 功能：生成本次 Release 的说明文档 RELEASE_NOTES.md
#=================================================
set -e

DATE_STR=$(date +'%Y-%m-%d %H:%M')

cat > RELEASE_NOTES.md << EOF
## ImmortalWrt Wi-Fi 路由器自动构建

编译时间：${DATE_STR}（北京时间）

### 支持机型
- H3C Magic NX30 Pro
- Ruijie RG-X60

### 内置插件
- Passwall（Xray + Sing-box）
- OpenClash（Mihomo Meta）
- Argon 主题及主题设置面板
- LuCI 简体中文
- APK LuCI 软件包管理器
- Wi-Fi 驱动及无线网络基础组件

### 默认参数
| 项目 | 值 |
|------|------|
| 主机名 | OpenWrt |
| 默认密码 | password |
| LAN 地址 | 192.168.6.1 |
| 默认语言 | 简体中文 |
| 默认主题 | Argon |

> 刷写前请确认设备型号、Flash 分区布局、U-Boot 和对应固件格式。两款机型均为独立的 Wi-Fi 路由器配置。
EOF

echo "RELEASE_NOTES.md 生成完毕"
