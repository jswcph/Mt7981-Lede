# OpenWrt 自动构建

基于 GitHub Actions 自动拉取源码、注入 Passwall / OpenClash / iStore / Argon 主题等插件，
按周编译并发布到 Release。

## 使用方法

1. 手动触发：Actions → Build OpenWrt Firmware → Run workflow，选择设备型号（或 all 编译全部）。
2. 定时触发：每周日 22:00（北京时间）自动编译全部机型并发布到 Release。

## 目录说明

- `scripts/part1.sh`：装依赖、拉源码、写 feeds、装 istore
- `scripts/part2.sh`：拼 `.config`、写默认设置覆盖目录、`make defconfig`
- `config/base.config`：所有设备通用的插件/精简 kmod 配置
- `config/devices/*.config`：每个设备型号的目标定义
- `files/`：会被整体覆盖进固件根文件系统（首次开机脚本在这里）

## 新增设备

1. 在 `config/devices/` 下新建 `你的型号.config`，写好 `CONFIG_TARGET_...DEVICE_xxx=y`
2. 在 `.github/workflows/build-openwrt.yml` 的 `workflow_dispatch.inputs.device.options` 和 `prepare` job 的 all 分支里加上新设备名

## 新增/更换插件

直接改 `config/base.config`，加对应的 `CONFIG_PACKAGE_xxx=y` 行即可，无需改动 workflow。

## 默认参数

| 项目 | 值 |
|---|---|
| 主机名 | OpenWrt |
| 默认密码 | password |
| LAN 地址 | 192.168.6.1 |
| WiFi | OpenWrt_2.4G / OpenWrt_5G |
| 主题 | Argon（已汉化） |
| 语言 | 简体中文 |

## 注意事项

- 源码仓库默认是 `coolsnowwolf/lede`，如果对应机型的 DTS 在该源码里不存在，手动触发时把 `repo_url` 改成 `https://github.com/immortalwrt/immortalwrt` 再试。
- `config/devices/*.config` 里的 `filogic` 是按 mt7981b 常见 subtarget 猜测的，如果编译产物里缺设备，请对照源码里 `target/linux/mediatek/` 下实际路径调整。
- 默认密码是明文写死在开机脚本里的，仅适合自用/内网环境，公网暴露前请务必手动改密码。
