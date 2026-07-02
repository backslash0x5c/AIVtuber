#!/usr/bin/env bash
# 手動起動用(デバッグ向け)。常用は systemctl --user start radio.target を推奨。
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
exec ./scripts/run_app.sh
