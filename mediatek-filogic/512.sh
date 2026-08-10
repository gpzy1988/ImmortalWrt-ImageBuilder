#!/bin/bash
#==============================================================
# 完全静态版 - 不执行任何 make 命令
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

# 只创建文件，不执行任何 make 命令
echo "✅ 开始静态适配..."

# 创建设备目录
DEVICE_DIR="${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}"
mkdir -p "$DEVICE_DIR"

# 创建设备定义文件
DEVICE_MK="${DEVICE_DIR}/${DEVICE_NAME}.mk"

cat > "$DEVICE_MK" << 'EOF'
define Device/cudy_tr3000-512mb-v1
  $(call Device/dsa-migration)
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

# 复制DTS文件
if [ -f "${DTS_DIR}/${DTS_BASE}.dts" ]; then
    cp "${DTS_DIR}/${DTS_BASE}.dts" "${DTS_DIR}/${DTS_NEW}.dts"
    # 修改分区大小
    sed -i 's/size = <0x1e00000>/size = <0x1d80000>/g' "${DTS_DIR}/${DTS_NEW}.dts"
    sed -i 's/size = <0x4000000>/size = <0x1d80000>/g' "${DTS_DIR}/${DTS_NEW}.dts"
fi

# 更新主 Makefile
MAIN_MK="${IB_DIR}/target/linux/${PLATFORM}/image/Makefile"
if [ -f "$MAIN_MK" ]; then
    sed -i "/include.*${DEVICE_NAME}\.mk/d" "$MAIN_MK" 2>/dev/null || true
    echo "" >> "$MAIN_MK"
    echo "include \$(TOPDIR)/target/linux/${PLATFORM}/image/${SUBTARGET}/${DEVICE_NAME}.mk" >> "$MAIN_MK"
fi

# 静默退出，完全静态操作
exit 0
