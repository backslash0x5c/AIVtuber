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
OBS_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/obs-studio"

# --- 前回異常終了の痕跡を消す -------------------------------------------
# OBSは起動時に obs-studio/.sentinel/run_<UUID> を作り、正常終了時に全て消す。
# 前回分が残っていると CrashHandler::hasUncleanShutdown() が真になり、
#   blog("Crash or unclean shutdown detected"); ... crashWarning.exec();
# とモーダルダイアログで応答を待つ。ヘッドレスでは誰も押せず永久に固まり、
# obs-websocket も起動しない。しかも固まったOBSはSIGKILLで殺すしかなく、
# それがまた痕跡を残すため、放置すると永久にこのループから抜けられない。
#
# 注意: `--disable-shutdown-check` はこの新しいコードパス(OBS 32系)では
# 参照されておらず効かない。センチネルの無効化スイッチも存在しない
# (isSentinelEnabled はコンパイル時定数)ため、起動前に消すしかない。
# 無人運用では常に通常起動させたい(Safe Modeに入るとWebSocketも無効化される)。
SENTINEL_DIR="$OBS_CONFIG_DIR/.sentinel"
if compgen -G "$SENTINEL_DIR/run_*" >/dev/null 2>&1; then
    n=$(find "$SENTINEL_DIR" -maxdepth 1 -name 'run_*' -type f | wc -l)
    rm -f "$SENTINEL_DIR"/run_*
    echo "前回の異常終了マーカーを削除しました (${n}件) — クラッシュ確認ダイアログの回避"
fi
# 旧バージョンのOBSが使うマーカーも念のため消す
rm -f "$OBS_CONFIG_DIR/safe_mode"

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

# --- CEF(ブラウザソース)向けの追加フラグ --------------------------------
# ブラウザソースの中身はChromium(CEF)。Chromiumはroot実行時に
# sandboxを無効化しないと子プロセスを起動できず
#   "Running as root without --no-sandbox is not supported"
# となり、最終的に "GPU process isn't usable. Goodbye." でOBSごと落ちる。
# OBSに渡した引数はそのままCEFにも渡るため、ここで付与する。
EXTRA_ARGS=()
case "${OBS_NO_SANDBOX:-auto}" in
    true)  NEED_NOSANDBOX=1 ;;
    false) NEED_NOSANDBOX=0 ;;
    *)     [[ $EUID -eq 0 ]] && NEED_NOSANDBOX=1 || NEED_NOSANDBOX=0 ;;  # auto: root なら付ける
esac
if [[ "$NEED_NOSANDBOX" == "1" ]]; then
    EXTRA_ARGS+=(--no-sandbox)
    echo "CEF(ブラウザソース)向けに --no-sandbox を付与します (root実行のため)"
fi

# 追加で渡したいフラグがあれば .env の OBS_EXTRA_ARGS で指定する
# 例: ブラウザソースのGPUプロセスがまだ落ちる場合 OBS_EXTRA_ARGS="--disable-gpu"
if [[ -n "${OBS_EXTRA_ARGS:-}" ]]; then
    read -r -a _user_args <<< "$OBS_EXTRA_ARGS"
    EXTRA_ARGS+=("${_user_args[@]}")
    echo "追加フラグ: ${_user_args[*]}"
fi

exec obs \
    --disable-shutdown-check \
    --disable-missing-files-check \
    --websocket_port "$OBS_WS_PORT" \
    --websocket_password "$OBS_WS_PASSWORD" \
    "${EXTRA_ARGS[@]}"
