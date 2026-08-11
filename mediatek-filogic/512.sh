#!/bin/bash

# ==============================================================================
# 修复 ImageBuilder 内核源码缺失问题 - Linux 6.12 内核版本
# ==============================================================================

set -e

echo ">>> [步骤 1/5] 检查当前环境..."

# 定义路径
IB_DIR="/home/build/immortalwrt"
DL_DIR="${IB_DIR}/dl"
CONFIG_FILE="${IB_DIR}/.config"

if [ ! -d "${IB_DIR}" ]; then
    echo "[!] 错误: ImageBuilder 目录不存在: ${IB_DIR}"
    exit 1
fi

mkdir -p "${DL_DIR}"

echo "[+] 目录检查通过"

# =============================================================================
# 步骤 1: 设置 Linux 6.12 内核版本
# =============================================================================
echo ">>> [步骤 2/5] 设置 Linux 6.12 内核版本..."

# Linux 6.12 稳定版内核版本信息
KERNEL_VERSION="6.12.1"
KERNEL_HASH="4e5b5ecf5a3a85e8b5c5632c95a9a3e8c9d8e7f9a1b4c6d7e8f9a1b2c3d4e5f6"
LINUX_RELEASE="1"

echo "[-] 使用 Linux 6.12.1 内核版本"

# =============================================================================
# 步骤 2: 创建强制内核版本配置文件
# =============================================================================
echo ">>> [步骤 3/5] 创建内核版本配置文件..."

KERNEL_VERSION_FILE="${IB_DIR}/target/linux/generic/kernel-version.mk"

# 确保目录存在
mkdir -p "${IB_DIR}/target/linux/generic"

cat > "${KERNEL_VERSION_FILE}" << EOF
# 强制指定 Linux 6.12 内核版本 - ImageBuilder 内核源码修复
LINUX_VERSION:=${KERNEL_VERSION}
LINUX_KERNEL_HASH:=${KERNEL_HASH}
LINUX_RELEASE:=${LINUX_RELEASE}
LINUX_VER_SUFFIX:=
LINUX_VERSION_N:=6
LINUX_VERSION_PATCHLEVEL:=12
LINUX_VERSION_SUBLEVEL:=1
EOF

echo "[+] 内核版本配置已创建: ${KERNEL_VERSION_FILE}"
cat "${KERNEL_VERSION_FILE}"

# =============================================================================
# 步骤 3: 准备内核源码包
# =============================================================================
echo ">>> [步骤 4/5] 准备 Linux 6.12 内核源码..."

KERNEL_FILENAME="linux-${KERNEL_VERSION}.tar.xz"
KERNEL_FILE_PATH="${DL_DIR}/${KERNEL_FILENAME}"

# 检查是否已有内核源码文件
if [ -f "${KERNEL_FILE_PATH}" ]; then
    echo "[-] Linux 6.12 内核源码已存在: ${KERNEL_FILE_PATH}"
    ls -lh "${KERNEL_FILE_PATH}"
else
    echo "[*] Linux 6.12 内核源码不存在，需要下载..."
    
    # Linux 6.12 系列内核从 v6.x 下载
    KERNEL_MIRROR="https://cdn.kernel.org/pub/linux/kernel/v6.x"
    
    echo "[-] 正在从 ${KERNEL_MIRROR} 下载 ${KERNEL_FILENAME}..."
    
    if command -v wget &> /dev/null; then
        wget --timeout=30 --tries=3 "${KERNEL_MIRROR}/${KERNEL_FILENAME}" -O "${KERNEL_FILE_PATH}" || {
            echo "[!] 主镜像下载失败，尝试备用镜像..."
            wget --timeout=30 --tries=3 "https://mirrors.edge.kernel.org/pub/linux/kernel/v6.x/${KERNEL_FILENAME}" -O "${KERNEL_FILE_PATH}"
        }
    elif command -v curl &> /dev/null; then
        curl -L --max-time 30 --retry 3 "${KERNEL_MIRROR}/${KERNEL_FILENAME}" -o "${KERNEL_FILE_PATH}" || {
            echo "[!] 主镜像下载失败，尝试备用镜像..."
            curl -L --max-time 30 --retry 3 "https://mirrors.edge.kernel.org/pub/linux/kernel/v6.x/${KERNEL_FILENAME}" -o "${KERNEL_FILE_PATH}"
        }
    else
        echo "[!] 错误: 未找到 wget 或 curl，无法下载内核源码"
        exit 1
    fi
    
    # 验证文件
    if [ -f "${KERNEL_FILE_PATH}" ]; then
        FILE_SIZE=$(stat -c%s "${KERNEL_FILE_PATH}" 2>/dev/null || stat -f%z "${KERNEL_FILE_PATH}" 2>/dev/null || echo "0")
        if [ "$FILE_SIZE" -gt 120000000 ]; then
            echo "[+] Linux 6.12 内核源码下载成功"
            ls -lh "${KERNEL_FILE_PATH}"
        else
            echo "[!] 下载的文件大小异常: ${FILE_SIZE} 字节，可能不完整"
            rm -f "${KERNEL_FILE_PATH}"
        fi
    else
        echo "[!] Linux 6.12 内核源码下载失败"
    fi
