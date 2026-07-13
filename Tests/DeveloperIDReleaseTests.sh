#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/build-developer-id-release.sh"
INFO_PLIST="$ROOT_DIR/Sources/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Sources/MacFanControl.entitlements"
LAUNCHD_PLIST="$ROOT_DIR/Helper/com.macfancontrol.helper.plist"
FAKE_TOOLS="$ROOT_DIR/Tests/Fixtures/DeveloperIDTools"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

require_pattern() {
    local pattern="$1"
    rg -q -- "$pattern" "$SCRIPT" || fail "missing release-script contract: $pattern"
}

[[ -f "$SCRIPT" ]] || fail "missing scripts/build-developer-id-release.sh"

require_pattern 'set -euo pipefail'
require_pattern 'DEVELOPER_ID_APPLICATION'
require_pattern 'DEVELOPMENT_TEAM'
require_pattern 'security[[:space:]]+find-identity'
require_pattern '--arch[[:space:]]+arm64'
require_pattern '--arch[[:space:]]+x86_64'
require_pattern 'lipo[[:space:]]+-create'
require_pattern 'lipo[[:space:]]+-archs'
require_pattern 'Contents/Library/LaunchDaemons'
require_pattern 'Contents/Resources/MacFanControlHelper'
require_pattern '--identifier[[:space:]]+com\.macfancontrol\.helper'
require_pattern '--timestamp'
require_pattern '--options[[:space:]]+runtime'
require_pattern '--entitlements'
require_pattern 'codesign[[:space:]]+--verify[[:space:]]+--strict'
require_pattern 'TeamIdentifier'
require_pattern 'Runtime Version'
require_pattern 'secure timestamp'
require_pattern 'mktemp'
require_pattern 'trap'

if rg -q -- '--deep|--sign[[:space:]]+-([[:space:]]|$)' "$SCRIPT"; then
    fail "release signing must not use --deep or ad-hoc signing"
fi

[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSHumanReadableCopyright' "$INFO_PLIST" 2>/dev/null || true)" \
    == 'Copyright © 2026 achen4020.' ]] || fail "Info.plist copyright is missing"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSApplicationCategoryType' "$INFO_PLIST" 2>/dev/null || true)" \
    == 'public.app-category.utilities' ]] || fail "Info.plist utilities category is missing"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO_PLIST" 2>/dev/null || true)" \
    == 'AppIcon' ]] || fail "Info.plist icon reference is missing"
[[ "$(plutil -convert json -o - "$ENTITLEMENTS")" == '{}' ]] \
    || fail "release entitlements must be empty"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :BundleProgram' "$LAUNCHD_PLIST")" \
    == 'Contents/Resources/MacFanControlHelper' ]] || fail "LaunchDaemon BundleProgram is incorrect"

expect_configuration_failure() {
    local expected="$1"
    shift
    local output
    if output="$(env "$@" bash "$SCRIPT" 2>&1)"; then
        fail "release script unexpectedly accepted invalid configuration"
    fi
    [[ "$output" == *"$expected"* ]] \
        || fail "release script did not report missing $expected"
}

expect_configuration_failure 'DEVELOPER_ID_APPLICATION' \
    -u DEVELOPER_ID_APPLICATION -u DEVELOPMENT_TEAM
expect_configuration_failure 'DEVELOPMENT_TEAM' \
    DEVELOPER_ID_APPLICATION=unused DEVELOPMENT_TEAM=

IDENTITY_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macfancontrol-identity-test.XXXXXX")"
trap 'rm -rf "$IDENTITY_TEST_DIR"' EXIT
SWIFT_MARKER="$IDENTITY_TEST_DIR/swift-called"
DEVELOPER_SHA='0123456789ABCDEF0123456789ABCDEF01234567'
DEVELOPER_NAME='Developer ID Application: Example Org (ABCDE12345)'
APPLE_DEVELOPMENT_NAME='Apple Development: Example Org (ABCDE12345)'
INSTALLER_NAME='Developer ID Installer: Example Org (ABCDE12345)'
FAKE_IDENTITIES="  1) $DEVELOPER_SHA \"$DEVELOPER_NAME\"
  2) FEDCBA9876543210FEDCBA9876543210FEDCBA98 \"$APPLE_DEVELOPMENT_NAME\"
  3) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA \"$INSTALLER_NAME\"
     3 valid identities found"

