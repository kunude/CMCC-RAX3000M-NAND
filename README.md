# CMCC-RAX3000M-NAND

## immortalwrt-dae（含最新版 dae 的固件）

`.github/workflows/immortalwrt-dae.yml`：在 ImmortalWrt master 上编译 RAX3000M(NAND) 固件，
代理部分**只装 dae**（把软件源自带的 dae 顶到上游最新正式版），**不含 passwall / passwall2**。

- 触发：Actions → **immortalwrt-dae Builder** → Run workflow
  - `dae_version` 留空或填 `latest`：每次编译自动取上游最新正式版
  - `dae_version` 填 `2.1.1` 之类：钉死该版本，便于复现同一份固件
- 配置基线：`config/dae.config`（改 `env.CONFIG_FILE` 可换成其它 config）
- DIY 脚本：
  - `diy-dae-part1.sh` —— feeds 不做任何定制，不引入 passwall（原 `diy-part1.sh` 会在
    feeds 更新前 `git clone` 三个 Openwrt-Passwall 仓库）
  - `diy-dae.sh` —— 改 dae 版本号/校验值、摘掉 `-Werror`、打开内核 BTF，
    并选中 dae / dae-geoip / dae-geosite 与 **LuCI 面板 `luci-app-dae` + 中文语言包**

### 和 passwall 版的配置差异

`config/dae.config` 由 `config/passwall2.config` 派生，做了 12 处「取消选中」，
另加 2 处「选中」（`luci-app-dae`、`luci-i18n-dae-zh-cn`），其余
（目标设备 `mediatek/filogic` + `DEVICE_cmcc_rax3000m`、内核选项、LuCI 组件、
ddns-go、wireguard 等）完全一致：

| 关掉的符号 | 原因 |
|---|---|
| `luci-app-passwall2`、`luci-i18n-passwall-zh-cn` | 主体，dae 顶替 |
| `luci-app-passwall_Nftables_Transparent_Proxy`、`..._INCLUDE_SingBox`、`..._INCLUDE_Geoview` | passwall v1 的子选项 |
| `sing-box`、`chinadns-ng`、`dns2socks`、`microsocks`、`ipt2socks`、`tcping`、`geoview` | 只为 passwall 服务的组件 |

dae 的 DNS 分流、透明代理、geoip/geosite 都由自身 eBPF + 内置 DNS 完成，不需要上面任何一个。
想保留其中某项（例如仍想用 `sing-box` 手动跑节点），把对应行改回 `=y` 即可。

