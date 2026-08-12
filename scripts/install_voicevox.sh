#!/usr/bin/env bash
# VOICEVOX ENGINE (Linux CPU版) をGitHubリリースからダウンロードして
# ./voicevox_engine/ に展開する。Dockerを使う場合はこのスクリプトは不要。
#
# 注意点:
#  - CPUのアーキテクチャ(arm64 / x64)を自動判定し、合う分割7zだけを取得する
#  - .vvpp / .vvppp は同じエンジンの別梱包(アプリ用)で不要なため取得しない
#    (これらまで落とすと容量を二重に消費し、ディスク/tmp が溢れる)
#  - 作業ディレクトリは /tmp ではなくリポジトリ配下(永続ディスク)に置く
#    (/tmp が tmpfs=RAM の環境で 1.7GB 級を落とすと溢れるため)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DIR="$REPO_DIR/voicevox_engine"
# 作業/ダウンロード先(永続ディスク上)。VOICEVOX_DL_DIR で上書き可能
WORK_DIR="${VOICEVOX_DL_DIR:-$REPO_DIR/.voicevox_dl}"

if [[ -x "$DEST_DIR/run" ]]; then
    echo "VOICEVOX ENGINE は既にインストール済みです: $DEST_DIR"
    exit 0
fi

if ! command -v 7z >/dev/null 2>&1 && ! command -v 7zr >/dev/null 2>&1; then
    echo "エラー: 7z が必要です (sudo apt install p7zip-full)" >&2
    exit 1
fi
SEVENZIP=$(command -v 7z || command -v 7zr)

# --- アーキテクチャ判定 -------------------------------------------------
case "$(uname -m)" in
    aarch64|arm64) ARCH="arm64" ;;
    x86_64|amd64)  ARCH="x64" ;;
    *)
        echo "エラー: 未対応のCPUアーキテクチャです: $(uname -m)" >&2
        echo "https://github.com/VOICEVOX/voicevox_engine/releases から手動で取得してください" >&2
        exit 1
        ;;
esac
echo "CPUアーキテクチャ: $ARCH"

# --- 取得するアセットURLの選定 -----------------------------------------
# linux-cpu-<arch>-*.7z (単一) または *.7z.001,002,... (分割) のみを対象。
# .vvpp / .vvppp / .txt は除外する。
echo "最新リリースを確認中..."
API_URL="https://api.github.com/repos/VOICEVOX/voicevox_engine/releases/latest"
URLS=$(curl -fsSL "$API_URL" \
    | grep -oE '"browser_download_url":[[:space:]]*"[^"]+"' \
    | grep -oE 'https://[^"]+' \
    | grep -E "linux-cpu-${ARCH}-[^/]*\.7z(\.[0-9]+)?$" \
    | sort || true)

if [[ -z "$URLS" ]]; then
    echo "エラー: linux-cpu-${ARCH} の 7z アセットが見つかりません" >&2
    echo "https://github.com/VOICEVOX/voicevox_engine/releases から手動で取得してください" >&2
    exit 1
fi

echo "取得対象:"
echo "$URLS" | sed 's#.*/#  - #'

# --- 空き容量の事前チェック --------------------------------------------
# 展開後を含めておおよそ 6GB は欲しい
mkdir -p "$WORK_DIR"
avail_kb=$(df -Pk "$WORK_DIR" | awk 'NR==2 {print $4}')
if [[ -n "${avail_kb:-}" ]] && (( avail_kb < 6 * 1024 * 1024 )); then
    echo "警告: $WORK_DIR の空き容量が $((avail_kb / 1024))MB しかありません。" >&2
    echo "      ダウンロードと展開に約6GBが必要です。'df -h' で空きを確認してください。" >&2
    echo "      (別ディスクを使う場合は VOICEVOX_DL_DIR=/path ./scripts/install_voicevox.sh)" >&2
fi

# --- ダウンロード (中断しても -C - で再開できる) -----------------------
cd "$WORK_DIR"
for url in $URLS; do
    fname="${url##*/}"
    echo "ダウンロード: $fname"
    curl -fL -C - -o "$fname" "$url"
done

# --- 展開 ---------------------------------------------------------------
FIRST_PART=$(ls -- *.7z.001 2>/dev/null | head -n1 || true)
[[ -z "$FIRST_PART" ]] && FIRST_PART=$(ls -- *.7z 2>/dev/null | head -n1 || true)
if [[ -z "$FIRST_PART" ]]; then
    echo "エラー: 7zアーカイブが見つかりません" >&2
    exit 1
fi

echo "展開中... ($FIRST_PART)"
"$SEVENZIP" x -y "$FIRST_PART" >/dev/null

# `run` 実行ファイルを含むディレクトリを探して配置する
# (`| head -n1` は find が SIGPIPE で死んで pipefail に引っかかるため -quit を使う)
ENGINE_DIR=$(find "$WORK_DIR" -maxdepth 3 -type f -name run -printf '%h\n' -quit)
if [[ -z "$ENGINE_DIR" ]]; then
    echo "エラー: 展開結果に run 実行ファイルが見つかりません" >&2
    exit 1
fi

rm -rf "$DEST_DIR"
mv "$ENGINE_DIR" "$DEST_DIR"
chmod +x "$DEST_DIR/run"

# 成功したのでダウンロード物と展開残骸を掃除して容量を戻す
cd "$REPO_DIR"
rm -rf "$WORK_DIR"

echo "VOICEVOX ENGINE をインストールしました: $DEST_DIR"
