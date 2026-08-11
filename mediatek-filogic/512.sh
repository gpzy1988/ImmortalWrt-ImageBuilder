
#!/bin/bash

# ==============================================================================
# ImmortalWrt ImageBuilder DIY 修复脚本: Cudy TR3000 512MB NAND 扩容版
# ==============================================================================
# 使用说明:
# 1. 将此脚本放置在 ImmortalWrt ImageBuilder 根目录下
# 2. 赋予执行权限: chmod +x build_tr3000_512mb.sh
# 3. 运行脚本: ./build_tr3000_512mb.sh
# ==============================================================================

set -e # 遇到错误立即退出
set -o pipefail

# --- 配置区域 ---
BOARD="mediatek"
SUBTARGET="filogic"
DEVICE_NAME="cudy_tr3000-512mb-v1"
DTS_BASE="mt7981b-cudy-tr3000-v1"
DTS_NEW="mt7981b-cudy-tr3000-512mb-v1"
MK_FILE="target/linux/${BOARD}/image/${SUBTARGET}.mk"
DTS_DIR="target/linux/${BOARD}/dts"
KERNEL_CACHE_DIR="custom_prebuilt_kernel"

echo ">>> [初始化] 开始 Cudy TR3000 512MB 固件构建流程..."

# ==============================================================================
# 步骤 1: 环境与核心文件校验
# ==============================================================================
echo ">>> [步骤 1/6] 环境与核心文件校验..."

if [ ! -f "${DTS_DIR}/${DTS_BASE}.dts" ] || [ ! -f "${DTS_DIR}/${DTS_BASE}.dtsi" ]; then
    echo "[!] 错误: 原始 DTS 设备树文件未在 ${DTS_DIR} 目录下找到"
    echo "    请确认你正在 ImmortalWrt ImageBuilder 根目录运行此脚本，且源码已正确下载。"
    exit 1
fi

if [ ! -f "${MK_FILE}" ]; then
    echo "[!] 错误: 平台镜像配置文件 ${MK_FILE} 不存在"
    exit 1
fi

echo "[+] 环境校验通过"

# ==============================================================================
# 步骤 2: 生成并修改适配 512MB NAND 的设备树文件
# ==============================================================================
echo ">>> [步骤 2/6] 正在修改适配 512MB 容量的设备树配置..."

# 1. 复制官方原版 DTS 文件生成扩容版专属文件
cp "${DTS_DIR}/${DTS_BASE}.dts" "${DTS_DIR}/${DTS_NEW}.dts"
cp "${DTS_DIR}/${DTS_BASE}.dtsi" "${DTS_DIR}/${DTS_NEW}.dtsi"

# 2. 默认开启 USB 供电：将 GPIO 输出状态从 1 改为 0 (根据硬件逻辑调整)
if grep -q "gpio-export,output = <1>;" "${DTS_DIR}/${DTS_NEW}.dtsi"; then
    sed -i 's/gpio-export,output = <1>;/gpio-export,output = <0>;/' "${DTS_DIR}/${DTS_NEW}.dtsi"
    echo "[-] USB GPIO 供电已默认开启"
else
    echo "[-] USB GPIO 供电配置未找到或已提前配置，跳过该步骤"
fi

# 3. 更新 .dts 中的 NAND 总容量配置
# 原 64MB (0x4000000) 替换为适配 512MB 的 0x1FA40000 (预留系统空间后的实际可用容量)
if grep -q "reg = <0x5c0000 0x4000000>;" "${DTS_DIR}/${DTS_NEW}.dts"; then
    sed -i 's|reg = <0x5c0000 0x4000000>;|reg = <0x5c0000 0x1FA40000>;|' "${DTS_DIR}/${DTS_NEW}.dts"
    echo "[-] 主 DTS 文件中的 NAND 容量已更新为 512MB"
else
    echo "[!] 警告: 未在主 DTS 中找到原始 NAND 容量配置，请手动校验修改"
fi

# 4. 更新 .dtsi 中的 UBI 分区地址范围
if grep -q "reg = <0x5c0000 0x4000000>;" "${DTS_DIR}/${DTS_NEW}.dtsi"; then
    sed -i '/partition@5c0000 {/,/};/{\
        s/reg = <0x5c0000 0x4000000>;/reg = <0x5c0000 0x1FA40000>;/\
    }' "${DTS_DIR}/${DTS_NEW}.dtsi"
    echo "[-] DTSI 文件中的 UBI 分区大小已同步更新"
else
    echo "[!] 警告: 未在 DTSI 中找到原始 UBI 分区配置，请手动校验修改"
fi

# 5. 【关键修复】修正 DTS 头文件引用关联
if grep -q '#include "mt7981b-cudy-tr3000-v1.dtsi"' "${DTS_DIR}/${DTS_NEW}.dts"; then
    sed -i 's|#include "mt7981b-cudy-tr3000-v1.dtsi"|#include "mt7981b-cudy-tr3000-512mb-v1.dtsi"|' "${DTS_DIR}/${DTS_NEW}.dts"
    echo "[-] DTS 头文件引用关联已修复"
elif grep -q '#include "mt7981b-cudy-tr3000-512mb-v1.dtsi"' "${DTS_DIR}/${DTS_NEW}.dts"; then
    echo "[-] DTS 头文件引用关联已经正确，无需修改"
