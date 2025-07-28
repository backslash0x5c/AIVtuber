#!/bin/bash
# 24時間ラジオ配信システム 総合診断スクリプト
# システム健康状態チェックとトラブルシューティング支援

set -e

# 色定義
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# 設定
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"
LOG_FILE="$SCRIPT_DIR/logs/system_check.log"
REPORT_FILE="$SCRIPT_DIR/logs/health_report_$(date +%Y%m%d_%H%M%S).json"

# グローバル変数
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0
ISSUES=()

# ログ関数
log() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
    ((PASSED_CHECKS++))
    ((TOTAL_CHECKS++))
}

error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"
    ISSUES+=("ERROR: $1")
    ((FAILED_CHECKS++))
    ((TOTAL_CHECKS++))
}

warn() {
    echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$LOG_FILE"
    ISSUES+=("WARNING: $1")
    ((WARNING_CHECKS++))
    ((TOTAL_CHECKS++))
}

info() {
    echo -e "${CYAN}[i]${NC} $1" | tee -a "$LOG_FILE"
}

# ヘッダー表示
show_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                  24時間ラジオ配信システム 総合診断                           ║"
    echo "║                     System Health Check & Diagnostics                       ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "実行時刻: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "診断ログ: $LOG_FILE"
    echo ""
}

# システム基本情報
check_system_info() {
    echo -e "${BLUE}${BOLD}=== システム基本情報 ===${NC}"
    
    info "OS: $(lsb_release -d | cut -f2)"
    info "カーネル: $(uname -r)"
    info "アーキテクチャ: $(uname -m)"
    info "CPU: $(nproc) cores"
    info "メモリ: $(free -h | awk 'NR==2{printf "%s/%s", $3,$2}')"
    info "ディスク: $(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3,$2,$5}')"
    info "稼働時間: $(uptime -p)"
    
    # 負荷平均
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    info "負荷平均: $load_avg"
    
    echo ""
}

# 設定ファイルチェック
check_configuration() {
    echo -e "${BLUE}${BOLD}=== 設定ファイル確認 ===${NC}"
    
    if [ -f "$CONFIG_FILE" ]; then
        success "設定ファイル存在: $CONFIG_FILE"
        
        # 設定内容チェック
        source "$CONFIG_FILE" 2>/dev/null || true
        
        # 必須設定確認
        if [ "$YOUTUBE_API_KEY" = "YOUR_YOUTUBE_DATA_API_KEY" ] || [ -z "$YOUTUBE_API_KEY" ]; then
            error "YouTube API キーが未設定"
        else
            success "YouTube API キー設定済み"
        fi
        
        if [ "$YOUTUBE_VIDEO_ID" = "YOUR_LIVE_VIDEO_ID" ] || [ -z "$YOUTUBE_VIDEO_ID" ]; then
            error "YouTube Video ID が未設定"
        else
            success "YouTube Video ID 設定済み"
        fi
        
        if [ "$YOUTUBE_STREAM_KEY" = "YOUR_YOUTUBE_STREAM_KEY" ] || [ -z "$YOUTUBE_STREAM_KEY" ]; then
            error "YouTube Stream Key が未設定"
        else
            success "YouTube Stream Key 設定済み"
        fi
        
    else
        error "設定ファイルが見つかりません: $CONFIG_FILE"
    fi
    
    echo ""
}

# Python環境チェック
check_python_environment() {
    echo -e "${BLUE}${BOLD}=== Python環境確認 ===${NC}"
    
    if command -v python3 &> /dev/null; then
        local python_version=$(python3 --version 2>&1)
        success "Python3: $python_version"
        
        # 必要なパッケージ確認
        local required_packages=("requests" "asyncio")
        for package in "${required_packages[@]}"; do
            if python3 -c "import $package" 2>/dev/null; then
                success "Python パッケージ '$package' インストール済み"
            else
                error "Python パッケージ '$package' が見つかりません"
            fi
        done
        
    else
        error "Python3 がインストールされていません"
    fi
    
    echo ""
}

