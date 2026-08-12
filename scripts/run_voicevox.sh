#!/usr/bin/env bash
# VOICEVOX ENGINE を起動する。
# ローカル展開版(./voicevox_engine/run)があればそれを、無ければDockerを使う。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE_BIN="$REPO_DIR/voicevox_engine/run"
HOST="${VOICEVOX_HOST:-127.0.0.1}"
PORT="${VOICEVOX_PORT:-50021}"

if [[ -x "$ENGINE_BIN" ]]; then
    exec "$ENGINE_BIN" --host "$HOST" --port "$PORT"
elif command -v docker >/dev/null; then
    exec docker run --rm --pull=missing \
        -p "$HOST:$PORT:50021" \
        --name voicevox-engine \
        voicevox/voicevox_engine:cpu-latest
else
    echo "エラー: VOICEVOX ENGINE が見つかりません。" >&2
    echo "scripts/install_voicevox.sh を実行するか、Dockerをインストールしてください。" >&2
    exit 1
fi
