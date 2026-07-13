#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/build-developer-id-release.sh"
NOTARIZE_SCRIPT="$ROOT_DIR/scripts/notarize-release.sh"
INFO_PLIST="$ROOT_DIR/Sources/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Sources/MacFanControl.entitlements"
LAUNCHD_PLIST="$ROOT_DIR/Helper/com.macfancontrol.helper.v2.plist"
FAKE_TOOLS="$ROOT_DIR/Tests/Fixtures/DeveloperIDTools"
LEGACY_INSTALLERS=("$ROOT_DIR/install-helper.sh" "$ROOT_DIR/install_smc_helper.sh")

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

require_pattern() {
    local pattern="$1"
    rg -q -- "$pattern" "$SCRIPT" || fail "missing release-script contract: $pattern"
}

[[ -f "$SCRIPT" ]] || fail "missing scripts/build-developer-id-release.sh"

for legacy_installer in "${LEGACY_INSTALLERS[@]}"; do
    [[ -f "$legacy_installer" ]] || fail "missing disabled legacy installer: $legacy_installer"
    rg -q '旧版.*安装脚本已停用' "$legacy_installer" \
        || fail "legacy installer is not clearly disabled: $legacy_installer"
    if rg -q 'launchctl[[:space:]]+(load|bootstrap)|cp .*PrivilegedHelperTools|chmod[[:space:]]+666' \
        "$legacy_installer"; then
        fail "legacy installer still performs privileged installation: $legacy_installer"
    fi
done

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
require_pattern '--identifier[[:space:]]+com\.macfancontrol\.helper\.v2'
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
cp "$LAUNCHD_PLIST" "$PIPELINE_ROOT/Helper/com.macfancontrol.helper.v2.plist"
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

[[ -f "$NOTARIZE_SCRIPT" ]] || fail "missing scripts/notarize-release.sh"

require_notarize_pattern() {
    local pattern="$1"
    rg -q -- "$pattern" "$NOTARIZE_SCRIPT" \
        || fail "missing notarization-script contract: $pattern"
}

require_notarize_pattern 'set -euo pipefail'
require_notarize_pattern 'ditto[[:space:]].*--keepParent'
require_notarize_pattern 'notarytool[[:space:]]+submit'
require_notarize_pattern '--keychain-profile'
require_notarize_pattern '--wait'
require_notarize_pattern '--output-format[[:space:]]+json'
require_notarize_pattern 'notarytool[[:space:]]+log'
require_notarize_pattern 'stapler[[:space:]]+staple'
require_notarize_pattern 'stapler[[:space:]]+validate'
require_notarize_pattern 'spctl[[:space:]]+--assess[[:space:]]+--type[[:space:]]+execute'
require_notarize_pattern 'shasum[[:space:]]+-a[[:space:]]+256'
require_notarize_pattern 'Accepted'
require_notarize_pattern 'mktemp'
require_notarize_pattern 'trap'

if rg -qi -- '--password|AC_PASSWORD|APPLE_ID_PASSWORD|NOTARY_PASSWORD' "$NOTARIZE_SCRIPT"; then
    fail "notarization script must use only a keychain profile"
fi

expect_notarize_argument_failure() {
    if bash "$NOTARIZE_SCRIPT" "$@" >/dev/null 2>&1; then
        fail "notarization script accepted invalid arguments: $*"
    fi
}

expect_notarize_argument_failure
expect_notarize_argument_failure '/missing/MacFanControl.app' '1.2.3'
expect_notarize_argument_failure '/missing/MacFanControl.app' '1.2.3' 'profile' 'extra'
expect_notarize_argument_failure '/missing/MacFanControl.app' '../1.2.3' 'profile'
expect_notarize_argument_failure '/missing/MacFanControl.app' '1.2.3' ''

NOTARY_TEST_DIR="$IDENTITY_TEST_DIR/notary-test"
NOTARY_TOOLS="$NOTARY_TEST_DIR/tools"
NOTARY_APP="$NOTARY_TEST_DIR/MacFanControl.app"
NOTARY_EVENTS="$NOTARY_TEST_DIR/events"
mkdir -p "$NOTARY_TOOLS" "$NOTARY_APP/Contents"
printf 'fake plist\n' > "$NOTARY_APP/Contents/Info.plist"

