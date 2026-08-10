#!/bin/bash
#==============================================================
# ImmortalWrt 24.x / 25.x ImageBuilder 通用设备添加模板
# 兼容：ImmortalWrt 24.10、25.xx
# 用法：修改【用户配置区】后直接执行
#==============================================================

#==============================================================
# 【用户配置区】——只改这里，下面不要动！
#==============================================================

# ---- 1. 平台 ----
# mediatek/ath79/ipq40xx/ramips/bcm53xx/rockchip/sunxi ...
PLATFORM="mediatek"

# 子目标，常见：filogic/generic/ath79/ipq40xx/ramips ...
SUBTARGET="filogic"

# ---- 2. 设备 ----
# 设备名（小写字母+数字+下划线+横杠）
DEVICE_NAME="cudy_tr3000-512mb-v1"
# 厂商名（显示在 LuCI 系统信息）
DEVICE_VENDOR="Cudy"
# 型号名
DEVICE_MODEL="TR3000"
# 变体说明
DEVICE_VARIANT="v1 (512MB NAND)"

# ---- 3. DTS 文件 ----
# ⚠️ 基础 DTS 必须已经存在于你的 ImageBuilder 里！
# 如果没有，需要先从 ImmortalWrt 源码仓库复制过来
DTS_BASE="mt7981b-cudy-tr3000-v1"
# 新 DTS 文件名（不含 .dts 后缀）
DTS_NEW="mt7981b-cudy-tr3000-512mb-v1"

# ---- 4. 固件分区参数 ----
# 固件总大小（单位 k），根据实际 NAND 大小计算
# 常见值：512MB=507904k / 256MB=253952k / 1GB=1015808k
IMAGE_SIZE="507904k"
# 闪存擦除块大小（NAND 通常 128k，eMMC 256k）
BLOCKSIZE="128k"
# 闪存页大小（NAND 通常 2048，eMMC 4096）
PAGESIZE="2048"
# UBI 坏块保护参数（-E 5 表示跳过 5 个 PEB）
UBINIZE_OPTS="-E 5"

# ---- 5. 内核相关 ----
# ImmortalWrt 24.x 默认 6.6，25.x 大部分 6.6，部分 6.12
# 不确定先填 6.6，这个值只影响显示不影响构建
KERNEL_VER="6.6"
# 内核是否放进 UBI（1=是 省空间，0=否 需要单独分区）
KERNEL_IN_UBI="1"

# ---- 6. 默认软件包（空格分隔）----
# 不需要可以留空 ""
DEVICE_PACKAGES="kmod-usb3 kmod-mt7915e kmod-mt7981-firmware automount"

#==============================================================
# 【脚本主体】——下面不用动
#==============================================================

set -e

# ---- 路径变量 ----
IB_DIR="$(pwd)"
DTS_DIR="${IB_DIR}/target/linux/${PLATFORM}/dts"
IMAGE_MK="${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}.mk"
TARGETINFO="${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}.targetinfo"

# ---- 颜色 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }

#==============================================================
# 步骤 0：预检查
#==============================================================
echo ""
echo "============================================="
echo "  ImmortalWrt 24.x/25.x 通用设备添加模板"
echo "  目标: ${PLATFORM}/${SUBTARGET} / ${DEVICE_NAME}"
echo "============================================="

# 检查基础 DTS 是否存在
if [ ! -f "${DTS_DIR}/${DTS_BASE}.dts" ]; then
    error "基础 DTS 不存在: ${DTS_DIR}/${DTS_BASE}.dts"
    echo "  请先从 ImmortalWrt 源码仓库复制："
    echo "  https://github.com/immortalwrt/immortalwrt/tree/openwrt/target/linux/${PLATFORM}/dts"
fi

# 检查 .mk 是否存在
if [ ! -f "${IMAGE_MK}" ]; then
    error "Image Makefile 不存在: ${IMAGE_MK}"
    echo "  请确认 PLATFORM='${PLATFORM}' SUBTARGET='${SUBTARGET}' 是否正确"
    echo "  可执行: ls ${IB_DIR}/target/linux/${PLATFORM}/image/"
    exit 1
fi

# 25.x 部分平台可能改名了，检查备选路径
ALT_MK="${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}/Makefile"
if [ ! -f "${IMAGE_MK}" ] && [ -f "${ALT_MK}" ]; then
    IMAGE_MK="${ALT_MK}"
    info "检测到 25.x 备选路径，使用: ${ALT_MK}"
fi

#==============================================================
# 步骤 1：复制 DTS/DTSI
#==============================================================
echo ""
echo "[步骤 1/5] 复制 DTS/DTSI..."

cp "${DTS_DIR}/${DTS_BASE}.dts" "${DTS_DIR}/${DTS_NEW}.dts"
ok "已创建 ${DTS_DIR}/${DTS_NEW}.dts"

# 有些设备有 .dtsi 包含文件，一并复制
if [ -f "${DTS_DIR}/${DTS_BASE}.dtsi" ]; then
    cp "${DTS_DIR}/${DTS_BASE}.dtsi" "${DTS_DIR}/${DTS_NEW}.dtsi"
    ok "已创建 ${DTS_DIR}/${DTS_NEW}.dtsi"
else
    info "无 .dtsi 文件，跳过"
fi

#==============================================================
# 步骤 2：修改分区大小（按需）
#==============================================================
echo ""
echo "[步骤 2/5] 修改分区大小..."

# 默认把 64MB(0x4000000) 改成 512MB(0x1FA40000)
# 如果你不需要改分区大小，把下面这行注释掉（加 #）
sed -i 's|reg = <0x5c0000 0x4000000>;|reg = <0x5c0000 0x1FA40000>;|g' \
    "${DTS_DIR}/${DTS_NEW}.dts"
