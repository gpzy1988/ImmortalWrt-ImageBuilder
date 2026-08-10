#!/bin/bash
#==============================================================
# 最小化适配脚本 - 不执行任何破坏性操作
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

# 设置路径
IB_DIR="/home/build/immortalwrt"
DTS_DIR="${IB_DIR}/target/linux/${PLATFORM}/dts"

echo "✅ 开始适配 Cudy TR3000 512MB 设备"

# 步骤1：复制DTS文件（不修改，只复制）
echo "📋 步骤1：复制DTS文件"
if [ -f "${DTS_DIR}/${DTS_BASE}.dts" ]; then
    cp "${DTS_DIR}/${DTS_BASE}.dts" "${DTS_DIR}/${DTS_NEW}.dts"
    echo "✅ DTS文件已复制"
else
    echo "❌ 基础DTS文件不存在，跳过"
fi

# 步骤2：创建设备定义（最小化版本）
echo "📋 步骤2：创建设备定义"

# 找到正确的Makefile路径
DEVICE_DIR="${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}"
mkdir -p "$DEVICE_DIR"

DEVICE_MK="${DEVICE_DIR}/${DEVICE_NAME}.mk"

cat > "$DEVICE_MK" << 'EOF'
define Device/cudy_tr3000-512mb-v1
  DEVICE_VENDOR := Cudy
  DEVICE_MODEL := TR3000
  DEVICE_VARIANT := v1 (512MB NAND)
  DEVICE_DTS := mt7981b-cudy-tr3000-512mb-v1
  DEVICE_DTS_DIR := ../dts
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 507904k
  KERNEL_IN_UBI := 1
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  SUPPORTED_DEVICES += cudy,tr3000 R47-512MB
endef
TARGET_DEVICES += cudy_tr3000-512mb-v1
EOF

echo "✅ 设备定义已创建"

# 步骤3：更新主Makefile（如果需要）
MAIN_MK="${IB_DIR}/target/linux/${PLATFORM}/image/Makefile"
if [ -f "$MAIN_MK" ]; then
    # 清除旧的包含
    sed -i "/include.*${DEVICE_NAME}\.mk/d" "$MAIN_MK" 2>/dev/null || true
    # 添加新的包含
    echo "" >> "$MAIN_MK"
    echo "include \$(TOPDIR)/target/linux/${PLATFORM}/image/${SUBTARGET}/${DEVICE_NAME}.mk" >> "$MAIN_MK"
    echo "✅ 主Makefile已更新"
fi

# 步骤4：验证文件
echo "📋 步骤3：验证文件"
if [ -f "$DEVICE_MK" ] && [ -f "${DTS_DIR}/${DTS_NEW}.dts" ]; then
    echo "✅ 所有必要文件已创建"
else
    echo "❌ 文件创建失败"
fi

# 静默退出，不执行任何清理操作
echo "✅ 适配完成，继续构建..."
exit 0