cat > "$NOTARY_TOOLS/ditto" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'ditto:%s\n' "$*" >> "${FAKE_NOTARY_EVENTS:?}"
if [[ "$1" == '-c' ]]; then
    destination="${!#}"
    printf 'fake zip\n' > "$destination"
else
    /bin/cp -R "$1" "$2"
fi
EOF

cat > "$NOTARY_TOOLS/xcrun" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'xcrun:%s\n' "$*" >> "${FAKE_NOTARY_EVENTS:?}"
if [[ "$1 $2" == 'notarytool submit' ]]; then
    if [[ -n "${FAKE_NOTARY_RESPONSE:-}" ]]; then
        printf '%s\n' "$FAKE_NOTARY_RESPONSE"
    else
        printf '{"id":"submission-123","status":"%s"}\n' "${FAKE_NOTARY_STATUS:?}"
    fi
    [[ "${FAKE_NOTARY_SUBMIT_FAIL:-0}" != '1' ]]
elif [[ "$1 $2" == 'stapler staple' ]]; then
    printf 'stapled\n' > "$3/Contents/fake-stapled-marker"
fi
EOF

cat > "$NOTARY_TOOLS/spctl" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'spctl:%s\n' "$*" >> "${FAKE_NOTARY_EVENTS:?}"
EOF

cat > "$NOTARY_TOOLS/shasum" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'shasum:%s\n' "$*" >> "${FAKE_NOTARY_EVENTS:?}"
printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  %s\n' "${!#}"
EOF
cat > "$NOTARY_TOOLS/mv" <<'EOF'
#!/bin/bash
set -euo pipefail
destination="${!#}"
source_path="$1"
marker="${FAKE_MV_FAILURE_MARKER:-}"
if [[ "${FAKE_MV_FAIL_SHA_ONCE:-0}" == '1' \
    && "$destination" == *'.zip.sha256' \
    && -n "$marker" \
    && ! -e "$marker" ]]; then
    : > "$marker"
    exit 75
fi
/bin/mv "$@"
signal_marker="${FAKE_MV_SIGNAL_MARKER:-}"
if [[ "${FAKE_MV_SIGNAL_AFTER_BACKUP:-0}" == '1' \
    && "$destination" == */previous.zip \
    && -n "$signal_marker" \
    && ! -e "$signal_marker" ]]; then
    : > "$signal_marker"
    kill -TERM "$PPID"
fi
EOF
chmod +x "$NOTARY_TOOLS/ditto" "$NOTARY_TOOLS/xcrun" \
    "$NOTARY_TOOLS/spctl" "$NOTARY_TOOLS/shasum" "$NOTARY_TOOLS/mv"

FINAL_ZIP="$NOTARY_TEST_DIR/MacFanControl_v1.2.3.zip"
FINAL_SHA="$FINAL_ZIP.sha256"
printf 'old zip\n' > "$FINAL_ZIP"
printf 'old sha\n' > "$FINAL_SHA"
: > "$NOTARY_EVENTS"

expect_semver_failure() {
    local version="$1"
    local output
    if output="$(bash "$NOTARIZE_SCRIPT" "$NOTARY_APP" "$version" 'Test-Profile' 2>&1)"; then
        fail "notarization script accepted invalid SemVer: $version"
    fi
    [[ "$output" == *'语义化版本号'* ]] \
        || fail "invalid SemVer did not fail version validation: $version"
}

expect_semver_failure '1.2.3-01'
expect_semver_failure '1.2.3-alpha.01'

expect_semver_reaches_app_validation() {
    local version="$1"
    local output
    if output="$(bash "$NOTARIZE_SCRIPT" '/missing/MacFanControl.app' \
        "$version" 'Test-Profile' 2>&1)"; then
        fail "missing app unexpectedly passed validation for SemVer: $version"
    fi
    [[ "$output" == *'应用包不存在'* ]] \
        || fail "valid SemVer was rejected before app validation: $version"
}

