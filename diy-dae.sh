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
# 这个脚本做三件事：
#   1) 沿用 diy-part2.sh 的常规定制（默认 IP 改成 192.168.2.1 等）
#   2) 把 feeds/packages/net/dae 从固件源自带的版本顶到 DAE_VERSION
#   3) 打开 dae 必需的 eBPF/BTF 内核选项，并选中 dae / dae-geoip / dae-geosite
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
cat >> .config <<EOF

# ===== 以下由 diy-dae.sh 注入（dae ${DAE_VER} 需要 eBPF CO-RE / BTF）=====
CONFIG_KERNEL_DEBUG_INFO=y
# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set
CONFIG_KERNEL_DEBUG_INFO_BTF=y
CONFIG_KERNEL_BPF_EVENTS=y
CONFIG_DWARVES=y
CONFIG_PACKAGE_dae=y
CONFIG_PACKAGE_dae-geoip=y
CONFIG_PACKAGE_dae-geosite=y
# ===== 注入结束 =====
EOF

echo "--- .config 末尾注入内容 ---"
tail -n 14 .config
echo "=== [diy-dae] 完成 ==="
