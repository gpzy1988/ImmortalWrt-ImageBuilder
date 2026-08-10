#!/bin/bash
#==============================================================
# ImmortalWrt 25.12.x 专属适配脚本
# 目标机型：Cudy TR3000 512MB NAND
# 完全适配mediatek/filogic 25.12.1全新目录结构
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

# -------------- 自动适配25.12目录规则 --------------
IB_DIR="/home/build/immortalwrt"
# 非Docker环境自动适配本地路径
[ ! -d "${IB_DIR}" ] && IB_DIR="$(pwd)"
DTS_DIR="${IB_DIR}/target/linux/${PLATFORM}/dts"

# 25.12专属路径自动检测
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
echo "  ImmortalWrt 25.12.x Cudy TR3000 512MB 专属适配"
echo "  目标: ${PLATFORM}/${SUBTARGET} / ${DEVICE_NAME}"
echo "============================================="

# 检查基础DTS是否存在
[ ! -f "${DTS_DIR}/${DTS_BASE}.dts" ] && error "基础DTS不存在，请从ImmortalWrt源码复制 ${DTS_DIR}/${DTS_BASE}.dts"

# 检查25.12专属Makefile是否存在
[ ! -f "${IMAGE_MK}" ] && error "未找到25.12适配的Makefile，实际路径：${IMAGE_MK}"

# -------------- Cudy TR3000专属适配：USB供电默认关闭 --------------
echo ""
info "执行Cudy TR3000专属适配：USB供电默认关闭"
if [ -f "${DTS_DIR}/${DTS_BASE}.dtsi" ]; then
    sed -i '/modem-power/,/};/ {s/gpio-export,output = <1>;/gpio-export,output = <0>;/}' \
        "${DTS_DIR}/${DTS_BASE}.dtsi"
    ok "USB供电默认状态已修改为关闭"
fi

# -------------- 步骤1：复制512MB专属DTS文件 --------------
echo ""
echo "[步骤 1/5] 复制512MB专属DTS/DTSI文件"
cp "${DTS_DIR}/${DTS_BASE}.dts" "${DTS_DIR}/${DTS_NEW}.dts"
ok "已创建 ${DTS_DIR}/${DTS_NEW}.dts"
[ -f "${DTS_DIR}/${DTS_BASE}.dtsi" ] && {
    cp "${DTS_DIR}/${DTS_BASE}.dtsi" "${DTS_DIR}/${DTS_NEW}.dtsi"
    ok "已创建 ${DTS_DIR}/${DTS_NEW}.dtsi"
} || info "无DTSI文件，跳过复制"

# -------------- 步骤2：修改512MB分区大小 --------------
echo ""
echo "[步骤 2/5] 修改512MB分区大小"
sed -i 's|reg = <0x5c0000 0x4000000>;|reg = <0x5c0000 0x1FA40000>;|g' \
    "${DTS_DIR}/${DTS_NEW}.dts"
ok "分区大小已从64MB更新为512MB"

# -------------- 步骤3：更新UBI分区定义 --------------
echo ""
echo "[步骤 3/5] 更新DTSI中UBI分区定义"
[ -f "${DTS_DIR}/${DTS_NEW}.dtsi" ] && {
    sed -i -e '/partition@5c0000 {/,/^[ \t]*};/ {
        s|compatible = "linux,ubi";|reg = <0x5c0000 0x1FA40000>;\n\t\tcompatible = "linux,ubi";|
    }' "${DTS_DIR}/${DTS_NEW}.dtsi"
    ok "UBI分区配置已更新为512MB"
} || info "无DTSI文件，跳过UBI修改"

# -------------- 步骤4：写入25.12格式设备定义 --------------
echo ""
echo "[步骤 4/5] 写入25.12专属Makefile设备定义"
if grep -q "define Device/${DEVICE_NAME}" "${IMAGE_MK}"; then
    warn "设备 ${DEVICE_NAME} 已存在，跳过写入"
else
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
    ok "25.12版本设备定义已写入 ${IMAGE_MK}"
fi

# -------------- 步骤5：写入25.12标准targetinfo --------------
echo ""
echo "[步骤 5/5] 写入25.12专属.targetinfo配置"
if grep -q "^${DEVICE_NAME}:" "${TARGETINFO}" 2>/dev/null; then
    warn "${DEVICE_NAME} 已存在于.targetinfo，跳过写入"
else
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
    ok "25.12专属.targetinfo配置已追加"
fi

# 自动规范化缩进，完全规避25.12的Tab字符校验
info "自动规范化.targetinfo缩进，替换所有Tab为4个空格"
sed -i 's/\t/    /g' "${TARGETINFO}"

# -------------- 25.12专属缓存清理与验证 --------------
echo ""
echo "============================================="
echo "  清理构建缓存，验证设备识别状态"
echo "============================================="
make clean >/dev/null 2>&1 || true

if make info 2>/dev/null | grep -q "${DEVICE_NAME}"; then
    ok "✅ ${DEVICE_NAME} 已被ImmortalWrt 25.12.x ImageBuilder完全识别！"
else
    warn "⚠️  make info 未找到设备，请检查："
    echo "  1. ${IMAGE_MK} 中TARGET_DEVICES是否追加成功"
    echo "  2. ${TARGETINFO} 缩进是否全部为空格，无Tab字符"
    echo "  3. ${DTS_DIR}/${DTS_NEW}.dts 是否存在且语法正确"
fi

# -------------- 显示最终生成的targetinfo内容 --------------
echo ""
info "${TARGETINFO} 中生成的设备条目："
echo "----------------------------------------"
grep -A 15 "^${DEVICE_NAME}:" "${TARGETINFO}" 2>/dev/null || echo "  (未找到)"
echo "----------------------------------------"

# -------------- 完成提示 --------------
echo ""
echo "============================================="
echo "  ✅ ImmortalWrt 25.12.x 适配全部完成"
echo "============================================="
echo ""
echo " 📦 构建固件命令："
echo "    make image PROFILE=\"${DEVICE_NAME}\""
echo ""
echo " 📂 固件输出路径："
echo "    bin/targets/${PLATFORM}/${SUBTARGET}/"
echo ""
echo " 🔧 自定义扩展软件包："
echo "    make image PROFILE=\"${DEVICE_NAME}\" PACKAGES=\"kmod-xxx kmod-yyy\""
echo ""
echo " 📏 调整根分区大小："
echo "    make image PROFILE=\"${DEVICE_NAME}\" ROOTFS_PARTSIZE=\"1024\""
echo "============================================="