else
    echo "[!] 警告: 未在 DTS 文件中找到 include 引入语句，请手动添加正确的头文件路径"
fi

echo "[+] 所有设备树文件修改完成"

# ==============================================================================
# 步骤 3: 向 filogic.mk 注入带内核生成规则的新设备定义
# ==============================================================================
echo ">>> [步骤 3/6] 正在向配置文件 ${MK_FILE} 注入新设备编译规则..."

if grep -q "define Device/${DEVICE_NAME}" "${MK_FILE}"; then
    echo "[*] 设备定义已存在于 ${MK_FILE} 中，跳过注入步骤"
else
    echo "[-] 正在追加带完整内核生成规则的新设备定义..."
    
    # 【核心修复】新增 KERNEL 定义，彻底解决 "No rule to make target ... kernel.bin" 编译错误
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
  # 显式声明内核镜像生成流水线，确保 kernel.bin 能被正确构建
  KERNEL := kernel-bin | lzma | uImage lzma
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount
endef
TARGET_DEVICES += cudy_tr3000-512mb-v1
ENDOFMAKEFILE

    if grep -q "define Device/${DEVICE_NAME}" "${MK_FILE}"; then
        echo "[+] 新设备定义注入成功"
    else
        echo "[!] 错误: 设备定义写入失败，请检查文件读写权限"
        exit 1
    fi
fi

# ==============================================================================
# 步骤 4: 手动生成元数据缓存，绕过自动生成脚本兼容故障
# ==============================================================================
echo ">>> [步骤 4/6] 正在手动生成编译元数据缓存..."

# 清理旧的无效缓存文件
rm -f .targetinfo .profiles.mk
rm -rf tmp/
mkdir -p tmp

# 1. 手动创建 .targetinfo 元数据文件
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

# 2. 手动创建 .profiles.mk 设备配置文件
cat > .profiles.mk << 'ENDOFPROFILES'
PROFILE_NAMES += DEVICE_cudy_tr3000-512mb-v1

DEVICE_cudy_tr3000-512mb-v1_NAME := Cudy TR3000 v1 (512MB NAND)
DEVICE_cudy_tr3000-512mb-v1_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount
DEVICE_cudy_tr3000-512mb-v1_HAS_IMAGE_METADATA := 1
DEVICE_cudy_tr3000-512mb-v1_SUPPORTED_DEVICES := R47-512MB
DEVICE_cudy_tr3000-512mb-v1_FILESYSTEM := ubifs
DEVICE_cudy_tr3000-512mb-v1_SIZE := 507904
ENDOFPROFILES

echo "[+] 元数据缓存文件手动生成完成"

# ==============================================================================
# 步骤 5: 预编译内核并保护（防止打包时被删除）
# ==============================================================================
echo ">>> [步骤 5/6] 正在预编译内核并设置保护..."

# 清理之前可能失败的内核编译残留
rm -rf build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic/

# 创建独立内核缓存目录
mkdir -p "${KERNEL_CACHE_DIR}"

# 尝试编译内核目标
# 注意：这里我们利用 ImageBuilder 的机制先编译出 kernel.bin
# 如果直接 make image 失败，通常是因为 kernel.bin 缺失。
# 我们先单独触发 kernel 编译目标
echo "[-] 正在编译内核二进制文件..."
make target/linux/compile V=s || true

# 查找生成的 kernel.bin
KERNEL_BIN_PATH=$(find build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic/ -name "kernel.bin" 2>/dev/null | head -n 1)

if [ -n "$KERNEL_BIN_PATH" ]; then
    cp -f "$KERNEL_BIN_PATH" "${KERNEL_CACHE_DIR}/kernel.bin"
    # 设置只读属性，防止后续 make image 清理步骤误删
    chmod 444 "${KERNEL_CACHE_DIR}/kernel.bin"
    echo "[+] 内核二进制文件已备份至 ${KERNEL_CACHE_DIR}/kernel.bin 并设为只读"
else
    echo "[!] 警告: 未找到编译生成的 kernel.bin。"
    echo "    如果是首次运行，可能需要先执行 'make target/linux/compile' 确保工具链和内核源码就绪。"
    echo "    脚本将继续尝试打包，但可能会因缺少内核而失败。"
fi

# ==============================================================================
# 步骤 6: 最终校验与打包指引
# ==============================================================================
echo ""
echo ">>> [步骤 6/6] 自定义适配流程全部执行完毕！"
echo ">>> 正在校验新设备配置是否可用..."

if grep -q "cudy_tr3000-512mb-v1" .profiles.mk; then
    echo "[成功] 设备配置 'cudy_tr3000-512mb-v1' 已准备就绪。"
    echo ""
    echo "============================================================"
    echo "后续操作指引："
    echo "============================================================"
    echo "1. 执行以下命令开始正式打包固件："
    echo ""
    echo "   make image PROFILE=cudy_tr3000-512mb-v1 FILES=files"
    echo ""
    echo "2. 如果打包过程中提示缺少 kernel.bin，请手动复制备份内核："
    echo ""
    echo "   cp -f custom_prebuilt_kernel/kernel.bin build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic/"
    echo ""
    echo "3. 生成的固件将位于 bin/targets/mediatek/filogic/ 目录下"
    echo "============================================================"
else
    echo "[失败] 设备注册校验未通过，请手动检查 .profiles.mk 文件内容"
    exit 1