ok "分区大小已更新 (64MB → 512MB)"

# 如果你的设备起始地址不是 0x5c0000，需要改成实际值
# 查看方法：grep "reg = <0x" ${DTS_DIR}/${DTS_BASE}.dts

#==============================================================
# 步骤 3：修改 DTSI UBI 定义（按需）
#==============================================================
echo ""
echo "[步骤 3/5] 修改 DTSI UBI 分区（如有）..."

if [ -f "${DTS_DIR}/${DTS_NEW}.dtsi" ]; then
    # 在 partition@5c0000 节点里加上 reg 属性
    sed -i -e '/partition@5c0000 {/,/^[ \t]*};/ {
        s|compatible = "linux,ubi";|reg = <0x5c0000 0x1FA40000>;\n\t\tcompatible = "linux,ubi";|
    }' "${DTS_DIR}/${DTS_NEW}.dtsi"
    ok "DTSI UBI 分区已更新"
else
    info "无 .dtsi 文件，跳过 UBI 修改"
fi

#==============================================================
# 步骤 4：写入 Image Makefile
#==============================================================
echo ""
echo "[步骤 4/5] 写入 ${SUBTARGET}.mk..."

# 检查是否已存在，避免重复添加
if grep -q "define Device/${DEVICE_NAME}" "${IMAGE_MK}"; then
    warn "设备 ${DEVICE_NAME} 已存在于 ${IMAGE_MK}，跳过写入"
else
    # 兼容 24.x 和 25.x 的 define Device 写法
    cat >> "${IMAGE_MK}" << MK_EOF

define Device/${DEVICE_NAME}
  DEVICE_VENDOR := ${DEVICE_VENDOR}
  DEVICE_MODEL := ${DEVICE_MODEL}
  DEVICE_VARIANT := ${DEVICE_VARIANT}
  DEVICE_DTS := ${DTS_NEW}
  DEVICE_DTS_DIR := ../dts
  SUPPORTED_DEVICES += ${DEVICE_NAME}
  UBINIZE_OPTS := ${UBINIZE_OPTS}
  BLOCKSIZE := ${BLOCKSIZE}
  PAGESIZE := ${PAGESIZE}
  IMAGE_SIZE := ${IMAGE_SIZE}
  KERNEL_IN_UBI := ${KERNEL_IN_UBI}
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  DEVICE_PACKAGES := ${DEVICE_PACKAGES}
endef
TARGET_DEVICES += ${DEVICE_NAME}
MK_EOF
    ok "${IMAGE_MK} 已写入"
fi

#==============================================================
# 步骤 5：写入 .targetinfo
#==============================================================
echo ""
echo "[步骤 5/5] 写入 ${SUBTARGET}.targetinfo..."

# 24.x 和 25.x 格式一致：YAML，空格缩进（不能用 Tab！）
if grep -q "^${DEVICE_NAME}:" "${TARGETINFO}" 2>/dev/null; then
    warn "${DEVICE_NAME} 已存在于 .targetinfo，跳过"
else
    cat >> "${TARGETINFO}" << TI_EOF

${DEVICE_NAME}:
  TARGET_DEVICE: ${DEVICE_NAME}
  KERNEL: ${KERNEL_VER}
  PROFILES: Default
  PLATFORM: ${PLATFORM}/${SUBTARGET}
  SUBTARGET: ${SUBTARGET}
  DEVICE_DTS: ${DTS_NEW}
  DEVICE_PACKAGES: ${DEVICE_PACKAGES}
  IMAGE_SIZE: ${IMAGE_SIZE}
  BLOCKSIZE: ${BLOCKSIZE}
  PAGESIZE: ${PAGESIZE}
  UBINIZE_OPTS: ${UBINIZE_OPTS}
TI_EOF
    ok "${TARGETINFO} 已追加"
fi

#==============================================================
# 验证
#==============================================================
echo ""
echo "============================================="
echo "  验证设备是否被识别..."
echo "============================================="

make clean >/dev/null 2>&1 || true

if make info 2>/dev/null | grep -q "${DEVICE_NAME}"; then
    ok "✅ ${DEVICE_NAME} 已被 ImageBuilder 识别！"
else
    warn "⚠️  make info 未找到 ${DEVICE_NAME}，请检查："
    echo "  1. ${IMAGE_MK} 中 TARGET_DEVICES 是否追加成功"
    echo "  2. ${TARGETINFO} 缩进必须用空格（不能用 Tab）"
    echo "  3. ${DTS_DIR}/${DTS_NEW}.dts 是否存在且语法正确"
    echo "  4. 如果 25.x 报错，确认 ${SUBTARGET}.mk 是否改名为 Makefile"
fi

# 显示追加的内容
echo ""
echo "[INFO] ${TARGETINFO} 中 ${DEVICE_NAME} 条目："
echo "----------------------------------------"
grep -A 15 "^${DEVICE_NAME}:" "${TARGETINFO}" 2>/dev/null || echo "  (未找到)"
echo "----------------------------------------"

#==============================================================
# 完成
#==============================================================
echo ""
echo "============================================="
echo "  ✅ 全部完成！"
echo "============================================="
echo ""
echo " 📦 构建固件："
echo "    make image PROFILE=\"${DEVICE_NAME}\""
echo ""
echo " 📂 输出位置："
echo "    bin/targets/${PLATFORM}/${SUBTARGET}/"
echo ""
echo " 🔧 添加额外软件包："
echo "    make image PROFILE=\"${DEVICE_NAME}\" \\"
echo "        PACKAGES=\"kmod-xxx kmod-yyy\""
echo ""
echo " 📏 调整根分区大小："
echo "    make image PROFILE=\"${DEVICE_NAME}\" \\"
echo "        ROOTFS_PARTSIZE=\"1024\""
echo "============================================="
