#!/bin/bash

set -euo pipefail

fail() {
    printf '错误：%s\n' "$1" >&2
    exit 1
}

[[ $# -eq 3 ]] \
    || fail "用法：$0 <MacFanControl.app> <semantic-version> <keychain-profile>"

APP_PATH="$1"
VERSION="$2"
KEYCHAIN_PROFILE="$3"

SEMANTIC_VERSION_PATTERN='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
[[ "$VERSION" =~ $SEMANTIC_VERSION_PATTERN ]] \
    || fail "版本必须是安全的语义化版本号"

version_without_build="${VERSION%%+*}"
if [[ "$version_without_build" == *-* ]]; then
    prerelease="${version_without_build#*-}"
    remaining_identifiers="$prerelease"
    while [[ -n "$remaining_identifiers" ]]; do
        if [[ "$remaining_identifiers" == *.* ]]; then
            prerelease_identifier="${remaining_identifiers%%.*}"
            remaining_identifiers="${remaining_identifiers#*.}"
        else
            prerelease_identifier="$remaining_identifiers"
            remaining_identifiers=
        fi
        if [[ "$prerelease_identifier" =~ ^[0-9]+$ \
            && "$prerelease_identifier" == 0* \
            && "$prerelease_identifier" != '0' ]]; then
            fail "版本必须是安全的语义化版本号：数字预发布标识不能有前导零"
        fi
    done
fi
[[ -n "$KEYCHAIN_PROFILE" ]] || fail "keychain profile 不能为空"
[[ -d "$APP_PATH" && -f "$APP_PATH/Contents/Info.plist" ]] \
    || fail "应用包不存在或结构无效：$APP_PATH"

APP_DIRECTORY="$(cd "$(dirname "$APP_PATH")" && pwd -P)"
APP_PATH="$APP_DIRECTORY/$(basename "$APP_PATH")"
ZIP_NAME="MacFanControl_v${VERSION}.zip"
SHA_NAME="$ZIP_NAME.sha256"
OUTPUT_ZIP="$APP_DIRECTORY/$ZIP_NAME"
OUTPUT_SHA="$APP_DIRECTORY/$SHA_NAME"

WORK_DIR="$(mktemp -d "$APP_DIRECTORY/.notarize-release.XXXXXX")"
chmod 700 "$WORK_DIR"
SUBMISSION_ZIP="$WORK_DIR/submission.zip"
SUBMISSION_JSON="$WORK_DIR/submission.json"
STAGED_ZIP="$WORK_DIR/$ZIP_NAME"
STAGED_SHA="$WORK_DIR/$SHA_NAME"
STAGED_APP="$WORK_DIR/$(basename "$APP_PATH")"
BACKUP_ZIP="$WORK_DIR/previous.zip"
BACKUP_SHA="$WORK_DIR/previous.sha256"
HAD_OUTPUT_ZIP=false
HAD_OUTPUT_SHA=false
PUBLISHED_ZIP=false
PUBLISHED_SHA=false
PUBLISH_COMPLETE=false

cleanup() {
    local exit_status=$?
    local can_remove_work_dir=true
    trap - EXIT
    trap '' INT TERM HUP
    set +e

    if [[ "$PUBLISH_COMPLETE" != true ]]; then
        if [[ "$PUBLISHED_SHA" == true ]]; then
            rm -f "$OUTPUT_SHA" || can_remove_work_dir=false
        fi
        if [[ "$PUBLISHED_ZIP" == true ]]; then
            rm -f "$OUTPUT_ZIP" || can_remove_work_dir=false
        fi
        if [[ "$HAD_OUTPUT_ZIP" == true && -e "$BACKUP_ZIP" ]]; then
            mv "$BACKUP_ZIP" "$OUTPUT_ZIP" || can_remove_work_dir=false
        fi
        if [[ "$HAD_OUTPUT_SHA" == true && -e "$BACKUP_SHA" ]]; then
            mv "$BACKUP_SHA" "$OUTPUT_SHA" || can_remove_work_dir=false
        fi
    fi

    if [[ "$can_remove_work_dir" == true ]]; then
        rm -rf "$WORK_DIR"
    else
        printf '警告：旧发布产物恢复失败，暂存目录保留在：%s\n' "$WORK_DIR" >&2
    fi
    exit "$exit_status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

json_field() {
    local field="$1"
    /usr/bin/plutil -extract "$field" raw -o - "$SUBMISSION_JSON" 2>/dev/null || true
}

fetch_notarization_log() {
    local submission_id="$1"
    if [[ -n "$submission_id" ]]; then
        printf '获取公证日志（submission ID：%s）……\n' "$submission_id" >&2
        xcrun notarytool log "$submission_id" \
            --keychain-profile "$KEYCHAIN_PROFILE" >&2 || true
    fi
}

printf '创建公证提交包……\n'
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$SUBMISSION_ZIP"

printf '提交 Apple 公证并等待结果……\n'
if ! xcrun notarytool submit "$SUBMISSION_ZIP" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait \
    --output-format json > "$SUBMISSION_JSON"; then
    submission_id="$(json_field id)"
    fetch_notarization_log "$submission_id"
    fail "公证提交失败${submission_id:+（submission ID：${submission_id}）}"
fi

submission_id="$(json_field id)"
submission_status="$(json_field status)"
if [[ -z "$submission_id" || "$submission_status" != 'Accepted' ]]; then
    fetch_notarization_log "$submission_id"
    if [[ -z "$submission_id" || -z "$submission_status" ]]; then
        fail "无法解析公证结果"
    fi
    fail "公证未通过（submission ID：${submission_id}，状态：${submission_status}）"
fi

printf '公证已通过（submission ID：%s），装订并验证票据……\n' "$submission_id"
ditto "$APP_PATH" "$STAGED_APP"
xcrun stapler staple "$STAGED_APP"
xcrun stapler validate "$STAGED_APP"
spctl --assess --type execute "$STAGED_APP"

printf '创建最终发布包和 SHA-256……\n'
ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$STAGED_ZIP"
checksum_output="$(shasum -a 256 "$STAGED_ZIP")"
checksum="${checksum_output%%[[:space:]]*}"
[[ "$checksum" =~ ^[A-Fa-f0-9]{64}$ ]] || fail "无法生成有效的 SHA-256"
printf '%s  %s\n' "$checksum" "$ZIP_NAME" > "$STAGED_SHA"

trap '' INT TERM HUP
if [[ -e "$OUTPUT_ZIP" ]]; then
    mv "$OUTPUT_ZIP" "$BACKUP_ZIP" || fail "无法备份已有发布 ZIP"
    HAD_OUTPUT_ZIP=true
fi
if [[ -e "$OUTPUT_SHA" ]]; then
    mv "$OUTPUT_SHA" "$BACKUP_SHA" || fail "无法备份已有 SHA-256 文件"
    HAD_OUTPUT_SHA=true
fi

mv "$STAGED_ZIP" "$OUTPUT_ZIP" || fail "无法发布最终 ZIP"
PUBLISHED_ZIP=true
mv "$STAGED_SHA" "$OUTPUT_SHA" || fail "无法发布 SHA-256 文件"
PUBLISHED_SHA=true
PUBLISH_COMPLETE=true
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

printf '公证发布包已生成：%s\n' "$OUTPUT_ZIP"
printf 'SHA-256 文件已生成：%s\n' "$OUTPUT_SHA"
