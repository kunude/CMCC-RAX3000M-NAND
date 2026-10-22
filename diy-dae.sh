#!/bin/bash
#
# diy-dae.sh —— dae 专用 DIY 脚本（part 2）
# 执行时机：feeds install 之后、make defconfig 之前，当前目录 = openwrt 源码根
#
# 输入（由 workflow 的 "Resolve dae version and checksum" 步骤注入）：
#   DAE_VERSION  例如 2.1.1（不含 v）
#   DAE_SHA256   dae-full-src.zip 的 sha256，必须与该版本严格对应
# 两者刻意不给默认值：写死默认值等于偷偷固定版本，升级时会以为改了其实没改。
#
# 这个脚本做四件事：
#   1) 沿用 diy-part2.sh 的常规定制（默认 IP 改成 192.168.2.1 等）
#   2) 把 feeds/packages/net/dae 从固件源自带的版本顶到 DAE_VERSION
#   3) 打开 dae 必需的 eBPF/BTF 内核选项，并选中 dae / dae-geoip / dae-geosite
#   4) 选中 LuCI 面板 luci-app-dae 与简体中文语言包
#
# 关于第 4 项：luci-app-dae 在 feeds（immortalwrt/luci → applications/luci-app-dae）
# 里是存在的，只是**默认不选**。它不选的话，dae 只能靠 SSH 改 /etc/config/dae，
# 网页上什么都看不到。它的 LUCI_DEPENDS 是 `+dae +dae-geoip +dae-geosite`，
# 所以只要 dae 那几个包能选中，它本身不会被依赖卡住；但它自己不在 .config 里，
# defconfig 也不会替你加上，必须显式写。
#
# 为什么必须自己开 BTF：
#   dae 用 eBPF + CO-RE，运行时必须有 /sys/kernel/btf/vmlinux。
#   ImmortalWrt 的 config/Config-kernel.in 里 KERNEL_DEBUG_INFO_BTF 的默认值是
#   「filogic 等目标 && BUILDBOT = y」，而 GitHub Actions 里 BUILDBOT=n，
#   静默走默认 = 关。不显式打开，编出来的固件能启动、dae 能装，
#   但 eBPF 加载会失败，而且日志里看不出是内核少东西。
#
#   另外 KERNEL_DEBUG_INFO_REDUCED 在非 BUILDBOT 时默认 y，
#   而 BTF 依赖 !KERNEL_DEBUG_INFO_REDUCED —— 所以这一项也必须显式关掉，
#   否则 BTF 会被依赖关系直接 disable。
#
set -e

DAE_VER="${DAE_VERSION:-}"
DAE_HASH="${DAE_SHA256:-}"
DAE_MK="feeds/packages/net/dae/Makefile"
WS="${GITHUB_WORKSPACE:-$(pwd)}"

if [ -z "${DAE_VER}" ] || [ "${DAE_VER}" = "latest" ]; then
    echo "::error::DAE_VERSION 未解析（当前值 '${DAE_VER}'）。应由 workflow 的 Resolve dae version 步骤注入；本地手动执行请显式传入 DAE_VERSION=x.y.z DAE_SHA256=<64 位 sha256>"
    exit 1
fi
if [ "${#DAE_HASH}" -ne 64 ]; then
    echo "::error::DAE_SHA256 不是合法的 sha256（长度 ${#DAE_HASH}），拒绝在不校验的情况下打包"
    exit 1
fi

echo "=== [diy-dae] 目标 dae 版本: ${DAE_VER} ==="
echo "=== [diy-dae] 源码 sha256: ${DAE_HASH} ==="

case "${DAE_VER}" in
    2.1.*) ;;
    *)
        echo "::warning::dae ${DAE_VER} 尚未在此配方上验证过。本 Makefile 依赖上游的 go:generate/bpf2go 接口与 example.dae 布局，大版本升级（例如 3.x 改了 eBPF 构建方式）可能需要同步调整 feeds 里的包定义，届时请对照上游 Makefile / CHANGELOGS.md。"
        ;;
esac

# ---------------------------------------------------------------- 1) 常规定制
if [ -f "${WS}/diy-part2.sh" ]; then
    echo "--- 执行 diy-part2.sh ---"
    bash "${WS}/diy-part2.sh"
else
    echo "::warning::未找到 ${WS}/diy-part2.sh，跳过常规定制"
fi

# ---------------------------------------------------------------- 2) dae 版本
if [ ! -f "${DAE_MK}" ]; then
    echo "::error::找不到 ${DAE_MK}（feeds 里没有 dae 包），无法升级 dae"
    exit 1
fi

OLD_VER="$(sed -n 's/^PKG_VERSION:=//p' "${DAE_MK}")"
echo "--- feeds 自带 dae: ${OLD_VER:-未知} -> ${DAE_VER} ---"