expect_semver_reaches_app_validation '1.2.3-0'
expect_semver_reaches_app_validation '1.2.3-alpha-beta+build.01'

if PATH="$NOTARY_TOOLS:$PATH" \
    FAKE_NOTARY_EVENTS="$NOTARY_EVENTS" \
    FAKE_NOTARY_STATUS='Rejected' \
    bash "$NOTARIZE_SCRIPT" "$NOTARY_APP" '1.2.3' 'Test-Profile' \
    >/dev/null 2>&1; then
    fail "rejected notarization unexpectedly succeeded"
fi
[[ "$(cat "$FINAL_ZIP")" == 'old zip' ]] \
    || fail "rejected notarization damaged the existing zip"
[[ "$(cat "$FINAL_SHA")" == 'old sha' ]] \
    || fail "rejected notarization damaged the existing checksum"
rg -q 'notarytool log submission-123 --keychain-profile Test-Profile' "$NOTARY_EVENTS" \
    || fail "rejected notarization did not fetch its log"
if rg -q 'stapler staple|spctl:|shasum:' "$NOTARY_EVENTS"; then
    fail "rejected notarization continued into publication checks"
fi

: > "$NOTARY_EVENTS"
if PATH="$NOTARY_TOOLS:$PATH" \
    FAKE_NOTARY_EVENTS="$NOTARY_EVENTS" \
    FAKE_NOTARY_STATUS='Accepted' \
    FAKE_NOTARY_SUBMIT_FAIL=1 \
    bash "$NOTARIZE_SCRIPT" "$NOTARY_APP" '1.2.3' 'Test-Profile' \
    >/dev/null 2>&1; then
    fail "failed notarytool submission unexpectedly succeeded"
fi
rg -q 'notarytool log submission-123 --keychain-profile Test-Profile' "$NOTARY_EVENTS" \
    || fail "failed submission with an id did not fetch its log"

: > "$NOTARY_EVENTS"
if PATH="$NOTARY_TOOLS:$PATH" \
    FAKE_NOTARY_EVENTS="$NOTARY_EVENTS" \
    FAKE_NOTARY_STATUS='unused' \
    FAKE_NOTARY_RESPONSE='{"id":"submission-parse-error"}' \
    bash "$NOTARIZE_SCRIPT" "$NOTARY_APP" '1.2.3' 'Test-Profile' \
    >/dev/null 2>&1; then
    fail "unparseable notarization result unexpectedly succeeded"
fi
rg -q 'notarytool log submission-parse-error --keychain-profile Test-Profile' "$NOTARY_EVENTS" \
    || fail "unparseable result with an id did not fetch its log"

: > "$NOTARY_EVENTS"
MV_FAILURE_MARKER="$NOTARY_TEST_DIR/mv-failed"
if PATH="$NOTARY_TOOLS:$PATH" \
    FAKE_NOTARY_EVENTS="$NOTARY_EVENTS" \
    FAKE_NOTARY_STATUS='Accepted' \
    FAKE_MV_FAIL_SHA_ONCE=1 \
    FAKE_MV_FAILURE_MARKER="$MV_FAILURE_MARKER" \
    bash "$NOTARIZE_SCRIPT" "$NOTARY_APP" '1.2.3' 'Test-Profile' \
    >/dev/null 2>&1; then
    fail "partial publication failure unexpectedly succeeded"
fi
[[ "$(cat "$FINAL_ZIP")" == 'old zip' ]] \
    || fail "partial publication failure did not restore the existing zip"
[[ "$(cat "$FINAL_SHA")" == 'old sha' ]] \
    || fail "partial publication failure did not restore the existing checksum"

