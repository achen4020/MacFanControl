#!/bin/bash

# uninstall-helper.sh - 卸载 Privileged Helper Tool

set -e

HELPER_ID="com.macfancontrol.helper"
HELPER_PATH="/Library/PrivilegedHelperTools/$HELPER_ID"
LAUNCHD_PLIST="/Library/LaunchDaemons/$HELPER_ID.plist"

echo "=== Mac 风扇控制 Helper 卸载程序 ==="
echo ""

# 检查是否以 root 运行
if [ "$EUID" -ne 0 ]; then
    echo "⚠️  需要管理员权限，请输入密码..."
    exec sudo "$0" "$@"
fi

# 停止服务
if launchctl list | grep -q "$HELPER_ID"; then
    echo "🛑 停止 Helper 服务..."
    launchctl unload "$LAUNCHD_PLIST" 2>/dev/null || true
fi

# 删除文件
echo "🗑️  删除 Helper 文件..."
rm -f "$HELPER_PATH"
rm -f "$LAUNCHD_PLIST"

echo ""
echo "✅ Helper Tool 已卸载"