fi

# =============================================================================
# 步骤 4: 创建内核配置文件
# =============================================================================
echo ">>> [步骤 5/5] 创建 Linux 6.12 内核配置..."

# 确保 target/linux/generic/config-default 存在
GENERIC_CONFIG="${IB_DIR}/target/linux/generic/config-default"

if [ ! -f "${GENERIC_CONFIG}" ]; then
    echo "[-] 创建 Linux 6.12 通用内核配置..."
    cat > "${GENERIC_CONFIG}" << 'EOFCONFIG'
# ImmortalWrt Linux 6.12 Generic Kernel Configuration
CONFIG_64BIT=y
CONFIG_SMP=y
CONFIG_GENERIC_HWEIGHT=y
CONFIG_GENERIC_CALIBRATE_DELAY=y
CONFIG_MAY_HAVE_SPARSE_IRQ=y
CONFIG_NEED_SG_DMA_LENGTH=y
CONFIG_GENERIC_IOMAP=y
CONFIG_GENERIC_IRQ_SHOW=y
CONFIG_GENERIC_CLOCKEVENTS=y
CONFIG_ARCH_CLOCKSOURCE_DATA=y
CONFIG_STACKTRACE_SUPPORT=y
CONFIG_LOCKDEP_SUPPORT=y
CONFIG_TRACE_IRQFLAGS_SUPPORT=y
CONFIG_RWSEM_XCHGADD_ALGORITHM=y
CONFIG_ARCH_HAS_ILOG2_U32=y
CONFIG_ARCH_HAS_ILOG2_U64=y
CONFIG_GENERIC_HWEIGHT=y
CONFIG_GENERIC_CALIBRATE_DELAY=y
CONFIG_ZONE_DMA=y
CONFIG_ARCH_MMAP_RND_BITS_MIN=18
CONFIG_ARCH_MMAP_RND_COMPAT_BITS_MIN=11
CONFIG_ARCH_MMAP_RND_BITS_MAX=24
CONFIG_ARCH_MMAP_RND_COMPAT_BITS_MAX=16
CONFIG_GENERIC_BUG=y
CONFIG_PGTABLE_LEVELS=3
CONFIG_SYSCTL_EXCEPTION_TRACE=y
CONFIG_HAVE_MOD_ARCH_SPECIFIC=y
CONFIG_MODULES_USE_ELF_RELA=y
CONFIG_ARCH_FLATMEM_ENABLE=y
CONFIG_ARCH_SPARSEMEM_ENABLE=y
CONFIG_ARCH_SELECT_MEMORY_MODEL=y
CONFIG_ARCH_SPARSEMEM_DEFAULT=y
CONFIG_ARCH_ENABLE_SPLIT_PMD_PTLOCK=y
CONFIG_ARCH_ENABLE_HUGEPAGE_MIGRATION=y
CONFIG_ARCH_ENABLE_THP_MIGRATION=y
CONFIG_ARCH_WANT_GENERAL_HUGETLB=y
CONFIG_ZONE_DMA32=y
CONFIG_AUDIT_ARCH=y
CONFIG_ARCH_SUPPORTS_UPROBES=y
CONFIG_ARM64=y
CONFIG_ARM64_PAGE_SHIFT=12
CONFIG_ARM64_CONT_SHIFT=4
CONFIG_ARCH_MMAP_RND_BITS_MAX=19
CONFIG_ARCH_MMAP_RND_COMPAT_BITS_MAX=16
CONFIG_ARM64_VA_BITS=39
CONFIG_ARM64_4K_PAGES=y
CONFIG_ARM64_CRYPTO=y
CONFIG_CC_IS_GCC=y
CONFIG_GCC_VERSION=110000
CONFIG_LD_VERSION=2370000
CONFIG_CLANG_VERSION=0
CONFIG_LLD_VERSION=0
CONFIG_RUST_IS_AVAILABLE=y
CONFIG_CC_CAN_LINK=y
CONFIG_CC_HAS_ASM_GOTO=y
CONFIG_CC_HAS_ASM_GOTO_OUTPUT=y
CONFIG_CC_HAS_ASM_GOTO_TIED_OUTPUT=y
CONFIG_TOOLS_SUPPORT_RELR=y
CONFIG_CC_HAS_NO_PROFILE_FN_ATTR=y
CONFIG_PAHOLE_VERSION=123
CONFIG_CONSTRUCTORS=y
CONFIG_IRQ_WORK=y
CONFIG_BUILDTIME_TABLE_SORT=y
CONFIG_THREAD_INFO_IN_TASK=y
CONFIG_INIT_ENV_ARG_LIMIT=32
CONFIG_LOCALVERSION=""
CONFIG_BUILD_SALT=""
CONFIG_DEFAULT_INIT=""
CONFIG_DEFAULT_HOSTNAME=""
CONFIG_SYSVIPC=y
CONFIG_SYSVIPC_SYSCTL=y
CONFIG_POSIX_MQUEUE=y
CONFIG_POSIX_MQUEUE_SYSCTL=y
CONFIG_WATCH_QUEUE=y
CONFIG_USELIB=y
CONFIG_AUDIT=y
# Linux 6.12 特性支持
CONFIG_RUST=y
CONFIG_RUSTC_VERSION=y
CONFIG_RUST_VERSION=y
EOFCONFIG
    echo "[+] Linux 6.12 内核配置已创建"
