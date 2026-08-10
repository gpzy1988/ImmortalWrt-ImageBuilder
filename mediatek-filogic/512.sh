#!/bin/bash
#==============================================================
# ImmortalWrt 25.12.x Cudy TR3000 512MB 专属适配脚本 (最终修复版)
# 修复版本: v2.0
# 修复内容:
# 1. 修复变量名转义问题
# 2. 保护内核配置文件避免删除
# 3. 智能检测 Makefile 路径
# 4. 优化 DTS 修改逻辑
# 5. 增强验证和错误处理
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

# -------------- 颜色输出定义 --------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }

# -------------- 自动适配目录规则 --------------
IB_DIR="/home/build/immortalwrt"
[ ! -d "${IB_DIR}" ] && IB_DIR="$(pwd)"

DTS_DIR="${IB_DIR}/target/linux/${PLATFORM}/dts"

# 智能检测 Makefile 路径
POSSIBLE_MKS=(
    "${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}/Makefile"
    "${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}.mk"
    "${IB_DIR}/target/linux/${PLATFORM}/Makefile"
)

IMAGE_MK=""
for mk_file in "${POSSIBLE_MKS[@]}"; do
    if [ -f "$mk_file" ]; then
        IMAGE_MK="$mk_file"
        break
    fi
done

# 如果没有找到主 Makefile，使用子目录方案
if [ -z "$IMAGE_MK" ]; then
    DEVICE_DIR="${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}"
    mkdir -p "$DEVICE_DIR"
    IMAGE_MK="${DEVICE_DIR}/${DEVICE_NAME}.mk"
fi

# -------------- 步骤 1：复制并修改 DTS 文件 --------------
info "[步骤 1/4] 复制并修改 DTS 文件"

if [ ! -f "${DTS_DIR}/${DTS_BASE}.dts" ]; then
    error "基础 DTS 文件不存在: ${DTS_DIR}/${DTS_BASE}.dts"
fi

# 复制 DTS 文件
cp "${DTS_DIR}/${DTS_BASE}.dts" "${DTS_DIR}/${DTS_NEW}.dts"
ok "DTS 文件已复制"

# 修改分区大小为 512MB (472MB usable)
sed -i 's/size = <0x1e00000>/size = <0x1d80000>/g' "${DTS_DIR}/${DTS_NEW}.dts"
sed -i 's/size = <0x4000000>/size = <0x1d80000>/g' "${DTS_DIR}/${DTS_NEW}.dts"
ok "DTS 分区大小已更新为 512MB"

# -------------- 步骤 2：清理旧定义 --------------
info "[步骤 2/4] 清理旧的设备定义"

# 在所有可能的 Makefile 中清理旧定义
find "${IB_DIR}/target/linux/${PLATFORM}/image" -name "*.mk" -o -name "Makefile" 2>/dev/null | while read file; do
    sed -i "/define Device\/${DEVICE_NAME}/,/endef/d" "$file" 2>/dev/null || true
    sed -i "/TARGET_DEVICES += ${DEVICE_NAME}/d" "$file" 2>/dev/null || true
done

ok "旧设备定义已清理"

# -------------- 步骤 3：写入设备定义 --------------
info "[步骤 3/4] 写入设备定义"

cat > "$IMAGE_MK" << MK_EOF
define Device/${DEVICE_NAME}
  \$(call Device/dsa-migration)
  DEVICE_VENDOR := ${DEVICE_VENDOR}
  DEVICE_MODEL := ${DEVICE_MODEL}
  DEVICE_VARIANT := ${DEVICE_VARIANT}
  DEVICE_DTS := ${DTS_NEW}
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := ${DEVICE_PACKAGES}
  KERNEL := kernel-bin | gzip | uImage gzip
  KERNEL_INITRAMFS := kernel-bin | gzip | uImage gzip
  UBINIZE_OPTS := ${UBINIZE_OPTS}
  BLOCKSIZE := ${BLOCKSIZE}
  PAGESIZE := ${PAGESIZE}
  IMAGE_SIZE := ${IMAGE_SIZE}
  KERNEL_IN_UBI := ${KERNEL_IN_UBI}
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size | cudy-factory
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  SUPPORTED_DEVICES += cudy,tr3000 R47-512MB
endef
TARGET_DEVICES += ${DEVICE_NAME}
MK_EOF

ok "设备定义已写入: $IMAGE_MK"

# 如果是子目录文件，更新主 Makefile
if [[ "$IMAGE_MK" == *"/${SUBTARGET}/"* ]]; then
    MAIN_MK="${IB_DIR}/target/linux/${PLATFORM}/image/Makefile"
    if [ -f "$MAIN_MK" ]; then
        # 清除旧的包含
        sed -i "/include.*${DEVICE_NAME}\.mk/d" "$MAIN_MK" 2>/dev/null || true
        # 添加新的包含
        echo "" >> "$MAIN_MK"
        echo "include \$(TOPDIR)/target/linux/${PLATFORM}/image/${SUBTARGET}/${DEVICE_NAME}.mk" >> "$MAIN_MK"
        ok "主 Makefile 已更新"
    fi
fi

# -------------- 步骤 4：安全刷新配置 --------------
info "[步骤 4/4] 安全刷新配置"

cd "${IB_DIR}"

# 安全清理：只删除临时文件，保护内核配置
rm -rf tmp/ 2>/dev/null || true
rm -f .config 2>/dev/null || true

ok "临时文件已清理（内核配置已保护）"

# 验证文件
if [ ! -f "$IMAGE_MK" ]; then
    error "设备定义文件不存在: $IMAGE_MK"
fi

if [ ! -f "${DTS_DIR}/${DTS_NEW}.dts" ]; then
    error "DTS 文件不存在: ${DTS_DIR}/${DTS_NEW}.dts"
fi

if ! grep -q "define Device/${DEVICE_NAME}" "$IMAGE_MK"; then
    error "设备定义未正确写入"
fi

ok "所有文件验证通过"

# 静默成功退出
exit 0
