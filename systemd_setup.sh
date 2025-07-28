#!/bin/bash
# 24時間ラジオ配信システム Systemdサービス設定スクリプト
# 自動起動、依存関係管理、障害復旧を設定

set -e

# 色定義
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 設定
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="radio-streaming"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
TIMER_FILE="/etc/systemd/system/${SERVICE_NAME}.timer"
USER=$(whoami)
GROUP=$(id -gn)

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 権限確認
check_permissions() {
    if [[ $EUID -eq 0 ]]; then
        error "このスクリプトはrootユーザーで実行しないでください"
    fi
    
    # sudo権限確認
    if ! sudo -n true 2>/dev/null; then
        warn "sudo権限が必要です。パスワードを入力してください。"
        sudo -v || error "sudo権限の取得に失敗しました"
    fi
    
    log "✓ 権限確認完了"
}

# 依存サービス確認
check_dependencies() {
    log "依存サービス確認中..."
    
    local missing_services=()
    
    # 必要なサービス
    local required_services=("ollama" "voicevox")
    
    for service in "${required_services[@]}"; do
        if ! systemctl list-unit-files | grep -q "^${service}.service"; then
            missing_services+=("$service")
        fi
    done
    
    if [ ${#missing_services[@]} -gt 0 ]; then
        warn "以下のサービスが見つかりません: ${missing_services[*]}"
        warn "先に依存サービスをインストールしてください"
    else
        success "依存サービス確認完了"
    fi
}

# メインサービスファイル作成
create_main_service() {
    log "メインサービス作成中..."
    
    sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=24時間ラジオ配信システム - AI Radio Streaming Service
Documentation=https://github.com/radio-streaming/docs
After=network-online.target ollama.service voicevox.service
Wants=network-online.target
Requires=ollama.service voicevox.service
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=forking
User=$USER
Group=$GROUP
WorkingDirectory=$SCRIPT_DIR
ExecStartPre=/bin/sleep 10
ExecStart=$SCRIPT_DIR/startup.sh start
ExecStop=$SCRIPT_DIR/startup.sh stop
ExecReload=$SCRIPT_DIR/startup.sh restart
PIDFile=$SCRIPT_DIR/radio_stream.pid
Restart=always
RestartSec=30
TimeoutStartSec=300
TimeoutStopSec=60
KillMode=mixed
KillSignal=SIGTERM

# 環境変数
Environment=HOME=$HOME
Environment=USER=$USER
Environment=DISPLAY=:1
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=PYTHONUNBUFFERED=1
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u $USER)

# リソース制限
MemoryMax=3500M
MemoryHigh=3000M
CPUQuota=150%
TasksMax=2000
IOWeight=100

# セキュリティ設定
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$SCRIPT_DIR /tmp /var/tmp
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictRealtime=true
RestrictNamespaces=true

# ログ設定
StandardOutput=append:$SCRIPT_DIR/logs/service.log
StandardError=append:$SCRIPT_DIR/logs/service_error.log
SyslogIdentifier=$SERVICE_NAME

# 障害復旧設定
RestartPreventExitStatus=SIGKILL
RestartForceExitStatus=SIGPIPE
SuccessExitStatus=0 1 2 8 SIGTERM

[Install]
WantedBy=multi-user.target
EOF

    success "メインサービス作成完了"
}

# 定期実行タイマー作成
create_timer_service() {
    log "定期実行タイマー作成中..."
    
    sudo tee "$TIMER_FILE" > /dev/null << EOF
[Unit]
Description=24時間ラジオ配信システム 定期メンテナンス
Requires=${SERVICE_NAME}.service

[Timer]
# 毎日午前3時にメンテナンス実行
OnCalendar=*-*-* 03:00:00
# システムが停止していた場合は起動後に実行
Persistent=true
# 実行時間をランダム化（負荷分散）
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

    # メンテナンススクリプト作成
    cat > "$SCRIPT_DIR/maintenance.sh" << 'EOF'
#!/bin/bash
# 定期メンテナンススクリプト

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/logs/maintenance.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "定期メンテナンス開始"

# ログローテーション
find "$SCRIPT_DIR/logs" -name "*.log" -type f -size +100M -exec gzip {} \;
find "$SCRIPT_DIR/logs" -name "*.log.gz" -type f -mtime +30 -delete

# 一時ファイルクリーンアップ
find /tmp -name "speech_*" -type f -mtime +1 -delete 2>/dev/null || true
find /tmp -name "voicevox_*" -type f -mtime +1 -delete 2>/dev/null || true

# システムリソース確認
MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')

log "メモリ使用率: ${MEMORY_USAGE}%"
log "ディスク使用率: ${DISK_USAGE}%"

# 高負荷時の警告
if (( $(echo "$MEMORY_USAGE > 90" | bc -l) )); then
    log "WARNING: メモリ使用率が高い (${MEMORY_USAGE}%)"
fi

if [ "$DISK_USAGE" -gt 90 ]; then
    log "WARNING: ディスク使用率が高い (${DISK_USAGE}%)"
fi

# サービス健康チェック
if ! systemctl is-active --quiet radio-streaming; then
    log "WARNING: ラジオ配信サービスが停止しています"
    systemctl start radio-streaming
fi

log "定期メンテナンス完了"
EOF

    chmod +x "$SCRIPT_DIR/maintenance.sh"
    
    success "定期実行タイマー作成完了"
}

# ログローテーション設定
create_logrotate_config() {
    log "ログローテーション設定中..."
    
    sudo tee "/etc/logrotate.d/$SERVICE_NAME" > /dev/null << EOF
$SCRIPT_DIR/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    create 644 $USER $GROUP
    postrotate
        # サービス再起動は不要（copytruncateを使用）
        /bin/true
    endscript
}
EOF

    success "ログローテーション設定完了"
}

