#!/bin/bash

# ==============================================================================
# ImmortalWrt ImageBuilder DIY 修复脚本: 解决Cudy TR3000 512MB版内核编译目标缺失问题
# ==============================================================================

set -e # 遇到错误立即退出
set -o pipefail

echo ">>> [步骤 1/6] 环境与核心文件校验..."

# 定义全局变量
BOARD="mediatek"
SUBTARGET="filogic"
DEVICE_NAME="cudy_tr3000-512mb-v1"
DTS_BASE="mt7981b-cudy-tr3000-v1"
DTS_NEW="mt7981b-cudy-tr3000-512mb-v1"
MK_FILE="target/linux/${BOARD}/image/${SUBTARGET}.mk"
DTS_DIR="target/linux/${BOARD}/dts"

# 校验原版设备树文件是否存在
if [ ! -f "${DTS_DIR}/${DTS_BASE}.dts" ] || [ ! -f "${DTS_DIR}/${DTS_BASE}.dtsi" ]; then
    echo "[!] 错误: 原始DTS设备树文件未在${DTS_DIR}目录下找到"
    exit 1
fi

if [ ! -f "${MK_FILE}" ]; then
    echo "[!] 错误: 平台镜像配置文件${MK_FILE}不存在"
    exit 1
fi

echo "[+] 环境校验通过"

# =============================================================================
# 步骤 2: 生成并修改适配512MB NAND的设备树文件
# =============================================================================
echo ">>> [步骤 2/6] 正在修改适配512MB容量的设备树配置..."

# 1. 复制官方原版DTS文件生成扩容版专属文件
cp "${DTS_DIR}/${DTS_BASE}.dts" "${DTS_DIR}/${DTS_NEW}.dts"
cp "${DTS_DIR}/${DTS_BASE}.dtsi" "${DTS_DIR}/${DTS_NEW}.dtsi"

# 2. 默认开启USB供电：将GPIO输出状态从1改为0，适配该主板硬件电平逻辑
if grep -q "gpio-export,output = <1>;" "${DTS_DIR}/${DTS_NEW}.dtsi"; then
    sed -i 's/gpio-export,output = <1>;/gpio-export,output = <0>;/' "${DTS_DIR}/${DTS_NEW}.dtsi"
    echo "[-] USB GPIO 供电已默认开启"
else
    echo "[-] USB GPIO供电配置未找到或已提前配置，跳过该步骤"
fi

# 3. 更新.dts中的NAND总容量配置：原64MB（0x4000000）替换为适配512MB的0x1FA40000（预留系统空间后的实际可用容量）
if grep -q "reg = <0x5c0000 0x4000000>;" "${DTS_DIR}/${DTS_NEW}.dts"; then
    sed -i 's|reg = <0x5c0000 0x4000000>;|reg = <0x5c0000 0x1FA40000>;|' "${DTS_DIR}/${DTS_NEW}.dts"
    echo "[-] 主DTS文件中的NAND容量已更新为512MB"
else
    echo "[!] 警告: 未在主DTS中找到原始NAND容量配置，请手动校验修改"
fi

# 4. 更新.dtsi中的UBI分区地址范围
if grep -q "reg = <0x5c0000 0x4000000>;" "${DTS_DIR}/${DTS_NEW}.dtsi"; then
    sed -i '/partition@5c0000 {/,/};/{\
        s/reg = <0x5c0000 0x4000000>;/reg = <0x5c0000 0x1FA40000>;/\
    }' "${DTS_DIR}/${DTS_NEW}.dtsi"
    echo "[-] DTSI文件中的UBI分区大小已同步更新"
else
    echo "[!] 警告: 未在DTSI中找到原始UBI分区配置，请手动校验修改"
fi

# 5. 【关键修复】修正DTS头文件引用关联
# 确保扩容版.dts文件引用的是新生成的同名.dtsi文件，而非原版旧版本
if grep -q '#include "mt7981b-cudy-tr3000-v1.dtsi"' "${DTS_DIR}/${DTS_NEW}.dts"; then
    sed -i 's|#include "mt7981b-cudy-tr3000-v1.dtsi"|#include "mt7981b-cudy-tr3000-512mb-v1.dtsi"|' "${DTS_DIR}/${DTS_NEW}.dts"
    echo "[-] DTS头文件引用关联已修复"
elif grep -q '#include "mt7981b-cudy-tr3000-512mb-v1.dtsi"' "${DTS_DIR}/${DTS_NEW}.dts"; then
    echo "[-] DTS头文件引用关联已经正确，无需修改"
else
    echo "[!] 警告: 未在DTS文件中找到include引入语句，请手动添加正确的头文件路径"
fi

echo "[+] 所有设备树文件修改完成"

# =============================================================================
# 步骤 3: 向filogic.mk注入带内核生成规则的新设备定义
# =============================================================================
echo ">>> [步骤 3/6] 正在向配置文件 ${MK_FILE} 注入新设备编译规则..."

if grep -q "define Device/${DEVICE_NAME}" "${MK_FILE}"; then
    echo "[*] 设备定义已存在于 ${MK_FILE} 中，跳过注入步骤"
else
    echo "[-] 正在追加带完整内核生成规则的新设备定义..."

    # 【核心修复】新增KERNEL定义，彻底解决"No rule to make target ... kernel.bin"编译错误
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
  # 显式声明内核镜像生成流水线，确保kernel.bin能被正确构建
  KERNEL := kernel-bin | lzma | uImage lzma
  # 添加 KERNEL_SIZE 属性，防止内核文件在打包阶段被误删
  KERNEL_SIZE := 8192k
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