sed -i -E \
    -e "s|^PKG_VERSION:=.*|PKG_VERSION:=${DAE_VER}|" \
    -e "s|^PKG_HASH:=.*|PKG_HASH:=${DAE_HASH}|" \
    -e "s|^PKG_RELEASE:=.*|PKG_RELEASE:=1|" \
    "${DAE_MK}"

# dae 2.1.1 的 eBPF 侧代码量翻了几倍（datapath 全量重写），配合工具链自带
# 的新版 clang，原本无害的告警在 -Wall -Werror 下会直接变成编译错误。
# 这里只摘掉 -Werror，保留 -Wall；真正的 error 依然会让构建失败。
sed -i 's/-Wall -Werror/-Wall/' "${DAE_MK}"

if ! grep -q "^PKG_VERSION:=${DAE_VER}$" "${DAE_MK}"; then
    echo "::error::dae 版本改写失败，请检查 Makefile 格式是否与 sed 规则匹配"
    exit 1
fi
sed -n '/^PKG_VERSION:=/p;/^PKG_HASH:=/p' "${DAE_MK}"

# ------------------------------------------------- 3) 内核 BTF + 包选择注入
#
# 为什么还要显式写 KERNEL_XDP_SOCKETS 和那几个 kmod——这是踩过的坑：
#
#   dae 的 DEPENDS 是
#     $(GO_ARCH_DEPENDS) $(BPF_DEPENDS) +ca-bundle +kmod-sched-core \
#     +kmod-sched-bpf +kmod-xdp-sockets-diag +kmod-veth
#   其中 kmod-xdp-sockets-diag 自己在 netsupport.mk 里写着
#     DEPENDS:=@KERNEL_XDP_SOCKETS
#
#   scripts/package-metadata.pl 的 mconf_depends() 对每个 `+dep` 会把该包的
#   `depends on` 重新发到本包上（源码注释：Menuconfig will not treat
#   'select FOO' as a real dependency，所以把 FOO 的 depends 也搬过来）。
#   于是 PACKAGE_dae 实际带上了 `depends on KERNEL_XDP_SOCKETS`。
#
#   而 config/passwall2.config 里是 `# CONFIG_KERNEL_XDP_SOCKETS is not set`
#   （passwall 不需要 BTF，当年这么写没问题）。kconfig 的规则是：
#   符号不可见时，.config 里的用户值被忽略；于是 PACKAGE_dae 整块隐形，
#   `CONFIG_PACKAGE_dae=y` 被 defconfig 静默丢弃，而且不给任何报错。
#   现象就是：BTF 那些符号全 OK，只有 dae / dae-geoip / dae-geosite 消失。
#
#   KERNEL_XDP_SOCKETS 默认值是 `default y if KERNEL_DEBUG_INFO_BTF`，
#   本来开了 BTF 就该是 y，只是被 config 里那行显式的 not set 压住了。
#   这里显式写 y，同时把 4 个 kmod 依赖也钉上，不再依赖 select 传递。
cat >> .config <<EOF

# ===== 以下由 diy-dae.sh 注入（dae ${DAE_VER} 需要 eBPF CO-RE / BTF）=====
CONFIG_KERNEL_DEBUG_INFO=y
# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set
CONFIG_KERNEL_DEBUG_INFO_BTF=y
CONFIG_KERNEL_BPF_EVENTS=y
CONFIG_DWARVES=y
# dae 的 kmod-xdp-sockets-diag 依赖它；不显式打开会让 PACKAGE_dae 直接隐形
CONFIG_KERNEL_XDP_SOCKETS=y
CONFIG_PACKAGE_dae=y
CONFIG_PACKAGE_dae-geoip=y
CONFIG_PACKAGE_dae-geosite=y
# dae 的其余运行期依赖，显式钉住，避免依赖 kconfig 的 select 传递
CONFIG_PACKAGE_ca-bundle=y
CONFIG_PACKAGE_kmod-sched-core=y
CONFIG_PACKAGE_kmod-sched-bpf=y
CONFIG_PACKAGE_kmod-xdp-sockets-diag=y
CONFIG_PACKAGE_kmod-veth=y
# LuCI 面板 + 简体中文语言包。feeds 里有 luci-app-dae，但默认不选，
# 不显式写的话网页上没有 dae 入口。
CONFIG_PACKAGE_luci-app-dae=y
CONFIG_PACKAGE_luci-i18n-dae-zh-cn=y
CONFIG_LUCI_LANG_zh_Hans=y
# ===== 注入结束 =====
EOF

echo "--- .config 末尾注入内容 ---"
tail -n 20 .config
echo "=== [diy-dae] 完成 ==="