workflow 里对应加了**反向校验**：`make defconfig` 之后若 `luci-app-passwall*` 又被依赖
顺带拉进来，直接 `::error::` 失败，避免「以为没有 passwall、其实被别的包带进来了」。

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
CONFIG_KERNEL_XDP_SOCKETS=y                     ← 见下节，缺了 dae 会整块消失
CONFIG_PACKAGE_dae=y
CONFIG_PACKAGE_dae-geoip=y
CONFIG_PACKAGE_dae-geosite=y
CONFIG_PACKAGE_ca-bundle=y
CONFIG_PACKAGE_kmod-sched-core=y
CONFIG_PACKAGE_kmod-sched-bpf=y
CONFIG_PACKAGE_kmod-xdp-sockets-diag=y
CONFIG_PACKAGE_kmod-veth=y
CONFIG_PACKAGE_luci-app-dae=y                   ← 网页面板，见下节
CONFIG_PACKAGE_luci-i18n-dae-zh-cn=y
CONFIG_LUCI_LANG_zh_Hans=y
```

workflow 在 `make defconfig` 之后会逐项核对上面这些符号（含 LuCI 面板与中文语言包），
缺一项就以 `::error::` 失败，不会白跑三个小时的编译；编译完成后还会从
`bin/targets/*/*/*.manifest`（镜像内实际安装清单）确认 `dae`、`luci-app-dae`、
`luci-i18n-dae-zh-cn` 真的进了镜像——**包编出来不等于装进固件**。

### LuCI 面板（服务 → dae）

`luci-app-dae` 在 feeds（`immortalwrt/luci` → `applications/luci-app-dae`）里是存在的，
但**默认不选**——不选的话 dae 只能靠 SSH 改 UCI，网页上什么都看不到。它没有 `HIDDEN` 标记，
`LUCI_DEPENDS:=+dae +dae-geoip +dae-geosite`，只要 dae 那几个包能选中，它自己不会被依赖卡住；
但它不在 `.config` 里，`defconfig` 也不会替你补上，必须显式写。

菜单位置 **服务 → dae**，三页：

| 页面 | 作用 |
|---|---|
| Settings | 启用开关、配置文件路径、日志轮转（写 `/etc/config/dae`） |
| Configuration | 直接编辑 `/etc/dae/config.dae`（保存时按 0600 写入） |
| Log | 查看 `/var/log/dae/dae.log` |

面板用到的 UCI 键与 `net/dae` 的 init 脚本完全对得上：`form.NamedSection, 'config', 'dae'`
+ `enabled` / `config_file` / `log_maxbackups` / `log_maxsize`；`hot_reload` 走
`dae reload /var/run/dae.pid`。对照 dae 2.1.1 源码，`--config`、`--logfile`、
`--logfile-maxsize`、`--logfile-maxbackups`、`--disable-timestamp` 与 pid 文件路径
（`/var/run/dae.pid`）全部照旧，所以面板和任意 2.x 版本都兼容。

**首次刷机后的一个坑**：`/etc/dae/config.dae` 不是包提供的文件（包里只装 `example.dae`），
而 UCI 默认 `enabled '0'`。正确顺序是先进 **服务 → dae → 配置**——页面读不到
`config.dae` 时会自动用 `example.dae` 兜底显示——把 `lan_interface` 改成 `br-lan`、
按需加订阅和分组，**保存**之后再回 Settings 打开启用。直接启用而不先保存，
会因为 `validate -c /etc/dae/config.dae` 找不到文件而启动失败。

### 为什么 `.config` 里明明写了 `dae=y`，defconfig 之后却没了

这是实际踩过的坑，链子比较长，记下来免得再查一遍：

1. dae 的 `DEPENDS` 里有 `+kmod-xdp-sockets-diag`；
2. `kmod-xdp-sockets-diag` 在 `package/kernel/linux/modules/netsupport.mk` 里写着
   `DEPENDS:=@KERNEL_XDP_SOCKETS`；
3. `scripts/package-metadata.pl` 的 `mconf_depends()` 会把每个 `+依赖` 的
   `depends on` **重新发到本包上**（源码注释：Menuconfig 不会把 `select FOO`
   当成真实依赖，所以要把 FOO 的 depends 也搬过来）；
4. 于是 `PACKAGE_dae` 实际带了一条 `depends on KERNEL_XDP_SOCKETS`；
5. 而 `config/passwall2.config` 里是 `# CONFIG_KERNEL_XDP_SOCKETS is not set`
   （passwall 不需要 BTF，当年这么写是对的）；kconfig 的规则是**符号不可见时
   忽略 `.config` 里的用户值**；
6. 结果 `PACKAGE_dae` 整块不可见，`CONFIG_PACKAGE_dae=y` 被 `make defconfig`
   **静默丢弃**，一个报错都不给——但 BTF 那几个符号全都正常保留，
   看起来像"只有 dae 有问题"。

`KERNEL_XDP_SOCKETS` 本来就是 `default y if KERNEL_DEBUG_INFO_BTF`，
开了 BTF 就该是 y，只是被 config 里那行显式 `not set` 压住了。
现在 `config/dae.config` 已改成 `=y`，`diy-dae.sh` 里也再写一遍（换 config 文件时也不会丢）。

同症状的排查口诀：**符号在 `tmp/.config-package.in` 里存在、但值不生效 ⇒ 找它的
`depends on` 里有没有哪个 `KERNEL_*` 是 n**。workflow 在 dae 校验失败时会自动
打印这个符号的定义、`.config` 里的实际值，以及 `package/feeds/packages/dae` 是否存在。

### 大版本升级的已知风险

`diy-dae.sh` 只换版本号与校验值，构建配方沿用 feeds 里的包定义。配方依赖上游三样东西：
`go:generate` 里的 bpf2go 参数、`control/kern/tproxy.c` 的目录结构、`example.dae` 能否当默认配置。
2.0.0 → 2.1.1 这三样都没动，所以直接换版本可行（2.1.1 唯一的坑是源码包不再带 `vendor/`，
依赖新版 Go 基建联网拉模块）。遇到 3.x 这类大改，脚本会打 `::warning::` 提示你回来核对，
失败时优先对照上游的 `Makefile`、`CHANGELOGS.md` 的 Upgrade notes，以及 immortalwrt/packages
里 `net/dae` 是否有更新。
