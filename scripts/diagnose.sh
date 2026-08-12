#!/usr/bin/env bash
# 配信が始まらないときの状況をまとめて出力する。
# 出力をそのまま貼れば原因の切り分けができる。
# (エラーがあっても最後まで走らせたいので set -e は使わない)

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

hr() { echo; echo "===== $* ====="; }

hr "システム"
echo "OS         : $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
echo "アーキテクチャ: $(uname -m)"
echo "ユーザー    : $(id -un)  (HOME=$HOME)"

hr "サービスの状態"
systemctl --user list-units 'radio-*' --all --no-pager --no-legend 2>/dev/null \
    | awk '{printf "  %-26s %-10s %s\n", $1, $3, $4}'

hr "各サービスの active/失敗理由"
for u in radio-xvfb radio-audio radio-voicevox radio-obs radio-bgm radio-app; do
    state=$(systemctl --user is-active "$u.service" 2>/dev/null)
    result=$(systemctl --user show "$u.service" -p Result --value 2>/dev/null)
    printf "  %-16s %-10s result=%s\n" "$u" "$state" "$result"
done

hr "OBS 本体"
if command -v obs >/dev/null; then
    echo "  実行ファイル: $(command -v obs)"
    echo "  バージョン  : $(obs --version 2>&1 | head -n1)"
else
    echo "  ❌ obs コマンドが見つかりません (OBSが未インストール)"
    echo "     arm64環境では公式PPAにパッケージが無いことがあります"
fi

hr "obs-websocket の設定 (server_enabled が true でないとポートを開かない)"
WS_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/obs-studio/plugin_config/obs-websocket/config.json"
if [[ -f "$WS_CONFIG" ]]; then
    echo "  ファイル: $WS_CONFIG"
    python3 -c '
import json, sys
try:
    c = json.load(open(sys.argv[1]))
except Exception as e:
    print("  ❌ 読み込めません:", e); raise SystemExit
enabled = c.get("server_enabled")
print("  server_enabled :", enabled, "" if enabled else "  ← ❌ これが false だと待ち受けません")
print("  server_port    :", c.get("server_port"))
print("  auth_required  :", c.get("auth_required"))
print("  server_password:", "***設定済み***" if c.get("server_password") else "❌未設定")
' "$WS_CONFIG" 2>/dev/null || echo "  (解析に失敗しました)"
else
    echo "  ❌ 設定ファイルがありません: $WS_CONFIG"
    echo "     run_obs.sh が起動時に生成します"
fi

hr "待ち受けポート (4455=obs-websocket, 8500=オーバーレイ)"
if command -v ss >/dev/null; then
    ss -ltnp 2>/dev/null | grep -E ':(4455|8500|50021|11434)\b' || echo "  (該当ポートの待ち受けなし)"
else
    echo "  ss コマンドがありません"
fi

hr "仮想ディスプレイ (Xvfb)"
pgrep -a Xvfb || echo "  ❌ Xvfb が動いていません"
if command -v xdpyinfo >/dev/null; then
    DISPLAY=:99 xdpyinfo >/dev/null 2>&1 \
        && echo "  DISPLAY=:99 へ接続OK" \
        || echo "  ❌ DISPLAY=:99 へ接続できません"
fi

hr "OpenGL (OBSの描画に必要)"
if command -v glxinfo >/dev/null; then
    DISPLAY=:99 glxinfo 2>&1 | grep -E 'OpenGL (version|renderer)' || echo "  取得できませんでした"
else
    echo "  glxinfo 未インストール (sudo apt install mesa-utils で詳細が見られます)"
fi

hr "radio-obs のログ (直近40行) ← 配信が始まらない原因はたいていここ"
journalctl --user -u radio-obs -n 40 --no-pager 2>/dev/null || echo "  ログを取得できません"

hr "radio-app のログ (直近20行)"
journalctl --user -u radio-app -n 20 --no-pager 2>/dev/null || echo "  ログを取得できません"

hr "設定 (.env の要点。鍵は伏せ字)"
if [[ -f "$REPO_DIR/.env" ]]; then
    # 鍵・パスワードは値を出さず「設定済み/未設定」だけ表示する
    grep -E '^(YOUTUBE_VIDEO_ID|YOUTUBE_STREAM_KEY|OBS_WS_PORT|OBS_WS_PASSWORD|OBS_ENABLED|AVATAR_MODE)=' \
        "$REPO_DIR/.env" \
        | awk -F= '{
            key = $1; val = substr($0, index($0, "=") + 1)
            if (key == "YOUTUBE_STREAM_KEY" || key == "OBS_WS_PASSWORD")
                printf "  %s=%s\n", key, (val == "" ? "❌未設定" : "***設定済み***")
            else
                printf "  %s=%s\n", key, val
          }'
else
    echo "  ❌ .env がありません"
fi

echo
echo "===== 以上 ====="
