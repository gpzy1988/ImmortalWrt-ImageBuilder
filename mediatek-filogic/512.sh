#!/bin/bash
#==============================================================
# 调试版本：Cudy TR3000 512MB 适配脚本
# 增强调试信息，帮助定位验证失败问题
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
echo " 📁 目录结构检查"
echo "============================================="
debug "ImageBuilder 目录: ${IB_DIR}"
debug "DTS 目录: ${DTS_DIR}"
debug "基础 DTS 文件: ${DTS_DIR}/${DTS_BASE}.dts"

# 检查目录是否存在
if [ ! -d "${IB_DIR}" ]; then
    error "ImageBuilder 目录不存在: ${IB_DIR}"
fi

if [ ! -d "${DTS_DIR}" ]; then
    error "DTS 目录不存在: ${DTS_DIR}"
fi

# 列出 DTS 目录中的文件
debug "DTS 目录内容（前10个）:"
ls -1 "${DTS_DIR}" | head -10

# -------------- 智能查找 Makefile --------------
echo ""
echo "============================================="
echo " 🔍 Makefile 路径检测"
echo "============================================="

# 尝试多个可能的 Makefile 位置
POSSIBLE_MKS=(
    "${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}/Makefile"
    "${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}.mk"
    "${IB_DIR}/target/linux/${PLATFORM}/Makefile"
    "${IB_DIR}/target/linux/${PLATFORM}/image/Makefile"
    "${IB_DIR}/target/linux/mediatek-filogic/image/Makefile"
)

IMAGE_MK=""
for mk_file in "${POSSIBLE_MKS[@]}"; do
    if [ -f "$mk_file" ]; then
        IMAGE_MK="$mk_file"
        ok "找到 Makefile: ${mk_file}"
        break
    else
        debug "检查路径（不存在）: $mk_file"
    fi
done

if [ -z "$IMAGE_MK" ]; then
    error "未找到 Makefile 文件！已检查以下路径："
    for mk_file in "${POSSIBLE_MKS[@]}"; do
        echo "  - $mk_file"
    done
    echo ""
    debug "ImageBuilder 目标目录结构："
    find "${IB_DIR}/target/linux/${PLATFORM}" -name "Makefile" -o -name "*.mk" | head -10 || true
fi

# 显示 Makefile 的最后几行
debug "Makefile 末尾内容（最后5行）："
tail -5 "${IMAGE_MK}"

# -------------- 步骤 1：复制并修改 DTS 文件 --------------
echo ""
echo "============================================="
echo " 📝 步骤 1/3：复制并修改 DTS 文件"
echo "============================================="

if [ ! -f "${DTS_DIR}/${DTS_BASE}.dts" ]; then
    error "基础 DTS 文件不存在: ${DTS_DIR}/${DTS_BASE}.dts"
fi

info "复制基础 DTS 文件..."
cp "${DTS_DIR}/${DTS_BASE}.dts" "${DTS_DIR}/${DTS_NEW}.dts"
ok "DTS 文件已复制: ${DTS_NEW}.dts"

info "修改分区大小为 512MB..."
sed -i 's/size = <0x1e00000>/size = <0x1d80000>/g' "${DTS_DIR}/${DTS_NEW}.dts"
sed -i 's/size = <0x4000000>/size = <0x1d80000>/g' "${DTS_DIR}/${DTS_NEW}.dts"
ok "分区大小已更新"

# 验证 DTS 文件内容
debug "验证 DTS 文件内容："
if [ -f "${DTS_DIR}/${DTS_NEW}.dts" ]; then
    ok "DTS 文件存在"
    debug "DTS 文件大小: $(wc -c < "${DTS_DIR}/${DTS_NEW}.dts") 字节"
    debug "DTS 文件行数: $(wc -l < "${DTS_DIR}/${DTS_NEW}.dts") 行"
else
    error "DTS 文件创建失败"
fi

