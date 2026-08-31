# Modify default IP
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

# Modify default theme
# sed -i 's/luci-theme-bootstrap/g' feeds/luci/collections/luci/Makefile

# Modify hostname
#sed -i 's/OpenWrt/CMCCRax3000M-Router/g' package/base-files/files/bin/config_generate
