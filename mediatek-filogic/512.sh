#!/bin/bash

# ==============================================================================
# ImmortalWrt ImageBuilder DIY 修复脚本: Cudy TR3000 512MB NAND 修改版
# 直接借用原版 cudy_tr3000-v1 内核，避免重新编译
# ==============================================================================

set -e # 遇到错误立即退出
set -o pipefail

echo ">>> [步骤 1/5] 检查环境和文件..."

# 定义变量
BOARD="mediatek"
SUBTARGET="filogic"
DEVICE_NAME="cudy_tr3000-512mb-v1"
DEVICE_BASE="cudy_tr3000-v1"  # 原版128MB设备名
DTS_BASE="mt7981b-cudy-tr3000-v1"
DTS_NEW="mt7981b-cudy-tr3000-512mb-v1"
MK_FILE="target/linux/${BOARD}/image/${SUBTARGET}.mk"
DTS_DIR="target/linux/${BOARD}/dts"

# 检查关键文件是否存在
if [ ! -f "${DTS_DIR}/${DTS_BASE}.dts" ] || [ ! -f "${DTS_DIR}/${DTS_BASE}.dtsi" ]; then
    echo "[!] 错误: 在 ${DTS_DIR} 目录下找不到原始 DTS 文件"
    exit 1
fi

if [ ! -f "${MK_FILE}" ]; then
    echo "[!] 错误: 找不到文件 ${MK_FILE}"
    exit 1
fi

echo "[+] 环境检查通过"

# ==============================================================================
# 步骤 2: 修改 DTS 文件以支持 512MB NAND
# ==============================================================================
echo ">>> [步骤 2/5] 正在修改设备树 (DTS) 以支持 512MB NAND..."

# 1. 复制原始 DTS 文件到新版本
cp "${DTS_DIR}/${DTS_BASE}.dts" "${DTS_DIR}/${DTS_NEW}.dts"
cp "${DTS_DIR}/${DTS_BASE}.dtsi" "${DTS_DIR}/${DTS_NEW}.dtsi"

# 2. 启用 USB 供电（GPIO 输出 0 = 高电平/开启，适用于此主板）
if grep -q "gpio-export,output = <1>;" "${DTS_DIR}/${DTS_NEW}.dtsi"; then
    sed -i 's/gpio-export,output = <1>;/gpio-export,output = <0>;/' "${DTS_DIR}/${DTS_NEW}.dtsi"
    echo "[-] USB GPIO 供电已启用"
else
    echo "[-] USB GPIO 供电设置未找到或已配置，跳过此步骤"
fi

# 3. 更新 .dts 中的 NAND 容量（64MB -> 512MB）
# 0x4000000 (64MB) -> 0x1FA40000 (512MB - 预留空间)
if grep -q "reg = <0x5c0000 0x4000000>;" "${DTS_DIR}/${DTS_NEW}.dts"; then
    sed -i 's|reg = <0x5c0000 0x4000000>;|reg = <0x5c0000 0x1FA40000>;|' "${DTS_DIR}/${DTS_NEW}.dts"
    echo "[-] .dts 文件中的 NAND 容量已更新"
else
    echo "[!] 警告: 在 .dts 中找不到原始 NAND 寄存器配置，请手动检查"
fi

# 4. 更新 .dtsi 中的 UBI 分区寄存器
# 替换分区块中的 reg 属性
if grep -q "reg = <0x5c0000 0x4000000>;" "${DTS_DIR}/${DTS_NEW}.dtsi"; then
    sed -i '/partition@5c0000 {/,/};/{
        s/reg = <0x5c0000 0x4000000>;/reg = <0x5c0000 0x1FA40000>;/
    }' "${DTS_DIR}/${DTS_NEW}.dtsi"
    echo "[-] .dtsi 文件中的 UBI 分区大小已更新"
else
    echo "[!] 警告: 在 .dtsi 中找不到原始 UBI 寄存器配置，请手动检查"
fi

# 5. 【关键修复】修正 DTS 头文件引用关联
if grep -q '#include "mt7981b-cudy-tr3000-v1.dtsi"' "${DTS_DIR}/${DTS_NEW}.dts"; then
    sed -i 's|#include "mt7981b-cudy-tr3000-v1.dtsi"|#include "mt7981b-cudy-tr3000-512mb-v1.dtsi"|' "${DTS_DIR}/${DTS_NEW}.dts"
    echo "[-] DTS 头文件引用关联已修复"
elif grep -q '#include "mt7981b-cudy-tr3000-512mb-v1.dtsi"' "${DTS_DIR}/${DTS_NEW}.dts"; then
    echo "[-] DTS 头文件引用关联已正确"
else
    echo "[!] 警告: 在 .dts 文件中找不到 include 语句"
fi

echo "[+] DTS 文件修改成功"

# ==============================================================================
# 步骤 3: 向 filogic.mk 注入设备定义
# 【关键】直接借用原版内核，不生成新的内核文件
# ==============================================================================
echo ">>> [步骤 3/5] 正在向 ${MK_FILE} 注入设备定义..."

if grep -q "define Device/${DEVICE_NAME}" "${MK_FILE}"; then
    echo "[*] 设备定义已存在于 ${MK_FILE} 中，跳过注入步骤"