# 監視スクリプト作成
create_monitoring_script() {
    log "監視スクリプト作成中..."
    
    cat > "$SCRIPT_DIR/monitor.sh" << 'EOF'
#!/bin/bash
# システム監視スクリプト

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALERT_LOG="$SCRIPT_DIR/logs/alerts.log"
CONFIG_FILE="$SCRIPT_DIR/config.env"

# 設定読み込み
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# 閾値設定
MEMORY_THRESHOLD=${MEMORY_THRESHOLD:-85}
CPU_THRESHOLD=${CPU_THRESHOLD:-80}
DISK_THRESHOLD=${DISK_THRESHOLD:-85}

alert() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALERT: $1" | tee -a "$ALERT_LOG"
    
    # 通知処理（必要に応じて拡張）
    # curl -X POST webhook_url -d "message=$1" # Slack通知など
}

# リソース監視
check_resources() {
    # メモリ使用率
    MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    if (( $(echo "$MEMORY_USAGE > $MEMORY_THRESHOLD" | bc -l) )); then
        alert "メモリ使用率が閾値を超えました: ${MEMORY_USAGE}%"
    fi
    
    # CPU使用率（1分平均）
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
    if (( $(echo "$CPU_USAGE > $CPU_THRESHOLD" | bc -l) )); then
        alert "CPU使用率が閾値を超えました: ${CPU_USAGE}%"
    fi
    
    # ディスク使用率
    DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$DISK_USAGE" -gt "$DISK_THRESHOLD" ]; then
        alert "ディスク使用率が閾値を超えました: ${DISK_USAGE}%"
    fi
}

# サービス監視
check_services() {
    local services=("radio-streaming" "ollama" "voicevox")
    
    for service in "${services[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            alert "サービス停止検出: $service"
            
            # 自動復旧試行
            systemctl start "$service" && \
                alert "サービス自動復旧成功: $service" || \
                alert "サービス自動復旧失敗: $service"
        fi
    done
}

# API監視
check_apis() {
    # Ollama API
    if ! curl -s http://localhost:11434/api/version > /dev/null; then
        alert "Ollama API応答なし"
    fi
    
    # VOICEVOX API
    if ! curl -s http://localhost:50021/version > /dev/null; then
        alert "VOICEVOX API応答なし"
    fi
}

# プロセス監視
check_processes() {
    local processes=("radio_streaming_bot.py" "obs" "Xvfb")
    
    for process in "${processes[@]}"; do
        if ! pgrep -f "$process" > /dev/null; then
            alert "プロセス停止検出: $process"
        fi
    done
}

# メイン監視処理
main() {
    check_resources
    check_services
    check_apis
    check_processes
}

# 引数処理
case "${1:-monitor}" in
    monitor)
        main
        ;;
    daemon)
        # デーモンモード（継続監視）
        while true; do
            main
            sleep 60
        done
        ;;
    *)
        echo "使用方法: $0 {monitor|daemon}"
        exit 1
        ;;
esac
EOF

    chmod +x "$SCRIPT_DIR/monitor.sh"
    
    success "監視スクリプト作成完了"
}

# Systemd設定適用
apply_systemd_configuration() {
    log "Systemd設定適用中..."
    
    # systemd設定リロード
    sudo systemctl daemon-reload
    
    # サービス有効化
    sudo systemctl enable "${SERVICE_NAME}.service"
    sudo systemctl enable "${SERVICE_NAME}.timer"
    
    # 依存サービス確認と有効化
    for service in ollama voicevox; do
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            sudo systemctl enable "$service.service"
            info "依存サービス有効化: $service"
        fi
    done
    
    success "Systemd設定適用完了"
}