# Ollamaサービスチェック
check_ollama_service() {
    echo -e "${BLUE}${BOLD}=== Ollama サービス確認 ===${NC}"
    
    # インストール確認
    if command -v ollama &> /dev/null; then
        success "Ollama コマンド利用可能"
        
        # サービス状態確認
        if systemctl is-active --quiet ollama; then
            success "Ollama サービス動作中"
            
            # API応答確認
            local api_start_time=$(date +%s.%N)
            if curl -s http://localhost:11434/api/version > /dev/null; then
                local api_end_time=$(date +%s.%N)
                local response_time=$(echo "$api_end_time - $api_start_time" | bc)
                success "Ollama API 応答正常 (${response_time}s)"
                
                # モデル確認
                if ollama list | grep -q "gemma:1b"; then
                    success "Gemma:1b モデル利用可能"
                    
                    # テスト推論実行
                    log "Ollama 推論テスト実行中..."
                    local test_response=$(ollama run gemma:1b "Hello" 2>/dev/null | head -1)
                    if [ -n "$test_response" ]; then
                        success "Ollama 推論テスト成功"
                        info "テスト応答: $test_response"
                    else
                        warn "Ollama 推論テストで応答が得られませんでした"
                    fi
                else
                    error "Gemma:1b モデルが見つかりません"
                fi
            else
                error "Ollama API 応答なし (http://localhost:11434)"
            fi
        else
            error "Ollama サービス停止中"
        fi
    else
        error "Ollama がインストールされていません"
    fi
    
    echo ""
}

