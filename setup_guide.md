# 24時間ラジオ配信システム 完全インストールガイド

## 📋 概要

このガイドでは、Ubuntu ServerにDockerを使わずにネイティブで24時間AI ラジオ配信システムを構築する手順を詳しく説明します。

### システム構成
- **OS**: Ubuntu 20.04/22.04/24.04 LTS
- **LLM**: Ollama + Gemma:1b
- **TTS**: VOICEVOX (ネイティブ版)
- **配信**: OBS Studio + YouTube Live
- **自動化**: Systemd + 監視スクリプト

## 🚀 クイックスタート（推奨）

### 自動インストール（最も簡単）

```bash
# リポジトリをクローンまたはダウンロード
cd ~/
git clone [repository-url] radio-streaming
cd radio-streaming

# 一括セットアップ実行
chmod +x complete_setup.sh
./complete_setup.sh

# 設定ファイル編集
nano config.env
# YOUTUBE_API_KEY, YOUTUBE_VIDEO_ID, YOUTUBE_STREAM_KEY を設定

# システム起動
./startup.sh start
```

所要時間: 15-30分で完了

## 🔧 手動インストール（詳細手順）

自動インストールがうまくいかない場合や、カスタマイズしたい場合の手順です。

### Phase 1: システム準備

#### Step 1-1: システム要件確認

```bash
# OSバージョン確認
lsb_release -a

# メモリ確認（4GB以上推奨）
free -h

# ディスク容量確認（20GB以上推奨）
df -h

# CPU情報確認
nproc
lscpu
```

#### Step 1-2: システム更新

```bash
# パッケージリスト更新
sudo apt update

# セキュリティアップデート適用
sudo apt upgrade -y

# 再起動（カーネル更新時）
sudo reboot  # 必要に応じて
```

#### Step 1-3: 基本依存関係インストール

```bash
# 基本パッケージ
sudo apt install -y \
    curl wget git unzip p7zip-full \
    build-essential cmake pkg-config \
    bc jq tree htop ncdu \
    software-properties-common

# 音声関連
sudo apt install -y \
    ffmpeg sox libsox-fmt-all \
    alsa-utils pulseaudio pulseaudio-utils

# 仮想ディスプレイ
sudo apt install -y \
    xvfb x11-utils mesa-utils
```

### Phase 2: Python環境構築

#### Step 2-1: Python3セットアップ

```bash
# Python3インストール
sudo apt install -y \
    python3 python3-pip python3-venv \
    python3-dev python3-wheel python3-setuptools

# pip更新
python3 -m pip install --user --upgrade pip
```

#### Step 2-2: Python依存関係インストール

```bash
# システム全体のパッケージ
sudo apt install -y \
    python3-numpy python3-scipy \
    python3-requests python3-websocket

# ユーザーレベルのパッケージ
pip3 install --user \
    requests websocket-client asyncio \
    fastapi uvicorn python-multipart pydantic
```

### Phase 3: Ollama + Gemma セットアップ

#### Step 3-1: Ollamaインストール

```bash
# Ollama自動インストール
curl -fsSL https://ollama.com/install.sh | sh

# サービス有効化
sudo systemctl enable ollama
sudo systemctl start ollama

# 起動確認
sudo systemctl status ollama
```

#### Step 3-2: Gemma:1bモデルダウンロード

```bash
# モデルダウンロード（時間がかかります：5-15分）
ollama pull gemma:1b

# モデル確認
ollama list

# テスト実行
ollama run gemma:1b "Hello, how are you?"
```

#### Step 3-3: Ollama動作確認

```bash
# API応答テスト
curl http://localhost:11434/api/version

# モデル動作テスト
curl -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{"model":"gemma:1b","prompt":"Hello","stream":false}'
```

### Phase 4: VOICEVOX ネイティブセットアップ

#### Step 4-1: VOICEVOX依存関係

