#!/bin/bash

# install-helper.sh - 安装 Privileged Helper Tool
# 需要管理员权限

set -e

HELPER_NAME="MacFanControlHelper"
HELPER_ID="com.macfancontrol.helper"
HELPER_PATH="/Library/PrivilegedHelperTools/$HELPER_ID"
LAUNCHD_PLIST="/Library/LaunchDaemons/$HELPER_ID.plist"

cd "$(dirname "$0")"

echo "=== Mac 风扇控制 Helper 安装程序 ==="
echo ""

# 检查是否以 root 运行
if [ "$EUID" -ne 0 ]; then
    echo "⚠️  需要管理员权限，请输入密码..."
    exec sudo "$0" "$@"
fi

# 编译
echo "🔧 编译 Helper Tool..."
swift build -c release 2>&1

if [ $? -ne 0 ]; then
    echo "❌ 编译失败"
    exit 1
fi

echo "✅ 编译成功"

# 停止现有服务
if launchctl list | grep -q "$HELPER_ID"; then
    echo "🛑 停止现有 Helper 服务..."
    launchctl unload "$LAUNCHD_PLIST" 2>/dev/null || true
fi

# 创建目录
echo "📁 创建目录..."
mkdir -p /Library/PrivilegedHelperTools

# 复制 Helper
echo "📋 安装 Helper Tool..."
cp ".build/release/$HELPER_NAME" "$HELPER_PATH"
chmod 544 "$HELPER_PATH"
chown root:wheel "$HELPER_PATH"

# 复制 launchd plist
echo "📋 安装 launchd 配置..."
cp "Helper/$HELPER_ID.plist" "$LAUNCHD_PLIST"
chmod 644 "$LAUNCHD_PLIST"
chown root:wheel "$LAUNCHD_PLIST"

# 加载服务
echo "🚀 启动 Helper 服务..."
launchctl load "$LAUNCHD_PLIST"

# 验证
sleep 1
if launchctl list | grep -q "$HELPER_ID"; then
    echo ""
    echo "✅ Helper Tool 安装成功！"
    echo ""
    echo "Helper 位置: $HELPER_PATH"
    echo "配置文件: $LAUNCHD_PLIST"
    echo ""
    echo "现在可以运行主应用: ./.build/release/MacFanControl"
else
    echo ""
    echo "⚠️  Helper 可能未正确启动，请检查日志:"
    echo "   sudo log show --predicate 'subsystem == \"com.macfancontrol.helper\"' --last 5m"
fi
