# 🔍 内核版本错误诊断与修复

## 🚨 问题分析

错误信息：
```
Missing kernel version/hash file for . Please create /home/build/immortalwrt/target/linux/generic/kernel-
```

**关键观察：** 错误路径 `kernel-` 结尾是空的，说明内核版本变量没有正确设置。

## 🔎 问题根源

这 **不是脚本问题**，而是 ImageBuilder 环境配置问题：

1. **镜像标签错误** - 可能使用了不兼容的 ImmortalWrt 镜像
2. **内核版本文件缺失** - ImageBuilder 中的内核配置文件损坏
3. **工作流配置问题** - build-wireless-router25.12.yml 中的镜像标签可能过时

## 📋 检查步骤

### 1. 检查当前使用的镜像标签

查看 `.github/workflows/build-wireless-router25.12.yml`：

```yaml
# 可能需要检查的部分
tag=mediatek-filogic-openwrt-25.12.1
# 或者
tag=mediatek-filogic-openwrt-23.05.4
```

### 2. 检查内核版本文件

在 ImageBuilder 容器中执行：

```bash
cd /home/build/immortalwrt

# 检查内核版本配置
cat include/kernel-version.mk

# 查找内核版本文件
ls -la target/linux/*/kernel-* 2>/dev/null || echo "无内核版本文件"

# 检查目标平台配置
ls -la target/linux/mediatek/
```

### 3. 验证 ImageBuilder 完整性

```bash
cd /home/build/immortalwrt

# 检查关键配置文件
ls -la include/ | grep kernel
ls -la target/linux/generic/ | grep kernel

# 尝试获取内核版本
cat include/kernel-version.mk | grep LINUX_VERSION
cat include/kernel-version.mk | grep LINUX_KERNEL_HASH
```

## ✅ 解决方案

### 方案 1: 修复 workflow 镜像标签（推荐）

编辑 `.github/workflows/build-wireless-router25.12.yml`：

```yaml
# 查找并修改镜像标签
# 确保 mediatek-filogic 使用正确的标签

case "$profile" in
cudy_tr3000-512mb-v1)
    # 使用正确的镜像标签
    tag=mediatek-filogic-openwrt-25.12.1
    echo "platform=mediatek/filogic" >> $GITHUB_ENV
    ;;
esac
```

### 方案 2: 创建缺失的内核版本文件

在 workflow 中添加修复步骤：

```yaml
- name: Fix kernel version files
  run: |
    cd /home/build/immortalwrt
    # 检查并创建内核版本文件
    if [ ! -f "include/kernel-version.mk" ]; then
      error "kernel-version.mk 缺失"
    fi
```

### 方案 3: 使用已知的正确镜像标签

根据 ImmortalWrt 25.12.x 的正确标签：

```yaml
# 对于 mediatek-filogic 平台
immortalwrt/imagebuilder:mediatek-filogic-openwrt-25.12.1

# 或者尝试快照版本
immortalwrt/imagebuilder:mediatek-filogic-snapshot
```

## 🔧 临时修复脚本

创建修复内核版本的脚本：<tool_call>content</arg_key><arg_value>#!/bin/bash
# 内核版本修复脚本
cd /home/build/immortalwrt

echo "============================================="
echo " 🔧 内核版本文件诊断"
echo "============================================="

# 检查当前内核版本配置
if [ -f "include/kernel-version.mk" ]; then
    echo "✅ kernel-version.mk 存在"
    echo ""
    echo "当前内容："
    cat include/kernel-version.mk
else
    echo "❌ kernel-version.mk 缺失"
fi

echo ""
echo "============================================="
echo " 检查内核相关文件"
echo "============================================="

# 查找所有内核版本相关文件
echo "📁 内核版本文件："
find target/linux/ -name "kernel-*" -type f 2>/dev/null

echo ""
echo "📁 内核配置文件："
find target/linux/mediatek/ -name "*.config" -type f 2>/dev/null | head -5

echo ""
echo "============================================="
echo " 诊断建议"
echo "============================================="

# 检查 ImageBuilder 镜像信息
if [ -f ".imagebuilder_info" ] || [ -f "VERSION" ]; then
    echo "📋 ImageBuilder 信息："
    cat .imagebuilder_info 2>/dev/null || cat VERSION 2>/dev/null
fi

echo ""
echo "🎯 如果此脚本显示 kernel-version.mk 存在但仍有错误，"
echo "   问题可能在于："
echo "   1. 镜像标签不正确"
echo "   2. ImageBuilder 环境损坏"
echo "   3. 需要重新拉取镜像"
echo ""
echo "💡 建议检查 workflow 文件中的镜像标签设置"
echo "============================================="
