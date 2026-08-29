#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# Modify default IP
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

# Modify default theme
# sed -i 's/luci-theme-bootstrap/g' feeds/luci/collections/luci/Makefile

# Modify hostname
#sed -i 's/OpenWrt/CMCCRax3000M-Router/g' package/base-files/files/bin/config_generate

# 移除 openwrt feeds 自带的核心库
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}
git clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages

# 移除 openwrt feeds 过时的luci版本
rm -rf feeds/luci/applications/luci-app-passwall
git clone https://github.com/Openwrt-Passwall/openwrt-passwall package/passwall-luci

# ========== 修复 sing-box 编译：锁定 go-json-experiment/json 兼容版本 ==========
SING_BOX_MK="package/passwall-packages/sing-box/Makefile"
if [ -f "$SING_BOX_MK" ]; then
    # 如果 sing-box Makefile 里没有自定义 Build/Prepare，就追加一个
    if ! grep -q "define Build/Prepare" "$SING_BOX_MK"; then
        cat >> "$SING_BOX_MK" << 'EOF'

define Build/Prepare
	$(Build/Prepare/Default)
	( cd $(PKG_BUILD_DIR) && \
	  sed -i 's|github.com/go-json-experiment/json v0.0.0-.*|github.com/go-json-experiment/json v0.0.0-20250113025959-68c5390da787|g' go.mod && \
	  rm -f go.sum && \
	  $(GO) mod tidy )
endef
EOF
    fi
fi
# ============================================================================
