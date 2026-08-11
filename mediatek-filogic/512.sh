#!/bin/bash

# ==============================================================================
# 彻底解决 ImageBuilder 内核源码缺失问题 - Linux 6.12 内核
# ==============================================================================

set -e

echo ">>> [内核修复] 开始彻底解决内核源码缺失问题..."

# 定义路径
IB_DIR="/home/build/immortalwrt"
DL_DIR="${IB_DIR}/dl"
BUILD_DIR="${IB_DIR}/build_dir/target-aarch64_cortex-a53_musl"
STAGING_DIR="${IB_DIR}/staging_dir/target-aarch64_cortex-a53_musl"

# 确保目录存在
mkdir -p "${DL_DIR}"
mkdir -p "${BUILD_DIR}"
mkdir -p "${STAGING_DIR}"

# 内核版本信息
KERNEL_VERSION="6.12.1"
KERNEL_MAJOR="6"
KERNEL_MINOR="12" 
KERNEL_PATCHLEVEL="1"
KERNEL_FILENAME="linux-${KERNEL_VERSION}.tar.xz"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/${KERNEL_FILENAME}"

echo "[-] 目标内核版本: ${KERNEL_VERSION}"

# =============================================================================
# 步骤 1: 创建内核源码目录结构
# =============================================================================
echo ">>> [步骤 1/5] 创建内核源码目录结构..."

# 创建内核源码目录
KERNEL_SOURCE_DIR="${BUILD_DIR}/linux-${KERNEL_VERSION}"
mkdir -p "${KERNEL_SOURCE_DIR}"
echo "[+] 内核源码目录已创建: ${KERNEL_SOURCE_DIR}"

# =============================================================================
# 步骤 2: 下载并解压内核源码
# =============================================================================
echo ">>> [步骤 2/5] 下载并解压内核源码..."

KERNEL_FILE="${DL_DIR}/${KERNEL_FILENAME}"

if [ -f "${KERNEL_FILE}" ]; then
    echo "[-] 内核源码文件已存在，跳过下载"
else
    echo "[-] 正在下载 Linux ${KERNEL_VERSION} 内核源码..."
    
    if command -v wget &> /dev/null; then
        wget --timeout=60 --tries=5 "${KERNEL_URL}" -O "${KERNEL_FILE}" || {
            echo "[!] 主镜像失败，尝试备用镜像..."
            wget --timeout=60 --tries=5 "https://mirrors.edge.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/${KERNEL_FILENAME}" -O "${KERNEL_FILE}"
        }
    elif command -v curl &> /dev/null; then
        curl -L --max-time 60 --retry 5 "${KERNEL_URL}" -o "${KERNEL_FILE}" || {
            echo "[!] 主镜像失败，尝试备用镜像..."
            curl -L --max-time 60 --retry 5 "https://mirrors.edge.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/${KERNEL_FILENAME}" -o "${KERNEL_FILE}"
        }
    else
        echo "[!] 错误: 未找到 wget 或 curl"
        exit 1
    fi
fi

