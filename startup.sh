#!/bin/bash
# 24時間ラジオ配信システム 統合起動スクリプト（Dockerなし版）
# 全サービスの起動・停止・監視・復旧を管理

set -e

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 設定
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIDFILE="$SCRIPT_DIR/radio_stream.pid"
CONFIG_FILE="$SCRIPT_DIR/config.env"
LOG_DIR="$SCRIPT_DIR/logs"

# ログディレクトリ作成
mkdir -p "$LOG_DIR"

# 設定読み込み
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# ログ関数
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_DIR/startup.log"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_DIR/startup.log"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_DIR/startup.log"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_DIR/startup.log"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_DIR/startup.log"
}

# 依存関係チェック
check_dependencies() {
    local missing_deps=()
    
    # 必要なコマンドリスト
    local required_commands=("python3" "ollama" "curl" "ffplay" "obs" "Xvfb")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        error "必要なコマンドが見つかりません: ${missing_deps[*]}"
        error "setup.sh を実行してインストールしてください"
        return 1
    fi
    
    return 0
}

# 設定ファイル確認
check_configuration() {
    if [ ! -f "$CONFIG_FILE" ]; then
        error "設定ファイルが見つかりません: $CONFIG_FILE"
        return 1
    fi
    
    # 必須設定項目チェック
    local required_vars=("YOUTUBE_API_KEY" "YOUTUBE_VIDEO_ID" "YOUTUBE_STREAM_KEY")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ] || [ "${!var}" = "YOUR_${var}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        error "設定ファイルに必須項目が設定されていません: ${missing_vars[*]}"
        error "$CONFIG_FILE を編集してください"
        return 1
    fi
    
    return 0
}