```bash
# 音声処理ライブラリ
sudo apt install -y \
    libsndfile1 libsndfile1-dev \
    espeak-ng espeak-ng-data \
    libasound2-dev portaudio19-dev

# Python音声処理
pip3 install --user \
    soundfile librosa scipy numpy
```

#### Step 4-2: VOICEVOXインストール

```bash
# インストールスクリプト実行
chmod +x voicevox_native_setup.sh
sudo ./voicevox_native_setup.sh install

# サービス起動確認
sudo systemctl status voicevox

# API動作確認
curl http://localhost:50021/version
curl http://localhost:50021/speakers
```

#### Step 4-3: VOICEVOX動作テスト

```bash
# 音声合成テスト
curl -X POST "http://localhost:50021/audio_query?text=こんにちは&speaker=1" \
  -H "Content-Type: application/json" > query.json

curl -X POST "http://localhost:50021/synthesis?speaker=1" \
  -H "Content-Type: application/json" \
  -d @query.json > test.wav

# 音声ファイル確認
file test.wav
ls -la test.wav

# 再生テスト（音声出力デバイスがある場合）
ffplay -nodisp -autoexit test.wav
```

### Phase 5: OBS Studio セットアップ

#### Step 5-1: OBS Studioインストール

```bash
# 公式PPAリポジトリ追加
sudo add-apt-repository ppa:obsproject/obs-studio
sudo apt update

# OBS Studioインストール
sudo apt install -y obs-studio

# 追加プラグイン（オプション）
sudo apt install -y obs-plugins
```

#### Step 5-2: OBS設定

```bash
# OBS設定スクリプト実行
chmod +x obs_config.sh
./obs_config.sh --setup

# 設定確認
./obs_config.sh --validate
```

### Phase 6: プロジェクトセットアップ

#### Step 6-1: プロジェクトディレクトリ作成

```bash
# プロジェクトディレクトリ
mkdir -p ~/radio-streaming/{logs,backup,scripts}
cd ~/radio-streaming

# 実行権限設定
chmod +x *.sh *.py 2>/dev/null || true
```

#### Step 6-2: 設定ファイル作成

```bash
# 設定ファイルコピー
cp config.env.template config.env

# 設定編集
nano config.env
```

**重要な設定項目：**
```bash
# 必須設定（要変更）
YOUTUBE_API_KEY="YOUR_ACTUAL_API_KEY"
YOUTUBE_VIDEO_ID="YOUR_ACTUAL_VIDEO_ID"
YOUTUBE_STREAM_KEY="YOUR_ACTUAL_STREAM_KEY"

# 推奨設定
VOICEVOX_SPEAKER_ID="1"        # 四国めたん（ノーマル）
LLM_TEMPERATURE="0.7"          # 応答の創造性
IDLE_SPEAK_INTERVAL="600"      # 10分間隔で自動発話
```

#### Step 6-3: YouTube API設定

**YouTube Data API v3 キー取得：**

