#!/bin/bash
# VOICEVOX ネイティブインストールスクリプト（Dockerなし版）
# Ubuntu 20.04/22.04 LTS対応
# 商用利用可能な音声合成エンジンのセットアップ

set -e

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 設定
VOICEVOX_VERSION="0.14.4"
INSTALL_DIR="/opt/voicevox"
TEMP_DIR="/tmp/voicevox_install"
LOG_FILE="/var/log/voicevox_install.log"

# ログ関数
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# システム要件チェック
check_system_requirements() {
    log "システム要件チェック中..."
    
    # OS確認
    if ! grep -q "Ubuntu" /etc/os-release; then
        error "このスクリプトはUbuntu専用です"
    fi
    
    # アーキテクチャ確認
    ARCH=$(uname -m)
    if [ "$ARCH" != "x86_64" ]; then
        error "x86_64アーキテクチャが必要です（現在: $ARCH）"
    fi
    
    # メモリ確認
    TOTAL_MEM=$(free -m | awk 'NR==2{printf "%d", $2}')
    if [ "$TOTAL_MEM" -lt 2000 ]; then
        warn "メモリが少ない可能性があります（推奨: 2GB以上, 現在: ${TOTAL_MEM}MB）"
    fi
    
    # ディスク容量確認
    AVAILABLE_SPACE=$(df / | tail -1 | awk '{print $4}')
    if [ "$AVAILABLE_SPACE" -lt 5000000 ]; then  # 5GB
        error "ディスク容量不足です（必要: 5GB以上）"
    fi
    
    log "✓ システム要件確認完了"
}

# 依存関係インストール
install_dependencies() {
    log "依存関係をインストール中..."
    
    # パッケージリスト更新
    sudo apt update
    
    # 基本依存関係
    sudo apt install -y \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        wget \
        unzip \
        p7zip-full \
        curl \
        build-essential \
        cmake \
        pkg-config \
        libffi-dev \
        libssl-dev \
        libsndfile1 \
        libsndfile1-dev \
        espeak-ng \
        espeak-ng-data \
        libasound2-dev \
        portaudio19-dev \
        libportaudio2 \
        libportaudiocpp0 \
        ffmpeg \
        libavcodec-extra \
        sox \
        libsox-fmt-all
    
    # Python依存関係
    sudo apt install -y \
        python3-numpy \
        python3-scipy \
        python3-sklearn \
        python3-librosa
    
    log "✓ 依存関係インストール完了"
}

# 作業ディレクトリ準備
prepare_directories() {
    log "ディレクトリ準備中..."
    
    # インストールディレクトリ作成
    sudo mkdir -p "$INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR/model"
    sudo mkdir -p "$INSTALL_DIR/speaker_info"
    
    # 一時ディレクトリ作成
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # ログディレクトリ
    sudo mkdir -p /var/log/voicevox
    
    log "✓ ディレクトリ準備完了"
}

