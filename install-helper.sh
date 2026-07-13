#!/bin/bash

set -euo pipefail

cat >&2 <<'EOF'
错误：旧版 Helper 安装脚本已停用。
请启动 Developer ID 签名的 MacFanControl.app，并在应用内安装风扇控制服务。
新版使用 SMAppService 与双向代码签名校验，不再向 /Library/PrivilegedHelperTools 手工复制 Helper。
EOF
exit 1
