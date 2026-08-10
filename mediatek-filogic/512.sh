#!/bin/bash
#==============================================================
# 智能修复版：Cudy TR3000 512MB 适配脚本
# 自动处理目录结构问题，确保设备被正确识别
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
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# -------------- 自动适配目录规则 --------------
IB_DIR="/home/build/immortalwrt"
[ ! -d "${IB_DIR}" ] && IB_DIR="$(pwd)"

DTS_DIR="${IB_DIR}/target/linux/${PLATFORM}/dts"

echo "============================================="
echo " 🔧 智能目录结构修复"
echo "============================================="

# 检查是否存在基础 Cudy 设备
BASE_DEVICE_MAKEFILE=""
for mk_file in "${IB_DIR}/target/linux/${PLATFORM}/image/"*cudy*.mk "${IB_DIR}/target/linux/${PLATFORM}/image/"*cudy*"/Makefile"; do
    if [ -f "$mk_file" ]; then
        BASE_DEVICE_MAKEFILE="$mk_file"
        info "找到基础 Cudy 设备 Makefile: $mk_file"
        break
    fi
done

if [ -n "$BASE_DEVICE_MAKEFILE" ]; then
    info "使用基础设备 Makefile 添加新设备"
    DEVICE_MK="$BASE_DEVICE_MAKEFILE"
else
    info "未找到基础 Cudy 设备，创建新的设备文件"

    # 创建子目录结构（如果不存在）
    DEVICE_DIR="${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}"
    if [ ! -d "$DEVICE_DIR" ]; then
        info "创建子目录: $DEVICE_DIR"
        mkdir -p "$DEVICE_DIR"
    fi

    DEVICE_MK="${DEVICE_DIR}/${DEVICE_NAME}.mk"
    info "设备文件: $DEVICE_MK"
fi

# -------------- 步骤 1：复制并修改 DTS 文件 --------------
echo ""
echo "============================================="
echo " 📝 步骤 1/4：复制并修改 DTS 文件"
echo "============================================="

if [ ! -f "${DTS_DIR}/${DTS_BASE}.dts" ]; then
    error "基础 DTS 文件不存在: ${DTS_DIR}/${DTS_BASE}.dts"
fi

info "复制基础 DTS 文件..."
cp "${DTS_DIR}/${DTS_BASE}.dts" "${DTS_DIR}/${DTS_NEW}.dts"
ok "DTS 文件已复制"

info "修改分区大小为 512MB..."
sed -i 's/size = <0x1e00000>/size = <0x1d80000>/g' "${DTS_DIR}/${DTS_NEW}.dts"
sed -i 's/size = <0x4000000>/size = <0x1d80000>/g' "${DTS_DIR}/${DTS_NEW}.dts"
ok "分区大小已更新"

# -------------- 步骤 2：写入设备定义 --------------
echo ""
echo "============================================="
echo " ⚙️  步骤 2/4：写入设备定义"
echo "============================================="

info "清理旧的设备定义..."
# 在所有可能的 Makefile 中清理旧定义
find "${IB_DIR}/target/linux/${PLATFORM}/image" -name "*.mk" -o -name "Makefile" | while read file; do
    sed -i "/define Device\/${DEVICE_NAME}/,/endef/d" "$file" 2>/dev/null || true
    sed -i "/TARGET_DEVICES += ${DEVICE_NAME}/d" "$file" 2>/dev/null || true
done

info "写入设备定义到: $DEVICE_MK"
cat > "$DEVICE_MK" << MK_EOF
# Cudy TR3000 512MB 专属定义
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

ok "设备定义已写入"

# 如果是子目录文件，还需要更新主 Makefile
if [[ "$DEVICE_MK" == *"/${SUBTARGET}/"* ]]; then
    MAIN_MK="${IB_DIR}/target/linux/${PLATFORM}/image/Makefile"
    if [ -f "$MAIN_MK" ]; then
        info "更新主 Makefile 以包含子目录..."
        # 清除旧的包含
        sed -i "/include.*${SUBTARGET}\.mk/d" "$MAIN_MK" 2>/dev/null || true
        # 添加新的包含
        echo "" >> "$MAIN_MK"
        echo "include \$(TOPDIR)/target/linux/${PLATFORM}/image/${SUBTARGET}/${DEVICE_NAME}.mk" >> "$MAIN_MK"
        ok "主 Makefile 已更新"
    fi
fi

