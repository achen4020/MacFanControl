#!/bin/bash

set -euo pipefail

VERSION="1.1.0"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/Info.plist)" == "${VERSION}" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sources/Info.plist)" == "${VERSION}" ]]
rg -q '<string>1\.1\.0</string>' build-app.sh
rg -q '版本 1\.1\.0' Sources/SettingsViews.swift

for text in '区域截图' 'SSD 存储' '网络上传下载' '自定义曲线' '屏幕录制权限'; do
    rg -q "${text}" README.md
done

echo "Release metadata and README checks passed for ${VERSION}"