# サービス開始
start_services() {
    log "24時間ラジオ配信システム開始中..."
    
    # 依存関係確認
    if ! check_dependencies; then
        return 1
    fi
    
    # 設定確認
    if ! check_configuration; then
        return 1
    fi
    
    # 既に起動している場合はスキップ
    if [ -f "$PIDFILE" ]; then
        warn "システムは既に起動中です。停止後に再開してください。"
        return 1
    fi
    
    # 1. 仮想ディスプレイ起動
    log "仮想ディスプレイ開始..."
    export DISPLAY=:1
    
    # 既存のXvfbプロセス確認・停止
    pkill -f "Xvfb :1" 2>/dev/null || true
    sleep 2
    
    Xvfb :1 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset > "$LOG_DIR/xvfb.log" 2>&1 &
    XVFB_PID=$!
    
    # Xvfb起動確認
    for i in {1..10}; do
        if kill -0 $XVFB_PID 2>/dev/null; then
            success "仮想ディスプレイ起動完了 (PID: $XVFB_PID)"
            break
        fi
        if [ $i -eq 10 ]; then
            error "仮想ディスプレイの起動に失敗しました"
            return 1
        fi
        sleep 1
    done
    
    # 2. Ollama起動確認・開始
    log "Ollama サービス確認中..."
    
    if ! systemctl is-active --quiet ollama; then
        log "Ollama サービス開始中..."
        sudo systemctl start ollama
        
        # 起動待機
        for i in {1..30}; do
            if systemctl is-active --quiet ollama; then
                success "Ollama サービス開始完了"
                break
            fi
            if [ $i -eq 30 ]; then
                error "Ollama サービスの開始に失敗しました"
                return 1
            fi
            sleep 1
        done
    else
        success "Ollama サービスは既に動作中"
    fi
    
    # Ollama API確認
    for i in {1..30}; do
        if curl -s http://localhost:11434/api/version > /dev/null; then
            success "Ollama API接続確認完了"
            break
        fi
        if [ $i -eq 30 ]; then
            error "Ollama APIに接続できません"
            return 1
        fi
        sleep 2
    done
    
    # 3. VOICEVOX起動確認・開始
    log "VOICEVOX サービス確認中..."
    
    if ! systemctl is-active --quiet voicevox; then
        log "VOICEVOX サービス開始中..."
        sudo systemctl start voicevox
        
        # 起動待機
        for i in {1..60}; do
            if systemctl is-active --quiet voicevox; then
                success "VOICEVOX サービス開始完了"
                break
            fi
            if [ $i -eq 60 ]; then
                error "VOICEVOX サービスの開始に失敗しました"
                return 1
            fi
            sleep 1
        done
    else
        success "VOICEVOX サービスは既に動作中"
    fi
    
    # VOICEVOX API確認
    for i in {1..60}; do
        if curl -s http://localhost:50021/version > /dev/null; then
            success "VOICEVOX API接続確認完了"
            break
        fi
        if [ $i -eq 60 ]; then
            error "VOICEVOX APIに接続できません"
            return 1
        fi
        sleep 2
    done
    
    # 4. 音声システム設定
    log "音声システム設定中..."
    
    # PulseAudio設定（必要に応じて）
    if command -v pactl &> /dev/null; then
        # PulseAudioサーバー起動
        pulseaudio --start --log-target=syslog 2>/dev/null || true
        
        # 音声デバイス確認
        if pactl info > /dev/null 2>&1; then
            success "PulseAudio設定完了"
        else
            warn "PulseAudio設定に問題があります"
        fi
    fi
    
    # 5. OBS Studio起動
    log "OBS Studio起動中..."
    
    # OBS設定ディレクトリ確認
    if [ ! -d "$HOME/.config/obs-studio" ]; then
        warn "OBS設定が見つかりません。デフォルト設定を作成します..."
        if [ -f "$SCRIPT_DIR/obs_config.sh" ]; then
            bash "$SCRIPT_DIR/obs_config.sh"
        fi
    fi
    
    # OBS起動
    DISPLAY=:1 obs --startstreaming --minimize-to-tray \
        --collection "Radio" --profile "Radio" \
        > "$LOG_DIR/obs.log" 2>&1 &
    OBS_PID=$!
    
    # OBS起動確認
    for i in {1..30}; do
        if kill -0 $OBS_PID 2>/dev/null; then
            success "OBS Studio起動完了 (PID: $OBS_PID)"
            break
        fi
        if [ $i -eq 30 ]; then
            error "OBS Studioの起動に失敗しました"
            return 1
        fi
        sleep 1
    done
    
    # 6. メインアプリケーション起動
    log "メインアプリケーション起動中..."
    
    if [ ! -f "$SCRIPT_DIR/radio_streaming_bot.py" ]; then
        error "メインアプリケーションが見つかりません: radio_streaming_bot.py"
        return 1
    fi
    
    cd "$SCRIPT_DIR"
    python3 radio_streaming_bot.py > "$LOG_DIR/main_app.log" 2>&1 &
    MAIN_PID=$!
    
    # アプリケーション起動確認
    for i in {1..15}; do
        if kill -0 $MAIN_PID 2>/dev/null; then
            success "メインアプリケーション起動完了 (PID: $MAIN_PID)"
            break
        fi
        if [ $i -eq 15 ]; then
            error "メインアプリケーションの起動に失敗しました"
            return 1
        fi
        sleep 2
    done
    
    # PIDファイル作成
    echo "$XVFB_PID $OBS_PID $MAIN_PID" > "$PIDFILE"
    
    # 起動完了メッセージ
    success "24時間ラジオ配信システム起動完了！"
    log "PID情報: Xvfb=$XVFB_PID, OBS=$OBS_PID, Main=$MAIN_PID"
    log "ログディレクトリ: $LOG_DIR"
    
    return 0
}

