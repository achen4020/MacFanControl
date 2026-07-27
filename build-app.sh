#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SIGNED_BUILD_SCRIPT="$ROOT_DIR/scripts/build-developer-id-release.sh"

fail() {
    printf '错误：%s\n' "$1" >&2
    exit 1
}

[[ -x "$SIGNED_BUILD_SCRIPT" ]] \
    || fail "找不到 Developer ID 构建脚本：$SIGNED_BUILD_SCRIPT"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" || -n "${DEVELOPMENT_TEAM:-}" ]]; then
    [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]] \
        || fail "设置 DEVELOPMENT_TEAM 时也必须设置 DEVELOPER_ID_APPLICATION"
    [[ -n "${DEVELOPMENT_TEAM:-}" ]] \
        || fail "设置 DEVELOPER_ID_APPLICATION 时也必须设置 DEVELOPMENT_TEAM"
    exec "$SIGNED_BUILD_SCRIPT"
fi

IDENTITIES="$(security find-identity -v -p codesigning)" \
    || fail "无法读取钥匙串中的代码签名身份"
IDENTITY_PATTERN='^[[:space:]]*[0-9]+\)[[:space:]]+([A-F0-9]{40})[[:space:]]+"Developer ID Application:.*\(([A-Z0-9]{10})\)"[[:space:]]*$'

while IFS= read -r identity_line; do
    if [[ "$identity_line" =~ $IDENTITY_PATTERN ]]; then
        export DEVELOPER_ID_APPLICATION="${BASH_REMATCH[1]}"
        export DEVELOPMENT_TEAM="${BASH_REMATCH[2]}"
        printf '使用 Developer ID Application（Team ID：%s）构建应用。\n' \
            "$DEVELOPMENT_TEAM"
        exec "$SIGNED_BUILD_SCRIPT"
    fi
done <<< "$IDENTITIES"

fail "钥匙串中找不到 Developer ID Application 证书；无签名构建无法注册安全风扇控制服务"
