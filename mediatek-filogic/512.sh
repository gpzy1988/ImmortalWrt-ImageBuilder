#!/bin/bash

# ==============================================================================
# 脚本名称: fix_cudy_tr3000_512mb.sh
# 功能描述: 为 ImmortalWrt/OpenWrt 源码添加 Cudy TR3000 512MB v1 支持
#           重点修复 "No rule to make target ... kernel.bin" 编译错误
# 适用版本: ImmortalWrt 23.05 / 24.10 / 25.12 (Mediatek Filogic 平台)
# ==============================================================================

set -e
set -o pipefail

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}>>> 开始配置 Cudy TR3000 512MB v1 编译环境...${NC}"

# --------------------------
# 1. 环境变量与路径检查
# --------------------------
BOARD="mediatek"
SUBTARGET="filogic"
DEVICE_ID="cudy_tr3000-512mb-v1"
DTS_BASE="mt7981b-cudy-tr3000-v1"
DTS_NEW="mt7981b-cudy_tr3000-512mb-v1"
MK_FILE="target/linux/${BOARD}/image/${SUBTARGET}.mk"
DTS_DIR="target/linux/${BOARD}/dts"

# 检查是否在源码根目录
if [ ! -f "Makefile" ] || [ ! -d "target/linux" ]; then
    echo -e "${RED}[错误] 请在 OpenWrt/ImmortalWrt 源码根目录下运行此脚本！${NC}"
    exit 1
fi

# 检查基础文件是否存在
if [ ! -f "${DTS_DIR}/${DTS_BASE}.dts" ]; then
    echo -e "${RED}[错误] 未找到基础设备树文件: ${DTS_DIR}/${DTS_BASE}.dts${NC}"
    echo -e "${YELLOW}提示: 请确保你的源码中已包含 Cudy TR3000 v1 的基础支持。${NC}"
    exit 1
fi

echo -e "${GREEN}[OK] 环境检查通过${NC}"

# --------------------------
# 2. 创建/更新设备树文件 (DTS)
# --------------------------
echo -e "${GREEN}>>> [步骤 1/3] 生成 512MB 专用设备树文件...${NC}"

# 复制并生成新的 DTS 文件
cp "${DTS_DIR}/${DTS_BASE}.dts" "${DTS_DIR}/${DTS_NEW}.dts"
cp "${DTS_DIR}/${DTS_BASE}.dtsi" "${DTS_DIR}/${DTS_NEW}.dtsi"

# 修改 DTS 中的 include 引用，指向新的 dtsi
sed -i "s|#include \"${DTS_BASE}.dtsi\"|#include \"${DTS_NEW}.dtsi\"|g" "${DTS_DIR}/${DTS_NEW}.dts"

# 修改 DTSI 中的 Flash 分区大小
# 原值通常为 0x4000000 (64MB) 或 0x8000000 (128MB)
# 512MB NAND 可用空间约为 0x1FA40000 (需预留 OOB 和坏块管理空间，具体视 UBI 配置而定)
# 这里我们将主要数据分区扩大以适配 512MB
if grep -q "reg = <0x5c0000 0x" "${DTS_DIR}/${DTS_NEW}.dtsi"; then
    # 注意：不同版本源码偏移量可能不同，此处针对常见 Filogic 布局进行替换
    # 将原来的 size 替换为更大的值 (例如 0x1FA40000)
    sed -i 's/reg = <0x5c0000 0x[0-9a-fA-F]*>;/reg = <0x5c0000 0x1FA40000>;/' "${DTS_DIR}/${DTS_NEW}.dtsi"
    echo -e "${GREEN}[OK] 已更新 DTSI 中的 Flash 分区大小为 512MB 适配值${NC}"
else
    echo -e "${YELLOW}[警告] 未在 DTSI 中找到标准的 reg 定义，请手动检查 ${DTS_DIR}/${DTS_NEW}.dtsi${NC}"
fi

echo -e "${GREEN}[OK] 设备树文件生成完毕${NC}"

# --------------------------
# 3. 注入 Image 编译规则 (关键步骤)
# --------------------------
echo -e "${GREEN}>>> [步骤 2/3] 注入编译规则到 ${MK_FILE}...${NC}"

# 检查是否已经存在该设备定义，避免重复注入
if grep -q "define Device/${DEVICE_ID}" "${MK_FILE}"; then
    echo -e "${YELLOW}[提示] 设备定义已存在，跳过注入步骤。${NC}"
else
    cat >> "${MK_FILE}" <<EOF

# ---------------------------------------------------------
# Added by fix_cudy_512mb.sh for Cudy TR3000 512MB v1
# ---------------------------------------------------------
define Device/${DEVICE_ID}
  DEVICE_VENDOR := Cudy
  DEVICE_MODEL := TR3000
  DEVICE_VARIANT := v1 (512MB NAND)
  DEVICE_DTS := ${DTS_NEW}
  DEVICE_DTS_DIR := ../dts
  SUPPORTED_DEVICES += cudy,tr3000-v1-512m
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 507904k
  KERNEL_IN_UBI := 1
  # 【核心修复】显式定义 KERNEL 生成规则，解决 "No rule to make target ... kernel.bin" 错误
  KERNEL := kernel-bin | lzma | uImage lzma
  KERNEL_DEPENDS := \$(LINUX_DIR)/arch/\$(LINUX_KARCH)/boot/dts/\$(DEVICE_DTS).dtb
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount
endef
TARGET_DEVICES += ${DEVICE_ID}
EOF
    echo -e "${GREEN}[OK] 编译规则注入成功${NC}"
fi

# --------------------------
# 4. 清理构建缓存
# --------------------------
echo -e "${GREEN}>>> [步骤 3/3] 清理旧的内核构建缓存...${NC}"

# 必须清理 build_dir 中的 linux 编译中间文件，否则 make 会认为内核已编译过而跳过
# 这会导致新的 DTS 不生效，且 kernel.bin 不会重新生成
rm -rf build_dir/target-aarch64*/linux-mediatek_filogic/
rm -rf build_dir/target-arm*/linux-mediatek_filogic/

echo -e "${GREEN}[OK] 缓存清理完毕${NC}"

# --------------------------
# 5. 完成提示
# --------------------------
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} 配置完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "接下来请执行以下命令开始编译："
echo -e "${YELLOW}make menuconfig${NC}  (确保选中 Target: MediaTek Filogic, Device: Cudy TR3000 v1 (512MB NAND))"
echo -e "${YELLOW}make -j\$(nproc)${NC}   (开始编译)"
echo ""
echo -e "如果仍然报错，请尝试先执行: ${YELLOW}make target/linux/clean${NC}"
echo ""