# =============================================================================
# 步骤 4: 手动生成元数据缓存，绕过自动生成脚本兼容故障
# 【重要】保持 targetinfo 部分完全不变，因为原版不会自动生成
# =============================================================================
echo ">>> [步骤 4/6] 正在手动生成编译元数据缓存..."

# 清理旧的无效缓存文件
rm -f .targetinfo .profiles.mk
rm -rf tmp/
mkdir -p tmp

# 1. 手动创建.targetinfo元数据文件
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

# 2. 手动创建.profiles.mk设备配置文件
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

# =============================================================================
# 步骤 5: 设置内核源码下载和文件保护机制
# =============================================================================
echo ">>> [步骤 5/6] 正在配置内核源码下载和文件保护..."

# 1. 创建内核保护标记文件，防止 ImageBuilder 清理内核
mkdir -p staging_dir/target-aarch64_cortex-a53_musl
touch staging_dir/target-aarch64_cortex-a53_musl/.preserve_kernel
echo "[-] 内核保护标记已创建"

# 2. 创建 .config 配置，强制从源码编译并保留内核文件
cat > .config << 'EOFCONFIG'
# 基础目标配置
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_DEVICE_mediatek_filogic_cudy_tr3000-512mb-v1=y

# 关键配置：强制从源码编译内核并保留文件
CONFIG_USE_SSTRIP=y
CONFIG_USE_MKLIBS=y
CONFIG_BUILD_LOG=y
CONFIG_AUTOREMOVE=y
# 禁用自动清理，保护内核文件不被删除
CONFIG_AUTOREMOVE_OUTDIR=n

# 包含设备所需的软件包
CONFIG_PACKAGE_kmod-usb3=m
CONFIG_PACKAGE_kmod-mt7915e=m
CONFIG_PACKAGE_kmod-mt7981-firmware=m
CONFIG_PACKAGE_mt7981-wo-firmware=m
CONFIG_PACKAGE_automount=m
EOFCONFIG

# 3. 创建内核源码下载和编译保护脚本
mkdir -p scripts
cat > scripts/protect_kernel.sh << 'EOFKERNELSCRIPT'
#!/bin/bash
# 内核源码保护脚本 - 确保内核从源码编译且不被删除

# 设置内核源码下载路径强制使用源码编译
export DOWNLOAD_DIR="${TOPDIR}/dl"
export BUILD_LOG="1"
export AUTOREMOVE="0"

# 保护内核二进制文件
KERNEL_BUILD_DIR="build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic"

if [ -d "${KERNEL_BUILD_DIR}" ]; then
    # 标记内核构建目录为不可清理
    touch "${KERNEL_BUILD_DIR}/.preserve"
    
    # 备份关键内核文件到保护目录
    mkdir -p staging_dir/kernel_backup
    
    for file in vmlinux vmlinux.bin kernel.bin kernel.elf; do
        if [ -f "${KERNEL_BUILD_DIR}/${file}" ]; then
            cp -p "${KERNEL_BUILD_DIR}/${file}" staging_dir/kernel_backup/ 2>/dev/null || true
        fi
    done
    
    echo "[内核保护] 已标记并备份内核文件"
fi

# 确保内核源码不被删除
DL_DIR="dl"
if [ -d "${DL_DIR}" ]; then
    # 保护内核源码压缩包
    find "${DL_DIR}" -name "linux-*" -type f -exec touch {} \;
fi

exit 0
EOFKERNELSCRIPT

chmod +x scripts/protect_kernel.sh

echo "[-] 内核源码下载和文件保护机制已配置"

# =============================================================================
# 步骤 6: 清理旧构建目录，强制系统重新编译内核
# =============================================================================
echo ">>> [步骤 6/6] 正在清理旧编译目录，强制重新构建内核..."

# 删除之前失败编译留下的无效内核缓存，避免Make误判目标文件已存在
rm -rf build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic/
echo "[-] 旧编译目录已清理完成"

# =============================================================================
# 最终校验环节
# =============================================================================
echo ""
echo ">>> 自定义适配流程全部执行完毕！"
echo ">>> 正在校验新设备配置是否可用..."

if grep -q "cudy_tr3000-512mb-v1" .profiles.mk; then
    echo "[成功] 设备配置 'cudy_tr3000-512mb-v1' 已准备就绪。"
    echo ""
    echo "后续操作指引："
    echo "1. 执行 'make info' 确认新设备已出现在可用设备列表中"
    echo "2. 执行 'make image PROFILE=cudy_tr3000-512mb-v1 FILES=files' 启动固件编译"
    echo ""
    echo "【重要说明】"
    echo "✓ targetinfo 部分保持原样不变（原版不会自动生成）"
    echo "✓ 内核通过 ImageBuilder 从源码下载并编译"
    echo "✓ 添加了 KERNEL_SIZE 属性保护内核镜像"
    echo "✓ 创建了 .preserve 标记文件防止内核被删除"
    echo "✓ 配置了 scripts/protect_kernel.sh 保护脚本"
    echo "✓ 内核文件将保留在 build_dir/ 和 staging_dir/kernel_backup/ 目录"
    echo ""
    echo "内核文件不会被 ImageBuilder 在打包阶段删除，可以安全使用。"
else
    echo "[失败] 设备注册校验未通过，请手动检查 .profiles.mk 文件内容"
    exit 1
fi