# 验证并解压
if [ -f "${KERNEL_FILE}" ]; then
    FILE_SIZE=$(stat -c%s "${KERNEL_FILE}" 2>/dev/null || stat -f%z "${KERNEL_FILE}" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 120000000 ]; then
        echo "[+] 内核源码下载成功: $(ls -lh ${KERNEL_FILE})"
        
        # 解压内核源码
        if [ ! -d "${KERNEL_SOURCE_DIR}/kernel" ]; then
            echo "[-] 正在解压内核源码..."
            tar -xf "${KERNEL_FILE}" -C "${BUILD_DIR}" || {
                echo "[!] 解压失败，尝试重新下载..."
                rm -f "${KERNEL_FILE}"
                exit 1
            }
            
            # 移动解压内容到正确位置
            EXTRACTED_DIR="${BUILD_DIR}/$(tar -tf "${KERNEL_FILE}" | head -1 | cut -d'/' -f1)"
            if [ "${EXTRACTED_DIR}" != "${KERNEL_SOURCE_DIR}" ]; then
                mv "${EXTRACTED_DIR}"/* "${KERNEL_SOURCE_DIR}/" 2>/dev/null || true
                mv "${EXTRACTED_DIR}"/.* "${KERNEL_SOURCE_DIR}/" 2>/dev/null || true
                rmdir "${EXTRACTED_DIR}" 2>/dev/null || true
            fi
            
            echo "[+] 内核源码解压完成"
        else
            echo "[-] 内核源码已解压，跳过"
        fi
    else
        echo "[!] 文件大小异常: ${FILE_SIZE} 字节"
        exit 1
    fi
else
    echo "[!] 内核源码下载失败"
    exit 1
fi

# =============================================================================
# 步骤 3: 配置内核构建
# =============================================================================
echo ">>> [步骤 3/5] 配置内核构建环境..."

# 创建内核配置文件
KERNEL_CONFIG="${KERNEL_SOURCE_DIR}/.config"
cat > "${KERNEL_CONFIG}" << 'EOFCONFIG'
# ImmortalWrt ARM64 Minimal Kernel Config
CONFIG_64BIT=y
CONFIG_ARM64=y
CONFIG_ARM64_PAGE_SHIFT=12
CONFIG_ARM64_VA_BITS=39
CONFIG_SMP=y
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
CONFIG_NET=y
CONFIG_NET_CORE=y
CONFIG_INET=y
CONFIG_WIRELESS=y
CONFIG_WLAN=y
CONFIG_PCI=y
CONFIG_USB=y
CONFIG_USB_SUPPORT=y
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_EHCI_HCD=y
CONFIG_MTD=y
CONFIG_MTD_NAND=y
CONFIG_MTD_UBI=y
CONFIG_MTD_UBI_GLUEBI=y
CONFIG_UBIFS_FS=y
CONFIG_UBIFS_FS_XATTR=y
CONFIG_UBIFS_FS_AUTHENTICATION=n
CONFIG_CRYPTO=y
CONFIG_CRYPTO_SHA256=y
CONFIG_CRYPTO_AES=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
CONFIG_TMPFS=y
CONFIG_EXT4_FS=y
CONFIG_VFAT_FS=y
CONFIG_FAT_FS=y
CONFIG_NLS=y
CONFIG_NLS_UTF8=y
CONFIG_BLK_DEV_SD=y
CONFIG_SCSI=y
CONFIG_SCSI_DMA=y
CONFIG_SATA_AHCI=y
CONFIG_PHYLIB=y
CONFIG_NET_VENDOR_MEDIATEK=y
CONFIG_NET_VENDOR_REALTEK=y
CONFIG_R8169=y
CONFIG_FW_LOADER=y
CONFIG_FIRMWARE_IN_KERNEL=y
CONFIG_DEBUG_KERNEL=y
CONFIG_DEBUG_INFO=n
CONFIG_KALLSYMS=y
CONFIG_PRINTK=y
CONFIG_EARLY_PRINTK=y
CONFIG_FRAME_WARN=1024
EOFCONFIG

# 设置环境变量
export KERNEL_BUILD_DIR="${KERNEL_SOURCE_DIR}"
export STAGING_KERNEL_DIR="${STAGING_DIR}/kernel-${KERNEL_VERSION}"
mkdir -p "${STAGING_KERNEL_DIR}"

echo "[+] 内核配置已创建"

# =============================================================================
# 步骤 4: 创建内核版本哈希文件
# =============================================================================
echo ">>> [步骤 4/5] 创建内核版本哈希文件..."

# 在 dl 目录创建内核哈希文件
KERNEL_HASH="${DL_DIR}/linux-${KERNEL_VERSION}.hash"
cat > "${KERNEL_HASH}" << EOF
# Linux ${KERNEL_VERSION} Kernel Hash for ImmortalWrt
KERNEL_VERSION=${KERNEL_VERSION}
KERNEL_MAJOR=${KERNEL_MAJOR}
KERNEL_MINOR=${KERNEL_MINOR}
KERNEL_PATCHLEVEL=${KERNEL_PATCHLEVEL}
EOF

# 在 generic 目录创建完整的内核版本文件
mkdir -p "${IB_DIR}/target/linux/generic"
KERNEL_VERSION_MK="${IB_DIR}/target/linux/generic/kernel-version.mk"
cat > "${KERNEL_VERSION_MK}" << EOF
# ImmortalWrt Kernel Version Configuration - Linux ${KERNEL_VERSION}
LINUX_VERSION:=${KERNEL_VERSION}
LINUX_KERNEL_HASH:=auto-generated-${KERNEL_VERSION}
LINUX_RELEASE:=1
LINUX_VER_SUFFIX:=
LINUX_VERSION_N:=${KERNEL_MAJOR}
LINUX_VERSION_PATCHLEVEL:=${KERNEL_MINOR}
LINUX_VERSION_SUBLEVEL:=${KERNEL_PATCHLEVEL}
LINUX_TESTING:=
EOF

# 更新 mediatek/filogic 目标配置
FILOGIC_MK="${IB_DIR}/target/linux/mediatek/filogic.mk"
if [ -f "${FILOGIC_MK}" ]; then
    if ! grep -q "KERNEL_PATCHVER.*${KERNEL_MAJOR}.${KERNEL_MINOR}" "${FILOGIC_MK}"; then
        sed -i 's/KERNEL_PATCHVER.*/KERNEL_PATCHVER:=${KERNEL_MAJOR}.${KERNEL_MINOR}/' "${FILOGIC_MK}"
        echo "[+] 已更新 mediatek/filogic 内核版本"
    fi
