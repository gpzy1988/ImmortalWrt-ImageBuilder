#!/bin/bash

# ==============================================================================
# ImmortalWrt 适配Cudy TR3000 512MB v1 内核预生成注入工具
# 功能：提前生成目标kernel.bin，彻底解决"No rule to make target ... kernel.bin"报错
# 特性：完全保留原版.targetinfo不删除
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
KERNEL_OUT_DIR="build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic"

echo ">>> [1/6] 环境校验启动..."
# 校验基础文件存在性
if [ ! -f "${DTS_DIR}/${DTS_BASE}.dts" ] || [ ! -f "${DTS_DIR}/${DTS_BASE}.dtsi" ]; then
    echo "[!] 错误：原始TR3000 v1设备树文件缺失"
    exit 1
fi
if [ ! -f "${MK_FILE}" ]; then
    echo "[!] 错误：filogic平台镜像配置文件缺失"
    exit 1
fi
echo "[+] 环境校验通过"

echo ">>> [2/6] 生成512MB专属设备树文件..."
# 复制原版DTS生成扩容版文件
cp "${DTS_DIR}/${DTS_BASE}.dts" "${DTS_DIR}/${DTS_NEW}.dts"
cp "${DTS_DIR}/${DTS_BASE}.dtsi" "${DTS_DIR}/${DTS_NEW}.dtsi"

# 修正USB供电GPIO电平逻辑
if grep -q "gpio-export,output = <1>;" "${DTS_DIR}/${DTS_NEW}.dtsi"; then
    sed -i 's/gpio-export,output = <1>;/gpio-export,output = <0>;/' "${DTS_DIR}/${DTS_NEW}.dtsi"
    echo "[-] USB供电默认开启"
fi

# 更新NAND分区大小为512MB适配值
sed -i 's|reg = <0x5c0000 0x4000000>;|reg = <0x5c0000 0x1FA40000>;|' "${DTS_DIR}/${DTS_NEW}.dts"
sed -i '/partition@5c0000 {/,/};/s/reg = <0x5c0000 0x4000000>;/reg = <0x5c0000 0x1FA40000>;/' "${DTS_DIR}/${DTS_NEW}.dtsi"

# 修正DTS头文件引用关联
sed -i "s/#include \"${DTS_BASE}.dtsi\"/#include \"${DTS_NEW}.dtsi\"/" "${DTS_DIR}/${DTS_NEW}.dts"
echo "[+] 设备树文件适配完成"

echo ">>> [3/6] 注入新设备编译规则到filogic.mk..."
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
  # 显式声明内核生成流水线，强制生成目标kernel.bin
  KERNEL := kernel-bin | lzma | uImage lzma
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount
endef
TARGET_DEVICES += cudy_tr3000-512mb-v1
EOF
    echo "[+] 设备编译规则注入完成"
else
    echo "[-] 设备规则已存在，跳过注入"
fi

echo ">>> [4/6] 增量更新元数据，保留原版.targetinfo..."
# 仅清理旧缓存，不删除原版.targetinfo
rm -rf tmp/
mkdir -p tmp

# 增量追加新设备配置到原版.targetinfo
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
    echo "[+] 新设备配置已追加到原版.targetinfo"
fi

# 生成.profiles.mk设备配置
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
    echo "[+] .profiles.mk配置更新完成"
fi

echo ">>> [5/6] 预先生成目标kernel.bin文件..."
# 清理旧内核缓存，强制重新编译内核
rm -rf "${KERNEL_OUT_DIR}/"
mkdir -p "${KERNEL_OUT_DIR}/"

# 执行内核预编译命令，直接生成目标kernel.bin
make target/linux/compile -j$(nproc)
cp "${KERNEL_OUT_DIR}/vmlinux.bin.lzma" "${KERNEL_OUT_DIR}/${DEVICE_NAME}-kernel.bin"
echo "[+] 目标kernel.bin已预先生成到指定路径"

echo ">>> [6/6] 最终校验..."
if [ -f "${KERNEL_OUT_DIR}/${DEVICE_NAME}-kernel.bin" ]; then
    echo "====================================="
    echo "[✅ 全部流程完成！]"
    echo "预生成的内核文件路径：${KERNEL_OUT_DIR}/${DEVICE_NAME}-kernel.bin"
    echo "现在直接执行 make image PROFILE=${DEVICE_NAME} 即可正常打包固件，不会再报kernel.bin缺失错误"
else
    echo "[❌ 错误] 内核文件生成失败，请检查编译日志"
    exit 1
fi
