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
- H3C Magic NX30 Pro
- 奇虎 360T7
- 小米 AX3000T
- 移动 RAX3000M（NAND 版）

### 内置插件
- Passwall（科学上网）
- OpenClash（科学上网）
- iStore 软件商店
- 终端（ttyd）
- Argon 主题及主题设置面板，已默认启用并汉化

### 默认参数
| 项目 | 值 |
|------|------|
| 主机名 | OpenWrt |
| 默认密码 | password |
| LAN 地址 | 192.168.6.1 |
| WiFi 2.4G 名称 | OpenWrt_2.4G |
| WiFi 5G 名称 | OpenWrt_5G |
| 默认语言 | 简体中文 |
| 默认主题 | Argon |

> 固件每周日 22:00（北京时间）由 GitHub Actions 自动编译发布，仅供个人学习测试使用，请刷机前确认与自己设备型号完全一致。
EOF

echo "RELEASE_NOTES.md 生成完毕"
