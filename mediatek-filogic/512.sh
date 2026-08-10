#!/bin/bash

# ==============================================================================
# ImmortalWrt ImageBuilder DIY Script: Cudy TR3000 512MB NAND Mod (Final Fix)
# Fixes: DTS Include Link, Kernel Build Rule, Manual Metadata Generation
# ==============================================================================

set -e # 遇到错误立即退出
set -o pipefail

echo ">>> [Step 1/5] Checking environment and files..."

# 定义变量
BOARD="mediatek"
SUBTARGET="filogic"
DEVICE_NAME="cudy_tr3000-512mb-v1"
DTS_BASE="mt7981b-cudy-tr3000-v1"
DTS_NEW="mt7981b-cudy-tr3000-512mb-v1"
MK_FILE="target/linux/${BOARD}/image/${SUBTARGET}.mk"
DTS_DIR="target/linux/${BOARD}/dts"

# 检查关键文件是否存在
if [ ! -f "${DTS_DIR}/${DTS_BASE}.dts" ] || [ ! -f "${DTS_DIR}/${DTS_BASE}.dtsi" ]; then
    echo "[!] Error: Original DTS files not found in ${DTS_DIR}"
    exit 1
fi

if [ ! -f "${MK_FILE}" ]; then
    echo "[!] Error: ${MK_FILE} not found."
    exit 1
fi

echo "[+] Environment check passed."

# ==============================================================================
# Step 2: Modify DTS Files for 512MB NAND
# ==============================================================================
echo ">>> [Step 2/5] Modifying Device Tree (DTS) for 512MB NAND..."

# 1. Copy original DTS files to new variant
cp "${DTS_DIR}/${DTS_BASE}.dts" "${DTS_DIR}/${DTS_NEW}.dts"
cp "${DTS_DIR}/${DTS_BASE}.dtsi" "${DTS_DIR}/${DTS_NEW}.dtsi"

# 2. Enable USB Power (GPIO Output 0 = High/On for this board usually)
if grep -q "gpio-export,output = <1>;" "${DTS_DIR}/${DTS_NEW}.dtsi"; then
    sed -i 's/gpio-export,output = <1>;/gpio-export,output = <0>;/' "${DTS_DIR}/${DTS_NEW}.dtsi"
    echo "[-] USB GPIO power enabled."
else
    echo "[-] USB GPIO power setting not found or already configured, skipping."
fi

# 3. Update NAND Capacity in .dts (64MB -> 512MB)
# 0x4000000 (64MB) -> 0x1FA40000 (512MB - reserved space)
if grep -q "reg = <0x5c0000 0x4000000>;" "${DTS_DIR}/${DTS_NEW}.dts"; then
    sed -i 's|reg = <0x5c0000 0x4000000>;|reg = <0x5c0000 0x1FA40000>;|' "${DTS_DIR}/${DTS_NEW}.dts"
    echo "[-] NAND capacity updated in .dts"
else
    echo "[!] Warning: Could not find original NAND reg in .dts, check manually."
fi

# 4. Update UBI Partition Reg in .dtsi
if grep -q "reg = <0x5c0000 0x4000000>;" "${DTS_DIR}/${DTS_NEW}.dtsi"; then
    sed -i '/partition@5c0000 {/,/};/{
        s/reg = <0x5c0000 0x4000000>;/reg = <0x5c0000 0x1FA40000>;/
    }' "${DTS_DIR}/${DTS_NEW}.dtsi"
    echo "[-] UBI partition size updated in .dtsi"
else
    echo "[!] Warning: Could not find original UBI reg in .dtsi, check manually."
fi

# 5. 【关键修复】修正 DTS 文件的 include 引用
# 确保 .dts 文件引用的是新的 .dtsi 文件，而不是旧的
if grep -q '#include "mt7981b-cudy-tr3000-v1.dtsi"' "${DTS_DIR}/${DTS_NEW}.dts"; then
    sed -i 's|#include "mt7981b-cudy-tr3000-v1.dtsi"|#include "mt7981b-cudy-tr3000-512mb-v1.dtsi"|' "${DTS_DIR}/${DTS_NEW}.dts"
    echo "[-] DTS include reference fixed."
