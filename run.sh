#!/bin/bash

echo "=================================================="
echo "24時間ラジオ対話配信システム - 起動"
echo "=================================================="
echo ""

# エラーチェック
if [ ! -f .env ]; then
    echo "エラー: .envファイルが見つかりません"
    echo ".env.exampleをコピーして.envを作成してください"
    exit 1
fi

# サービスチェック
echo "サービスの確認中..."
echo ""

# Ollama
echo -n "Ollama: "
if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "✓ 稼働中"
else
    echo "✗ 停止中 - ollama serve で起動してください"
    exit 1
fi

# VOICEVOX
echo -n "VOICEVOX: "
if curl -s http://localhost:50021/version > /dev/null 2>&1; then
    echo "✓ 稼働中"
else
    echo "✗ 停止中 - VOICEVOXを起動してください"
    exit 1
fi

echo ""
echo "全てのサービスが稼働しています"
echo "配信を開始します..."
echo ""

# プログラムを実行
python3 -m src.main
