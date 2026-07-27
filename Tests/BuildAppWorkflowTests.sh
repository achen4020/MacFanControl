#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macfancontrol-build-app-test.XXXXXX")"
TOOLS_DIR="$TEST_DIR/tools"
MARKER="$TEST_DIR/release-environment"
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/scripts" "$TOOLS_DIR"
cp "$ROOT_DIR/build-app.sh" "$TEST_DIR/build-app.sh"

cat > "$TOOLS_DIR/security" <<'EOF'
#!/bin/bash
printf '%s\n' \
  '  1) 0123456789ABCDEF0123456789ABCDEF01234567 "Developer ID Application: Example Org (ABCDE12345)"' \
  '     1 valid identities found'
EOF

cat > "$TOOLS_DIR/swift" <<'EOF'
#!/bin/bash
exit 75
EOF

cat > "$TEST_DIR/scripts/build-developer-id-release.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n%s\n' \
  "${DEVELOPER_ID_APPLICATION:-}" \
  "${DEVELOPMENT_TEAM:-}" > "${FAKE_RELEASE_MARKER:?}"
EOF
chmod +x "$TOOLS_DIR/security" "$TOOLS_DIR/swift" \
  "$TEST_DIR/scripts/build-developer-id-release.sh"

if ! PATH="$TOOLS_DIR:/usr/bin:/bin" \
    FAKE_RELEASE_MARKER="$MARKER" \
    bash "$TEST_DIR/build-app.sh" </dev/null; then
    echo "FAIL: build-app.sh 未委托给 Developer ID 构建流程" >&2
    exit 1
fi

[[ "$(sed -n '1p' "$MARKER")" == '0123456789ABCDEF0123456789ABCDEF01234567' ]] \
  || { echo "FAIL: 未自动选择 Developer ID Application 身份" >&2; exit 1; }
[[ "$(sed -n '2p' "$MARKER")" == 'ABCDE12345' ]] \
  || { echo "FAIL: 未从签名身份提取 Team ID" >&2; exit 1; }

echo "Build app workflow checks passed."
