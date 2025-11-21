#!/bin/bash

echo "=================================================="
echo "24時間ラジオ対話配信システム - セットアップ"
echo "=================================================="
echo ""

# エラーが発生したら停止
set -e

# Python3のチェック
echo "[1/6] Python3の確認..."
if ! command -v python3 &> /dev/null; then
    echo "エラー: Python3がインストールされていません"
    exit 1
fi
echo "✓ Python3: $(python3 --version)"

# pipのチェック
echo ""
echo "[2/6] pipの確認..."
if ! command -v pip3 &> /dev/null; then
    echo "エラー: pip3がインストールされていません"
    exit 1
fi
echo "✓ pip3がインストールされています"

# FFmpegのチェック
echo ""
echo "[3/6] FFmpegの確認..."
if ! command -v ffmpeg &> /dev/null; then
    echo "警告: FFmpegがインストールされていません"
    echo "FFmpegをインストールしてください:"
    echo "  sudo apt update && sudo apt install -y ffmpeg"
else
    echo "✓ FFmpeg: $(ffmpeg -version | head -n1)"
fi

# Python依存パッケージのインストール
echo ""
echo "[4/6] Python依存パッケージのインストール..."
pip3 install -r requirements.txt
echo "✓ 依存パッケージのインストール完了"

# .envファイルの作成
echo ""
echo "[5/6] 環境変数ファイルの設定..."
if [ ! -f .env ]; then
    cp .env.example .env
    echo "✓ .envファイルを作成しました"
    echo "  .envファイルを編集して、必要な設定を入力してください:"
    echo "  - YOUTUBE_VIDEO_ID"
    echo "  - YOUTUBE_STREAM_KEY"
else
    echo "✓ .envファイルは既に存在します"
fi

# Ollamaのチェック
echo ""
echo "[6/6] Ollamaの確認..."
if ! command -v ollama &> /dev/null; then
    echo "警告: Ollamaがインストールされていません"
    echo "Ollamaをインストールしてください:"
    echo "  curl -fsSL https://ollama.com/install.sh | sh"
else
    echo "✓ Ollamaがインストールされています"
    echo ""
    echo "gemma2:2bモデルをダウンロードしますか? (y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "モデルをダウンロード中..."
        ollama pull gemma2:2b
        echo "✓ モデルのダウンロード完了"
    fi
fi

echo ""
echo "=================================================="
echo "セットアップ完了!"
echo "=================================================="
echo ""
echo "次のステップ:"
echo "1. .envファイルを編集して設定を入力"
echo "2. VOICEVOXを起動 (http://localhost:50021)"
echo "3. Ollamaを起動 (ollama serve)"
echo "4. プログラムを実行 (python3 -m src.main)"
echo ""
