#!/bin/bash

# 创建 MacFanControl.app 应用程序包
# 使用方法: ./build-app.sh

cd "$(dirname "$0")"

APP_NAME="MacFanControl"
APP_BUNDLE="${APP_NAME}.app"

echo "=== 构建 Mac 风扇控制应用 ==="
echo ""

# 1. 编译 Swift 应用 (Release 版本)
echo "[1/5] 编译 Swift 应用..."
swift build -c release 2>&1

if [ $? -ne 0 ]; then
    echo "编译失败"
    exit 1
fi

# 2. 编译 smc_helper
echo "[2/5] 编译 SMC Helper..."
clang -framework IOKit -framework CoreFoundation -O2 -o smc_helper smc_helper.c

if [ $? -ne 0 ]; then
    echo "SMC Helper 编译失败"
    exit 1
fi

# 3. 创建应用程序包
echo "[3/5] 创建应用程序包..."

# 清理旧的应用包
rm -rf "${APP_BUNDLE}"

# 创建目录结构
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# 复制可执行文件
cp ".build/release/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"

# 复制 smc_helper 到 Resources
cp smc_helper "${APP_BUNDLE}/Contents/Resources/"
chmod +x "${APP_BUNDLE}/Contents/Resources/smc_helper"

# 复制图标文件
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "${APP_BUNDLE}/Contents/Resources/"
elif [ -f "logo.png" ]; then
    # 如果没有 icns 但有 logo.png，自动生成
    echo "    生成应用图标..."
    mkdir -p AppIcon.iconset
    sips -z 16 16 logo.png --out AppIcon.iconset/icon_16x16.png 2>/dev/null
    sips -z 32 32 logo.png --out AppIcon.iconset/icon_16x16@2x.png 2>/dev/null
    sips -z 32 32 logo.png --out AppIcon.iconset/icon_32x32.png 2>/dev/null
    sips -z 64 64 logo.png --out AppIcon.iconset/icon_32x32@2x.png 2>/dev/null
    sips -z 128 128 logo.png --out AppIcon.iconset/icon_128x128.png 2>/dev/null
    sips -z 256 256 logo.png --out AppIcon.iconset/icon_128x128@2x.png 2>/dev/null
    sips -z 256 256 logo.png --out AppIcon.iconset/icon_256x256.png 2>/dev/null
    sips -z 512 512 logo.png --out AppIcon.iconset/icon_256x256@2x.png 2>/dev/null
    sips -z 512 512 logo.png --out AppIcon.iconset/icon_512x512.png 2>/dev/null
    sips -z 1024 1024 logo.png --out AppIcon.iconset/icon_512x512@2x.png 2>/dev/null
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
    cp AppIcon.icns "${APP_BUNDLE}/Contents/Resources/"
fi

# 创建 Info.plist
cat > "${APP_BUNDLE}/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.macfancontrol.app</string>
    <key>CFBundleName</key>
    <string>Mac风扇控制</string>
    <key>CFBundleDisplayName</key>
    <string>Mac 风扇控制</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>MacFanControl</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>用于通过快捷键选择并编辑屏幕区域截图。</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
EOF

# 创建 PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

echo "[4/5] 对应用程序包进行临时签名..."
codesign --force --deep --sign - \
    --requirements '=designated => identifier "com.macfancontrol.app"' \
    "${APP_BUNDLE}"

if [ $? -ne 0 ]; then
    echo "应用程序签名失败"
    exit 1
fi

echo "[5/5] 完成!"
echo ""
echo "=== 构建成功 ==="
echo ""
echo "应用程序: $(pwd)/${APP_BUNDLE}"
echo ""
echo "安装方法:"
echo "  方法1: 将 ${APP_BUNDLE} 拖到 /Applications 文件夹"
echo "  方法2: 运行 cp -r ${APP_BUNDLE} /Applications/"
echo ""
echo "运行方法:"
echo "  双击 ${APP_BUNDLE} 或运行: open ${APP_BUNDLE}"
echo ""

# 询问是否立即运行
read -p "是否立即运行应用? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    open "${APP_BUNDLE}"
fi
