#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_APP="$ROOT_DIR/MacFanControl.app"
ENTITLEMENTS="$ROOT_DIR/Sources/MacFanControl.entitlements"

fail() {
    printf '错误：%s\n' "$1" >&2
    exit 1
}

[[ -n "${DEVELOPER_ID_APPLICATION:-}" ]] || fail "必须设置 DEVELOPER_ID_APPLICATION"
[[ -n "${DEVELOPMENT_TEAM:-}" ]] || fail "必须设置 DEVELOPMENT_TEAM"

IDENTITIES="$(security find-identity -v -p codesigning)" \
    || fail "无法读取钥匙串中的代码签名身份"
DEVELOPER_IDENTITY_PATTERN='^[[:space:]]*[0-9]+\)[[:space:]]+([A-F0-9]{40})[[:space:]]+"(Developer ID Application:[^"]+)"[[:space:]]*$'
IDENTITY_MATCHED=false
while IFS= read -r identity_line; do
    if [[ "$identity_line" =~ $DEVELOPER_IDENTITY_PATTERN ]]; then
        identity_sha="${BASH_REMATCH[1]}"
        identity_name="${BASH_REMATCH[2]}"
        if [[ "$DEVELOPER_ID_APPLICATION" == "$identity_sha" \
            || "$DEVELOPER_ID_APPLICATION" == "$identity_name" ]]; then
            IDENTITY_MATCHED=true
            break
        fi
    fi
done <<< "$IDENTITIES"
unset IDENTITIES identity_line identity_sha identity_name

if [[ "$IDENTITY_MATCHED" != true ]]; then
    fail "钥匙串中找不到指定的 Developer ID Application 签名身份"
fi

WORK_DIR="$(mktemp -d "$ROOT_DIR/.developer-id-release.XXXXXX")"
chmod 700 "$WORK_DIR"
STAGED_APP="$WORK_DIR/MacFanControl.app"
BACKUP_APP="$WORK_DIR/MacFanControl.previous.app"
APP="$STAGED_APP"
APP_EXECUTABLE="$STAGED_APP/Contents/MacOS/MacFanControl"
HELPER_EXECUTABLE="$STAGED_APP/Contents/Resources/MacFanControlHelper"
PUBLISH_STARTED=false
PUBLISH_COMPLETE=false
HAD_OUTPUT=false

