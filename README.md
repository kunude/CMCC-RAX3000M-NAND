# CMCC-RAX3000M-NAND

## immortalwrt-dae（含最新版 dae 的固件）

`.github/workflows/immortalwrt-dae.yml`：在 ImmortalWrt master 上编译 RAX3000M(NAND) 固件，
并把软件源自带的 dae 2.0.0 顶到上游最新正式版（默认 **2.1.1**）。

- 触发：Actions → **immortalwrt-dae Builder** → Run workflow（`dae_version` 可改）
- 配置基线：`config/passwall2.config`（改 `env.CONFIG_FILE` 可换成其它 config）
- DIY 脚本：`diy-dae.sh` —— 改 dae 版本号/校验值、摘掉 `-Werror`、打开内核 BTF 与 dae 包

启用 dae 的关键是**内核必须带 BTF**（dae 用 eBPF CO-RE，运行时读 `/sys/kernel/btf/vmlinux`）。
ImmortalWrt 的 `KERNEL_DEBUG_INFO_BTF` 只在 `BUILDBOT=y` 时对 filogic 默认开启，
GitHub Actions 里 `BUILDBOT=n`，所以 `diy-dae.sh` 显式写入：

```
CONFIG_KERNEL_DEBUG_INFO=y
# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set   ← BTF 依赖它必须为 n
CONFIG_KERNEL_DEBUG_INFO_BTF=y
CONFIG_KERNEL_BPF_EVENTS=y
CONFIG_DWARVES=y
CONFIG_PACKAGE_dae=y
CONFIG_PACKAGE_dae-geoip=y
CONFIG_PACKAGE_dae-geosite=y
```

workflow 在 `make defconfig` 之后会逐项核对上面这些符号，缺一项就以 `::error::` 失败，
不会白跑三个小时的编译。

> 升级 dae 版本时，`DAE_SHA256` 要一起换，取上游 release 里 `dae-full-src.zip.dgst` 的 sha256。