SIGNAL_VERSION='1.2.3-0'
SIGNAL_ZIP="$NOTARY_TEST_DIR/MacFanControl_v${SIGNAL_VERSION}.zip"
SIGNAL_SHA="$SIGNAL_ZIP.sha256"
SIGNAL_MARKER="$NOTARY_TEST_DIR/mv-signalled"
printf 'old signal zip\n' > "$SIGNAL_ZIP"
printf 'old signal sha\n' > "$SIGNAL_SHA"
: > "$NOTARY_EVENTS"
PATH="$NOTARY_TOOLS:$PATH" \
FAKE_NOTARY_EVENTS="$NOTARY_EVENTS" \
FAKE_NOTARY_STATUS='Accepted' \
FAKE_MV_SIGNAL_AFTER_BACKUP=1 \
FAKE_MV_SIGNAL_MARKER="$SIGNAL_MARKER" \
bash "$NOTARIZE_SCRIPT" "$NOTARY_APP" "$SIGNAL_VERSION" 'Test-Profile' \
    >/dev/null 2>&1 || true
[[ -e "$SIGNAL_MARKER" ]] || fail "signal race fixture did not run"
signal_old_complete=false
signal_new_complete=false
if [[ "$(cat "$SIGNAL_ZIP" 2>/dev/null || true)" == 'old signal zip' \
    && "$(cat "$SIGNAL_SHA" 2>/dev/null || true)" == 'old signal sha' ]]; then
    signal_old_complete=true
fi
if [[ "$(cat "$SIGNAL_ZIP" 2>/dev/null || true)" == 'fake zip' \
    && "$(cat "$SIGNAL_SHA" 2>/dev/null || true)" \
        == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  MacFanControl_v${SIGNAL_VERSION}.zip" ]]; then
    signal_new_complete=true
fi
[[ "$signal_old_complete" == true || "$signal_new_complete" == true ]] \
    || fail "signal during publication left missing or mixed artifacts"

: > "$NOTARY_EVENTS"
PATH="$NOTARY_TOOLS:$PATH" \
FAKE_NOTARY_EVENTS="$NOTARY_EVENTS" \
FAKE_NOTARY_STATUS='Accepted' \
bash "$NOTARIZE_SCRIPT" "$NOTARY_APP" '1.2.3' 'Test-Profile' >/dev/null

[[ -f "$FINAL_ZIP" && -f "$FINAL_SHA" ]] \
    || fail "accepted notarization did not publish both artifacts"
[[ "$(cat "$FINAL_SHA")" \
    == 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  MacFanControl_v1.2.3.zip' ]] \
    || fail "checksum file format is not '<sha256><two spaces><filename>'"
[[ ! -e "$NOTARY_APP/Contents/fake-stapled-marker" ]] \
    || fail "notarization modified the caller's input app"
stapled_target="$(sed -n 's/^xcrun:stapler staple //p' "$NOTARY_EVENTS")"
[[ -n "$stapled_target" && "$stapled_target" != "$NOTARY_APP" \
    && "$stapled_target" == */.notarize-release.*/MacFanControl.app ]] \
    || fail "stapler did not target a private staged app copy"

submit_line="$(rg -n 'notarytool submit' "$NOTARY_EVENTS" | cut -d: -f1)"
staple_line="$(rg -n 'stapler staple' "$NOTARY_EVENTS" | cut -d: -f1)"
validate_line="$(rg -n 'stapler validate' "$NOTARY_EVENTS" | cut -d: -f1)"
assess_line="$(rg -n 'spctl:--assess --type execute' "$NOTARY_EVENTS" | cut -d: -f1)"
final_ditto_line="$(rg -n 'ditto:.*--keepParent' "$NOTARY_EVENTS" | tail -1 | cut -d: -f1)"
checksum_line="$(rg -n 'shasum:-a 256' "$NOTARY_EVENTS" | cut -d: -f1)"
[[ "$submit_line" -lt "$staple_line" \
    && "$staple_line" -lt "$validate_line" \
    && "$validate_line" -lt "$assess_line" \
    && "$assess_line" -lt "$final_ditto_line" \
    && "$final_ditto_line" -lt "$checksum_line" ]] \
    || fail "accepted notarization pipeline ran out of order"

printf 'Developer ID notarization contract checks passed.\n'
