#!/bin/bash
set -e
# ImmortalWrt 25.12.x Cudy TR3000 512MB 全自动适配脚本
# 专为GitHub Actions无交互环境设计

# 基础配置
PLATFORM="mediatek"
SUBTARGET="filogic"
DEVICE_NAME="cudy_tr3000-512mb-v1"
DTS_BASE="mt7981b-cudy-tr3000-v1"
DTS_NEW="mt7981b-cudy-tr3000-512mb-v1"
IMAGE_SIZE="507904k"
BLOCKSIZE="128k"
PAGESIZE="2048"
UBINIZE_OPTS="-E 5"
DEVICE_PACKAGES="kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount"

# 自动定位ImageBuilder根目录
IB_DIR="/home/build/immortalwrt"
[ ! -d "${IB_DIR}" ] && IB_DIR="$(pwd)"
DTS_DIR="${IB_DIR}/target/linux/${PLATFORM}/dts"

# 自动检测25.12.x的Makefile路径
if [ -d "${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}" ]; then
    IMAGE_MK="${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}/Makefile"
else
    IMAGE_MK="${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}.mk"
fi

echo "============================================="
echo "  开始全自动适配 Cudy TR3000 512MB"
echo "  平台: ImmortalWrt 25.12.x / MediaTek Filogic"
echo "============================================="

# 前置检查
[ ! -f "${DTS_DIR}/${DTS_BASE}.dts" ] && {
    echo "ERROR: 基础DTS文件不存在: ${DTS_DIR}/${DTS_BASE}.dts"
    exit 1
}
[ ! -f "${IMAGE_MK}" ] && {
    echo "ERROR: 目标Makefile不存在: ${IMAGE_MK}"
    exit 1
}

# 步骤 1: 生成512MB专属DTS
echo "[1/4] 生成512MB专属DTS文件"
cp "${DTS_DIR}/${DTS_BASE}.dts" "${DTS_DIR}/${DTS_NEW}.dts"
# 修改NAND分区大小从64MB到512MB
sed -i 's|reg = <0x5c0000 0x4000000>;|reg = <0x5c0000 0x1FA40000>;|g' "${DTS_DIR}/${DTS_NEW}.dts"
echo "✅ DTS分区大小已更新为512MB"

# 步骤 2: 注入设备定义到Makefile
echo "[2/4] 注入设备定义到Makefile"
# 清除旧定义防止重复
sed -i "/define Device\/${DEVICE_NAME}/,/endef/d" "${IMAGE_MK}"
sed -i "/TARGET_DEVICES += ${DEVICE_NAME}/d" "${IMAGE_MK}"

# 追加新定义
cat >> "${IMAGE_MK}" << MK_EOF

define Device/${DEVICE_NAME}
  DEVICE_VENDOR := Cudy
  DEVICE_MODEL := TR3000
  DEVICE_VARIANT := v1 (512MB NAND)
  DEVICE_DTS := ${DTS_NEW}
  DEVICE_DTS_DIR := ../dts
  SUPPORTED_DEVICES += R47-512MB
  UBINIZE_OPTS := ${UBINIZE_OPTS}
  BLOCKSIZE := ${BLOCKSIZE}
  PAGESIZE := ${PAGESIZE}
  IMAGE_SIZE := ${IMAGE_SIZE}
  KERNEL_IN_UBI := 1
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  DEVICE_PACKAGES := ${DEVICE_PACKAGES}
endef
TARGET_DEVICES += ${DEVICE_NAME}
MK_EOF

# 强制在文件末尾添加空行，避免Makefile语法错误
echo "" >> "${IMAGE_MK}"
echo "✅ Makefile设备定义已写入"

# 步骤 3: 深度清理缓存并强制刷新Profile注册
echo "[3/4] 深度清理缓存并刷新Profile注册"
cd "${IB_DIR}"
rm -rf tmp/ .config staging_dir/host staging_dir/target-*
make defconfig 2>&1 | tee /tmp/defconfig.log
echo "✅ make defconfig 执行完成"

# 步骤 4: 静默验证Profile存在性
echo "[4/4] 验证Profile自动识别结果"
if make info 2>/dev/null | grep -q "${DEVICE_NAME}"; then
    echo "✅ Profile ${DEVICE_NAME} 已成功自动识别！"
    echo "============================================="
    echo "  适配全部完成，准备开始构建"
    echo "============================================="
else
    echo "❌ Profile识别失败，输出调试信息："
    echo "--- Makefile末尾内容 ---"
    tail -n 30 "${IMAGE_MK}"
    echo "--- defconfig日志 ---"
    cat /tmp/defconfig.log
    echo "--- DTS文件列表 ---"
    ls -l "${DTS_DIR}/${DTS_NEW}.dts"
    exit 1
fi