1. [Google Cloud Console](https://console.cloud.google.com/) にアクセス
2. 新しいプロジェクト作成または既存プロジェクト選択
3. 「APIとサービス」→「ライブラリ」
4. 「YouTube Data API v3」を検索して有効化
5. 「認証情報」→「認証情報を作成」→「APIキー」
6. 作成されたAPIキーをコピー

**YouTube ライブ配信設定：**

1. [YouTube Studio](https://studio.youtube.com/) にアクセス
2. 「作成」→「ライブ配信を開始」
3. 「ウェブカメラ」または「配信ソフトウェア」を選択
4. ストリームキーをコピー
5. 配信URLのビデオIDをコピー

### Phase 7: Systemd サービス設定

#### Step 7-1: サービスファイル作成

```bash
# Systemdサービス設定
chmod +x systemd_setup.sh
sudo ./systemd_setup.sh install
```

#### Step 7-2: サービス有効化

```bash
# サービス有効化
sudo systemctl enable radio-streaming
sudo systemctl enable ollama
sudo systemctl enable voicevox

# 依存関係確認
systemctl list-dependencies radio-streaming
```

### Phase 8: 初回起動テスト

#### Step 8-1: 手動起動テスト

```bash
# システム診断
./system_check.sh

# 手動起動
./startup.sh start

# 状態確認
./startup.sh status

# ログ確認
tail -f logs/main_app.log
```

#### Step 8-2: 自動起動テスト

```bash
# 自動起動サービス開始
sudo systemctl start radio-streaming

# 状態確認
sudo systemctl status radio-streaming

# ログ監視
sudo journalctl -u radio-streaming -f
```

### Phase 9: 最終動作確認

#### Step 9-1: 全サービス確認

```bash
# 統合動作確認
./system_check.sh full

# パフォーマンステスト
./system_check.sh perf

# ネットワーク接続テスト
./system_check.sh network
```

#### Step 9-2: 配信テスト

1. **YouTube配信開始確認**
   - YouTube Studioで配信が開始されているか確認
   - 音声が出力されているか確認

2. **コメント機能テスト**
   - YouTubeでテストコメントを投稿
   - システムが応答するか確認

3. **スーパーチャットテスト**
   - テスト用スーパーチャット送信
   - 特別な感謝メッセージが読み上げられるか確認

## 🛠️ トラブルシューティング

### よくある問題と対処法

#### 問題1: Ollama起動失敗

**症状：**
```bash
curl: (7) Failed to connect to localhost port 11434
```

**対処法：**
```bash
# サービス状態確認
sudo systemctl status ollama

# ログ確認
sudo journalctl -u ollama -n 50

# 手動起動
sudo systemctl restart ollama

# ポート確認
sudo netstat -tlnp | grep 11434
```

#### 問題2: VOICEVOX API応答なし

**症状：**
```bash
curl: (7) Failed to connect to localhost port 50021
```

**対処法：**
```bash
# VOICEVOX再起動
sudo systemctl restart voicevox

# ログ確認
sudo journalctl -u voicevox -n 50

# 手動起動テスト
sudo -u voicevox /opt/voicevox/run
```

#### 問題3: OBS配信開始失敗

**症状：**
- OBSが起動するが配信が開始されない
- 映像・音声が配信されない

**対処法：**
```bash
# OBS設定再作成
./obs_config.sh --clean
./obs_config.sh --setup

# 音声設定確認
./setup_audio.sh

# 仮想ディスプレイ確認
export DISPLAY=:1
xdpyinfo -display :1
```

#### 問題4: YouTube API エラー

**症状：**
```
API request failed: 403 Forbidden
```

**対処法：**
1. APIキーが正しく設定されているか確認
2. YouTube Data API v3が有効化されているか確認
3. APIクォータ制限に達していないか確認
4. ライブ配信が実際に開始されているか確認

#### 問題5: メモリ不足

**症状：**
- システムが重い
- プロセスが強制終了される

**対処法：**
```bash
# メモリ使用量確認
free -h
ps aux --sort=-%mem | head -10

# Swapファイル追加
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# 設定最適化
nano config.env  # メモリ制限設定
```

### ログファイル一覧

| ログファイル | 内容 | 場所 |
|-------------|------|------|
| main_app.log | メインアプリケーション | ~/radio-streaming/logs/ |
| startup.log | システム起動 | ~/radio-streaming/logs/ |
| obs.log | OBS Studio | ~/radio-streaming/logs/ |
| system_check.log | システム診断 | ~/radio-streaming/logs/ |
| service.log | Systemdサービス | ~/radio-streaming/logs/ |

### 緊急時対応手順

#### 完全停止

```bash
# 全サービス強制停止
./startup.sh force-stop
sudo systemctl stop radio-streaming
sudo pkill -f "radio_streaming_bot.py"
sudo pkill -f "obs"
```

#### 設定リセット

```bash
# 設定バックアップ
cp config.env config.env.backup.$(date +%Y%m%d)

# デフォルト設定復元
cp config.env.template config.env

# OBS設定リセット
./obs_config.sh --clean
./obs_config.sh --setup
```

#### システム再インストール

```bash
# 完全クリーンアップ
./startup.sh stop
sudo systemctl disable radio-streaming
sudo ./systemd_setup.sh remove
sudo ./voicevox_native_setup.sh uninstall

# 再インストール
./complete_setup.sh
```

## 📊 パフォーマンス最適化

### メモリ最適化

```bash
# Swap設定
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf

# メモリキャッシュクリア（緊急時）
sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
```

### CPU最適化

```bash
# Ollama設定
export OLLAMA_NUM_PARALLEL=1
export OLLAMA_MAX_LOADED_MODELS=1

# プロセス優先度調整
echo 'PROCESS_PRIORITY="-5"' >> config.env
```

### ネットワーク最適化

```bash
# TCP設定
echo 'net.core.rmem_max = 134217728' | sudo tee -a /etc/sysctl.conf
echo 'net.core.wmem_max = 134217728' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

## 🔒 セキュリティ設定

### ファイアウォール設定

```bash
# UFW有効化
sudo ufw enable

# 必要なポートのみ開放
sudo ufw allow ssh
sudo ufw allow 22/tcp

# 内部APIポートは外部アクセス禁止
sudo ufw deny 11434  # Ollama
sudo ufw deny 50021  # VOICEVOX
```

### ファイル権限設定

```bash
# 設定ファイル権限
chmod 600 config.env
chmod 640 logs/*.log

# スクリプトファイル権限
chmod 755 *.sh
chmod 644 *.py
```

### 定期バックアップ

```bash
# バックアップスクリプト作成
cat > backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backup/radio-streaming"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"
tar czf "$BACKUP_DIR/config_backup_$DATE.tar.gz" \
    config.env logs/ ~/.config/obs-studio/

# 古いバックアップ削除（30日以上）
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +30 -delete
EOF

chmod +x backup.sh

# cron設定（毎日午前3時）
echo "0 3 * * * $PWD/backup.sh" | crontab -
```

## 📈 監視・運用

### 日常監視コマンド

```bash
# システム健康チェック
./system_check.sh quick

# リソース監視
./startup.sh monitor

# ログ監視
tail -f logs/main_app.log

# サービス状態確認
sudo systemctl status radio-streaming ollama voicevox
```

### 定期メンテナンス

**週次作業：**
- システム診断実行
- ログファイル確認
- ディスク容量確認
- バックアップ実行

**月次作業：**
- システムアップデート
- 設定最適化確認
- パフォーマンス分析
- セキュリティ確認

## 🎯 運用開始チェックリスト

- [ ] システム要件確認完了
- [ ] 全コンポーネントインストール完了
- [ ] YouTube API設定完了
- [ ] 配信テスト成功
- [ ] 自動起動設定完了
- [ ] 監視システム動作確認
- [ ] バックアップ設定完了
- [ ] セキュリティ設定完了
- [ ] 運用手順書作成完了
- [ ] 緊急時対応手順確認完了

## 🔗 参考資料

### 公式ドキュメント
- [Ollama Documentation](https://ollama.ai/docs)
- [VOICEVOX](https://voicevox.hiroshiba.jp/)
- [OBS Studio](https://obsproject.com/)
- [YouTube Live Streaming API](https://developers.google.com/youtube/v3/live)

### 関連技術
- [Ubuntu Server Guide](http://ubuntu.com/server/docs)
- [Systemd Documentation](https://systemd.io/)
- [PulseAudio Documentation](https://www.freedesktop.org/wiki/Software/PulseAudio/)

---

このガイドで不明な点があれば、各段階でのログファイルを確認し、必要に応じて個別のトラブルシューティング手順を実施してください。