# サービス停止
stop_services() {
    log "24時間ラジオ配信システム停止中..."
    
    if [ ! -f "$PIDFILE" ]; then
        warn "PIDファイルが見つかりません。強制停止を実行します。"
        force_stop_all
        return 0
    fi
    
    # PIDファイル読み込み
    if ! read XVFB_PID OBS_PID MAIN_PID < "$PIDFILE"; then
        error "PIDファイルの読み込みに失敗しました"
        return 1
    fi
    
    # メインアプリケーション停止
    log "メインアプリケーション停止中..."
    if [ -n "$MAIN_PID" ] && kill -0 "$MAIN_PID" 2>/dev/null; then
        kill -TERM "$MAIN_PID" 2>/dev/null
        
        # 正常終了待機
        for i in {1..10}; do
            if ! kill -0 "$MAIN_PID" 2>/dev/null; then
                success "メインアプリケーション停止完了"
                break
            fi
            if [ $i -eq 10 ]; then
                warn "強制停止を実行します"
                kill -KILL "$MAIN_PID" 2>/dev/null || true
            fi
            sleep 1
        done
    fi
    
    # OBS停止
    log "OBS Studio停止中..."
    if [ -n "$OBS_PID" ] && kill -0 "$OBS_PID" 2>/dev/null; then
        kill -TERM "$OBS_PID" 2>/dev/null
        sleep 3
        kill -KILL "$OBS_PID" 2>/dev/null || true
        success "OBS Studio停止完了"
    fi
    
    # 追加のOBSプロセス停止
    pkill -f obs 2>/dev/null || true
    
    # Xvfb停止
    log "仮想ディスプレイ停止中..."
    if [ -n "$XVFB_PID" ] && kill -0 "$XVFB_PID" 2>/dev/null; then
        kill -TERM "$XVFB_PID" 2>/dev/null
        sleep 2
        kill -KILL "$XVFB_PID" 2>/dev/null || true
        success "仮想ディスプレイ停止完了"
    fi
    
    # 追加のXvfbプロセス停止  
    pkill -f "Xvfb :1" 2>/dev/null || true
    
    # VOICEVOXサービス停止（オプション）
    if [ "${STOP_VOICEVOX:-false}" = "true" ]; then
        log "VOICEVOX サービス停止中..."
        sudo systemctl stop voicevox 2>/dev/null || true
        success "VOICEVOX サービス停止完了"
    fi
    
    # PIDファイル削除
    rm -f "$PIDFILE"
    
    success "24時間ラジオ配信システム停止完了"
    return 0
}

# 強制停止
force_stop_all() {
    warn "全プロセス強制停止を実行します..."
    
    # プロセス名による停止
    pkill -f "radio_streaming_bot.py" 2>/dev/null || true
    pkill -f "obs" 2>/dev/null || true
    pkill -f "Xvfb :1" 2>/dev/null || true
    
    # PIDファイル削除
    rm -f "$PIDFILE"
    
    success "強制停止完了"
}

# サービス状態確認
check_status() {
    log "サービス状況確認中..."
    
    local all_running=true
    
    # Ollama確認
    if systemctl is-active --quiet ollama && curl -s http://localhost:11434/api/version > /dev/null; then
        echo -e "  ${GREEN}✓${NC} Ollama: 動作中"
    else
        echo -e "  ${RED}✗${NC} Ollama: 停止中または応答なし"
        all_running=false
    fi
    
    # VOICEVOX確認
    if systemctl is-active --quiet voicevox && curl -s http://localhost:50021/version > /dev/null; then
        echo -e "  ${GREEN}✓${NC} VOICEVOX: 動作中"
    else
        echo -e "  ${RED}✗${NC} VOICEVOX: 停止中または応答なし"
        all_running=false
    fi
    
    # 仮想ディスプレイ確認
    if pgrep -f "Xvfb :1" > /dev/null; then
        echo -e "  ${GREEN}✓${NC} 仮想ディスプレイ: 動作中"
    else
        echo -e "  ${RED}✗${NC} 仮想ディスプレイ: 停止中"
        all_running=false
    fi
    
    # OBS確認
    if pgrep -f obs > /dev/null; then
        echo -e "  ${GREEN}✓${NC} OBS Studio: 動作中"
    else
        echo -e "  ${RED}✗${NC} OBS Studio: 停止中"
        all_running=false
    fi
    
    # メインアプリ確認
    if pgrep -f "radio_streaming_bot.py" > /dev/null; then
        echo -e "  ${GREEN}✓${NC} メインアプリケーション: 動作中"
    else
        echo -e "  ${RED}✗${NC} メインアプリケーション: 停止中"
        all_running=false
    fi
    
    # 統合状態
    echo ""
    if $all_running; then
        success "全サービス正常動作中"
        return 0
    else
        warn "一部サービスに問題があります"
        return 1
    fi
}