# VOICEVOXサービスチェック
check_voicevox_service() {
    echo -e "${BLUE}${BOLD}=== VOICEVOX サービス確認 ===${NC}"
    
    # インストール確認
    if [ -d "/opt/voicevox" ]; then
        success "VOICEVOX インストールディレクトリ存在"
        
        # サービス状態確認
        if systemctl is-active --quiet voicevox; then
            success "VOICEVOX サービス動作中"
            
            # API応答確認
            local api_start_time=$(date +%s.%N)
            if curl -s http://localhost:50021/version > /dev/null; then
                local api_end_time=$(date +%s.%N)
                local response_time=$(echo "$api_end_time - $api_start_time" | bc)
                success "VOICEVOX API 応答正常 (${response_time}s)"
                
                # バージョン情報取得
                local version_info=$(curl -s http://localhost:50021/version 2>/dev/null)
                if [ -n "$version_info" ]; then
                    info "VOICEVOX バージョン: $version_info"
                fi
                
                # スピーカー一覧取得
                local speakers_count=$(curl -s http://localhost:50021/speakers 2>/dev/null | jq length 2>/dev/null || echo "N/A")
                if [ "$speakers_count" != "N/A" ] && [ "$speakers_count" -gt 0 ]; then
                    success "利用可能スピーカー数: $speakers_count"
                else
                    warn "スピーカー情報の取得に失敗しました"
                fi
                
                # 音声合成テスト
                log "VOICEVOX 音声合成テスト実行中..."
                local test_query=$(curl -s -X POST "http://localhost:50021/audio_query?text=テスト&speaker=1" 2>/dev/null)
                if echo "$test_query" | grep -q "accent_phrases"; then
                    success "VOICEVOX 音声合成テスト成功"
                else
                    warn "VOICEVOX 音声合成テストに失敗しました"
                fi
            else
                error "VOICEVOX API 応答なし (http://localhost:50021)"
            fi
        else
            error "VOICEVOX サービス停止中"
        fi
    else
        error "VOICEVOX がインストールされていません (/opt/voicevox)"
    fi
    
    echo ""
}

# OBS Studioチェック
check_obs_studio() {
    echo -e "${BLUE}${BOLD}=== OBS Studio 確認 ===${NC}"
    
    if command -v obs &> /dev/null; then
        success "OBS Studio インストール済み"
        
        # 設定ディレクトリ確認
        local obs_config_dir="$HOME/.config/obs-studio"
        if [ -d "$obs_config_dir" ]; then
            success "OBS 設定ディレクトリ存在"
            
            # プロファイル確認
            if [ -d "$obs_config_dir/basic/profiles/Radio" ]; then
                success "ラジオ配信プロファイル存在"
            else
                warn "ラジオ配信プロファイルが見つかりません"
            fi
            
            # シーンコレクション確認
            if [ -f "$obs_config_dir/basic/scenes/Radio.json" ]; then
                success "ラジオ配信シーン存在"
            else
                warn "ラジオ配信シーンが見つかりません"
            fi
        else
            warn "OBS 設定ディレクトリが初期化されていません"
        fi
        
        # 仮想ディスプレイ確認
        if command -v Xvfb &> /dev/null; then
            success "仮想ディスプレイ (Xvfb) 利用可能"
            
            # 実行中プロセス確認
            if pgrep -f "Xvfb :1" > /dev/null; then
                success "仮想ディスプレイ実行中"
            else
                warn "仮想ディスプレイが起動していません"
            fi
        else
            error "仮想ディスプレイ (Xvfb) がインストールされていません"
        fi
    else
        error "OBS Studio がインストールされていません"
    fi
    
    echo ""
}

# 音声システムチェック
check_audio_system() {
    echo -e "${BLUE}${BOLD}=== 音声システム確認 ===${NC}"
    
    # PulseAudio確認
    if command -v pactl &> /dev/null; then
        success "PulseAudio コマンド利用可能"
        
        if pulseaudio --check; then
            success "PulseAudio サーバー動作中"
            
            # 音声デバイス一覧
            local input_devices=$(pactl list short sources | wc -l)
            local output_devices=$(pactl list short sinks | wc -l)
            info "音声入力デバイス数: $input_devices"
            info "音声出力デバイス数: $output_devices"
        else
            warn "PulseAudio サーバーが動作していません"
        fi
    else
        error "PulseAudio がインストールされていません"
    fi
    
    # ALSA確認
    if command -v aplay &> /dev/null; then
        success "ALSA コマンド利用可能"
    else
        warn "ALSA ツールがインストールされていません"
    fi
    
    # FFmpeg音声処理確認
    if command -v ffplay &> /dev/null; then
        success "FFplay (音声再生) 利用可能"
    else
        error "FFplay がインストールされていません"
    fi
    
    echo ""
}

# ネットワーク接続チェック
check_network_connectivity() {
    echo -e "${BLUE}${BOLD}=== ネットワーク接続確認 ===${NC}"
    
    # インターネット接続
    if ping -c 1 8.8.8.8 &>/dev/null; then
        success "インターネット接続正常"
    else
        error "インターネット接続に問題があります"
    fi
    
    # DNS解決
    if nslookup google.com &>/dev/null; then
        success "DNS解決正常"
    else
        error "DNS解決に問題があります"
    fi
    
    # YouTube API接続テスト
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE" 2>/dev/null || true
        if [ "$YOUTUBE_API_KEY" != "YOUR_YOUTUBE_DATA_API_KEY" ] && [ -n "$YOUTUBE_API_KEY" ]; then
            log "YouTube API 接続テスト中..."
            local api_test=$(curl -s "https://www.googleapis.com/youtube/v3/search?part=snippet&maxResults=1&q=test&key=$YOUTUBE_API_KEY")
            if echo "$api_test" | grep -q '"items"'; then
                success "YouTube API 接続正常"
            else
                error "YouTube API 接続に問題があります"
                info "レスポンス: $(echo "$api_test" | head -1)"
            fi
        else
            warn "YouTube API キーが未設定のため接続テストをスキップ"
        fi
    fi
    
    echo ""
}

# プロセス・サービスチェック
check_processes_and_services() {
    echo -e "${BLUE}${BOLD}=== プロセス・サービス確認 ===${NC}"
    
    # Systemdサービス確認
    local services=("ollama" "voicevox" "radio-streaming")
    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            if systemctl is-active --quiet "$service"; then
                if systemctl is-enabled --quiet "$service"; then
                    success "サービス '$service': 有効 & 動作中"
                else
                    warn "サービス '$service': 動作中だが自動起動無効"
                fi
            else
                if systemctl is-enabled --quiet "$service"; then
                    warn "サービス '$service': 有効だが停止中"
                else
                    error "サービス '$service': 無効 & 停止中"
                fi
            fi
        else
            warn "サービス '$service': 未定義"
        fi
    done
    
    # プロセス確認
    local processes=(
        "radio_streaming_bot.py:メインアプリケーション"
        "obs:OBS Studio"
        "Xvfb :1:仮想ディスプレイ"
        "ollama serve:Ollama サーバー"
        "voicevox_engine:VOICEVOX エンジン"
    )
    
    for process_info in "${processes[@]}"; do
        local process_name=$(echo "$process_info" | cut -d: -f1)
        local process_desc=$(echo "$process_info" | cut -d: -f2)
        
        if pgrep -f "$process_name" > /dev/null; then
            local pid=$(pgrep -f "$process_name" | head -1)
            local cpu_usage=$(ps -p "$pid" -o %cpu --no-headers 2>/dev/null | xargs || echo "N/A")
            local mem_usage=$(ps -p "$pid" -o %mem --no-headers 2>/dev/null | xargs || echo "N/A")
            success "$process_desc 実行中 (PID: $pid, CPU: ${cpu_usage}%, MEM: ${mem_usage}%)"
        else
            error "$process_desc が実行されていません"
        fi
    done
    
    echo ""
}

# リソース使用量チェック
check_resource_usage() {
    echo -e "${BLUE}${BOLD}=== リソース使用量確認 ===${NC}"
    
    # メモリ使用量
    local mem_total=$(free -m | awk 'NR==2{print $2}')
    local mem_used=$(free -m | awk 'NR==2{print $3}')
    local mem_percentage=$(( mem_used * 100 / mem_total ))
    
    if [ $mem_percentage -lt 70 ]; then
        success "メモリ使用量: ${mem_used}MB/${mem_total}MB (${mem_percentage}%)"
    elif [ $mem_percentage -lt 85 ]; then
        warn "メモリ使用量: ${mem_used}MB/${mem_total}MB (${mem_percentage}%) - 高負荷"
    else
        error "メモリ使用量: ${mem_used}MB/${mem_total}MB (${mem_percentage}%) - 危険レベル"
    fi
    
    # CPU使用量
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
    if (( $(echo "$cpu_usage < 70" | bc -l) )); then
        success "CPU使用量: ${cpu_usage}%"
    elif (( $(echo "$cpu_usage < 85" | bc -l) )); then
        warn "CPU使用量: ${cpu_usage}% - 高負荷"
    else
        error "CPU使用量: ${cpu_usage}% - 危険レベル"
    fi
    
    # ディスク使用量
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ $disk_usage -lt 70 ]; then
        success "ディスク使用量: ${disk_usage}%"
    elif [ $disk_usage -lt 85 ]; then
        warn "ディスク使用量: ${disk_usage}% - 高使用量"
    else
        error "ディスク使用量: ${disk_usage}% - 容量不足"
    fi
    
    # 負荷平均
    local load_1min=$(uptime | awk -F'load average:' '{print $2}' | awk -F, '{print $1}' | xargs)
    local cpu_cores=$(nproc)
    local load_percentage=$(echo "scale=1; $load_1min * 100 / $cpu_cores" | bc)
    
    if (( $(echo "$load_percentage < 70" | bc -l) )); then
        success "システム負荷: ${load_1min} (${load_percentage}%)"
    elif (( $(echo "$load_percentage < 100" | bc -l) )); then
        warn "システム負荷: ${load_1min} (${load_percentage}%) - 高負荷"
    else
        error "システム負荷: ${load_1min} (${load_percentage}%) - 過負荷"
    fi
    
    echo ""
}

# ログファイルチェック
check_log_files() {
    echo -e "${BLUE}${BOLD}=== ログファイル確認 ===${NC}"
    
    local log_dir="$SCRIPT_DIR/logs"
    if [ -d "$log_dir" ]; then
        success "ログディレクトリ存在: $log_dir"
        
        # ログファイル一覧
        local log_files=(
            "main_app.log:メインアプリケーション"
            "obs.log:OBS Studio"
            "startup.log:システム起動"
            "service.log:Systemdサービス"
        )
        
        for log_info in "${log_files[@]}"; do
            local log_file=$(echo "$log_info" | cut -d: -f1)
            local log_desc=$(echo "$log_info" | cut -d: -f2)
            local log_path="$log_dir/$log_file"
            
            if [ -f "$log_path" ]; then
                local file_size=$(du -h "$log_path" | cut -f1)
                local last_modified=$(stat -c %y "$log_path" | cut -d. -f1)
                success "$log_desc ログ: $file_size (最終更新: $last_modified)"
                
                # エラー数カウント
                local error_count=$(grep -c "ERROR\|CRITICAL\|FATAL" "$log_path" 2>/dev/null || echo "0")
                if [ $error_count -gt 0 ]; then
                    warn "$log_desc ログに $error_count 件のエラーがあります"
                fi
            else
                warn "$log_desc ログファイルが見つかりません: $log_path"
            fi
        done
    else
        error "ログディレクトリが存在しません: $log_dir"
    fi
    
    echo ""
}

# セキュリティチェック
check_security() {
    echo -e "${BLUE}${BOLD}=== セキュリティ確認 ===${NC}"
    
    # ファイアウォール確認
    if command -v ufw &> /dev/null; then
        local ufw_status=$(ufw status | head -1)
        if echo "$ufw_status" | grep -q "Status: active"; then
            success "ファイアウォール (UFW) 有効"
        else
            warn "ファイアウォール (UFW) 無効"
        fi
    else
        warn "UFW ファイアウォールがインストールされていません"
    fi
    
    # 重要ファイルの権限確認
    local sensitive_files=("$CONFIG_FILE")
    for file in "${sensitive_files[@]}"; do
        if [ -f "$file" ]; then
            local permissions=$(stat -c %a "$file")
            if [ "$permissions" = "600" ] || [ "$permissions" = "644" ]; then
                success "ファイル権限適切: $file ($permissions)"
            else
                warn "ファイル権限要確認: $file ($permissions)"
            fi
        fi
    done
    
    # プロセス実行ユーザー確認
    if [ "$(whoami)" = "root" ]; then
        error "rootユーザーでの実行は推奨されません"
    else
        success "非rootユーザーで実行中: $(whoami)"
    fi
    
    echo ""
}

# パフォーマンステスト
run_performance_test() {
    echo -e "${BLUE}${BOLD}=== パフォーマンステスト ===${NC}"
    
    # Ollama応答時間テスト
    if curl -s http://localhost:11434/api/version &>/dev/null; then
        log "Ollama 応答時間テスト実行中..."
        local start_time=$(date +%s.%N)
        ollama run gemma:1b "Hello" >/dev/null 2>&1 || true
        local end_time=$(date +%s.%N)
        local response_time=$(echo "scale=2; $end_time - $start_time" | bc)
        
        if (( $(echo "$response_time < 5.0" | bc -l) )); then
            success "Ollama 応答時間: ${response_time}秒 (良好)"
        elif (( $(echo "$response_time < 10.0" | bc -l) )); then
            warn "Ollama 応答時間: ${response_time}秒 (やや遅い)"
        else
            error "Ollama 応答時間: ${response_time}秒 (遅い)"
        fi
    fi
    
    # VOICEVOX応答時間テスト
    if curl -s http://localhost:50021/version &>/dev/null; then
        log "VOICEVOX 応答時間テスト実行中..."
        local start_time=$(date +%s.%N)
        curl -s -X POST "http://localhost:50021/audio_query?text=テスト&speaker=1" >/dev/null
        local end_time=$(date +%s.%N)
        local response_time=$(echo "scale=2; $end_time - $start_time" | bc)
        
        if (( $(echo "$response_time < 2.0" | bc -l) )); then
            success "VOICEVOX 応答時間: ${response_time}秒 (良好)"
        elif (( $(echo "$response_time < 5.0" | bc -l) )); then
            warn "VOICEVOX 応答時間: ${response_time}秒 (やや遅い)"
        else
            error "VOICEVOX 応答時間: ${response_time}秒 (遅い)"
        fi
    fi
    
    echo ""
}

# 統合レポート生成
generate_health_report() {
    echo -e "${BLUE}${BOLD}=== 総合診断結果 ===${NC}"
    
    # 統計情報
    local success_rate=$(( PASSED_CHECKS * 100 / TOTAL_CHECKS ))
    echo -e "${CYAN}診断項目数: $TOTAL_CHECKS${NC}"
    echo -e "${GREEN}正常: $PASSED_CHECKS${NC}"
    echo -e "${YELLOW}警告: $WARNING_CHECKS${NC}"
    echo -e "${RED}エラー: $FAILED_CHECKS${NC}"
    echo -e "${CYAN}成功率: ${success_rate}%${NC}"
    echo ""
    
    # 総合判定
    if [ $FAILED_CHECKS -eq 0 ] && [ $WARNING_CHECKS -eq 0 ]; then
        echo -e "${GREEN}${BOLD}🎉 システム状態: 非常に良好${NC}"
        local status="EXCELLENT"
    elif [ $FAILED_CHECKS -eq 0 ] && [ $WARNING_CHECKS -le 3 ]; then
        echo -e "${YELLOW}${BOLD}✓ システム状態: 良好（軽微な警告あり）${NC}"
        local status="GOOD"
    elif [ $FAILED_CHECKS -le 2 ]; then
        echo -e "${YELLOW}${BOLD}⚠ システム状態: 注意（修正推奨）${NC}"
        local status="WARNING"
    else
        echo -e "${RED}${BOLD}❌ システム状態: 問題あり（要対応）${NC}"
        local status="CRITICAL"
    fi
    
    # 問題点一覧
    if [ ${#ISSUES[@]} -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}${BOLD}=== 検出された問題 ===${NC}"
        for issue in "${ISSUES[@]}"; do
            echo "  • $issue"
        done
    fi
    
    # 推奨アクション
    echo ""
    echo -e "${BLUE}${BOLD}=== 推奨アクション ===${NC}"
    if [ $FAILED_CHECKS -gt 0 ]; then
        echo "  • エラー項目の修正を実施してください"
        echo "  • ログファイルで詳細を確認: $LOG_FILE"
    fi
    if [ $WARNING_CHECKS -gt 0 ]; then
        echo "  • 警告項目の改善を検討してください"
    fi
    echo "  • 定期的な診断実行を推奨します"
    echo "  • システム監視の継続を行ってください"
    
    # JSONレポート生成
    generate_json_report "$status"
    
    echo ""
    echo -e "${CYAN}詳細レポート: $REPORT_FILE${NC}"
}

# JSONレポート生成
generate_json_report() {
    local status="$1"
    
    cat > "$REPORT_FILE" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "status": "$status",
  "summary": {
    "total_checks": $TOTAL_CHECKS,
    "passed": $PASSED_CHECKS,
    "warnings": $WARNING_CHECKS,
    "errors": $FAILED_CHECKS,
    "success_rate": $(( PASSED_CHECKS * 100 / TOTAL_CHECKS ))
  },
  "system_info": {
    "os": "$(lsb_release -d | cut -f2)",
    "kernel": "$(uname -r)",
    "cpu_cores": $(nproc),
    "memory_total": "$(free -m | awk 'NR==2{print $2}')MB",
    "uptime": "$(uptime -p)"
  },
  "resource_usage": {
    "memory_percentage": $(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}'),
    "cpu_usage": $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}'),
    "disk_usage": $(df / | tail -1 | awk '{print $5}' | sed 's/%//')
  },
  "issues": [
$(printf '    "%s"' "${ISSUES[@]}" | paste -sd, -)
  ]
}
EOF
}

# メイン診断実行
run_full_diagnosis() {
    show_header
    
    # ログディレクトリ作成
    mkdir -p "$(dirname "$LOG_FILE")"
    > "$LOG_FILE"  # ログファイル初期化
    
    # 各種チェック実行
    check_system_info
    check_configuration
    check_python_environment
    check_ollama_service
    check_voicevox_service
    check_obs_studio
    check_audio_system
    check_network_connectivity
    check_processes_and_services
    check_resource_usage
    check_log_files
    check_security
    run_performance_test
    
    # 統合レポート
    generate_health_report
}

# 使用方法表示
show_usage() {
    echo -e "${BLUE}システム診断スクリプト 使用方法${NC}"
    echo ""
    echo "使用方法: $0 [コマンド]"
    echo ""
    echo -e "${GREEN}コマンド:${NC}"
    echo "  full       - 完全診断実行（デフォルト）"
    echo "  quick      - 基本項目のみ診断"
    echo "  ollama     - Ollama のみ診断"
    echo "  voicevox   - VOICEVOX のみ診断"
    echo "  obs        - OBS Studio のみ診断"
    echo "  network    - ネットワークのみ診断"
    echo "  resources  - リソース使用量のみ診断"
    echo "  services   - デーモン・サービスのみ診断"
    echo "  logs       - ログファイルのみ確認"
    echo "  perf       - パフォーマンステストのみ実行"
    echo "  report     - 最新レポート表示"
    echo "  help       - このヘルプを表示"
    echo ""
    echo -e "${CYAN}出力ファイル:${NC}"
    echo "  ログ: $LOG_FILE"
    echo "  レポート: logs/health_report_YYYYMMDD_HHMMSS.json"
}

# メイン処理
main() {
    case "${1:-full}" in
        full)
            run_full_diagnosis
            ;;
        quick)
            show_header
            check_system_info
            check_configuration
            check_ollama_service
            check_voicevox_service
            check_processes_and_services
            generate_health_report
            ;;
        ollama)
            show_header
            check_ollama_service
            ;;
        voicevox)
            show_header
            check_voicevox_service
            ;;
        obs)
            show_header
            check_obs_studio
            ;;
        network)
            show_header
            check_network_connectivity
            ;;
        resources)
            show_header
            check_resource_usage
            ;;
        services)
            show_header
            check_processes_and_services
            ;;
        logs)  
            show_header
            check_log_files
            ;;
        perf)
            show_header
            run_performance_test
            ;;
        report)
            if [ -f "$REPORT_FILE" ]; then
                cat "$REPORT_FILE" | jq .
            else
                error "レポートファイルが見つかりません"
            fi
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

# 実行
main "$@"
