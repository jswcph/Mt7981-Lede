#!/bin/bash
#=================================================
# check-trim-config.sh
# 可独立删除的配置精简核验模块（只检查，不修改配置）
# 用途：在 make defconfig 后检查 base.config 中部分精简项
#       是否被 Kconfig 依赖解析重新启用。
# 删除本模块时，同时删除 scripts/part2.sh 中对应调用即可。
# 注意：本脚本不强制关闭任何选项，避免破坏设备驱动依赖。
#=================================================
set -e

CONFIG_FILE="${1:-$(pwd)/.config}"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: 找不到配置文件：$CONFIG_FILE" >&2
  exit 1
fi

# 这些项目来自 config/base.config 现有精简项；只作最终状态报告。
CHECK_ITEMS=(
  CONFIG_F2FS_FS
  CONFIG_BSD_PROCESS_ACCT
  CONFIG_CPU_FREQ_STAT
  CONFIG_THERMAL_HWMON
  CONFIG_PCIEAER
  CONFIG_PCIE_PME
  CONFIG_GPIO_CDEV
  CONFIG_MTD_VIRT_CONCAT
  CONFIG_PAGE_POOL_STATS
  CONFIG_PTP_1588_CLOCK_OPTIONAL
  CONFIG_REALTEK_PHY_HWMON
)

printf '\n==== 精简配置最终状态核验（只读）====\n'
for item in "${CHECK_ITEMS[@]}"; do
  if grep -qE "^${item}=y$|^${item}=m$" "$CONFIG_FILE"; then
    value="$(grep -E "^${item}=(y|m)$" "$CONFIG_FILE" | tail -n1 | cut -d= -f2)"
    printf 'WARN: %-38s enabled (%s) — 可能由设备/依赖配置要求\n' "$item" "$value"
  elif grep -qE "^# ${item} is not set$" "$CONFIG_FILE"; then
    printf 'OK:   %-38s disabled\n' "$item"
  else
    printf 'INFO: %-38s 未显式出现在 .config\n' "$item"
  fi
done
printf '==== 核验完成；本模块没有修改 .config ====\n\n'
