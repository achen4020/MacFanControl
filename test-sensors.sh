#!/bin/bash
# 测试 M4 Mac 上可用的温度获取方式

echo "=== Mac mini M4 温度测试 ==="
echo ""

echo "1. 检查 IOHIDEventSystem (需要编译测试)..."
echo ""

echo "2. 使用 powermetrics 获取温度 (需要 sudo):"
echo "   sudo powermetrics --samplers smc -i1 -n1"
echo ""

echo "3. 检查 thermal 相关 sysctl:"
sysctl -a 2>/dev/null | grep -i thermal | head -10
echo ""

echo "4. 检查 ioreg 中的温度传感器:"
ioreg -l 2>/dev/null | grep -i "temperature" | head -5
echo ""

echo "5. 检查 HID 温度传感器服务:"
ioreg -r -c IOHIDEventService 2>/dev/null | grep -E "Product|temperature|Temperature" | head -20
echo ""

echo "6. 检查 AppleARMIODevice:"
ioreg -r -c AppleARMIODevice 2>/dev/null | grep -i temp | head -10
echo ""

echo "=== 测试完成 ==="
echo ""
echo "如果上面没有找到温度信息，可能需要使用 sudo 运行 powermetrics:"
echo "  sudo powermetrics --samplers smc -i1 -n1 2>&1 | grep -i temp"
