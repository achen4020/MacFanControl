#!/bin/bash

set -euo pipefail

VERSION="1.1.2"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/Info.plist)" == "${VERSION}" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sources/Info.plist)" == "${VERSION}" ]]
rg -q '版本 1\.1\.2' Sources/SettingsViews.swift
rg -q 'version-1\.1\.2-blue' README.md
rg -q 'MacFanControl_v1\.1\.2\.zip' README.md
rg -q '^## MacFanControl v1\.1\.2$' docs/releases/v1.1.2.md

for text in '区域截图' 'SSD 存储' '网络上传下载' '自定义曲线' '屏幕录制权限'; do
    rg -q "${text}" README.md
done

echo "Release metadata and README checks passed for ${VERSION}"
