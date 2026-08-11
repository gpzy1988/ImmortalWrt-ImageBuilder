#!/bin/bash
# ==============================================================================
# ImmortalWrt ImageBuilder 引用源码编译Cudy TR3000 512MB v1适配内核脚本
# 特性：直接编译源码生成适配512MB分区的专属内核，保留原版.targetinfo
# ==============================================================================

set -e
set -o pipefail

# 全局变量定义
BOARD="mediatek"
SUBTARGET="filogic"
DEVICE_NAME="cudy_tr3000-512mb-v1"
DTS_BASE="mt7981b-cudy-tr3000-v1"
DTS_NEW="mt7981b-cudy-tr3000-512mb-v1"
MK_FILE="target/linux/${BOARD}/image/${SUBTARGET}.mk"
DTS_DIR="target/linux/${BOARD}/dts"
KERNEL_BUILD_DIR="build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic"

echo ">>> [1/7] 校验内核源码完整性..."
if [ ! -d "${KERNEL_BUILD_DIR}/arch/arm64/boot/dts/mediatek" ]; then
    echo "[!] 错误：内核源码未正确解压到指定目录，请先执行前置准备步骤"
    exit 1
fi
echo "[+] 内核源码校验通过"

echo ">>> [2/7] 生成512MB专属设备树文件并同步到内核源码目录..."
# 生成适配512MB的设备树文件
cp "${DTS_DIR}/${DTS_BASE}.dts" "${DTS_DIR}/${DTS_NEW}.dts"
cp "${DTS_DIR}/${DTS_BASE}.dtsi" "${DTS_DIR}/${DTS_NEW}.dtsi"
# 修正USB供电GPIO电平逻辑
sed -i 's/gpio-export,output = <1>;/gpio-export,output = <0>;/' "${DTS_DIR}/${DTS_NEW}.dtsi"
# 更新NAND分区大小为512MB适配值
sed -i 's|reg = <0x5c0000 0x4000000>;|reg = <0x5c0000 0x1FA40000>;|' "${DTS_DIR}/${DTS_NEW}.dts"
sed -i '/partition@5c0000 {/,/};/s/reg = <0x5c0000 0x4000000>;/reg = <0x5c0000 0x1FA40000>;/' "${DTS_DIR}/${DTS_NEW}.dtsi"
# 修正DTS头文件引用关联
sed -i "s/#include \"${DTS_BASE}.dtsi\"/#include \"${DTS_NEW}.dtsi\"/" "${DTS_DIR}/${DTS_NEW}.dts"
# 将新生成的设备树同步到内核源码的DTS目录，确保编译时能找到
cp "${DTS_DIR}/${DTS_NEW}.dts" "${KERNEL_BUILD_DIR}/arch/arm64/boot/dts/mediatek/"
cp "${DTS_DIR}/${DTS_NEW}.dtsi" "${KERNEL_BUILD_DIR}/arch/arm64/boot/dts/mediatek/"
echo "[+] 512MB专属设备树已同步到内核源码目录"

echo ">>> [3/7] 注入新设备编译规则到filogic.mk..."
if ! grep -q "define Device/${DEVICE_NAME}" "${MK_FILE}"; then
    cat >> "${MK_FILE}" << 'EOF'

define Device/cudy_tr3000-512mb-v1
  DEVICE_VENDOR := Cudy
  DEVICE_MODEL := TR3000
  DEVICE_VARIANT := v1 (512MB NAND)
  DEVICE_DTS := mt7981b-cudy-tr3000-512mb-v1
  DEVICE_DTS_DIR := ../dts
  SUPPORTED_DEVICES += R47-512MB
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 507904k
  KERNEL_IN_UBI := 1
  KERNEL := kernel-bin | lzma | uImage lzma
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount
endef
TARGET_DEVICES += cudy_tr3000-512mb-v1
EOF
    echo "[+] 设备编译规则注入完成"
fi

echo ">>> [4/7] 增量更新元数据，保留原版.targetinfo..."
rm -rf tmp/ && mkdir -p tmp
# 仅增量追加新设备配置，不删除原版.targetinfo原有内容
if ! grep -q "Target-Profile: DEVICE_${DEVICE_NAME}" .targetinfo; then
    cat >> .targetinfo << 'EOF'
Target-Profile: DEVICE_cudy_tr3000-512mb-v1
Target-Profile-Name: Cudy TR3000 v1 (512MB NAND)
Target-Profile-Packages: kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount
Target-Profile-hasImageMetadata: 1
Target-Profile-SupportedDevices: R47-512MB
Target-Profile-Filesystem: ubifs
Target-Profile-Size: 507904
EOF
fi
# 更新.profiles.mk设备配置
if ! grep -q "DEVICE_${DEVICE_NAME}" .profiles.mk 2>/dev/null; then
    cat >> .profiles.mk << 'EOF'
PROFILE_NAMES += DEVICE_cudy_tr3000-512mb-v1

DEVICE_cudy_tr3000-512mb-v1_NAME := Cudy TR3000 v1 (512MB NAND)
DEVICE_cudy_tr3000-512mb-v1_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount
DEVICE_cudy_tr3000-512mb-v1_HAS_IMAGE_METADATA := 1
DEVICE_cudy_tr3000-512mb-v1_SUPPORTED_DEVICES := R47-512MB
DEVICE_cudy_tr3000-512mb-v1_FILESYSTEM := ubifs
DEVICE_cudy_tr3000-512mb-v1_SIZE := 507904
EOF
fi
echo "[+] 元数据增量更新完成"

echo ">>> [5/7] 配置内核编译环境..."
# 复用ImageBuilder自带的内核配置文件，避免重复配置
cp "build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic/.config" "${KERNEL_BUILD_DIR}/.config"
make -C "${KERNEL_BUILD_DIR}" olddefconfig
echo "[+] 内核编译环境配置完成"

echo ">>> [6/7] 引用源码编译适配内核..."
# 直接编译内核源码，生成适配512MB设备树的vmlinux
make -C "${KERNEL_BUILD_DIR}" -j$(nproc)
# 按ImageBuilder规则生成目标kernel.bin
cd "${KERNEL_BUILD_DIR}"
lzma -f -k arch/arm64/boot/Image
mkimage -A aarch64 -O linux -T kernel -C lzma \
    -a 0x40080000 -e 0x40080000 \
    -n "ImmortalWrt Linux-5.15" \
    -d arch/arm64/boot/Image.lzma "${DEVICE_NAME}-kernel.bin"
cd -
echo "[+] 源码编译适配内核完成"

echo ">>> [7/7] 最终校验..."
if [ -f "${KERNEL_BUILD_DIR}/${DEVICE_NAME}-kernel.bin" ]; then
    echo "====================================="
    echo "[✅ 内核源码编译全部完成！]"
    echo "生成的适配内核路径：${KERNEL_BUILD_DIR}/${DEVICE_NAME}-kernel.bin"
    echo "现在直接执行 make image PROFILE=cudy_tr3000-512mb-v1 即可正常打包固件"
else
    echo "[❌ 错误] 适配内核生成失败，请检查编译日志"
    exit 1
fi
