# 换源码基底 — 应用说明

## 这个包里有什么

1. `build-Ruijie-OpenWrt.yml` → 覆盖你仓库里的 `.github/workflows/build-Ruijie-OpenWrt.yml`
   - REPO_URL 改为 `https://github.com/RuijieNetworksCommunity/MT798X-6.6-24.10`
   - REPO_BRANCH 改为 `openwrt-24.10-6.6`
   - 删除了"注入锐捷 DTS / DTSI 与镜像定义"这一步（新源码原生自带四款设备，不再需要注入）

2. 四个 `.config` 文件 → 覆盖 `config/devices/` 目录下对应同名文件
   - 设备 Kconfig 符号名按新源码实际命名做了修正（X60 系列改成了短横线 `ruijie-rg-x60` / `ruijie-rg-x60-pro`，X30E 系列名字不变）

## 你需要自己做的事（这个包没有覆盖，需要你手动处理）

- **`scripts/ruijie-device-patch.sh`**：workflow 已经不再调用它，可以留着不动，也可以删掉，不影响构建。
- **`config/base.config`**：建议先跑一次构建看看有没有 Kconfig 报警/软件包缺失。新源码是 openwrt-24.10（内核 6.6），跟你之前对着 immortalwrt master（内核 6.12）写的通用配置可能有个别选项对不上，需要用编译日志核对。
- **`scripts/part1.sh` / `part2.sh`**：逻辑本身不用改（它们只是读 REPO_URL/REPO_BRANCH 和拼 `.config`），但如果里面有针对 immortalwrt 特有目录结构写的逻辑（比如提前判断内核版本号之类的），需要留意一下。

## 建议的验证步骤

1. 先手动跑一次单设备（比如 `ruijie_rg-x30e-pro`，因为这台我们已经用真机固件验证过，风险最低）
2. 确认能正常产出 `factory.bin` / `sysupgrade.bin`
3. 再跑其余三个设备
