#!/usr/bin/env bash
# 24時間AIラジオ配信システム セットアップスクリプト (Ubuntu Server 向け)
# 実行後は README.md の「起動」手順に従ってください。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

# .env は依存関係が無く、かつ後続ステップが失敗しても手元に残したいので最初に作る
# (巨大なダウンロードで中断しても OBS_WS_PASSWORD が生成済みになるように)
echo "==== [1/7] .env の準備 ===="
if [[ ! -f .env ]]; then
    cp .env.example .env
    # obs-websocket用のパスワードを自動生成
    WS_PW=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)
    sed -i "s/^OBS_WS_PASSWORD=.*/OBS_WS_PASSWORD=$WS_PW/" .env
    echo ".env を作成し、OBS_WS_PASSWORD を自動生成しました: $REPO_DIR/.env"
else
    echo ".env は既に存在します"
    if ! grep -qE '^OBS_WS_PASSWORD=.+' .env; then
        WS_PW=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)
        sed -i "s|^OBS_WS_PASSWORD=.*|OBS_WS_PASSWORD=$WS_PW|" .env
        echo "  OBS_WS_PASSWORD が空だったので自動生成しました"
    fi
fi

echo "==== [2/7] APTパッケージのインストール ===="
sudo apt-get update
sudo apt-get install -y \
    curl ca-certificates software-properties-common \
    python3 python3-venv python3-pip \
    ffmpeg mpv \
    pulseaudio pulseaudio-utils \
    xvfb p7zip-full \
    fonts-noto-cjk

echo "==== [3/7] OBS Studio のインストール ===="
if ! command -v obs >/dev/null; then
    sudo add-apt-repository -y ppa:obsproject/obs-studio
    sudo apt-get update
    sudo apt-get install -y obs-studio
else
    echo "OBSはインストール済みです"
fi

echo "==== [4/7] Ollama のインストール ===="
if ! command -v ollama >/dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
else
    echo "Ollamaはインストール済みです"
fi

echo "==== [5/7] Python仮想環境の構築 ===="
if [[ ! -d venv ]]; then
    python3 -m venv venv
fi
./venv/bin/pip install --upgrade pip -q
./venv/bin/pip install -r requirements.txt -q
echo "Python依存パッケージをインストールしました"

# 数GBのダウンロードを伴うため最後に近い位置で実行し、失敗しても中断しない
# (ここで止めると .env やsystemdユニットが未配置のままになるため)
echo "==== [6/7] VOICEVOX ENGINE のインストール ===="
VOICEVOX_OK=1
if command -v docker >/dev/null; then
    echo "Dockerが利用可能です。エンジンは初回起動時にDockerイメージを取得します。"
elif [[ -x "$REPO_DIR/voicevox_engine/run" ]]; then
    echo "VOICEVOX ENGINEはインストール済みです"
else
    if ! bash "$REPO_DIR/scripts/install_voicevox.sh"; then
        VOICEVOX_OK=0
        echo "警告: VOICEVOX ENGINE のインストールに失敗しました (セットアップは続行します)" >&2
        echo "      空き容量を確認し (df -h)、後で次を再実行してください:" >&2
        echo "      ./scripts/install_voicevox.sh" >&2
    fi
fi

echo "==== [7/7] systemd ユーザーユニットの配置 ===="
mkdir -p ~/.config/systemd/user
for unit in "$REPO_DIR"/systemd/user/*; do
    sed "s|__RADIO_DIR__|$REPO_DIR|g" "$unit" > ~/.config/systemd/user/"$(basename "$unit")"
done
systemctl --user daemon-reload
systemctl --user enable radio-xvfb radio-audio radio-voicevox radio-obs radio-bgm radio-app radio.target
# ログアウト後もユーザーサービスを動かし続ける
sudo loginctl enable-linger "$USER"
echo "systemdユニットを配置しました"

echo
if [[ "$VOICEVOX_OK" == "0" ]]; then
    echo "==== セットアップ完了 (VOICEVOXのみ未完了) ===="
    echo "先に ./scripts/install_voicevox.sh を成功させてください。音声合成に必要です。"
else
    echo "==== セットアップ完了 ===="
fi
echo "次の手順:"
echo "  1. LLMモデルの取得:        ollama pull \$(grep OLLAMA_MODEL .env | cut -d= -f2)"
echo "  2. .env の設定:            nano .env  (YOUTUBE_VIDEO_ID / YOUTUBE_STREAM_KEY)"
echo "     ※ OBS_WS_PASSWORD は自動生成済みなので変更不要"
echo "  3. BGMを置く(任意):        cp your_music.mp3 bgm/"
echo "  4. 起動:                   systemctl --user start radio.target"
echo "  5. ログ確認:               journalctl --user -u radio-app -f"