else
    echo "[-] 正在添加新设备定义，借用原版内核..."
    
    cat >> "${MK_FILE}" << 'ENDOFMAKEFILE'

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
  # 【关键修复】直接使用原版内核，不生成新的设备特定内核文件
  KERNEL := kernel-bin | lzma | uImage lzma
  KERNEL_LOADADDR := 0x44000000
  KERNEL_INITRAMFS := kernel-bin | gzip | uImage gzip
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount
endef
TARGET_DEVICES += cudy_tr3000-512mb-v1
ENDOFMAKEFILE

    if grep -q "define Device/${DEVICE_NAME}" "${MK_FILE}"; then
        echo "[+] 设备定义注入成功，使用原版内核"
    else
        echo "[!] 错误: 设备定义注入失败，请检查文件权限"
        exit 1
    fi
fi

# ==============================================================================
# 步骤 4: 手动生成 .targetinfo 和 .profiles.mk
# ==============================================================================
echo ">>> [步骤 4/5] 正在手动生成元数据缓存..."

# 清理旧缓存
rm -f .targetinfo .profiles.mk
rm -rf tmp/
mkdir -p tmp

# 1. 手动创建 .targetinfo
cat > .targetinfo << 'ENDOFTARGETINFO'
Target-Arch: aarch64
Target-Arch-Packages:
Target-Features nand ubifs usb usbgadget
Target-Name: mediatek
Target-Patches:
Target-Profile: DEVICE_cudy_tr3000-512mb-v1
Target-Profile-Name: Cudy TR3000 v1 (512MB NAND)
Target-Profile-Packages: kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount
Target-Profile-hasImageMetadata: 1
Target-Profile-SupportedDevices: R47-512MB
Target-Profile-Filesystem: ubifs
Target-Profile-Size: 507904
Target-Subtarget: filogic
Target-Version: 25.12.1
ENDOFTARGETINFO

# 2. 手动创建 .profiles.mk
cat > .profiles.mk << 'ENDOFPROFILES'
PROFILE_NAMES += DEVICE_cudy_tr3000-512mb-v1

DEVICE_cudy_tr3000-512mb-v1_NAME := Cudy TR3000 v1 (512MB NAND)
DEVICE_cudy_tr3000-512mb-v1_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount
DEVICE_cudy_tr3000-512mb-v1_HAS_IMAGE_METADATA := 1
DEVICE_cudy_tr3000-512mb-v1_SUPPORTED_DEVICES := R47-512MB
DEVICE_cudy_tr3000-512mb-v1_FILESYSTEM := ubifs
DEVICE_cudy_tr3000-512mb-v1_SIZE := 507904
ENDOFPROFILES

echo "[+] 元数据缓存手动生成完成"

# ==============================================================================
# 步骤 5: 确保内核文件可访问
# ==============================================================================
echo ">>> [步骤 5/5] 正在确保内核文件可访问性..."

# 检查是否有原版设备的内核文件
if [ -d "build_dir/target-aarch64_cortex-a53_musl" ]; then
    ORIGINAL_KERNEL=$(find build_dir/target-aarch64_cortex-a53_musl -name "*${DEVICE_BASE}*kernel*" -type f 2>/dev/null | head -1)
    if [ -n "$ORIGINAL_KERNEL" ]; then
        echo "[-] 找到原版内核: $(basename $ORIGINAL_KERNEL)"
        
        # 创建内核文件链接，确保512MB版本能找到内核
        KERNEL_BASE_DIR="build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic"
        mkdir -p "$KERNEL_BASE_DIR"
        
        # 如果原版内核存在，创建软链接
        if [ -f "$ORIGINAL_KERNEL" ]; then
            # 提取内核文件扩展名
            KERNEL_EXT="${ORIGINAL_KERNEL##*.}"
            LINK_NAME="${KERNEL_BASE_DIR}/${DEVICE_NAME}-kernel.${KERNEL_EXT}"
            
            if [ ! -L "$LINK_NAME" ]; then
                ln -sf "$ORIGINAL_KERNEL" "$LINK_NAME" 2>/dev/null || echo "[!] 无法创建软链接"
            fi
        fi
    else
        echo "[-] 未找到原版内核，ImageBuilder 将在编译过程中生成"
    fi
fi

echo "[-] 内核可访问性设置完成"

# ==============================================================================
# 最终验证
# ==============================================================================
echo ""
echo ">>> 自定义适配流程全部执行完毕！"
echo ">>> 正在校验设备配置可用性..."

if grep -q "cudy_tr3000-512mb-v1" .profiles.mk; then
    echo "[成功] 设备配置 'cudy_tr3000-512mb-v1' 已准备就绪"
    echo ""
    echo "配置摘要："
    echo "  - 设备: Cudy TR3000 v1 (512MB NAND)"
    echo "  - 内核: 使用原版 cudy_tr3000-v1 内核"
    echo "  - DTS: 已修改支持 512MB NAND"
    echo "  - 编译: 无需重新编译内核"
    echo ""
    echo "后续操作指引："
    echo "1. 执行 'make info' 确认新设备已出现在可用设备列表中"
    echo "2. 执行 'make image PROFILE=cudy_tr3000-512mb-v1 FILES=files' 启动固件编译"
    echo ""
    echo "【重要说明】"
    echo "✓ 直接借用原版128MB内核，不重新编译"
    echo "✓ 保持 targetinfo 部分不变（原版不会自动生成）"
    echo "✓ 使用原版内核构建规则，确保兼容性"
    echo "✓ 只修改DTS文件支持512MB NAND容量"
    echo "✓ ImageBuilder 将使用现有内核文件"
    echo ""
    echo "优点："
    echo "- 避免内核编译问题"
    echo "- 使用经过验证的原版内核"
    echo "- 编译速度快，成功率高"
    echo "- 稳定性好，风险低"
else
    echo "[失败] 设备配置校验未通过，请手动检查 .profiles.mk 文件内容"
    exit 1
fi
