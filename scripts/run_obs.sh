#!/usr/bin/env bash
# ヘッドレス(Xvfb)環境でOBSを起動する。
# obs-websocketの待ち受けはCLI引数で強制するため、GUI操作は一切不要。
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

export DISPLAY="${DISPLAY:-:99}"
# GPUの無いVPSではソフトウェアレンダリングを使う
export LIBGL_ALWAYS_SOFTWARE=1

exec obs \
    --disable-shutdown-check \
    --disable-missing-files-check \
    --websocket_port "${OBS_WS_PORT:-4455}" \
    --websocket_password "$OBS_WS_PASSWORD"