# 詳細状態確認
detailed_status() {
    echo -e "${CYAN}=== 詳細システム状態 ===${NC}"
    
    # システムリソース
    echo -e "\n${BLUE}システムリソース:${NC}"
    echo "  CPU使用率: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')%"
    echo "  メモリ使用率: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"
    echo "  ディスク使用率: $(df / | tail -1 | awk '{print $5}')"
    
    # プロセス情報
    echo -e "\n${BLUE}プロセス情報:${NC}"
    if [ -f "$PIDFILE" ]; then
        read XVFB_PID OBS_PID MAIN_PID < "$PIDFILE" 2>/dev/null || true
        echo "  Xvfb PID: ${XVFB_PID:-N/A}"
        echo "  OBS PID: ${OBS_PID:-N/A}"  
        echo "  Main App PID: ${MAIN_PID:-N/A}"
    else
        echo "  PIDファイルが見つかりません"
    fi
    
    # ログファイル情報
    echo -e "\n${BLUE}ログファイル:${NC}"
    for logfile in "$LOG_DIR"/*.log; do
        if [ -f "$logfile" ]; then
            local size=$(du -h "$logfile" | cut -f1)
            local mtime=$(stat -c %y "$logfile" | cut -d. -f1)
            echo "  $(basename "$logfile"): ${size} (最終更新: $mtime)"
        fi
    done
    
    # ネットワーク接続
    echo -e "\n${BLUE}ネットワーク接続:${NC}"
    if ping -c 1 8.8.8.8 &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} インターネット接続: 正常"
    else
        echo -e "  ${RED}✗${NC} インターネット接続: 問題あり" 
    fi
    
    # API応答時間
    echo -e "\n${BLUE}API応答時間:${NC}"
    local ollama_time=$(curl -o /dev/null -s -w "%{time_total}" http://localhost:11434/api/version 2>/dev/null || echo "N/A")
    local voicevox_time=$(curl -o /dev/null -s -w "%{time_total}" http://localhost:50021/version 2>/dev/null || echo "N/A")
    echo "  Ollama API: ${ollama_time}秒"
    echo "  VOICEVOX API: ${voicevox_time}秒"
}

# リソース監視
monitor_resources() {
    log "リソース監視開始（Ctrl+Cで終了）..."
    
    while true; do
        clear
        echo -e "${CYAN}=== 24時間ラジオ配信システム リアルタイム監視 ===${NC}"
        echo "最終更新: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        
        # サービス状態
        check_status
        
        # リソース使用量
        echo -e "\n${BLUE}リソース使用量:${NC}"
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
        local mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
        local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
        
        # カラー表示（使用率に基づく）
        local cpu_color="${GREEN}"
        local mem_color="${GREEN}"
        local disk_color="${GREEN}"
        
        if (( $(echo "$cpu_usage > 80" | bc -l) )); then cpu_color="${RED}"; fi
        if (( $(echo "$mem_usage > 80" | bc -l) )); then mem_color="${RED}"; fi
        if [ "$disk_usage" -gt 80 ]; then disk_color="${RED}"; fi
        
        echo -e "  CPU: ${cpu_color}${cpu_usage}%${NC}"
        echo -e "  メモリ: ${mem_color}${mem_usage}%${NC}"
        echo -e "  ディスク: ${disk_color}${disk_usage}%${NC}"
        
        # プロセス監視
        echo -e "\n${BLUE}プロセス監視:${NC}"
        local main_cpu=$(ps -p $(pgrep -f "radio_streaming_bot.py" | head -1) -o %cpu --no-headers 2>/dev/null || echo "0")
        local obs_cpu=$(ps -p $(pgrep -f "obs" | head -1) -o %cpu --no-headers 2>/dev/null || echo "0")
        
        echo "  メインアプリ CPU: ${main_cpu}%"
        echo "  OBS Studio CPU: ${obs_cpu}%"
        
        # 統計情報（ログから取得）
        if [ -f "$LOG_DIR/main_app.log" ]; then
            local error_count=$(grep -c "ERROR" "$LOG_DIR/main_app.log" 2>/dev/null || echo "0")
            local comment_count=$(grep -c "新しいコメント" "$LOG_DIR/main_app.log" 2>/dev/null || echo "0")
            
            echo -e "\n${BLUE}アプリケーション統計:${NC}"
            echo "  処理コメント数: $comment_count"
            echo "  エラー数: $error_count"
        fi
        
        sleep 5
    done
}

# 自動復旧機能
auto_recovery() {
    log "自動復旧機能開始（Ctrl+Cで終了）..."
    
    local check_interval=${RECOVERY_INTERVAL:-60}
    local max_restarts=5
    local restart_count=0
    local last_restart_time=0
    
    while true; do
        sleep "$check_interval"
        
        local current_time=$(date +%s)
        local services_down=()
        
        # サービス死活監視
        if ! pgrep -f "radio_streaming_bot.py" > /dev/null; then
            services_down+=("メインアプリケーション")
        fi
        
        if ! pgrep -f "obs" > /dev/null; then
            services_down+=("OBS Studio")
        fi
        
        if ! pgrep -f "Xvfb :1" > /dev/null; then
            services_down+=("仮想ディスプレイ")
        fi
        
        if ! systemctl is-active --quiet voicevox || ! curl -s http://localhost:50021/version > /dev/null; then
            services_down+=("VOICEVOX")
        fi
        
        if ! systemctl is-active --quiet ollama || ! curl -s http://localhost:11434/api/version > /dev/null; then
            services_down+=("Ollama")
        fi
        
        # サービス復旧処理
        if [ ${#services_down[@]} -gt 0 ]; then
            warn "停止サービス検出: ${services_down[*]}"
            
            # 復旧制限チェック
            if [ $restart_count -ge $max_restarts ]; then
                local time_since_last=$((current_time - last_restart_time))
                if [ $time_since_last -lt 3600 ]; then  # 1時間
                    error "復旧試行回数上限に達しました。手動対応が必要です。"
                    continue
                else
                    restart_count=0  # 1時間経過でカウンターリセット
                fi
            fi
            
            log "システム復旧を実行します..."
            
            # 全サービス停止
            stop_services
            sleep 10
            
            # 全サービス再開
            if start_services; then
                success "システム復旧完了"
                restart_count=$((restart_count + 1))
                last_restart_time=$current_time
            else
                error "システム復旧に失敗しました"
                restart_count=$((restart_count + 1))
            fi
        fi
    done
}

# ログ表示
show_logs() {
    local log_type="${1:-all}"
    
    case "$log_type" in
        main|app)
            if [ -f "$LOG_DIR/main_app.log" ]; then
                tail -f "$LOG_DIR/main_app.log"
            else
                error "メインアプリログが見つかりません"
            fi
            ;;
        obs)
            if [ -f "$LOG_DIR/obs.log" ]; then
                tail -f "$LOG_DIR/obs.log"
            else
                error "OBSログが見つかりません"
            fi
            ;;
        system|startup)
            if [ -f "$LOG_DIR/startup.log" ]; then
                tail -f "$LOG_DIR/startup.log"
            else
                error "システムログが見つかりません"
            fi
            ;;
        all|*)
            echo -e "${BLUE}利用可能なログファイル:${NC}"
            for logfile in "$LOG_DIR"/*.log; do
                if [ -f "$logfile" ]; then
                    echo "  $(basename "$logfile")"
                fi
            done
            echo ""
            echo "使用法: $0 logs {main|obs|system|all}"
            ;;
    esac
}

# 使用方法表示
show_usage() {
    echo -e "${BLUE}24時間ラジオ配信システム 操作コマンド${NC}"
    echo ""
    echo "使用方法: $0 {start|stop|restart|status|monitor|recovery|logs|force-stop}"
    echo ""
    echo -e "${GREEN}基本操作:${NC}"
    echo "  start      - 全サービス開始"
    echo "  stop       - 全サービス停止"
    echo "  restart    - 全サービス再起動"
    echo "  status     - サービス状況確認"
    echo ""
    echo -e "${GREEN}監視・保守:${NC}"
    echo "  monitor    - リアルタイムリソース監視"
    echo "  recovery   - 自動復旧機能開始"
    echo "  logs       - ログ表示 {main|obs|system|all}"
    echo "  detailed   - 詳細状態表示"
    echo ""
    echo -e "${GREEN}緊急時:${NC}"
    echo "  force-stop - 全プロセス強制停止"
    echo ""
    echo -e "${YELLOW}設定ファイル:${NC} $CONFIG_FILE"
    echo -e "${YELLOW}ログディレクトリ:${NC} $LOG_DIR"
}

# メイン処理
main() {
    case "${1:-help}" in
        start)
            start_services
            ;;
        stop)
            stop_services
            ;;
        restart)
            log "システム再起動中..."
            stop_services
            sleep 5
            start_services
            ;;
        status)
            check_status
            ;;
        detailed)
            detailed_status
            ;;
        monitor)
            monitor_resources
            ;;
        recovery)
            auto_recovery
            ;;
        logs)
            show_logs "$2"
            ;;
        force-stop)
            force_stop_all
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

# Ctrl+C処理
trap 'echo -e "\n\n操作を中断しました"; exit 0' INT

# メイン実行
main "$@"
