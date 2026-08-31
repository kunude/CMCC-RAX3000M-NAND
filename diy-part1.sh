#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# 移除 openwrt feeds 自带的核心库
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}
git clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages

# 移除 openwrt feeds 过时的luci版本
rm -rf feeds/luci/applications/luci-app-passwall
git clone https://github.com/Openwrt-Passwall/openwrt-passwall package/passwall-luci
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall package/openwrt-passwall
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall2 package/openwrt-passwall2

echo 'https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-25.12/aarch64_cortex-a53/passwall_luci/packages.adb' >>./package/system/opkg/files/customfeeds.conf
echo 'https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-25.12/aarch64_cortex-a53/passwall_packages/packages.adb' >>./package/system/opkg/files/customfeeds.conf