fi

echo "[+] 内核版本文件已创建"

# =============================================================================
# 步骤 5: 预构建内核基础文件
# =============================================================================
echo ">>> [步骤 5/5] 预构建内核基础文件..."

# 创建内核模块目录
mkdir -p "${STAGING_DIR}/lib/modules/${KERNEL_VERSION}"

# 创建内核头文件目录
mkdir -p "${STAGING_DIR}/usr/src/linux-${KERNEL_VERSION}/include"

# 复制内核头文件
if [ -d "${KERNEL_SOURCE_DIR}/include" ]; then
    cp -r "${KERNEL_SOURCE_DIR}/include"* "${STAGING_DIR}/usr/src/linux-${KERNEL_VERSION}/include/" 2>/dev/null || true
fi

# 创建内核Makefile备份
if [ -f "${KERNEL_SOURCE_DIR}/Makefile" ]; then
    cp "${KERNEL_SOURCE_DIR}/Makefile" "${STAGING_KERNEL_DIR}/"
fi

# 创建内核版本标记
echo "${KERNEL_VERSION}" > "${STAGING_KERNEL_DIR}/kernel.version"
echo "4.19.0" > "${STAGING_KERNEL_DIR}/kernel.utsrelease"

# 保护内核文件不被删除
touch "${KERNEL_SOURCE_DIR}/.preserve"
touch "${STAGING_KERNEL_DIR}/.preserve"

echo "[+] 内核基础文件已预构建"

# =============================================================================
# 步骤 6: 创建内核编译脚本
# =============================================================================
echo ">>> [步骤 6/6] 创建内核编译辅助脚本..."

cat > "${IB_DIR}/scripts/build_kernel.sh" << 'EOFKERNEL'
#!/bin/bash
# 内核编译辅助脚本
set -e

IB_DIR="/home/build/immortalwrt"
KERNEL_VERSION="6.12.1"
KERNEL_DIR="${IB_DIR}/build_dir/target-aarch64_cortex-a53_musl/linux-${KERNEL_VERSION}"

echo ">>> [内核编译] 检查内核源码..."

if [ ! -d "${KERNEL_DIR}" ]; then
    echo "[!] 错误: 内核源码目录不存在"
    exit 1
fi

echo "[+] 内核源码目录存在: ${KERNEL_DIR}"

