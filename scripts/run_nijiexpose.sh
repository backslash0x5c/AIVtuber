#!/usr/bin/env bash
# ヘッドレス(Xvfb)環境で nijiexpose を起動する (AVATAR_MODE=inochi2d 用)。
# 本アプリがVMC(OSC/UDP)で口パク・表情を送り、OBSが画面キャプチャで取り込む。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO_DIR/nijiexpose/nijiexpose"

if [[ ! -x "$BIN" ]]; then
    echo "エラー: nijiexpose がありません。scripts/install_nijiexpose.sh を実行してください。" >&2
    exit 1
fi

export DISPLAY="${DISPLAY:-:99}"
# GPUの無いVPSではソフトウェアレンダリングを使う
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER="${GALLIUM_DRIVER:-llvmpipe}"

exec "$BIN"