# -------------- 步骤 3：强制刷新配置 --------------
echo ""
echo "============================================="
echo " 🔄 步骤 3/4：强制刷新配置"
echo "============================================="

cd "${IB_DIR}"

info "彻底清理缓存..."
rm -rf tmp/ .config staging_dir/ build_dir/
ok "缓存已清理"

info "执行 make defconfig..."
if make defconfig V=s 2>&1 | tail -20; then
    ok "make defconfig 成功"
else
    warn "defconfig 有警告，但继续执行"
fi

# 尝试重新加载模块
info "重新扫描设备信息..."
make -C target/linux/mediatek 2>/dev/null || true

# -------------- 步骤 4：最终验证 --------------
echo ""
echo "============================================="
echo " ✅ 步骤 4/4：最终验证"
echo "============================================="

info "检查设备文件..."
if [ -f "$DEVICE_MK" ]; then
    ok "设备文件存在: $DEVICE_MK"
else
    error "设备文件不存在: $DEVICE_MK"
fi

if [ -f "${DTS_DIR}/${DTS_NEW}.dts" ]; then
    ok "DTS 文件存在: ${DTS_DIR}/${DTS_NEW}.dts"
else
    error "DTS 文件不存在: ${DTS_DIR}/${DTS_NEW}.dts"
fi

info "设备定义验证..."
if grep -q "define Device/${DEVICE_NAME}" "$DEVICE_MK"; then
    ok "设备定义存在"
else
    error "设备定义不存在"
fi

if grep -q "TARGET_DEVICES += ${DEVICE_NAME}" "$DEVICE_MK"; then
    ok "TARGET_DEVICES 存在"
else
    error "TARGET_DEVICES 不存在"
fi

echo ""
info "尝试设备识别..."
info "执行: make info 2>&1 | grep -E 'cudy|${DEVICE_NAME}'"

# 获取完整的设备列表
ALL_DEVICES=$(make info 2>&1 || echo "")

echo ""
debug "设备列表（包含 Cudy 的）："
echo "$ALL_DEVICES" | grep -i cudy || warn "未找到任何 Cudy 设备"

echo ""
debug "设备列表（包含我们的设备）："
echo "$ALL_DEVICES" | grep "${DEVICE_NAME}" || warn "未找到我们的设备"

# 最终验证
if echo "$ALL_DEVICES" | grep -q "${DEVICE_NAME}"; then
    ok "🎉 设备 ${DEVICE_NAME} 已成功识别！"
    echo ""
    echo "============================================="
    echo " ✨ 适配成功！"
    echo "============================================="
    echo ""
    echo "构建命令："
    echo "  make image PROFILE=\"${DEVICE_NAME}\""
    echo ""
    echo "或构建完整固件："
    echo "  make"
    echo ""
    echo "输出路径："
    echo "  bin/targets/${PLATFORM}/${SUBTARGET}/"
    echo "============================================="
else
    warn "⚠️ 设备未被自动识别"
    echo ""
    echo "============================================="
    echo " 🔧 手动构建方案"
    echo "============================================="
    echo ""
    echo "由于设备未被自动识别，可以尝试直接构建："
    echo ""
    echo "1. 手动指定设备名称构建："
    echo "   make image PROFILE=\"${DEVICE_NAME}\""
    echo ""
    echo "2. 或使用 Image 命令："
    echo "   make image PROFILE=\"${DEVICE_NAME}\" PACKAGES=\"luci\""
    echo ""
    echo "3. 检查设备文件内容："
    echo "   cat $DEVICE_MK"
    echo ""
    echo "============================================="
fi

echo ""
echo "============================================="
echo " 📋 完整调试信息"
echo "============================================="
echo ""
echo "📁 关键路径："
echo "  ImageBuilder: ${IB_DIR}"
echo "  设备定义文件: ${DEVICE_MK}"
echo "  DTS 文件: ${DTS_DIR}/${DTS_NEW}.dts"
echo ""
echo "📄 文件状态："
echo "  设备定义: $(grep -c "define Device/${DEVICE_NAME}" "$DEVICE_MK" 2>/dev/null || echo '0')"
echo "  TARGET_DEVICES: $(grep -c "TARGET_DEVICES += ${DEVICE_NAME}" "$DEVICE_MK" 2>/dev/null || echo '0')"
echo ""
echo "🔍 设备定义内容（最后20行）："
tail -20 "$DEVICE_MK"
echo ""
echo "============================================="
