#!/bin/bash

set -euo pipefail

APP_PATH="${1:-MacFanControl.app}"
REQUIREMENT="$(codesign -dr - "${APP_PATH}" 2>&1)"

if [[ "${REQUIREMENT}" == *"cdhash"* ]]; then
    echo "失败：应用指定要求依赖 cdhash，重新构建后会导致 TCC 权限失效"
    echo "${REQUIREMENT}"
    exit 1
fi

if [[ "${REQUIREMENT}" != *'identifier "com.macfancontrol.app"'* ]]; then
    echo "失败：应用指定要求未绑定 com.macfancontrol.app"
    echo "${REQUIREMENT}"
    exit 1
fi

echo "通过：应用使用稳定的指定要求"