# 設定テスト
test_configuration() {
    log "設定テスト実行中..."
    
    # 設定ファイル構文チェック
    if ! systemd-analyze verify "$SERVICE_FILE"; then
        error "サービスファイルの構文エラーが検出されました"
    fi
    
    # 依存関係チェック
    info "サービス依存関係:"
    systemctl list-dependencies "${SERVICE_NAME}.service" --plain
    
    # タイマー確認
    if [ -f "$TIMER_FILE" ]; then
        info "タイマー設定:"
        systemctl list-timers "${SERVICE_NAME}.timer" --all
    fi
    
    success "設定テスト完了"
}

# サービス状態表示
show_service_status() {
    echo -e "${CYAN}=== サービス状態 ===${NC}"
    
    # メインサービス
    echo -e "\n${BLUE}メインサービス:${NC}"
    systemctl status "${SERVICE_NAME}.service" --no-pager -l
    
    # 依存サービス
    echo -e "\n${BLUE}依存サービス:${NC}"
    for service in ollama voicevox; do
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            echo -e "\n--- $service ---"
            systemctl status "$service.service" --no-pager -l
        fi
    done
    
    # タイマー
    if [ -f "$TIMER_FILE" ]; then
        echo -e "\n${BLUE}定期実行タイマー:${NC}"
        systemctl status "${SERVICE_NAME}.timer" --no-pager -l
    fi
}

# サービス管理コマンド表示
show_service_commands() {
    echo -e "${BLUE}=== サービス管理コマンド ===${NC}"
    echo ""
    echo -e "${GREEN}基本操作:${NC}"
    echo "  sudo systemctl start $SERVICE_NAME     # サービス開始"
    echo "  sudo systemctl stop $SERVICE_NAME      # サービス停止"
    echo "  sudo systemctl restart $SERVICE_NAME   # サービス再起動"
    echo "  sudo systemctl status $SERVICE_NAME    # サービス状態確認"
    echo ""
    echo -e "${GREEN}自動起動管理:${NC}"
    echo "  sudo systemctl enable $SERVICE_NAME    # 自動起動有効化"
    echo "  sudo systemctl disable $SERVICE_NAME   # 自動起動無効化"
    echo ""
    echo -e "${GREEN}ログ確認:${NC}"
    echo "  sudo journalctl -u $SERVICE_NAME -f    # リアルタイムログ"
    echo "  sudo journalctl -u $SERVICE_NAME --since today"
    echo "  tail -f $SCRIPT_DIR/logs/service.log"
    echo ""
    echo -e "${GREEN}監視・メンテナンス:${NC}"
    echo "  $SCRIPT_DIR/monitor.sh                 # 状態監視"
    echo "  $SCRIPT_DIR/maintenance.sh             # メンテナンス実行"
    echo "  systemctl list-dependencies $SERVICE_NAME"
}

# 設定削除
remove_configuration() {
    warn "Systemd設定を削除します..."
    
    read -p "本当に削除しますか？ (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # サービス停止・無効化
        sudo systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
        sudo systemctl stop "${SERVICE_NAME}.timer" 2>/dev/null || true
        sudo systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true
        sudo systemctl disable "${SERVICE_NAME}.timer" 2>/dev/null || true
        
        # ファイル削除
        sudo rm -f "$SERVICE_FILE"
        sudo rm -f "$TIMER_FILE"
        sudo rm -f "/etc/logrotate.d/$SERVICE_NAME"
        rm -f "$SCRIPT_DIR/maintenance.sh"
        rm -f "$SCRIPT_DIR/monitor.sh"
        
        # systemd設定リロード
        sudo systemctl daemon-reload
        
        success "設定削除完了"
    else
        log "削除をキャンセルしました"
    fi
}

# 使用方法表示
show_usage() {
    echo -e "${BLUE}Systemdサービス設定スクリプト${NC}"
    echo ""
    echo "使用方法: $0 [コマンド]"
    echo ""
    echo -e "${GREEN}コマンド:${NC}"
    echo "  install    - サービス設定とインストール（デフォルト）"
    echo "  test       - 設定テスト実行"
    echo "  status     - サービス状態表示"
    echo "  commands   - 管理コマンド一覧表示"
    echo "  remove     - 設定削除"
    echo "  help       - このヘルプを表示"
    echo ""
    echo -e "${YELLOW}注意事項:${NC}"
    echo "  - sudo権限が必要です"
    echo "  - 事前にOllamaとVOICEVOXのインストールが必要です"
    echo "  - サービスの自動起動が有効になります"
}

# メイン実行
main() {
    case "${1:-install}" in
        install)
            log "Systemdサービス設定開始"
            check_permissions
            check_dependencies
            create_main_service
            create_timer_service
            create_logrotate_config
            create_monitoring_script
            apply_systemd_configuration
            test_configuration
            
            success "Systemdサービス設定完了！"
            echo ""
            show_service_commands
            ;;
        test)
            check_permissions
            test_configuration
            ;;
        status)
            show_service_status
            ;;
        commands)
            show_service_commands
            ;;
        remove)
            check_permissions
            remove_configuration
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            error "不明なコマンド: $1"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