cleanup() {
    local exit_status=$?
    local can_remove_work_dir=true
    trap - EXIT INT TERM HUP
    set +e

    if [[ "$PUBLISH_COMPLETE" != true ]]; then
        if [[ -e "$BACKUP_APP" ]]; then
            if ! rm -rf "$OUTPUT_APP"; then
                can_remove_work_dir=false
            elif ! mv "$BACKUP_APP" "$OUTPUT_APP"; then
                can_remove_work_dir=false
            fi
        elif [[ "$PUBLISH_STARTED" == true && "$HAD_OUTPUT" != true ]]; then
            rm -rf "$OUTPUT_APP"
        fi
    fi

    if [[ "$can_remove_work_dir" == true ]]; then
        rm -rf "$WORK_DIR"
    else
        printf '警告：旧应用恢复失败，备份保留在：%s\n' "$BACKUP_APP" >&2
    fi
    exit "$exit_status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

APP_ARM_SCRATCH="$WORK_DIR/app-arm64"
APP_X86_SCRATCH="$WORK_DIR/app-x86_64"
HELPER_ARM_SCRATCH="$WORK_DIR/helper-arm64"
HELPER_X86_SCRATCH="$WORK_DIR/helper-x86_64"

printf '构建 arm64 主应用……\n'
swift build --package-path "$ROOT_DIR" -c release --arch arm64 \
    --scratch-path "$APP_ARM_SCRATCH" --product MacFanControl
APP_ARM_BIN_DIR="$(swift build --package-path "$ROOT_DIR" -c release --arch arm64 \
    --scratch-path "$APP_ARM_SCRATCH" --show-bin-path)"

printf '构建 x86_64 主应用……\n'
swift build --package-path "$ROOT_DIR" -c release --arch x86_64 \
    --scratch-path "$APP_X86_SCRATCH" --product MacFanControl
APP_X86_BIN_DIR="$(swift build --package-path "$ROOT_DIR" -c release --arch x86_64 \
    --scratch-path "$APP_X86_SCRATCH" --show-bin-path)"

printf '构建 arm64 Helper……\n'
swift build --package-path "$ROOT_DIR" -c release --arch arm64 \
    --scratch-path "$HELPER_ARM_SCRATCH" --product MacFanControlHelper
HELPER_ARM_BIN_DIR="$(swift build --package-path "$ROOT_DIR" -c release --arch arm64 \
    --scratch-path "$HELPER_ARM_SCRATCH" --show-bin-path)"

printf '构建 x86_64 Helper……\n'
swift build --package-path "$ROOT_DIR" -c release --arch x86_64 \
    --scratch-path "$HELPER_X86_SCRATCH" --product MacFanControlHelper
HELPER_X86_BIN_DIR="$(swift build --package-path "$ROOT_DIR" -c release --arch x86_64 \
    --scratch-path "$HELPER_X86_SCRATCH" --show-bin-path)"

[[ -x "$APP_ARM_BIN_DIR/MacFanControl" ]] || fail "arm64 主应用产物不存在"
[[ -x "$APP_X86_BIN_DIR/MacFanControl" ]] || fail "x86_64 主应用产物不存在"
[[ -x "$HELPER_ARM_BIN_DIR/MacFanControlHelper" ]] || fail "arm64 Helper 产物不存在"
[[ -x "$HELPER_X86_BIN_DIR/MacFanControlHelper" ]] || fail "x86_64 Helper 产物不存在"

mkdir -p \
    "$APP/Contents/MacOS" \
    "$APP/Contents/Resources" \
    "$APP/Contents/Library/LaunchDaemons"

cp "$ROOT_DIR/Sources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/Helper/com.macfancontrol.helper.v2.plist" \
    "$APP/Contents/Library/LaunchDaemons/com.macfancontrol.helper.v2.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

lipo -create \
    "$APP_ARM_BIN_DIR/MacFanControl" \
    "$APP_X86_BIN_DIR/MacFanControl" \
    -output "$APP_EXECUTABLE"
lipo -create \
    "$HELPER_ARM_BIN_DIR/MacFanControlHelper" \
    "$HELPER_X86_BIN_DIR/MacFanControlHelper" \
    -output "$HELPER_EXECUTABLE"
chmod 755 "$APP_EXECUTABLE" "$HELPER_EXECUTABLE"

verify_universal() {
    local binary="$1"
    local architectures
    architectures="$(lipo -archs "$binary")"
    [[ " $architectures " == *" arm64 "* ]] || fail "$binary 缺少 arm64 架构"
    [[ " $architectures " == *" x86_64 "* ]] || fail "$binary 缺少 x86_64 架构"
}

verify_universal "$APP_EXECUTABLE"
verify_universal "$HELPER_EXECUTABLE"

PLIST_BUNDLE_PROGRAM="$(/usr/libexec/PlistBuddy -c 'Print :BundleProgram' \
    "$APP/Contents/Library/LaunchDaemons/com.macfancontrol.helper.v2.plist")"
[[ "$PLIST_BUNDLE_PROGRAM" == "Contents/Resources/MacFanControlHelper" ]] \
    || fail "LaunchDaemon BundleProgram 与包内 Helper 路径不一致"

printf '签署 Helper……\n'
codesign --force --timestamp --options runtime \
    --sign "$DEVELOPER_ID_APPLICATION" \
    --identifier com.macfancontrol.helper.v2 \
    "$HELPER_EXECUTABLE"

printf '签署主应用……\n'
codesign --force --timestamp --options runtime \
    --sign "$DEVELOPER_ID_APPLICATION" \
    --entitlements "$ENTITLEMENTS" \
    "$APP"

codesign --verify --strict --verbose=2 "$HELPER_EXECUTABLE"
codesign --verify --strict --verbose=2 "$APP"

signature_details() {
    local signed_path="$1"
    codesign --display --verbose=4 "$signed_path" 2>&1
}

verify_signature_metadata() {
    local signed_path="$1"
    local details="$2"
    local team_id

    team_id="$(printf '%s\n' "$details" | sed -n 's/^TeamIdentifier=//p')"
    [[ -n "$team_id" ]] || fail "$signed_path 的签名缺少 TeamIdentifier"
    [[ "$team_id" == "$DEVELOPMENT_TEAM" ]] \
        || fail "$signed_path 的 TeamIdentifier 与 DEVELOPMENT_TEAM 不一致"
    grep -q '^Runtime Version=' <<< "$details" \
        || fail "$signed_path 未启用 Hardened Runtime"
    grep -q '^Timestamp=' <<< "$details" \
        || fail "$signed_path 的签名缺少 secure timestamp"

    printf '%s' "$team_id"
}

APP_DETAILS="$(signature_details "$APP_EXECUTABLE")"
HELPER_DETAILS="$(signature_details "$HELPER_EXECUTABLE")"
APP_TEAM_ID="$(verify_signature_metadata "$APP_EXECUTABLE" "$APP_DETAILS")"
HELPER_TEAM_ID="$(verify_signature_metadata "$HELPER_EXECUTABLE" "$HELPER_DETAILS")"
[[ "$APP_TEAM_ID" == "$HELPER_TEAM_ID" ]] \
    || fail "主应用与 Helper 的 Team ID 不一致"

if [[ -e "$OUTPUT_APP" ]]; then
    HAD_OUTPUT=true
    mv "$OUTPUT_APP" "$BACKUP_APP" \
        || fail "无法备份已有的 MacFanControl.app"
fi

PUBLISH_STARTED=true
mv "$STAGED_APP" "$OUTPUT_APP" \
    || fail "无法发布已验证的 MacFanControl.app"
PUBLISH_COMPLETE=true

printf 'Developer ID 应用构建完成：%s\n' "$OUTPUT_APP"