elif grep -q '#include "mt7981b-cudy-tr3000-512mb-v1.dtsi"' "${DTS_DIR}/${DTS_NEW}.dts"; then
    echo "[-] DTS include reference already correct."
else
    echo "[!] Warning: Could not find include line in .dts, please check manually."
fi

echo "[+] DTS files modified successfully."

# ==============================================================================
# Step 3: Inject Device Definition into filogic.mk with Kernel Rule
# ==============================================================================
echo ">>> [Step 3/5] Injecting device definition into ${MK_FILE}..."

if grep -q "define Device/${DEVICE_NAME}" "${MK_FILE}"; then
    echo "[*] Device definition already exists in ${MK_FILE}, skipping injection."
else
    echo "[-] Appending new device definition with KERNEL rule..."
    
    # 【关键修复】增加 KERNEL 定义，解决 "No rule to make target ... kernel.bin" 错误
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
  # 显式定义内核生成规则，确保 kernel.bin 能被正确构建
  KERNEL := kernel-bin | lzma | uImage lzma
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount
endef
TARGET_DEVICES += cudy_tr3000-512mb-v1
ENDOFMAKEFILE

    if grep -q "define Device/${DEVICE_NAME}" "${MK_FILE}"; then
        echo "[+] Device definition injected successfully."
    else
        echo "[!] Error: Failed to inject device definition. Check permissions."
        exit 1
    fi
fi

# ==============================================================================
# Step 4: Manually Generate .targetinfo and .profiles.mk
# Bypasses automatic generation failures
# ==============================================================================
echo ">>> [Step 4/5] Manually generating metadata cache..."

# Clean old cache
rm -f .targetinfo .profiles.mk
rm -rf tmp/
mkdir -p tmp

# 1. Manually Create .targetinfo
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

# 2. Manually Create .profiles.mk
cat > .profiles.mk << 'ENDOFPROFILES'
PROFILE_NAMES += DEVICE_cudy_tr3000-512mb-v1

DEVICE_cudy_tr3000-512mb-v1_NAME := Cudy TR3000 v1 (512MB NAND)
DEVICE_cudy_tr3000-512mb-v1_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount
DEVICE_cudy_tr3000-512mb-v1_HAS_IMAGE_METADATA := 1
DEVICE_cudy_tr3000-512mb-v1_SUPPORTED_DEVICES := R47-512MB
DEVICE_cudy_tr3000-512mb-v1_FILESYSTEM := ubifs
DEVICE_cudy_tr3000-512mb-v1_SIZE := 507904
ENDOFPROFILES

echo "[+] Metadata cache generated manually."

# ==============================================================================
# Step 5: Clean Build Directory to Force Re-compilation
# ==============================================================================
echo ">>> [Step 5/5] Cleaning build directory to force kernel re-build..."

# 必须清理掉之前失败的内核编译缓存，否则 Make 会认为目标已存在（虽然是空的或错误的）
rm -rf build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic/
echo "[-] Build directory cleaned."

# ==============================================================================
# Final Verification
# ==============================================================================
echo ""
echo ">>> DIY Process Completed!"
echo ">>> Verifying profile availability..."

if grep -q "cudy_tr3000-512mb-v1" .profiles.mk; then
    echo "[SUCCESS] Profile 'cudy_tr3000-512mb-v1' is ready."
    echo ""
    echo "Next steps:"
    echo "1. Run 'make info' to confirm the profile is listed."
    echo "2. Run 'make image PROFILE=cudy_tr3000-512mb-v1 FILES=files' to build."
else
    echo "[FAILED] Profile verification failed. Please check .profiles.mk content."
    exit 1
fi
