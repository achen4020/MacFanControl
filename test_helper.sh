#!/bin/bash
# 测试 MacFanControl Helper Tool
# 需要 sudo 权限运行

echo "MacFanControl Helper 测试"
echo "========================="

# 检查 helper 是否已安装
if [ ! -f "/Library/PrivilegedHelperTools/com.macfancontrol.helper" ]; then
    echo "错误: Helper Tool 未安装"
    echo "请先运行: ./install_helper.sh"
    exit 1
fi

# 加载 helper daemon
echo "正在加载 Helper Daemon..."
sudo launchctl unload /Library/LaunchDaemons/com.macfancontrol.helper.plist 2>/dev/null
sudo launchctl load /Library/LaunchDaemons/com.macfancontrol.helper.plist

sleep 2

# 检查是否运行
if launchctl list | grep -q macfancontrol; then
    echo "Helper Daemon 已启动"
else
    echo "警告: Helper Daemon 可能未启动"
fi

# 查看 helper 日志
echo ""
echo "Helper 日志 (最近 10 条):"
echo "-------------------------"
log show --predicate 'process == "com.macfancontrol.helper"' --last 1m 2>/dev/null | tail -10

echo ""
echo "测试完成。请运行 MacFanControl 应用查看结果。"
