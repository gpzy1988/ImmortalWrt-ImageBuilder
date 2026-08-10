
#!/bin/bash
#==============================================================
# ImmortalWrt 25.12.x Cudy TR3000 512MB 专属适配脚本 (仅修改版)
# 功能：完成所有文件修改与 Profile 注册，不执行 make image
#==============================================================

set -e

# -------------- 基础配置区 --------------
PLATFORM="mediatek"
SUBTARGET="filogic"
DEVICE_NAME="cudy_tr3000-512mb-v1"
DEVICE_VENDOR="Cudy"
DEVICE_MODEL="TR3000"
DEVICE_VARIANT="v1 (512MB NAND)"
DEVICE_TITLE="${DEVICE_VENDOR} ${DEVICE_MODEL} ${DEVICE_VARIANT}"
DTS_BASE="mt7981b-cudy-tr3000-v1"
DTS_NEW="mt7981b-cudy-tr3000-512mb-v1"
IMAGE_SIZE="507904k"
BLOCKSIZE="128k"
PAGESIZE="2048"
UBINIZE_OPTS="-E 5"
KERNEL_VER="6.6"
KERNEL_IN_UBI="1"
DEVICE_PACKAGES="kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount"

# -------------- 自动适配 25.12 目录规则 --------------
IB_DIR="/home/build/immortalwrt"
[ ! -d "${IB_DIR}" ] && IB_DIR="$(pwd)"
DTS_DIR="${IB_DIR}/target/linux/${PLATFORM}/dts"

# 25.12 专属路径自动检测
if [ -d "${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}" ]; then
    IMAGE_MK="${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}/Makefile"
    TARGETINFO="$(dirname "${IMAGE_MK}")/${SUBTARGET}.targetinfo"
else
    IMAGE_MK="${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}.mk"
    TARGETINFO="${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}.targetinfo"
fi

# -------------- 颜色输出定义 --------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }

# -------------- 前置检查 --------------
echo ""
echo "============================================="
echo "  ImmortalWrt 25.12.x Cudy TR3000 512MB 适配"
echo "  模式: 仅修改配置，不自动构建"
echo "============================================="

[ ! -f "${DTS_DIR}/${DTS_BASE}.dts" ] && error "基础 DTS 不存在: ${DTS_DIR}/${DTS_BASE}.dts"
[ ! -f "${IMAGE_MK}" ] && error "目标 Makefile 不存在: ${IMAGE_MK}"

# -------------- 步骤 1：复制并修改 DTS --------------
echo ""
info "[步骤 1/4] 准备 512MB 专属 DTS 文件"
cp "${DTS_DIR}/${DTS_BASE}.dts" "${DTS_DIR}/${DTS_NEW}.dts"
[ -f "${DTS_DIR}/${DTS_BASE}.dtsi" ] && cp "${DTS_DIR}/${DTS_BASE}.dtsi" "${DTS_DIR}/${DTS_NEW}.dtsi"

# 修改分区大小 (64MB -> 512MB)
sed -i 's|reg = <0x5c0000 0x4000000>;|reg = <0x5c0000 0x1FA40000>;|g' "${DTS_DIR}/${DTS_NEW}.dts"
ok "DTS 分区大小已更新为 512MB"

# -------------- 步骤 2：写入 Makefile 设备定义 --------------
echo ""
info "[步骤 2/4] 写入 Makefile 设备定义"
# 先清除可能存在的旧定义，防止重复追加
sed -i "/define Device\/${DEVICE_NAME}/,/endef/d" "${IMAGE_MK}"
sed -i "/TARGET_DEVICES += ${DEVICE_NAME}/d" "${IMAGE_MK}"

cat >> "${IMAGE_MK}" << MK_EOF

define Device/${DEVICE_NAME}
  DEVICE_VENDOR := ${DEVICE_VENDOR}
  DEVICE_MODEL := ${DEVICE_MODEL}
  DEVICE_VARIANT := ${DEVICE_VARIANT}
  DEVICE_DTS := ${DTS_NEW}
  DEVICE_DTS_DIR := ../dts
  SUPPORTED_DEVICES += R47-512MB
  UBINIZE_OPTS := ${UBINIZE_OPTS}
  BLOCKSIZE := ${BLOCKSIZE}
  PAGESIZE := ${PAGESIZE}
  IMAGE_SIZE := ${IMAGE_SIZE}
  KERNEL_IN_UBI := ${KERNEL_IN_UBI}
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  DEVICE_PACKAGES := ${DEVICE_PACKAGES}
endef
TARGET_DEVICES += ${DEVICE_NAME}
MK_EOF
ok "Makefile 定义已写入 ${IMAGE_MK}"

# -------------- 步骤 3：写入 targetinfo --------------
echo ""
info "[步骤 3/4] 更新 .targetinfo"
# 清除旧条目
sed -i "/^${DEVICE_NAME}:/,/^$/d" "${TARGETINFO}"

cat >> "${TARGETINFO}" << TI_EOF

${DEVICE_NAME}:
  TARGET_DEVICE: ${DEVICE_NAME}
  DEVICE_TITLE: ${DEVICE_TITLE}
  KERNEL: ${KERNEL_VER}
  PROFILES: Default
  PLATFORM: ${PLATFORM}/${SUBTARGET}
  SUBTARGET: ${SUBTARGET}
  DEVICE_DTS: ${DTS_NEW}
  DEVICE_PACKAGES: ${DEVICE_PACKAGES}
  IMAGE_SIZE: ${IMAGE_SIZE}
  BLOCKSIZE: ${BLOCKSIZE}
  PAGESIZE: ${PAGESIZE}
  UBINIZE_OPTS: ${UBINIZE_OPTS}
TI_EOF

# 强制替换 Tab 为空格
sed -i 's/\t/    /g' "${TARGETINFO}"
ok ".targetinfo 已更新并规范化缩进"

# -------------- 步骤 4：深度清理与验证 --------------
echo ""
info "[步骤 4/4] 清理缓存并验证 Profile 识别"
cd "${IB_DIR}"
rm -rf tmp/ .config
make defconfig >/dev/null 2>&1 || true

echo ""
echo "============================================="
echo "  验证结果"
echo "============================================="

if make info 2>/dev/null | grep -q "${DEVICE_NAME}"; then
    ok "✅ 设备 ${DEVICE_NAME} 已被 ImmortalWrt 25.12.x 成功识别！"
    
    echo ""
    echo "----------------------------------------"
    echo " 📦 适配完成，请手动执行以下命令构建："
    echo "----------------------------------------"
    echo ""
    echo " make image PROFILE=\"${DEVICE_NAME}\""
    echo ""
    echo " 📂 固件输出路径："
    echo " bin/targets/${PLATFORM}/${SUBTARGET}/"
    echo ""
    echo " 🔧 带自定义包构建示例："
    echo " make image PROFILE=\"${DEVICE_NAME}\" PACKAGES=\"curl luci luci-i18n-base-zh-cn ...\""
    echo ""
    echo " 📏 调整根分区大小示例："
    echo " make image PROFILE=\"${DEVICE_NAME}\" ROOTFS_PARTSIZE=\"1024\""
    echo "----------------------------------------"
else
    warn "⚠️ 验证失败：make info 未找到设备"
    echo ""
    echo "请检查以下文件："
    echo "1. ${IMAGE_MK} 末尾是否有 TARGET_DEVICES += ${DEVICE_NAME}"
    echo "2. ${TARGETINFO} 中条目缩进是否全部为空格"
    echo "3. ${DTS_DIR}/${DTS_NEW}.dts 语法是否正确"
fi
echo "============================================="
