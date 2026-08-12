#!/usr/bin/env bash
# メインアプリを仮想環境のPythonで起動する。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

PYTHON="$REPO_DIR/venv/bin/python"
if [[ ! -x "$PYTHON" ]]; then
    echo "エラー: venv がありません。先に ./setup.sh を実行してください。" >&2
    exit 1
fi

exec "$PYTHON" -m app.main
