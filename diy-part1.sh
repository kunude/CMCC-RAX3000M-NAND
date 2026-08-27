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

# Uncomment a feed source
#sed -i 's/^#\(.*helloworld\)/\1/' feeds.conf.default

# Add a feed source
#echo 'src-git helloworld https://github.com/fw876/helloworld' >>feeds.conf.default
#echo 'src-git passwall https://github.com/xiaorouji/openwrt-passwall' >>feeds.conf.default

echo 'https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-25.12/aarch64_cortex-a53/passwall_luci/packages.adb' >>./package/system/opkg/files/customfeeds.conf
echo 'https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-25.12/aarch64_cortex-a53/passwall_packages/packages.adb' >>./package/system/opkg/files/customfeeds.conf
