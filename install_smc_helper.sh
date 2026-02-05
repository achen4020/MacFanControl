#!/bin/bash
# 安装 SMC Helper 作为 LaunchDaemon
# 需要 sudo 权限

set -e

HELPER_NAME="com.macfancontrol.smchelper"
HELPER_PATH="/Library/PrivilegedHelperTools/$HELPER_NAME"
PLIST_PATH="/Library/LaunchDaemons/$HELPER_NAME.plist"
SOCKET_PATH="/var/run/$HELPER_NAME.sock"
SOURCE_PATH="./smc_helper"

echo "MacFanControl SMC Helper 安装程序"
echo "================================="

# 检查是否以 root 运行
if [ "$EUID" -ne 0 ]; then
    echo "请使用 sudo 运行此脚本"
    echo "用法: sudo ./install_smc_helper.sh"
    exit 1
fi

# 检查源文件
if [ ! -f "$SOURCE_PATH" ]; then
    echo "错误: 找不到 smc_helper 二进制文件"
    echo "请先编译: clang -framework IOKit -framework CoreFoundation -o smc_helper smc_helper.c"
    exit 1
fi

# 停止现有服务
echo "停止现有服务..."
launchctl unload "$PLIST_PATH" 2>/dev/null || true

# 创建目录
mkdir -p /Library/PrivilegedHelperTools

# 复制文件
echo "安装 Helper Tool..."
cp "$SOURCE_PATH" "$HELPER_PATH"
chown root:wheel "$HELPER_PATH"
chmod 755 "$HELPER_PATH"

# 创建 LaunchDaemon plist
echo "创建 LaunchDaemon 配置..."
cat > "$PLIST_PATH" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.macfancontrol.smchelper</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Library/PrivilegedHelperTools/com.macfancontrol.smchelper</string>
        <string>daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/var/log/com.macfancontrol.smchelper.log</string>
</dict>
</plist>
PLIST

chown root:wheel "$PLIST_PATH"
chmod 644 "$PLIST_PATH"

# 加载服务
echo "启动服务..."
launchctl load "$PLIST_PATH"

sleep 1

# 检查服务状态
if launchctl list | grep -q "$HELPER_NAME"; then
    echo ""
    echo "安装完成!"
    echo "Helper 服务已启动并以 root 权限运行"
    echo ""
    echo "现在可以直接运行 MacFanControl 应用了!"
else
    echo ""
    echo "警告: 服务可能未正确启动"
    echo "请检查: sudo launchctl list | grep macfancontrol"
fi
