#!/usr/bin/env bash
# VOICEVOX ENGINE (Linux CPU版) をGitHubリリースからダウンロードして
# ./voicevox_engine/ に展開する。Dockerを使う場合はこのスクリプトは不要。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DIR="$REPO_DIR/voicevox_engine"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ -x "$DEST_DIR/run" ]]; then
    echo "VOICEVOX ENGINE は既にインストール済みです: $DEST_DIR"
    exit 0
fi

if ! command -v 7z >/dev/null; then
    echo "エラー: 7z が必要です (sudo apt install p7zip-full)" >&2
    exit 1
fi

echo "最新リリースを確認中..."
API_URL="https://api.github.com/repos/VOICEVOX/voicevox_engine/releases/latest"
URLS=$(curl -fsSL "$API_URL" \
    | grep -oE '"browser_download_url": *"[^"]*linux-cpu[^"]*"' \
    | grep -oE 'https://[^"]+' || true)

if [[ -z "$URLS" ]]; then
    echo "エラー: linux-cpu 版のダウンロードURLが見つかりません" >&2
    echo "https://github.com/VOICEVOX/voicevox_engine/releases から手動で取得してください" >&2
    exit 1
fi

cd "$WORK_DIR"
for url in $URLS; do
    echo "ダウンロード: $url"
    curl -fL -O "$url"
done

FIRST_PART=$(ls -- *.7z.001 2>/dev/null | head -n1 || true)
if [[ -z "$FIRST_PART" ]]; then
    FIRST_PART=$(ls -- *.7z 2>/dev/null | head -n1 || true)
fi
if [[ -z "$FIRST_PART" ]]; then
    echo "エラー: 7zアーカイブが見つかりません" >&2
    exit 1
fi

echo "展開中..."
7z x -y "$FIRST_PART" >/dev/null

# `run` 実行ファイルを含むディレクトリを探して配置する
ENGINE_DIR=$(find "$WORK_DIR" -maxdepth 3 -type f -name run -printf '%h\n' | head -n1)
if [[ -z "$ENGINE_DIR" ]]; then
    echo "エラー: 展開結果に run 実行ファイルが見つかりません" >&2
    exit 1
fi

mv "$ENGINE_DIR" "$DEST_DIR"
chmod +x "$DEST_DIR/run"
echo "VOICEVOX ENGINE をインストールしました: $DEST_DIR"
