#!/usr/bin/env bash
# nijiexpose (Inochi2D系のVTuber配信アプリ) をGitHubリリースから取得して
# ./nijiexpose/ に展開する。AVATAR_MODE=inochi2d の場合のみ必要。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DIR="$REPO_DIR/nijiexpose"
VERSION="${NIJIEXPOSE_VERSION:-v1.0.0-beta2}"
URL="https://github.com/nijigenerate/nijiexpose/releases/download/${VERSION}/nijiexpose-linux-x86_64.zip"

if [[ -d "$DEST_DIR" ]] && find "$DEST_DIR" -maxdepth 2 -type f -name "nijiexpose*" | grep -q .; then
    echo "nijiexpose は既にインストール済みです: $DEST_DIR"
    exit 0
fi

# 公式バイナリは x86_64 のみ (v1.0.0-beta2 時点。arm64ビルドは提供されていない)
if [[ "$(uname -m)" != "x86_64" ]]; then
    echo "エラー: nijiexpose の公式Linuxビルドは x86_64 のみです (このマシン: $(uname -m))" >&2
    echo "選択肢:" >&2
    echo "  1) x86_64 のVPSを使う" >&2
    echo "  2) ソースからビルドする (D言語ldc2が必要): https://github.com/nijigenerate/nijiexpose" >&2
    echo "  3) AVATAR_MODE=browser に戻してLive2D/パペットを使う (arm64で動作可)" >&2
    exit 1
fi

if ! command -v unzip >/dev/null; then
    echo "エラー: unzip が必要です (sudo apt install unzip)" >&2
    exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "ダウンロード: $URL"
curl -fL -o "$WORK_DIR/nijiexpose.zip" "$URL"

echo "展開中..."
unzip -q "$WORK_DIR/nijiexpose.zip" -d "$WORK_DIR/extract"

# 実行ファイルを含むディレクトリを配置
# (`| head -n1` は find が SIGPIPE で死んで pipefail に引っかかるため -quit を使う)
BIN_PATH=$(find "$WORK_DIR/extract" -maxdepth 3 -type f -name "nijiexpose" -print -quit)
if [[ -z "$BIN_PATH" ]]; then
    echo "エラー: 展開結果に nijiexpose 実行ファイルが見つかりません" >&2
    find "$WORK_DIR/extract" -maxdepth 3 -type f > "$WORK_DIR/listing.txt" || true
    head "$WORK_DIR/listing.txt" >&2 || true
    exit 1
fi

rm -rf "$DEST_DIR"
mv "$(dirname "$BIN_PATH")" "$DEST_DIR"
chmod +x "$DEST_DIR/nijiexpose"
echo "nijiexpose をインストールしました: $DEST_DIR"
echo
echo "次の手順:"
echo "  1. 手元PCの nijiexpose でモデルを読み込み、VMC受信とトラッキング紐づけを設定"
echo "  2. モデル(.inp)と設定 (~/.config/nijiexpose 等) をVPSの同じ場所へコピー"
echo "  3. .env に AVATAR_MODE=inochi2d を設定"
echo "  4. systemctl --user enable --now radio-nijiexpose"
