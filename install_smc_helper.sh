#!/bin/bash

set -euo pipefail

cat >&2 <<'EOF'
错误：旧版 Socket Helper 安装脚本已停用。
请启动 Developer ID 签名的 MacFanControl.app，并在应用内安装风扇控制服务。
新版使用 SMAppService 与签名 XPC，不再创建 /var/run/com.macfancontrol.smchelper.sock。
EOF
exit 1