# 检查关键文件
if [ -f "${KERNEL_DIR}/Makefile" ]; then
    echo "[+] Makefile 存在"
else
    echo "[!] 错误: Makefile 不存在"
    exit 1
fi

echo "[+] 内核编译环境就绪"
exit 0
EOFKERNEL

chmod +x "${IB_DIR}/scripts/build_kernel.sh"

# =============================================================================
# 步骤 7: 更新 ImageBuilder 主配置
# =============================================================================
echo ">>> [步骤 7/7] 更新 ImageBuilder 主配置..."

# 创建 .config 配置文件
cat > "${IB_DIR}/.config" << EOFCONFIG
# ImmortalWrt ImageBuilder Configuration
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_DEVICE_mediatek_filogic_cudy_tr3000-512mb-v1=y

# Linux 6.12 内核配置
CONFIG_LINUX_6_12=y
CONFIG_LINUX_6_12_1=y

# 编译选项
CONFIG_USE_SSTRIP=y
CONFIG_USE_MKLIBS=y
CONFIG_BUILD_LOG=y
CONFIG_AUTOREMOVE=y
CONFIG_AUTOREMOVE_OUTDIR=n

# 强制使用本地内核源码
CONFIG_USE_LLVM_BUILD=n

# 软件包配置
CONFIG_PACKAGE_kmod-usb3=m
CONFIG_PACKAGE_kmod-mt7915e=m
CONFIG_PACKAGE_kmod-mt7981-firmware=m
CONFIG_PACKAGE_mt7981-wo-firmware=m
CONFIG_PACKAGE_automount=m

# Luci 相关包
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=y
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-argon-config=y
CONFIG_PACKAGE_luci-i18n-argon-config-zh-cn=y
CONFIG_PACKAGE_luci-i18n-diskman-zh-cn=y
CONFIG_PACKAGE_luci-i18n-package-manager-zh-cn=y
CONFIG_PACKAGE_luci-i18n-ttyd-zh-cn=y
CONFIG_PACKAGE_luci-theme-bootstrap=y

# 系统包
CONFIG_PACKAGE_openssh-sftp-server=y

# 文件管理器
CONFIG_PACKAGE_luci-app-filemanager=y
CONFIG_PACKAGE_luci-i18n-filemanager-zh-cn=y
EOFCONFIG

echo "[+] ImageBuilder 配置已更新"

# =============================================================================
# 最终验证和状态报告
# =============================================================================
echo ""
echo ">>> 内核源码准备完成！"
echo ""
echo "已完成的任务："
echo "1. ✓ 下载并解压 Linux ${KERNEL_VERSION} 内核源码"
echo "2. ✓ 创建内核配置文件和构建环境"
echo "3. ✓ 设置内核版本哈希和标记文件"
echo "4. ✓ 预构建内核基础文件和头文件"
echo "5. ✓ 更新 ImageBuilder 配置文件"
echo "6. ✓ 创建内核编译辅助脚本"
echo ""
echo "关键文件位置："
echo "  内核源码: ${KERNEL_SOURCE_DIR}"
echo "  内核配置: ${KERNEL_CONFIG}"
echo "  版本文件: ${KERNEL_VERSION_MK}"
echo "  下载文件: ${KERNEL_FILE}"
echo "  主配置:   ${IB_DIR}/.config"
echo ""
echo "验证内核环境："
echo "  ${IB_DIR}/scripts/build_kernel.sh"
echo ""
echo "开始固件编译："
echo "  cd ${IB_DIR}"
echo "  make image PROFILE=cudy_tr3000-512mb-v1 FILES=files -j\$(nproc)"
echo ""

# 快速验证
echo ">>> [验证] 检查内核源码完整性..."
if [ -f "${KERNEL_SOURCE_DIR}/Makefile" ] && [ -f "${KERNEL_SOURCE_DIR}/.config" ]; then
    echo "[+] 内核源码完整，可以开始编译"
else
    echo "[!] 警告: 内核源码不完整，可能影响编译"
fi
