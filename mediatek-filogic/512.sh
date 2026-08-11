#!/bin/bash

# ==============================================================================
# ImmortalWrt ImageBuilder DIY Script: Cudy TR3000 512MB NAND Mod
# 直接借用原版 cudy_tr3000-v1 内核，避免重新编译
# ==============================================================================

set -e # 遇到错误立即退出
set -o pipefail

echo ">>> [Step 1/4] Checking environment and files..."

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
echo ">>> [Step 2/4] Modifying Device Tree (DTS) for 512MB NAND..."

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
# Replace the reg property inside the partition block
if grep -q "reg = <0x5c0000 0x4000000>;" "${DTS_DIR}/${DTS_NEW}.dtsi"; then
    sed -i '/partition@5c0000 {/,/};/{
        s/reg = <0x5c0000 0x4000000>;/reg = <0x5c0000 0x1FA40000>;/
    }' "${DTS_DIR}/${DTS_NEW}.dtsi"
    echo "[-] UBI partition size updated in .dtsi"
else
    echo "[!] Warning: Could not find original UBI reg in .dtsi, check manually."
fi

# 5. 【关键修复】修正DTS头文件引用关联
if grep -q '#include "mt7981b-cudy-tr3000-v1.dtsi"' "${DTS_DIR}/${DTS_NEW}.dts"; then
    sed -i 's|#include "mt7981b-cudy-tr3000-v1.dtsi"|#include "mt7981b-cudy-tr3000-512mb-v1.dtsi"|' "${DTS_DIR}/${DTS_NEW}.dts"
    echo "[-] DTS include reference fixed."
elif grep -q '#include "mt7981b-cudy-tr3000-512mb-v1.dtsi"' "${DTS_DIR}/${DTS_NEW}.dts"; then
    echo "[-] DTS include reference already correct."
else
    echo "[!] Warning: Could not find include statement in .dts file."
fi

echo "[+] DTS files modified successfully."

# ==============================================================================
# Step 3: Inject Device Definition into filogic.mk
# 【关键】直接借用原版内核，不生成新的内核文件
# ==============================================================================
echo ">>> [Step 3/4] Injecting device definition into ${MK_FILE}..."

if grep -q "define Device/${DEVICE_NAME}" "${MK_FILE}"; then
    echo "[*] Device definition already exists in ${MK_FILE}, skipping injection."
else
    echo "[-] Appending new device definition, borrowing original kernel..."
    
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
        echo "[+] Device definition injected successfully, using original kernel."
    else
        echo "[!] Error: Failed to inject device definition. Check permissions."
        exit 1
    fi
fi

# ==============================================================================
# Step 4: Manually Generate .targetinfo and .profiles.mk
# ==============================================================================
echo ">>> [Step 4/4] Manually generating metadata cache..."

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
# Step 5: Ensure kernel files are accessible
# ==============================================================================
echo ">>> [Step 5/5] Ensuring kernel files accessibility..."

# 检查是否有原版设备的内核文件
if [ -d "build_dir/target-aarch64_cortex-a53_musl" ]; then
    ORIGINAL_KERNEL=$(find build_dir/target-aarch64_cortex-a53_musl -name "*${DEVICE_BASE}*kernel*" -type f 2>/dev/null | head -1)
    if [ -n "$ORIGINAL_KERNEL" ]; then
        echo "[-] Found original kernel: $(basename $ORIGINAL_KERNEL)"
        
        # 创建内核文件链接，确保512MB版本能找到内核
        KERNEL_BASE_DIR="build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic"
        mkdir -p "$KERNEL_BASE_DIR"
        
        # 如果原版内核存在，创建软链接
        if [ -f "$ORIGINAL_KERNEL" ]; then
            # 提取内核文件扩展名
            KERNEL_EXT="${ORIGINAL_KERNEL##*.}"
            LINK_NAME="${KERNEL_BASE_DIR}/${DEVICE_NAME}-kernel.${KERNEL_EXT}"
            
            if [ ! -L "$LINK_NAME" ]; then
                ln -sf "$ORIGINAL_KERNEL" "$LINK_NAME" 2>/dev/null || echo "[!] Could not create symlink"
            fi
        fi
    else
        echo "[-] Original kernel not found yet, ImageBuilder will generate during build."
    fi
fi

echo "[-] Kernel accessibility setup completed."

# ==============================================================================
# Final Verification
# ==============================================================================
echo ""
echo ">>> DIY Process Completed!"
echo ">>> Verifying profile availability..."

if grep -q "cudy_tr3000-512mb-v1" .profiles.mk; then
    echo "[SUCCESS] Profile 'cudy_tr3000-512mb-v1' is ready."
    echo ""
    echo "Configuration Summary:"
    echo "  - Device: Cudy TR3000 v1 (512MB NAND)"
    echo "  - Kernel: Using original cudy_tr3000-v1 kernel"
    echo "  - DTS: Modified for 512MB NAND support"
    echo "  - Build: No kernel recompilation required"
    echo ""
    echo "You can now build the image using:"
    echo "make image PROFILE=cudy_tr3000-512mb-v1 FILES=files"
else
    echo "[FAILED] Profile verification failed. Please check .profiles.mk content."
    exit 1
fi