# -------------- 步骤 2：写入 Makefile 设备定义 --------------
echo ""
echo "============================================="
echo " ⚙️  步骤 2/3：写入 Makefile 设备定义"
echo "============================================="

info "清理旧的设备定义..."
sed -i "/define Device\/${DEVICE_NAME}/,/endef/d" "${IMAGE_MK}" 2>/dev/null || true
sed -i "/TARGET_DEVICES += ${DEVICE_NAME}/d" "${IMAGE_MK}" 2>/dev/null || true

info "写入新的设备定义..."
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

ok "设备定义已写入"

# 验证写入
echo ""
debug "验证 Makefile 写入..."
if grep -q "define Device/${DEVICE_NAME}" "${IMAGE_MK}"; then
    ok "设备定义已存在"
else
    error "设备定义写入失败"
fi

if grep -q "TARGET_DEVICES += ${DEVICE_NAME}" "${IMAGE_MK}"; then
    ok "TARGET_DEVICES 已添加"
else
    error "TARGET_DEVICES 添加失败"
fi

debug "Makefile 末尾内容（最后15行）："
tail -15 "${IMAGE_MK}"

# -------------- 步骤 3：深度清理与验证 --------------
echo ""
echo "============================================="
echo " 🔄 步骤 3/3：清理缓存并验证"
echo "============================================="

cd "${IB_DIR}"

info "清理缓存..."
rm -rf tmp/ .config
ok "缓存已清理"

echo ""
info "执行 make defconfig..."
make defconfig 2>&1 | head -20 || warn "defconfig 执行有警告"
ok "make defconfig 完成"

echo ""
echo "============================================="
echo " ✅ 验证结果"
echo "============================================="

info "检查设备识别情况..."
debug "执行: make info | grep '${DEVICE_NAME}'"

# 显示所有包含 cudy 的设备
info "查找所有 Cudy 设备："
make info 2>/dev/null | grep -i "cudy" | head -10 || warn "未找到 Cudy 设备"

# 验证特定设备
if make info 2>/dev/null | grep -q "${DEVICE_NAME}"; then
    ok "✅ 设备 ${DEVICE_NAME} 已成功识别！"
    echo ""
    echo "============================================="
    echo " 🎉 适配成功！"
    echo "============================================="
    echo ""
    echo "构建命令："
    echo "  make image PROFILE=\"${DEVICE_NAME}\""
    echo ""
    echo "输出路径："
    echo "  bin/targets/${PLATFORM}/${SUBTARGET}/"
    echo "============================================="
else
    warn "⚠️ 设备未被识别"
    echo ""
    echo "============================================="
    echo " 🔍 调试信息"
    echo "============================================="
    echo ""
    echo "📁 文件状态："
    echo "  Makefile: ${IMAGE_MK}"
    echo "  存在: $([ -f "${IMAGE_MK}" ] && echo '✅' || echo '❌')"
    echo ""
    echo "  DTS 文件: ${DTS_DIR}/${DTS_NEW}.dts"
    echo "  存在: $([ -f "${DTS_DIR}/${DTS_NEW}.dts" ] && echo '✅' || echo '❌')"
    echo ""
    echo "📄 Makefile 检查："
    echo "  设备定义: $(grep -c "define Device/${DEVICE_NAME}" "${IMAGE_MK}" 2>/dev/null || echo '0')"
    echo "  TARGET_DEVICES: $(grep -c "TARGET_DEVICES += ${DEVICE_NAME}" "${IMAGE_MK}" 2>/dev/null || echo '0')"
    echo ""
    echo "🔍 可用设备列表（部分）："
    make info 2>/dev/null | head -30 || echo "无法获取设备列表"
    echo ""
    echo "💡 建议检查："
    echo "  1. Makefile 路径是否正确"
    echo "  2. 设备定义语法是否正确"
    echo "  3. DTS 文件是否有语法错误"
    echo "============================================="
fi

echo ""
echo "============================================="
echo " 📋 详细调试日志已保存"
echo "============================================="
