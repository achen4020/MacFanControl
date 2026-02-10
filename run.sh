#!/bin/bash

# Mac 风扇控制启动脚本
# 使用方法: ./run.sh

cd "$(dirname "$0")"

echo "🔧 编译 Mac 风扇控制..."
swift build -c release 2>&1

if [ $? -eq 0 ]; then
    echo "✅ 编译成功!"
    echo "🚀 启动应用..."
    echo ""
    echo "注意: 应用将在菜单栏运行，请查看屏幕右上角的风扇图标"
    echo "按 Ctrl+C 可退出"
    echo ""
    ./.build/release/MacFanControl
else
    echo "❌ 编译失败，请检查错误信息"
    exit 1
fi
