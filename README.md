# CMCC-RAX3000M-NAND

## immortalwrt-dae（含最新版 dae 的固件）

`.github/workflows/immortalwrt-dae.yml`：在 ImmortalWrt master 上编译 RAX3000M(NAND) 固件，
并把软件源自带的 dae 顶到上游最新正式版。

- 触发：Actions → **immortalwrt-dae Builder** → Run workflow
  - `dae_version` 留空或填 `latest`：每次编译自动取上游最新正式版
  - `dae_version` 填 `2.1.1` 之类：钉死该版本，便于复现同一份固件
- 配置基线：`config/passwall2.config`（改 `env.CONFIG_FILE` 可换成其它 config）
- DIY 脚本：`diy-dae.sh` —— 改 dae 版本号/校验值、摘掉 `-Werror`、打开内核 BTF 与 dae 包

### 版本与校验值是自动的

dae 的 OpenWrt 包是 `PKG_VERSION` + `PKG_HASH` **成对**使用的，只改版本号会在
`make download` 阶段因校验失败中断。所以 workflow 第一步
「Resolve dae version and checksum」会：

1. 调 `api.github.com/repos/daeuniverse/dae/releases/latest` 拿 tag（或用手填的版本）；
2. 下载同一 release 里的 `dae-full-src.zip.dgst`，从中提取 `sha256`；
3. 把 `DAE_VERSION` / `DAE_SHA256` 写进 `$GITHUB_ENV`，`diy-dae.sh` 只负责套用。

即升级 dae 不需要改任何文件，跑一次就是最新版；想锁定版本只填版本号，校验值仍自动取。
`diy-dae.sh` 不会给版本/校验值留默认值——留默认值等于偷偷钉死版本，升级时容易以为改了其实没改。

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

### 大版本升级的已知风险

`diy-dae.sh` 只换版本号与校验值，构建配方沿用 feeds 里的包定义。配方依赖上游三样东西：
`go:generate` 里的 bpf2go 参数、`control/kern/tproxy.c` 的目录结构、`example.dae` 能否当默认配置。
2.0.0 → 2.1.1 这三样都没动，所以直接换版本可行（2.1.1 唯一的坑是源码包不再带 `vendor/`，
依赖新版 Go 基建联网拉模块）。遇到 3.x 这类大改，脚本会打 `::warning::` 提示你回来核对，
失败时优先对照上游的 `Makefile`、`CHANGELOGS.md` 的 Upgrade notes，以及 immortalwrt/packages
里 `net/dae` 是否有更新。
