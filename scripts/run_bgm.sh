#!/usr/bin/env bash
# bgm/ ディレクトリ内の音楽ファイルを仮想シンクへループ再生する。
# ファイルが無い場合は何もせず待機する(音声のみでも配信は成立する)。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BGM_DIR="$REPO_DIR/bgm"
SINK_NAME="${MIX_SINK:-radio_mix}"

shopt -s nullglob
files=("$BGM_DIR"/*.{mp3,ogg,wav,flac,m4a,opus})
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
    echo "bgm/ に音楽ファイルがありません。BGMなしで待機します。"
    exec sleep infinity
fi

exec mpv \
    --no-video \
    --ao=pulse \
    --audio-device="pulse/$SINK_NAME" \
    --loop-playlist=inf \
    --shuffle \
    --volume=100 \
    --really-quiet \
    "${files[@]}"