run_identity_preflight() {
    local identity="$1"
    rm -f "$SWIFT_MARKER"
    IDENTITY_OUTPUT="$(
        PATH="$FAKE_TOOLS:$PATH" \
        FAKE_SECURITY_IDENTITIES="$FAKE_IDENTITIES" \
        FAKE_SWIFT_MARKER="$SWIFT_MARKER" \
        DEVELOPER_ID_APPLICATION="$identity" \
        DEVELOPMENT_TEAM='ABCDE12345' \
        bash "$SCRIPT" 2>&1
    )" || IDENTITY_STATUS=$?
    IDENTITY_STATUS="${IDENTITY_STATUS:-0}"
}

assert_identity_accepted() {
    local identity="$1"
    IDENTITY_STATUS=
    run_identity_preflight "$identity"
    [[ -f "$SWIFT_MARKER" ]] \
        || fail "exact Developer ID identity did not reach the build stage"
}

assert_identity_rejected() {
    local identity="$1"
    IDENTITY_STATUS=
    run_identity_preflight "$identity"
    [[ "$IDENTITY_STATUS" -ne 0 ]] || fail "invalid signing identity was accepted"
    [[ ! -f "$SWIFT_MARKER" ]] || fail "invalid signing identity reached the build stage"
    [[ "$IDENTITY_OUTPUT" == *'找不到指定的 Developer ID Application 签名身份'* ]] \
        || fail "invalid signing identity did not fail during identity validation"
}

assert_identity_accepted "$DEVELOPER_NAME"
assert_identity_accepted "$DEVELOPER_SHA"
assert_identity_rejected "$APPLE_DEVELOPMENT_NAME"
assert_identity_rejected "$INSTALLER_NAME"
assert_identity_rejected 'Developer ID Application:'
assert_identity_rejected 'Example Org'

require_pattern 'OUTPUT_APP'
require_pattern 'STAGED_APP'
require_pattern '\.developer-id-release\.XXXXXX'
if rg -q '^APP="\$ROOT_DIR/MacFanControl\.app"$' "$SCRIPT"; then
    fail "build and signing must target a private staged app"
fi

last_verification_line="$(rg -n 'verify_signature_metadata' "$SCRIPT" | tail -1 | cut -d: -f1)"
publish_line="$(rg -n 'mv[[:space:]].*"\$STAGED_APP"[[:space:]]+"\$OUTPUT_APP"' "$SCRIPT" \
    | tail -1 | cut -d: -f1)"
[[ -n "$last_verification_line" && -n "$publish_line" \
    && "$publish_line" -gt "$last_verification_line" ]] \
    || fail "final output must be published only after signature metadata verification"

PIPELINE_ROOT="$IDENTITY_TEST_DIR/pipeline-root"
mkdir -p \
    "$PIPELINE_ROOT/scripts" \
    "$PIPELINE_ROOT/Sources" \
    "$PIPELINE_ROOT/Helper" \
    "$PIPELINE_ROOT/MacFanControl.app"
cp "$SCRIPT" "$PIPELINE_ROOT/scripts/build-developer-id-release.sh"
cp "$INFO_PLIST" "$PIPELINE_ROOT/Sources/Info.plist"
cp "$ENTITLEMENTS" "$PIPELINE_ROOT/Sources/MacFanControl.entitlements"
cp "$LAUNCHD_PLIST" "$PIPELINE_ROOT/Helper/com.macfancontrol.helper.plist"
cp "$ROOT_DIR/AppIcon.icns" "$PIPELINE_ROOT/AppIcon.icns"
printf 'keep-existing-output\n' > "$PIPELINE_ROOT/MacFanControl.app/sentinel"

rm -f "$SWIFT_MARKER"
if PATH="$FAKE_TOOLS:$PATH" \
    FAKE_SECURITY_IDENTITIES="$FAKE_IDENTITIES" \
    FAKE_SWIFT_MARKER="$SWIFT_MARKER" \
    FAKE_SWIFT_MODE=build \
    FAKE_CODESIGN_FAIL_APP=1 \
    DEVELOPER_ID_APPLICATION="$DEVELOPER_NAME" \
    DEVELOPMENT_TEAM='ABCDE12345' \
    bash "$PIPELINE_ROOT/scripts/build-developer-id-release.sh" >/dev/null 2>&1; then
    fail "fake app-signing failure unexpectedly succeeded"
fi
[[ "$(cat "$PIPELINE_ROOT/MacFanControl.app/sentinel" 2>/dev/null || true)" \
    == 'keep-existing-output' ]] \
    || fail "pre-publish failure damaged the existing output app"

printf 'Developer ID release contract checks passed.\n'
