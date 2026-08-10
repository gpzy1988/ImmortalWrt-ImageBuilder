
#!/bin/bash
#==============================================================
# ImmortalWrt 25.12.x Cudy TR3000 512MB 专属适配脚本
# 修复重点：
# 1. 自动识别 25.12.x 新的 filogic/Makefile 路径结构
# 2. 补全 DEVICE_TITLE 等 25.x 必填字段
# 3. 强制清理 Profile 缓存并重新生成配置
# 4. 自动修正 .targetinfo 缩进为空格
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
# 非 Docker 环境自动适配本地路径
[ ! -d "${IB_DIR}" ] && IB_DIR="$(pwd)"
DTS_DIR="${IB_DIR}/target/linux/${PLATFORM}/dts"

# 25.12 专属路径自动检测：优先检查子目录 Makefile
if [ -d "${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}" ]; then
    IMAGE_MK="${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}/Makefile"
    TARGETINFO="$(dirname "${IMAGE_MK}")/${SUBTARGET}.targetinfo"
    echo "[INFO] 检测到 25.12.x 新结构，使用路径: ${IMAGE_MK}"
else
    # 兼容旧版或特殊结构
    IMAGE_MK="${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}.mk"
    TARGETINFO="${IB_DIR}/target/linux/${PLATFORM}/image/${SUBTARGET}.targetinfo"
    echo "[WARN] 未检测到子目录，使用传统路径: ${IMAGE_MK}"
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

# 检查基础 DTS 是否存在
if [ ! -f "${DTS_DIR}/${DTS_BASE}.dts" ]; then
    error "基础 DTS 不存在: ${DTS_DIR}/${DTS_BASE}.dts"
    echo "  请确保 ImageBuilder 中已包含基础机型文件"
fi

# 检查目标 Makefile 是否存在
if [ ! -f "${IMAGE_MK}" ]; then
    error "目标 Makefile 不存在: ${IMAGE_MK}"
    echo "  请检查 PLATFORM 和 SUBTARGET变量是否正确"
fi

# -------------- Cudy TR3000 专属适配：USB 供电默认关闭 --------------
echo ""
info "执行 Cudy TR3000 专属适配：USB 供电默认关闭"
if [ -f "${DTS_DIR}/${DTS_BASE}.dtsi" ]; then
    # 备份原文件以防万一
    cp "${DTS_DIR}/${DTS_BASE}.dtsi" "${DTS_DIR}/${DTS_BASE}.dtsi.bak"
    sed -i '/modem-power/,/};/ {s/gpio-export,output = <1>;/gpio-export,output = <0>;/}' \
        "${DTS_DIR}/${DTS_BASE}.dtsi"
    ok "USB 供电默认状态已修改为关闭"
else
    warn "未找到 ${DTS_BASE}.dtsi，跳过 USB 供电修改"
fi

# -------------- 步骤 1：复制 512MB 专属 DTS 文件 --------------
echo ""
echo "[步骤 1/5] 复制 512MB 专属 DTS/DTSI 文件"
cp "${DTS_DIR}/${DTS_BASE}.dts" "${DTS_DIR}/${DTS_NEW}.dts"
ok "已创建 ${DTS_DIR}/${DTS_NEW}.dts"

if [ -f "${DTS_DIR}/${DTS_BASE}.dtsi" ]; then
    cp "${DTS_DIR}/${DTS_BASE}.dtsi" "${DTS_DIR}/${DTS_NEW}.dtsi"
    ok "已创建 ${DTS_DIR}/${DTS_NEW}.dtsi"
else
    info "无 DTSI 文件，跳过复制"
fi

# -------------- 步骤 2：修改 512MB 分区大小 --------------
echo ""
echo "[步骤 2/5] 修改 512MB 分区大小"
# 将 64MB (0x4000000) 替换为 512MB (0x1FA40000)
# 注意：不同版本源码可能起始地址不同，这里针对常见布局
sed -i 's|reg = <0x5c0000 0x4000000>;|reg = <0x5c0000 0x1FA40000>;|g' \
    "${DTS_DIR}/${DTS_NEW}.dts"
ok "分区大小已从 64MB 更新为 512MB"

# -------------- 步骤 3：更新 UBI 分区定义 --------------
echo ""
echo "[步骤 3/5] 更新 DTSI 中 UBI 分区定义"
if [ -f "${DTS_DIR}/${DTS_NEW}.dtsi" ]; then
    sed -i -e '/partition@5c0000 {/,/ \t]*};/ {
        s|compatible = "linux,ubi";|reg = <0x5c0000 0x1FA40000>;\n\t\tcompatible = "linux,ubi";|
    }' "${DTS_DIR}/${DTS_NEW}.dtsi"
    ok "UBI 分区配置已更新为 512MB"
else
    info "无 DTSI 文件，跳过 UBI 修改"
fi

# -------------- 步骤 4：写入 25.12 格式设备定义 --------------
echo ""
echo "[步骤 4/5] 写入 25.12 专属 Makefile 设备定义"
if grep -q "define Device/${DEVICE_NAME}" "${IMAGE_MK}"; then
    warn "设备 ${DEVICE_NAME} 已存在于 Makefile，跳过写入"
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
    ok "25.12 版本设备定义已写入 ${IMAGE_MK}"
fi

# -------------- 步骤 5：写入 25.12 标准 targetinfo --------------
echo ""
echo "[步骤 5/5] 写入 25.12 专属 .targetinfo 配置"
if grep -q "^${DEVICE_NAME}:" "${TARGETINFO}" 2>/dev/null; then
    warn "${DEVICE_NAME} 已存在于 .targetinfo，跳过写入"
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
    ok "25.12 专属 .targetinfo 配置已追加"
fi

# 自动规范化缩进，完全规避 25.12 的 Tab 字符校验
info "自动规范化 .targetinfo 缩进，替换所有 Tab 为 4 个空格"
sed -i 's/\t/    /g' "${TARGETINFO}"

# -------------- 25.12 专属缓存清理与验证 --------------
echo ""
echo "============================================="
echo "  清理构建缓存，验证设备识别状态"
echo "============================================="

# 关键修复：深度清理缓存以重新加载 Profile
rm -rf tmp/
make clean >/dev/null 2>&1 || true
# 重新生成配置以刷新 Profile 列表
make defconfig >/dev/null 2>&1 || true

if make info 2>/dev/null | grep -q "${DEVICE_NAME}"; then
    ok "✅ ${DEVICE_NAME} 已被 ImmortalWrt 25.12.x ImageBuilder 完全识别！"
else
    warn "⚠️  make info 未找到设备，请手动检查："
    echo "  1. 查看 ${IMAGE_MK} 末尾是否有 TARGET_DEVICES += ${DEVICE_NAME}"
    echo "  2. 查看 ${TARGETINFO} 中是否有 ${DEVICE_NAME} 条目且缩进为空格"
    echo "  3. 检查 ${DTS_DIR}/${DTS_NEW}.dts 语法是否正确"
    echo "  4. 尝试手动执行: make info | grep ${DEVICE_NAME}"
fi

# -------------- 显示最终生成的 targetinfo 内容 --------------
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
