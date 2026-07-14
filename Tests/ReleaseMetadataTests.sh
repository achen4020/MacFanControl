#!/bin/bash

set -euo pipefail

VERSION="1.1.1"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/Info.plist)" == "${VERSION}" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sources/Info.plist)" == "${VERSION}" ]]
rg -q '<string>1\.1\.1</string>' build-app.sh
rg -q '版本 1\.1\.1' Sources/SettingsViews.swift
rg -q 'version-1\.1\.1-blue' README.md
rg -q 'MacFanControl_v1\.1\.1\.zip' README.md
rg -q '^## MacFanControl v1\.1\.1$' docs/releases/v1.1.1.md

for text in '区域截图' 'SSD 存储' '网络上传下载' '自定义曲线' '屏幕录制权限'; do
    rg -q "${text}" README.md
done

echo "Release metadata and README checks passed for ${VERSION}"
