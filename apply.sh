#!/bin/sh
# ============================================================
#  iKuai Q3000 移植注入脚本
#
#  用法:  sh apply.sh <ImmortalWrt 源码树根目录>
#  作用:  把 Q3000 的设备树 / 设备注册 / 板级网络配置注入源码树
#
#  基座:  tfnhui/immortalwrt-mt798x-25.12  @ build-20260923-130
#  说明:  filogic-ext.mk 与 02_network 采用「整文件覆盖」，因此脚本会
#         先校验目标文件的 md5 是否等于已知基座版本；不一致则拒绝覆盖
#         （防止基座换版后误删新设备）。确需强制覆盖时用 FORCE=1。
# ============================================================
set -e

SRC="${1:?用法: sh apply.sh <源码树根目录>}"
HERE="$(cd "$(dirname "$0")" && pwd)"

# 已知基座（build-20260923-130）对应文件的 md5
BASE_MD5_FILOGIC_MK="a8cd251279c68fdec71fed8005514698"
BASE_MD5_02_NETWORK="6c0dd03d4ad822956b914d6e672fb9e4"

echo ">>> 源码树: $SRC"
if [ ! -f "$SRC/rules.mk" ]; then
    echo "!!! 目标目录不是 OpenWrt/ImmortalWrt 源码树（缺少 rules.mk）" >&2
    exit 1
fi

md5_of() { md5sum "$1" 2>/dev/null | awk '{print $1}'; }

check_base() {
    # $1=目标文件  $2=期望 md5  $3=人类可读名
    if [ ! -f "$1" ]; then
        echo "!!! 目标文件不存在: $1" >&2
        exit 1
    fi
    got="$(md5_of "$1")"
    if [ "$got" != "$2" ]; then
        echo "!!! $3 与已知基座版本不一致" >&2
        echo "      期望 md5: $2" >&2
        echo "      实际 md5: $got" >&2
        echo "    基座源码树可能已换版本，整文件覆盖会丢失新设备。" >&2
        echo "    确需强制覆盖：FORCE=1 sh apply.sh $SRC" >&2
        if [ "${FORCE:-0}" != "1" ]; then
            exit 1
        fi
        echo "    [FORCE=1] 继续覆盖……" >&2
    else
        echo "    $3 基座校验通过"
    fi
}

echo ">>> [1/3] 安装设备树 mt7981b-ikuai-q3000.dts"
mkdir -p "$SRC/target/linux/mediatek/dts-ext"
cp "$HERE/target/linux/mediatek/dts-ext/mt7981b-ikuai-q3000.dts" \
   "$SRC/target/linux/mediatek/dts-ext/mt7981b-ikuai-q3000.dts"

echo ">>> [2/3] 覆盖设备注册表 filogic-ext.mk"
check_base "$SRC/target/linux/mediatek/image/filogic-ext.mk" \
           "$BASE_MD5_FILOGIC_MK" "filogic-ext.mk"
cp "$HERE/target/linux/mediatek/image/filogic-ext.mk" \
   "$SRC/target/linux/mediatek/image/filogic-ext.mk"

echo ">>> [3/3] 覆盖板级网络配置 02_network"
check_base "$SRC/target/linux/mediatek/filogic/base-files/etc/board.d/02_network" \
           "$BASE_MD5_02_NETWORK" "02_network"
cp "$HERE/target/linux/mediatek/filogic/base-files/etc/board.d/02_network" \
   "$SRC/target/linux/mediatek/filogic/base-files/etc/board.d/02_network"

echo ">>> 校验注入结果"
printf '    DTS            : %s\n' "$(test -f "$SRC/target/linux/mediatek/dts-ext/mt7981b-ikuai-q3000.dts" && echo OK || echo MISSING)"
printf '    filogic-ext.mk : %s 处 ikuai_q3000\n' "$(grep -c 'Device/ikuai_q3000' "$SRC/target/linux/mediatek/image/filogic-ext.mk" || true)"
printf '    02_network     : %s 处 ikuai,q3000\n' "$(grep -c 'ikuai,q3000' "$SRC/target/linux/mediatek/filogic/base-files/etc/board.d/02_network" || true)"
echo ">>> 注入完成"
