#!/bin/bash
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

# Modify hostname
#sed -i 's/OpenWrt/CMCCRax3000M-Router/g' package/base-files/files/bin/config_generate

# 移除 feeds 自带的核心库
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}
git clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages

rm -rf feeds/luci/applications/luci-app-passwall
git clone https://github.com/Openwrt-Passwall/openwrt-passwall package/passwall-luci

# ===== 修复 sing-box 依赖版本 =====
SING_BOX_MK="package/passwall-packages/sing-box/Makefile"
sed -i '/^define Build\/Prepare/,/^endef/d' "$SING_BOX_MK"
cat >> "$SING_BOX_MK" << 'EOF'

define Build/Prepare
	$(Build/Prepare/Default)
	( cd $(PKG_BUILD_DIR) && \
	  go mod edit -replace=github.com/go-json-experiment/json@v0.0.0-20250813024750-ebf49471dced=github.com/go-json-experiment/json@v0.0.0-20250113025959-68c5390da787 && \
	  go mod download github.com/go-json-experiment/json )
endef
EOF
# ============================================================================
