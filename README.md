# 24時間ラジオ対話配信システム

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/license/apache-2-0)
[![Python](https://img.shields.io/badge/python-3.8+-blue.svg)](https://www.python.org/)
[![Platform: Ollama](https://img.shields.io/badge/Platform-Ollama-green.svg)](https://ollama.com/)
[![gemma3:1b](https://img.shields.io/badge/gemma3-1b-orange.svg)](https://ollama.com/library/gemma3)
[![Voice: VOICEVOX](https://img.shields.io/badge/Voice-VOICEVOX-brightgreen.svg)](https://voicevox.hiroshiba.jp/)

YouTubeライブ配信でコメントに自動応答する24時間ラジオ配信システムです。

## 機能

- YouTubeライブチャットからコメントを取得
- Ollama (gemma3:1b) を使用したAI応答生成
- VOICEVOXによる音声合成
- 静止画 + 音声でYouTubeライブ配信
- コメントがない時の自動雑談機能
- 会話履歴を保持して文脈に沿った対話

## システム要件

- **OS**: Ubuntu Server (CLI環境)
- **Python**: 3.8以上
- **FFmpeg**: 音声エンコードと配信用
- **Ollama**: ローカルLLM実行環境
- **VOICEVOX**: 音声合成エンジン

## インストール

### 1. 必要なソフトウェアのインストール

```bash
# システムパッケージの更新
sudo apt update && sudo apt upgrade -y

# FFmpegのインストール
sudo apt install -y ffmpeg python3 python3-pip

# Ollamaのインストール
curl -fsSL https://ollama.com/install.sh | sh

# VOICEVOXのインストール
# https://voicevox.hiroshiba.jp/ から最新版のダウンロードスクリプトを実行
# スクリプト実行により./voicevoxディレクトリが作成される

# AppImageを展開
chmod +x ./voicevox/VOICEVOX.AppImage
./voicevox/VOICEVOX.AppImage --appimage-extract
```

### 2. プロジェクトのセットアップ

```bash
# リポジトリをクローン
git clone <repository-url>
cd radio-streaming

# 仮想環境の作成と有効化
python3 -m venv venv
source venv/bin/activate

# Python依存パッケージのインストール
pip install pytchat requests python-dotenv pydub

# セットアップスクリプトを実行
./setup.sh
```

### 3. 環境変数の設定

`.env`ファイルを編集して、必要な設定を入力します:

```bash
nano .env
```

必須設定:
- `YOUTUBE_VIDEO_ID`: YouTubeライブ配信のビデオID
- `YOUTUBE_STREAM_KEY`: YouTube配信キー

オプション設定:
- `OLLAMA_MODEL`: 使用するLLMモデル (デフォルト: gemma3:1b)
- `VOICEVOX_SPEAKER_ID`: 話者ID (デフォルト: 1)
- `IDLE_CHAT_INTERVAL`: 雑談までの待機時間（秒）

### 4. Ollamaモデルのダウンロード

```bash
ollama pull gemma3:1b
```

### 5. 配信用静止画の準備

```bash
# プロジェクトルートにimage.pngを配置
# 推奨サイズ: 1280x720 または 1920x1080
cp /path/to/your/image.png ./image.png
```

静止画がない場合は音声のみで配信されます。

## 使用方法

### 1. 必要なサービスを起動

#### VOICEVOXの起動

```bash
# VOICEVOXをバックグラウンドで起動
# nohup: ターミナルを閉じても処理を継続
# &: バックグラウンドで実行
nohup ./voicevox/squashfs-root/vv-engine/run > voicevox.log 2>&1 &

# 起動確認
curl http://localhost:50021/version
```

#### Ollamaの起動

```bash
# Ollamaサーバーを起動（別のターミナルで）
ollama serve
```

### 2. ラジオ配信システムの起動

```bash
# 仮想環境を有効化
source venv/bin/activate

# プログラムを起動
./run.sh
```

### 3. 停止方法

`Ctrl+C` を押してプログラムを停止します。

## システムフロー

```
YouTubeコメント取得
       ↓
   コメントあり?
  ↙          ↘
YES          NO
 ↓            ↓
コメント処理  30秒経過?
 ↓            ↓
Ollama応答   雑談生成
 ↓            ↓
 └─→ VOICEVOX ←┘
       ↓
    音声合成
       ↓
  YouTube配信
```

## ファイル構成

```
radio-streaming/
├── src/
│   ├── __init__.py          # パッケージ初期化
│   ├── main.py              # メインプログラム
│   ├── config.py            # 設定管理
│   ├── youtube_client.py    # YouTubeコメント取得
│   ├── ollama_client.py     # Ollama API連携
│   ├── voicevox_client.py   # VOICEVOX連携
│   └── audio_streamer.py    # FFmpeg配信（静止画+音声）
├── setup.sh                # セットアップスクリプト
├── run.sh                  # 起動スクリプト
├── .env.example            # 環境変数テンプレート
├── .env                    # 環境変数設定（要作成）
├── image.png               # 配信用静止画（要配置）
└── README.md               # このファイル
```

## トラブルシューティング

### VOICEVOXに接続できない

- VOICEVOXが起動しているか確認
- `http://localhost:50021`でアクセスできるか確認

```bash
curl http://localhost:50021/version
```

### Ollamaに接続できない

- Ollamaサービスが起動しているか確認
- モデルがダウンロードされているか確認

```bash
ollama list
```

### YouTubeコメントが取得できない

- `YOUTUBE_VIDEO_ID`が正しいか確認
- ライブ配信が開始されているか確認
- チャット機能が有効になっているか確認

### FFmpegエラー

- FFmpegがインストールされているか確認
- `YOUTUBE_STREAM_KEY`が正しいか確認

```bash
ffmpeg -version
```

## 設定のカスタマイズ

### 雑談の頻度を変更

`.env`ファイルで`IDLE_CHAT_INTERVAL`を変更:

```
IDLE_CHAT_INTERVAL=60  # 60秒後に雑談
```

### 会話履歴の保持数を変更

`.env`ファイルで`MAX_CONVERSATION_HISTORY`を変更:

```
MAX_CONVERSATION_HISTORY=20  # 最大20件の会話を記憶
```

### VOICEVOXの話者を変更

利用可能な話者を確認:

```bash
curl http://localhost:50021/speakers | python3 -m json.tool
```

`.env`ファイルで`VOICEVOX_SPEAKER_ID`を変更:

```
VOICEVOX_SPEAKER_ID=3  # 話者IDを変更
```

## ライセンス

このプロジェクトはApache License 2.0の下で公開されています。詳細は[LICENSE](LICENSE)ファイルを参照してください。
