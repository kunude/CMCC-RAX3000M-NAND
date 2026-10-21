#!/bin/bash
#
# diy-dae-part1.sh —— dae 专用 part1 脚本
# 执行时机：feeds update 之前，当前目录 = openwrt 源码根
#
# 这里**故意什么都不做**。
#
# 原 diy-part1.sh 干的是 passwall 那套的事：
#   1) rm -rf feeds/packages/net/{xray-core,sing-box,chinadns-ng,...}
#      —— 删掉 feed 自带的客户端，给下面克隆的上游版本让路
#   2) git clone Openwrt-Passwall/openwrt-passwall{,-packages,-licu}
#      —— 把上游 passwall 塞进 package/，绕开 feed 里的旧版本
#
# dae 版固件不需要 passwall，所以这两步都不做：
#   - 不删：feed 里的包留着也不影响，反正 .config 里没选
#   - 不克隆：省掉三次 git clone，feeds 更新/install 快一截，
#     也不会出现 package/ 与 feeds/ 同名包互相覆盖的老问题
#
# 需要换别的代理方案（homeproxy / nikki / openclash 之类）时，
# 请另建独立脚本，不要往这里堆。
set -e

echo "=== [diy-dae-part1] 无 feeds 定制：不引入 passwall / passwall2 ==="
