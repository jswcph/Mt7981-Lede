#!/bin/bash
#=================================================
# generate-release-notes.sh
# 功能：生成本次 Release 的说明文档 RELEASE_NOTES.md
#=================================================
set -e

DATE_STR=$(date +'%Y-%m-%d %H:%M')

cat > RELEASE_NOTES.md << EOF
## LEDE-OpenWrt Mt7981b/Mt7986a固件

编译时间：${DATE_STR}（北京时间）

### 支持机型
- 安博通 ASR3000
- H3C Magic NX30 Pro
- 奇虎 360T7
- 小米 AX3000T
- 小米 Wr30u
- 红米 AX6000
- 移动 RAX3000M（NAND 版）
- 移动 RAX3000Me
- 锐捷 X60Pro
- 磊科 N60
- 磊科 N60Pro
- 诺基亚 Nokia_ea0326gmp
- 捷希 Q30Pro

### 内置插件
- Passwall（Xray+Singbox）
- OpenClash（Mihomo内核）
- Argon 主题及主题设置面板，已默认启用并汉化

### 默认参数
| 项目 | 值 |
|------|------|
| 主机名 | OpenWrt |
| 默认密码 | password |
| LAN 地址 | 192.168.6.1 |
| WiFi 2.4G 名称 | OpenWrt_2.4G |
| WiFi 5G 名称 | OpenWrt_5G |
| 默认主题 | Argon |

> 本项目固件由Lede源码构建，仅供个人学习测试使用，请勿滥用商用盈利，本仓库不承担法律责任。
> 固件每周日 22:00（北京时间）由 GitHub Actions 自动编译发布。
EOF

echo "RELEASE_NOTES.md 生成完毕"