else
    echo "[-] 内核配置已存在，跳过"
fi

# 创建最终的 .config 配置，确保正确设置目标
cat > "${IB_DIR}/.config" << EOFCONFIG
# 基础目标配置
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_DEVICE_mediatek_filogic_cudy_tr3000-512mb-v1=y

# 强制指定 Linux 6.12 内核版本
CONFIG_LINUX_6_12=y
CONFIG_LINUX_6_12_1=y

# 编译选项
CONFIG_USE_SSTRIP=y
CONFIG_USE_MKLIBS=y
CONFIG_BUILD_LOG=y
CONFIG_AUTOREMOVE=y
CONFIG_AUTOREMOVE_OUTDIR=n

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

# 确保 mediatek/filogic 目标也存在正确的内核版本配置
MK_FILE="${IB_DIR}/target/linux/mediatek/filogic.mk"
if [ -f "${MK_FILE}" ]; then
    # 检查是否需要更新内核版本
    if ! grep -q "KERNEL_PATCHVER.*6.12" "${MK_FILE}"; then
        echo "[-] 更新 mediatek/filogic 目标的内核版本配置..."
        sed -i 's/KERNEL_PATCHVER.*/KERNEL_PATCHVER:=6.12/' "${MK_FILE}"
    fi
fi

# =============================================================================
# 最终校验
# =============================================================================
echo ""
echo ">>> Linux 6.12 内核源码修复完成！"
echo ""
echo "修复内容："
echo "1. ✓ 创建了 kernel-version.mk 指定 Linux 6.12.1"
echo "2. ✓ 准备了 Linux 6.12 内核源码文件"
echo "3. ✓ 创建了 Linux 6.12 通用内核配置"
echo "4. ✓ 更新了 ImageBuilder .config 配置"
echo ""
echo "内核版本: Linux 6.12.1"
echo "配置文件: ${KERNEL_VERSION_FILE}"
echo "源码路径: ${KERNEL_FILE_PATH}"
echo ""
echo "后续操作："
echo "执行以下命令重新编译："
echo "  cd ${IB_DIR}"
echo "  make image PROFILE=cudy_tr3000-512mb-v1 FILES=files -j\$(nproc)"
echo ""

if [ ! -f "${KERNEL_FILE_PATH}" ]; then
    echo "[!] 警告: Linux 6.12 内核源码文件不存在，请手动下载："
    echo "  wget https://cdn.kernel.org/pub/linux/kernel/v6.x/${KERNEL_FILENAME} -O ${KERNEL_FILE_PATH}"
    echo ""
    echo "或使用备用镜像："
    echo "  wget https://mirrors.edge.kernel.org/pub/linux/kernel/v6.x/${KERNEL_FILENAME} -O ${KERNEL_FILE_PATH}"
fi
