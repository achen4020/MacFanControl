#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/build-developer-id-release.sh"
INFO_PLIST="$ROOT_DIR/Sources/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Sources/MacFanControl.entitlements"
LAUNCHD_PLIST="$ROOT_DIR/Helper/com.macfancontrol.helper.plist"

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

printf 'Developer ID release contract checks passed.\n'
