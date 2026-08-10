#!/bin/bash
#==============================================================
# ImmortalWrt 25.12.x Cudy TR3000 512MB 专属适配脚本 (修复版)
# 修复重点：
# 1. 移除对 .targetinfo 的依赖（25.12.x 已废弃）
# 2. 强制清理缓存并重新生成 .config 以刷新 Profile 列表
# 3. 确保 Makefile 路径和语法完全兼容 25.12.x
# 4. 修复变量名中的下划线转义问题
#==============================================================
set -e

# -------------- 基础配置区 --------------
PLATFORM="mediatek"
SUBTARGET="filogic"
DEVICE_NAME="cudy_tr3000-512mb-v1"
DEVICE_VENDOR="Cudy"
DEVICE_MODEL="TR3000"
DEVICE_VARIANT="v1 (512MB NAND)"
DTS_BASE="mt7981b-cudy-tr3000-v1"
DTS_NEW="mt7981b-cudy-tr3000-512mb-v1"
IMAGE_SIZE="507904k"
BLOCKSIZE="128k"
PAGESIZE="2048"
UBINIZE_OPTS="-E 5"
KERNEL_IN_UBI="1"
DEVICE_PACKAGES="kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount"

# -------------- 自动适配目录规则 --------------
IB_DIR="/home/build/immortalwrt"
[ ! -d "${IB_DIR}" ] && IB_DIR="$(pwd)"

DTS_DIR="${IB_DIR}/target/linux/${PLATFORM}/dts"

# 25.12 专属路径检测：优先检查子目录 Makefile
if [ -d "${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}" ]; then
    IMAGE_MK="${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}/Makefile"
else
    IMAGE_MK="${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}.mk"
fi

# -------------- 颜色输出定义 --------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }

# -------------- 前置检查 --------------
echo ""
echo "============================================="
echo " 前置检查"
echo "============================================="

# 检查 ImageBuilder 目录
if [ ! -d "${IB_DIR}" ]; then
    error "ImageBuilder 目录不存在: ${IB_DIR}"
fi

info "ImageBuilder 目录: ${IB_DIR}"
ok "目录检查通过"

# 检查 DTS 目录
if [ ! -d "${DTS_DIR}" ]; then
    error "DTS 目录不存在: ${DTS_DIR}"
fi

ok "DTS 目录检查通过: ${DTS_DIR}"

# 检查 IMAGE_MK 文件
if [ ! -f "${IMAGE_MK}" ]; then
    error "Makefile 不存在: ${IMAGE_MK}"
fi

ok "Makefile 检查通过: ${IMAGE_MK}"

# -------------- 步骤 1：复制并修改 DTS 文件 --------------
echo ""
info "[步骤 1/3] 复制并修改 DTS 文件"

if [ ! -f "${DTS_DIR}/${DTS_BASE}.dts" ]; then
    error "基础 DTS 文件不存在: ${DTS_DIR}/${DTS_BASE}.dts"
fi

# 复制 DTS 文件
cp "${DTS_DIR}/${DTS_BASE}.dts" "${DTS_DIR}/${DTS_NEW}.dts"

# 修改分区大小为 512MB (472MB usable)
sed -i 's/size = <0x1e00000>/size = <0x1d80000>/g' "${DTS_DIR}/${DTS_NEW}.dts"
sed -i 's/size = <0x4000000>/size = <0x1d80000>/g' "${DTS_DIR}/${DTS_NEW}.dts"

ok "DTS 文件已复制并修改: ${DTS_NEW}.dts"
ok "DTS 分区大小已更新为 512MB"

# -------------- 步骤 2：写入 Makefile 设备定义 --------------
echo ""
info "[步骤 2/3] 写入 Makefile 设备定义"

# 先清除可能存在的旧定义，防止重复追加
sed -i "/define Device\/${DEVICE_NAME}/,/endef/d" "${IMAGE_MK}"
sed -i "/TARGET_DEVICES += ${DEVICE_NAME}/d" "${IMAGE_MK}"

cat >> "${IMAGE_MK}" << MK_EOF

define Device/${DEVICE_NAME}
  DEVICE_VENDOR := ${DEVICE_VENDOR}
  DEVICE_MODEL := ${DEVICE_MODEL}
  DEVICE_VARIANT := ${DEVICE_VARIANT}
  DEVICE_DTS := ${DTS_NEW}
  DEVICE_DTS_DIR := ../dts
  SUPPORTED_DEVICES += R47-512MB
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

ok "Makefile 定义已写入 ${IMAGE_MK}"

# -------------- 步骤 3：深度清理与验证 --------------
echo ""
info "[步骤 3/3] 清理缓存并验证 Profile 识别"

cd "${IB_DIR}"

# 关键修复：ImageBuilder 必须删除 .config 和 tmp 才能重新扫描 Makefile
rm -rf tmp/ .config

info "正在执行 make defconfig 以刷新 Profile 列表..."
make defconfig >/dev/null 2>&1 || true

echo ""
echo "============================================="
echo " 验证结果"
echo "============================================="

# 验证 Profile 是否被识别
if make info 2>/dev/null | grep -q "${DEVICE_NAME}"; then
    ok "✅ 设备 ${DEVICE_NAME} 已被 ImmortalWrt 25.12.x 成功识别！"
    echo ""
    echo "----------------------------------------"
    echo " 📦 适配完成，请手动执行以下命令构建："
    echo "----------------------------------------"
    echo ""
    echo " make image PROFILE=\"${DEVICE_NAME}\""
    echo ""
    echo " 📂 固件输出路径："
    echo " bin/targets/${PLATFORM}/${SUBTARGET}/"
    echo ""
    echo " 🔧 带自定义包构建示例："
    echo " make image PROFILE=\"${DEVICE_NAME}\" PACKAGES=\"curl luci luci-i18n-base-zh-cn ...\""
    echo ""
    echo " 📏 调整根分区大小示例："
    echo " make image PROFILE=\"${DEVICE_NAME}\" ROOTFS_PARTSIZE=\"1024\""
    echo "----------------------------------------"
else
    warn "⚠️ 验证失败：make info 未找到设备"
    echo ""
    echo "请检查以下文件："
    echo "1. ${IMAGE_MK} 末尾是否有 TARGET_DEVICES += ${DEVICE_NAME}"
    echo "2. ${DTS_DIR}/${DTS_NEW}.dts 语法是否正确"
    echo "3. 尝试手动执行: make info | grep ${DEVICE_NAME}"
fi

echo "============================================="
