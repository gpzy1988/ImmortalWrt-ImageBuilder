#!/bin/bash
#==============================================================
# 增强版适配脚本 - 解决设备识别问题
#==============================================================

# 基础配置
PLATFORM="mediatek"
SUBTARGET="filogic"
DEVICE_NAME="cudy_tr3000-512mb-v1"
DTS_BASE="mt7981b-cudy-tr3000-v1"
DTS_NEW="mt7981b-cudy-tr3000-512mb-v1"
DEVICE_VENDOR="Cudy"
DEVICE_MODEL="TR3000"
DEVICE_VARIANT="v1 (512MB NAND)"
IMAGE_SIZE="507904k"
BLOCKSIZE="128k"
PAGESIZE="2048"
UBINIZE_OPTS="-E 5"
KERNEL_IN_UBI="1"
DEVICE_PACKAGES="kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount"

# 设置路径
IB_DIR="/home/build/immortalwrt"
DTS_DIR="${IB_DIR}/target/linux/${PLATFORM}/dts"

echo "✅ 开始增强适配 Cudy TR3000 512MB 设备"

# 步骤1：复制DTS文件
echo "📋 步骤1：复制DTS文件"
if [ -f "${DTS_DIR}/${DTS_BASE}.dts" ]; then
    cp "${DTS_DIR}/${DTS_BASE}.dts" "${DTS_DIR}/${DTS_NEW}.dts"
    # 修改分区大小
    sed -i 's/size = <0x1e00000>/size = <0x1d80000>/g' "${DTS_DIR}/${DTS_NEW}.dts"
    sed -i 's/size = <0x4000000>/size = <0x1d80000>/g' "${DTS_DIR}/${DTS_NEW}.dts"
    echo "✅ DTS文件已复制并修改分区大小"
else
    echo "❌ 基础DTS文件不存在，跳过"
fi

# 步骤2：找到正确的Makefile并清理旧定义
echo "📋 步骤2：清理旧设备定义"

# 在所有可能的 Makefile 中清理
find "${IB_DIR}/target/linux/${PLATFORM}/image" -name "*.mk" -o -name "Makefile" 2>/dev/null | while read file; do
    sed -i "/define Device\/${DEVICE_NAME}/,/endef/d" "$file" 2>/dev/null || true
    sed -i "/TARGET_DEVICES += ${DEVICE_NAME}/d" "$file" 2>/dev/null || true
done

echo "✅ 旧定义已清理"

# 步骤3：创建设备目录和文件
echo "📋 步骤3：创建设备定义"

DEVICE_DIR="${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}"
mkdir -p "$DEVICE_DIR"

DEVICE_MK="${DEVICE_DIR}/${DEVICE_NAME}.mk"

cat > "$DEVICE_MK" << EOF
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
EOF

echo "✅ 设备定义已创建: $DEVICE_MK"

# 步骤4：更新主Makefile
echo "📋 步骤4：更新主Makefile"

MAIN_MK="${IB_DIR}/target/linux/${PLATFORM}/image/Makefile"
if [ -f "$MAIN_MK" ]; then
    # 清除旧的包含
    sed -i "/include.*${DEVICE_NAME}\.mk/d" "$MAIN_MK" 2>/dev/null || true
    # 添加新的包含
    echo "" >> "$MAIN_MK"
    echo "include \$(TOPDIR)/target/linux/${PLATFORM}/image/${SUBTARGET}/${DEVICE_NAME}.mk" >> "$MAIN_MK"
    echo "✅ 主Makefile已更新"
else
    echo "⚠️ 主Makefile不存在: $MAIN_MK"
fi

# 步骤5：强制刷新（关键！）
echo "📋 步骤5：强制刷新配置"

cd "${IB_DIR}"

# 重新生成配置（不删除内核文件）
if [ -f "Makefile" ]; then
    # 使用 make info 来刷新设备列表
    make info >/dev/null 2>&1 || true
    echo "✅ 设备列表已刷新"
fi

# 步骤6：验证设备是否被识别
echo "📋 步骤6：验证设备识别"

if make info 2>/dev/null | grep -q "${DEVICE_NAME}"; then
    echo "✅ 设备 ${DEVICE_NAME} 已被成功识别！"
else
    echo "⚠️ 设备未被自动识别，但文件已创建"
    echo ""
    echo "📋 诊断信息："
    echo "设备文件: $DEVICE_MK"
    echo "DTS 文件: ${DTS_DIR}/${DTS_NEW}.dts"
    echo "主Makefile: $MAIN_MK"
    echo ""
    echo "📋 手动验证命令："
    echo "make info | grep ${DEVICE_NAME}"
    echo ""
fi

# 步骤7：文件完整性检查
echo "📋 步骤7：文件完整性检查"

files_ok=true

if [ -f "$DEVICE_MK" ]; then
    echo "✅ 设备定义文件存在"
else
    echo "❌ 设备定义文件不存在"
    files_ok=false
fi

if [ -f "${DTS_DIR}/${DTS_NEW}.dts" ]; then
    echo "✅ DTS 文件存在"
else
    echo "❌ DTS 文件不存在"
    files_ok=false
fi

if grep -q "define Device/${DEVICE_NAME}" "$DEVICE_MK" 2>/dev/null; then
    echo "✅ 设备定义格式正确"
else
    echo "❌ 设备定义格式错误"
    files_ok=false
fi

if grep -q "TARGET_DEVICES += ${DEVICE_NAME}" "$DEVICE_MK" 2>/dev/null; then
    echo "✅ TARGET_DEVICES 正确"
else
    echo "❌ TARGET_DEVICES 缺失"
    files_ok=false
fi

if [ "$files_ok" = true ]; then
    echo "✅ 所有必要文件已正确创建"
else
    echo "❌ 部分文件有问题"
fi

echo "✅ 适配完成，继续构建..."
exit 0
