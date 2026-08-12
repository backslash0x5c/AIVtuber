#!/usr/bin/env bash
# ヘッドレス(Xvfb)環境でOBSを起動する。
#
# 重要: obs-websocket の `--websocket_port` / `--websocket_password` は値を
# 上書きするだけで、**サーバーを有効化しない**(server_enabled の既定値は false)。
# そのため起動前に plugin_config/obs-websocket/config.json を書いて有効化する。
# これによりGUI操作は一切不要になる。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# .env から OBS_WS_PORT / OBS_WS_PASSWORD を読む
if [[ -f "$REPO_DIR/.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$REPO_DIR/.env"
    set +a
fi

if [[ -z "${OBS_WS_PASSWORD:-}" ]]; then
    echo "エラー: OBS_WS_PASSWORD が .env に設定されていません" >&2
    exit 1
fi

OBS_WS_PORT="${OBS_WS_PORT:-4455}"

# --- obs-websocket サーバーを有効化する ---------------------------------
# 既存の設定は保持しつつ、必要なキーだけ更新する(冪等)
WS_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/obs-studio/plugin_config/obs-websocket"
WS_CONFIG="$WS_CONFIG_DIR/config.json"
mkdir -p "$WS_CONFIG_DIR"

python3 - "$WS_CONFIG" "$OBS_WS_PORT" "$OBS_WS_PASSWORD" <<'PY'
import json, pathlib, sys

path, port, password = pathlib.Path(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
cfg = {}
if path.is_file():
    try:
        cfg = json.loads(path.read_text() or "{}")
    except (json.JSONDecodeError, OSError):
        cfg = {}          # 壊れていたら作り直す
if not isinstance(cfg, dict):
    cfg = {}

cfg.update({
    "server_enabled": True,      # ← これが無いとポートを開かない(既定 false)
    "server_port": port,
    "auth_required": True,
    "server_password": password,
    "first_load": False,         # 初回起動ウィザードでパスワードが再生成されるのを防ぐ
})
path.write_text(json.dumps(cfg, indent=2) + "\n")
PY

chmod 600 "$WS_CONFIG"
echo "obs-websocket を有効化しました: $WS_CONFIG (port=$OBS_WS_PORT)"

export DISPLAY="${DISPLAY:-:99}"
# GPUの無いVPSではソフトウェアレンダリングを使う
export LIBGL_ALWAYS_SOFTWARE=1

exec obs \
    --disable-shutdown-check \
    --disable-missing-files-check \
    --websocket_port "$OBS_WS_PORT" \
    --websocket_password "$OBS_WS_PASSWORD"