# VOICEVOX Engine ダウンロード
download_voicevox_engine() {
    log "VOICEVOX Engine ダウンロード中..."
    
    # CPUバージョンのURLを決定
    ENGINE_URL="https://github.com/VOICEVOX/voicevox_engine/releases/download/${VOICEVOX_VERSION}/voicevox_engine-linux-cpu-${VOICEVOX_VERSION}.7z"
    
    # ダウンロード
    info "ダウンロード URL: $ENGINE_URL"
    wget -O voicevox_engine.7z "$ENGINE_URL" --progress=bar:force 2>&1 | tee -a "$LOG_FILE"
    
    if [ ! -f "voicevox_engine.7z" ]; then
        error "VOICEVOX Engine のダウンロードに失敗しました"
    fi
    
    # 展開
    log "ファイル展開中..."
    7z x voicevox_engine.7z
    
    # ファイル移動
    if [ -d "linux-cpu" ]; then
        sudo cp -r linux-cpu/* "$INSTALL_DIR/"
    else
        error "展開されたファイルが見つかりません"
    fi
    
    log "✓ VOICEVOX Engine インストール完了"
}

# 音声モデルダウンロード
download_voice_models() {
    log "音声モデルダウンロード中..."
    
    # モデルURL一覧
    declare -a MODEL_URLS=(
        "https://github.com/VOICEVOX/voicevox_core/releases/download/0.14.4/model-0.14.4.zip"
    )
    
    for MODEL_URL in "${MODEL_URLS[@]}"; do
        info "モデルダウンロード: $MODEL_URL"
        
        MODEL_FILE="model_$(basename $MODEL_URL)"
        wget -O "$MODEL_FILE" "$MODEL_URL" --progress=bar:force 2>&1 | tee -a "$LOG_FILE"
        
        if [ -f "$MODEL_FILE" ]; then
            log "モデル展開中: $MODEL_FILE"
            unzip -q "$MODEL_FILE" -d model_temp
            sudo cp -r model_temp/* "$INSTALL_DIR/model/"
            rm -rf model_temp "$MODEL_FILE"
        else
            warn "モデルファイルのダウンロードに失敗: $MODEL_FILE"
        fi
    done
    
    log "✓ 音声モデル インストール完了"
}

# スピーカー情報設定
setup_speaker_info() {
    log "スピーカー情報設定中..."
    
    # スピーカー情報JSONファイル作成
    sudo tee "$INSTALL_DIR/speaker_info/speakers.json" > /dev/null << 'EOF'
[
  {
    "name": "四国めたん",
    "speaker_uuid": "7ffcb7ce-00ec-4bdc-82cd-45a8889e43ff",
    "styles": [
      {
        "name": "ノーマル",
        "id": 2,
        "type": "talk"
      },
      {
        "name": "あまあま",
        "id": 0,
        "type": "talk"
      },
      {
        "name": "ツンツン",
        "id": 6,
        "type": "talk"
      },
      {
        "name": "セクシー",
        "id": 4,
        "type": "talk"
      }
    ],
    "version": "0.14.4"
  },
  {
    "name": "ずんだもん",
    "speaker_uuid": "388f246b-8c41-4ac1-8e2d-5d79f3ff56d9",
    "styles": [
      {
        "name": "ノーマル",
        "id": 3,
        "type": "talk"
      },
      {
        "name": "あまあま",
        "id": 1,
        "type": "talk"
      },
      {
        "name": "ツンツン",
        "id": 7,
        "type": "talk"
      },
      {
        "name": "セクシー",
        "id": 5,
        "type": "talk"
      }
    ],
    "version": "0.14.4"
  }
]
EOF
    
    log "✓ スピーカー情報設定完了"
}

# Python仮想環境セットアップ
setup_python_environment() {
    log "Python環境セットアップ中..."
    
    cd "$INSTALL_DIR"
    
    # 仮想環境作成
    sudo python3 -m venv venv
    sudo chown -R $USER:$USER "$INSTALL_DIR/venv"
    
    # 仮想環境をアクティベート
    source "$INSTALL_DIR/venv/bin/activate"
    
    # pipアップグレード
    pip install --upgrade pip setuptools wheel
    
    # 必要なPythonパッケージインストール
    pip install \
        fastapi==0.68.0 \
        uvicorn[standard]==0.15.0 \
        python-multipart \
        pydantic \
        soundfile \
        numpy \
        scipy \
        librosa \
        pyopenjtalk==0.3.0 \
        unidic-lite \
        jiwer \
        resampy \
        psutil \
        GPUtil || true
    
    # VOICEVOX Core Python バインディング
    if [ -f "$INSTALL_DIR/voicevox_core.py" ]; then
        log "VOICEVOX Core Python バインディング設定"
    else
        warn "VOICEVOX Core Python バインディングが見つかりません"
    fi
    
    deactivate
    
    log "✓ Python環境セットアップ完了"
}

# 実行スクリプト作成
create_execution_scripts() {
    log "実行スクリプト作成中..."
    
    # メイン実行スクリプト
    sudo tee "$INSTALL_DIR/run" > /dev/null << 'EOF'
#!/bin/bash
# VOICEVOX Engine 実行スクリプト

cd /opt/voicevox
source venv/bin/activate

# 環境変数設定
export VV_CPU_NUM_THREADS=2
export VV_ENABLE_GPU=false
export OMP_NUM_THREADS=2
export PYTHONPATH=/opt/voicevox:$PYTHONPATH
export LD_LIBRARY_PATH=/opt/voicevox:$LD_LIBRARY_PATH

# ログ設定
export VOICEVOX_LOG_DIR=/var/log/voicevox
mkdir -p $VOICEVOX_LOG_DIR

# エンジン起動
echo "VOICEVOX Engine starting..."
echo "Log directory: $VOICEVOX_LOG_DIR"
echo "Python path: $(which python)"
echo "Working directory: $(pwd)"

# FastAPI サーバー起動（uvicornを使用）
uvicorn voicevox_engine.app.application:generate_app \
    --host 127.0.0.1 \
    --port 50021 \
    --log-level info \
    --access-log \
    --log-config logging_config.json 2>&1 | tee $VOICEVOX_LOG_DIR/engine.log
EOF
    
    sudo chmod +x "$INSTALL_DIR/run"
    
    # ログ設定ファイル
    sudo tee "$INSTALL_DIR/logging_config.json" > /dev/null << 'EOF'
{
    "version": 1,
    "disable_existing_loggers": false,
    "formatters": {
        "default": {
            "format": "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
        }
    },
    "handlers": {
        "default": {
            "formatter": "default",
            "class": "logging.StreamHandler",
            "stream": "ext://sys.stdout"
        }
    },
    "root": {
        "level": "INFO",
        "handlers": ["default"]
    }
}
EOF
    
    # 健康チェックスクリプト
    sudo tee "$INSTALL_DIR/health_check.sh" > /dev/null << 'EOF'
#!/bin/bash
# VOICEVOX Engine 健康チェック

RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:50021/version)

if [ "$RESPONSE" = "200" ]; then
    echo "HEALTHY"
    exit 0
else
    echo "UNHEALTHY (HTTP: $RESPONSE)"
    exit 1
fi
EOF
    
    sudo chmod +x "$INSTALL_DIR/health_check.sh"
    
    log "✓ 実行スクリプト作成完了"
}

# VOICEVOXユーザー作成
create_voicevox_user() {
    log "VOICEVOXユーザー作成中..."
    
    # システムユーザー作成
    if ! id -u voicevox > /dev/null 2>&1; then
        sudo useradd -r -s /bin/false -d "$INSTALL_DIR" -c "VOICEVOX Engine User" voicevox
        log "VOICEVOXユーザー作成完了"
    else
        log "VOICEVOXユーザーは既に存在します"
    fi
    
    # 権限設定
    sudo chown -R voicevox:voicevox "$INSTALL_DIR"
    sudo chown -R voicevox:voicevox /var/log/voicevox
    
    # 実行権限
    sudo chmod +x "$INSTALL_DIR/run"
    sudo chmod +x "$INSTALL_DIR/health_check.sh"
    
    log "✓ 権限設定完了"
}

# Systemdサービスファイル作成
create_systemd_service() {
    log "Systemdサービス作成中..."
    
    sudo tee /etc/systemd/system/voicevox.service > /dev/null << EOF
[Unit]
Description=VOICEVOX Engine - Text-to-Speech Service
Documentation=https://voicevox.hiroshiba.jp/
After=network.target
Wants=network.target

[Service]
Type=simple
User=voicevox
Group=voicevox
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/run
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=always
RestartSec=10
TimeoutStartSec=300
TimeoutStopSec=30

# 環境変数
Environment=HOME=$INSTALL_DIR
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=PYTHONUNBUFFERED=1

# セキュリティ設定
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$INSTALL_DIR /var/log/voicevox /tmp
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

# リソース制限
MemoryMax=1G
CPUQuota=80%
TasksMax=1000

# ログ設定
StandardOutput=append:/var/log/voicevox/service.log
StandardError=append:/var/log/voicevox/service.log

[Install]
WantedBy=multi-user.target
EOF
    
    # systemd設定リロード
    sudo systemctl daemon-reload
    
    # サービス有効化（自動起動設定）
    sudo systemctl enable voicevox.service
    
    log "✓ Systemdサービス作成完了"
}

# ファイアウォール設定
configure_firewall() {
    log "ファイアウォール設定中..."
    
    # UFWが有効な場合のみ設定
    if sudo ufw status | grep -q "Status: active"; then
        sudo ufw allow 50021/tcp comment "VOICEVOX Engine API"
        log "✓ ファイアウォール設定完了"
    else
        warn "UFWが無効です。必要に応じて手動でポート50021を開放してください。"
    fi
}

# インストール後の設定
post_install_configuration() {
    log "インストール後設定中..."
    
    # ログローテーション設定
    sudo tee /etc/logrotate.d/voicevox > /dev/null << 'EOF'
/var/log/voicevox/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    create 644 voicevox voicevox
}
EOF
    
    # 一時ディレクトリクリーンアップ
    rm -rf "$TEMP_DIR"
    
    log "✓ インストール後設定完了"
}

# インストールテスト
test_installation() {
    log "インストールテスト実行中..."
    
    # サービス起動
    sudo systemctl start voicevox.service
    
    # 起動待機
    for i in {1..30}; do
        if curl -s http://localhost:50021/version > /dev/null; then
            log "✓ VOICEVOX Engine 起動確認完了"
            break
        fi
        
        if [ $i -eq 30 ]; then
            error "VOICEVOX Engine の起動に失敗しました"
        fi
        
        sleep 2
    done
    
    # バージョン情報取得
    VERSION_INFO=$(curl -s http://localhost:50021/version | python3 -m json.tool 2>/dev/null || echo "バージョン情報取得失敗")
    info "VOICEVOX Engine バージョン情報: $VERSION_INFO"
    
    # スピーカー一覧取得テスト
    SPEAKERS=$(curl -s http://localhost:50021/speakers | python3 -c "import sys, json; data=json.load(sys.stdin); print(f'利用可能スピーカー数: {len(data)}')" 2>/dev/null || echo "スピーカー情報取得失敗")
    info "$SPEAKERS"
    
    # 音声合成テスト
    log "音声合成テスト実行中..."
    
    # 音声クエリ生成
    AUDIO_QUERY=$(curl -s -X POST "http://localhost:50021/audio_query?text=インストールテストです&speaker=1")
    
    if echo "$AUDIO_QUERY" | grep -q "accent_phrases"; then
        # 音声合成
        curl -s -X POST -H "Content-Type: application/json" \
            -d "$AUDIO_QUERY" \
            "http://localhost:50021/synthesis?speaker=1" \
            > /tmp/voicevox_test.wav
        
        if [ -s /tmp/voicevox_test.wav ]; then
            log "✓ 音声合成テスト成功"
            rm -f /tmp/voicevox_test.wav
        else
            error "音声合成テスト失敗"
        fi
    else
        error "音声クエリ生成失敗"
    fi
    
    log "✓ インストールテスト完了"
}

# 使用可能スピーカー一覧表示
show_available_speakers() {
    log "使用可能スピーカー一覧:"
    
    SPEAKERS_JSON=$(curl -s http://localhost:50021/speakers 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$SPEAKERS_JSON" ]; then
        echo "$SPEAKERS_JSON" | python3 -c "
import sys, json
try:
    speakers = json.load(sys.stdin)
    for speaker in speakers:
        print(f\"\\033[0;34m{speaker['name']}\\033[0m (UUID: {speaker['speaker_uuid']})\")
        for style in speaker.get('styles', []):
            print(f\"  - {style['name']} (ID: {style['id']}, Type: {style['type']})\")
        print()
except Exception as e:
    print(f'スピーカー情報の解析に失敗: {e}')
"
    else
        warn "スピーカー情報の取得に失敗しました"
    fi
}

# 使用方法を表示
show_usage_instructions() {
    log "セットアップ完了！"
    
    echo ""
    echo -e "${BLUE}=== VOICEVOX Engine 使用方法 ===${NC}"
    echo ""
    echo -e "${GREEN}サービス管理:${NC}"
    echo "  sudo systemctl start voicevox     # サービス開始"
    echo "  sudo systemctl stop voicevox      # サービス停止"
    echo "  sudo systemctl restart voicevox   # サービス再起動"
    echo "  sudo systemctl status voicevox    # サービス状態確認"
    echo ""
    echo -e "${GREEN}ログ確認:${NC}"
    echo "  sudo journalctl -u voicevox -f    # リアルタイムログ表示"
    echo "  tail -f /var/log/voicevox/engine.log"
    echo ""
    echo -e "${GREEN}API使用例:${NC}"
    echo "  curl http://localhost:50021/version"
    echo "  curl http://localhost:50021/speakers"
    echo "  curl http://localhost:50021/docs   # API仕様書（ブラウザで開く）"
    echo ""
    echo -e "${GREEN}健康チェック:${NC}"
    echo "  $INSTALL_DIR/health_check.sh"
    echo ""
    echo -e "${YELLOW}注意事項:${NC}"
    echo "  - API エンドポイント: http://localhost:50021"
    echo "  - 商用利用時は適切なライセンスを確認してください"
    echo "  - サービスの自動起動が有効になっています"
    echo ""
}

# クリーンアップ
cleanup() {
    log "クリーンアップ実行中..."
    
    # 一時ファイル削除
    rm -rf "$TEMP_DIR"
    rm -f /tmp/voicevox_*
    
    log "✓ クリーンアップ完了"
}

# エラーハンドリング
handle_error() {
    error "インストール中にエラーが発生しました"
    cleanup
    exit 1
}

trap handle_error ERR

# メイン実行関数
main() {
    echo -e "${BLUE}VOICEVOX Engine ネイティブインストール開始${NC}"
    echo "インストール先: $INSTALL_DIR"
    echo "バージョン: $VOICEVOX_VERSION"
    echo ""
    
    check_system_requirements
    install_dependencies
    prepare_directories
    download_voicevox_engine
    download_voice_models
    setup_speaker_info
    setup_python_environment
    create_execution_scripts
    create_voicevox_user
    create_systemd_service
    configure_firewall
    post_install_configuration
    test_installation
    show_available_speakers
    show_usage_instructions
    cleanup
    
    echo ""
    log "VOICEVOX Engine インストール完了！"
}

# 引数処理
case "${1:-install}" in
    install)
        main
        ;;
    test)
        test_installation
        ;;
    speakers)
        show_available_speakers
        ;;
    clean)
        cleanup
        ;;
    uninstall)
        log "VOICEVOX アンインストール中..."
        sudo systemctl stop voicevox 2>/dev/null || true
        sudo systemctl disable voicevox 2>/dev/null || true
        sudo rm -f /etc/systemd/system/voicevox.service
        sudo systemctl daemon-reload
        sudo userdel voicevox 2>/dev/null || true
        sudo rm -rf "$INSTALL_DIR"
        sudo rm -rf /var/log/voicevox
        sudo rm -f /etc/logrotate.d/voicevox
        log "✓ アンインストール完了"
        ;;
    *)
        echo "使用方法: $0 {install|test|speakers|clean|uninstall}"
        echo ""
        echo "  install    - VOICEVOX をインストール"
        echo "  test       - インストール後のテスト実行"
        echo "  speakers   - 利用可能スピーカー一覧表示"
        echo "  clean      - 一時ファイルクリーンアップ"
        echo "  uninstall  - VOICEVOX をアンインストール"
        exit 1
        ;;
esac
