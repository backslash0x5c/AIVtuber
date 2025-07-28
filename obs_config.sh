#!/bin/bash
# OBS Studio 自動配信設定スクリプト（24時間ラジオ配信用）
# ヘッドレス環境での音声配信に最適化

set -e

# 色定義
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# 設定読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# デフォルト設定
STREAM_KEY="${YOUTUBE_STREAM_KEY:-YOUR_YOUTUBE_STREAM_KEY}"
STREAM_URL="${OBS_STREAM_URL:-rtmp://a.rtmp.youtube.com/live2}"
VIDEO_BITRATE="${OBS_VIDEO_BITRATE:-2500}"
AUDIO_BITRATE="${OBS_AUDIO_BITRATE:-128}"
AUDIO_DEVICE="${AUDIO_DEVICE:-default}"

# OBS設定ディレクトリ
OBS_CONFIG_DIR="$HOME/.config/obs-studio"
OBS_BASIC_DIR="$OBS_CONFIG_DIR/basic"
OBS_SCENES_DIR="$OBS_BASIC_DIR/scenes"
OBS_PROFILES_DIR="$OBS_BASIC_DIR/profiles"

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

# OBSディレクトリ作成
create_obs_directories() {
    log "OBS設定ディレクトリ作成中..."
    
    mkdir -p "$OBS_CONFIG_DIR"
    mkdir -p "$OBS_BASIC_DIR"
    mkdir -p "$OBS_SCENES_DIR"
    mkdir -p "$OBS_PROFILES_DIR/Radio"
    mkdir -p "$OBS_CONFIG_DIR/plugin_config"
    mkdir -p "$OBS_CONFIG_DIR/logs"
    
    log "✓ ディレクトリ作成完了"
}

# グローバル設定ファイル作成
create_global_config() {
    log "OBSグローバル設定作成中..."
    
    cat > "$OBS_CONFIG_DIR/global.ini" << EOF
[General]
EnableAutoUpdates=false
OpenStatsOnStartup=false
ShowWhatsNew=false
SnappingEnabled=true
SnapDistance=10.0
ScreenSnapping=true
SourceSnapping=true
CenterSnapping=false
HideProjectorCursor=true
ProjetorAlwaysOnTop=true
SaveProjectors=true
EnableOutputTimer=true
OutputTimerInterval=10.0

[BasicWindow]
cx=1920
cy=1080
posx=0
posy=0

[PropertiesWindow]
cx=720
cy=580

[SceneCollections]
Current=Radio

[Profiles]
Current=Radio

[Hotkeys]
# 基本的なホットキー設定（ヘッドレス環境では主に使用しない）

[Audio]
DisableAudioDucking=true
HotkeyMutePush=false
HotkeysNeverDisableAutostart=true

[Video]
BaseCX=1920
BaseCY=1080
OutputCX=1920
OutputCY=1080
FPSType=0
FPSCommon=30
ColorFormat=NV12
ColorSpace=709
ColorRange=Partial

[Network]
BindIP=Default
EnableNewSocketLoop=false
EnableLowLatencyMode=false

[AdvOut]
TrackIndex=1
MonitoringDeviceID=default
EOF

    log "✓ グローバル設定作成完了"
}

# プロファイル設定作成
create_profile_config() {
    log "OBSプロファイル設定作成中..."
    
    cat > "$OBS_PROFILES_DIR/Radio/basic.ini" << EOF
[General]
Name=Radio

[Video]
BaseCX=1920
BaseCY=1080
OutputCX=1920
OutputCY=1080
FPSType=0
FPSCommon=30
ColorFormat=NV12
ColorSpace=709
ColorRange=Partial
ScaleType=bicubic

[Audio]
SampleRate=44100
ChannelSetup=Stereo
MeterDecayRate=23.53
PeakMeterType=0

[Stream1]
Type=rtmp_common
Service=YouTube - RTMPS
Server=$STREAM_URL
key=$STREAM_KEY
Encoder=obs_x264
EncoderSettings=rate_control=CBR bitrate=$VIDEO_BITRATE keyint_sec=2 preset=veryfast profile=main tune=zerolatency
Audio=1
AudioBitrate=$AUDIO_BITRATE
AudioEncoder=ffmpeg_aac

[Output]
Mode=Advanced

[AdvOut]
TrackIndex=1
Encoder=obs_x264
ApplyServiceSettings=true
UseAdvanced=true
EnforceServiceBitrate=true
Type=Streaming

# ストリーミング設定
StreamEncoder=obs_x264
StreamEncoderSettings=rate_control=CBR bitrate=$VIDEO_BITRATE keyint_sec=2 preset=veryfast profile=main tune=zerolatency x264opts= buffer_size=$VIDEO_BITRATE
StreamAudioEncoder=ffmpeg_aac
StreamAudioBitrate=$AUDIO_BITRATE
StreamAudioSettings=bitrate=$AUDIO_BITRATE

# 録画設定（無効）
RecType=Standard
RecFormat=mp4
RecEncoder=obs_x264
RecRB=false
RecRBTime=20
RecRBSize=512

# 音声トラック設定
Track1Name=Mixed: all sources
Track2Name=
Track3Name=
Track4Name=
Track5Name=
Track6Name=
Track1Bitrate=$AUDIO_BITRATE
Track2Bitrate=160
Track3Bitrate=160
Track4Bitrate=160
Track5Bitrate=160
Track6Bitrate=160

# その他の出力設定
FFOutputToFile=false
FFFormat=mp4
FFFormatMimeType=video/mp4
FFVBitrate=$VIDEO_BITRATE
FFVGOPSize=120
FFUseMaxCRF=false
FFMaxCRF=20
FFCRFMax=20
FFCRFMin=0
FFCQP=20
FFBFrames=2
FFColorRange=0
FFColorSpace=0
EOF

    log "✓ プロファイル設定作成完了"
}

# シーンコレクション作成
create_scene_collection() {
    log "OBSシーンコレクション作成中..."
    
    cat > "$OBS_SCENES_DIR/Radio.json" << EOF
{
    "current_scene": "ラジオ配信",
    "current_program_scene": "ラジオ配信",
    "scene_order": [
        {
            "name": "ラジオ配信"
        },
        {
            "name": "待機画面"
        },
        {
            "name": "エラー画面"
        }
    ],
    "name": "Radio",
    "sources": [
        {
            "balance": 0.5,
            "deinterlace_field_order": 0,
            "deinterlace_mode": 0,
            "enabled": true,
            "flags": 0,
            "hotkeys": {},
            "id": "pulse_input_capture",
            "mixers": 255,
            "monitoring_type": 0,
            "muted": false,
            "name": "システム音声",
            "private_settings": {},
            "push-to-mute": false,
            "push-to-mute-delay": 0,
            "push-to-talk": false,
            "push-to-talk-delay": 0,
            "settings": {
                "device_id": "$AUDIO_DEVICE"
            },
            "sync": 0,
            "volume": 1.0
        },
        {
            "balance": 0.5,
            "deinterlace_field_order": 0,
            "deinterlace_mode": 0,
            "enabled": true,
            "flags": 0,
            "hotkeys": {},
            "id": "color_source_v3",
            "mixers": 0,
            "monitoring_type": 0,
            "muted": false,
            "name": "背景色",
            "private_settings": {},
            "push-to-mute": false,
            "push-to-mute-delay": 0,
            "push-to-talk": false,
            "push-to-talk-delay": 0,
            "settings": {
                "color": 4278190080,
                "width": 1920,
                "height": 1080
            },
            "sync": 0,
            "volume": 1.0
        },
        {
            "balance": 0.5,
            "deinterlace_field_order": 0,
            "deinterlace_mode": 0,
            "enabled": true,
            "flags": 0,
            "hotkeys": {},
            "id": "text_gdiplus_v3",
            "mixers": 0,
            "monitoring_type": 0,
            "muted": false,
            "name": "タイトル",
            "private_settings": {},
            "push-to-mute": false,
            "push-to-mute-delay": 0,
            "push-to-talk": false,
            "push-to-talk-delay": 0,
            "settings": {
                "align": "center",
                "bk_color": 4278190080,
                "bk_opacity": 0,
                "color": 4294967295,
                "font": {
                    "face": "Arial",
                    "flags": 1,
                    "size": 72,
                    "style": ""
                },
                "gradient": true,
                "gradient_color": 4294934528,
                "gradient_dir": 90.0,
                "gradient_opacity": 100,
                "outline": true,
                "outline_color": 4278190080,
                "outline_opacity": 100,
                "outline_size": 4,
                "text": "🎵 24時間 AI ラジオ配信 🎵",
                "valign": "center"
            },
            "sync": 0,
            "volume": 1.0
        },
        {
            "balance": 0.5,
            "deinterlace_field_order": 0,
            "deinterlace_mode": 0,
            "enabled": true,
            "flags": 0,
            "hotkeys": {},
            "id": "text_gdiplus_v3",
            "mixers": 0,
            "monitoring_type": 0,
            "muted": false,
            "name": "サブタイトル",
            "private_settings": {},
            "push-to-mute": false,
            "push-to-mute-delay": 0,
            "push-to-talk": false,
            "push-to-talk-delay": 0,
            "settings": {
                "align": "center",
                "bk_color": 4278190080,
                "bk_opacity": 0,
                "color": 4294967295,
                "font": {
                    "face": "Arial",
                    "flags": 0,
                    "size": 36,
                    "style": ""
                },
                "gradient": false,
                "outline": true,
                "outline_color": 4278190080,
                "outline_opacity": 80,
                "outline_size": 2,
                "text": "コメントお待ちしています！\\n Powered by Ollama + VOICEVOX",
                "valign": "center"
            },
            "sync": 0,
            "volume": 1.0
        },
        {
            "balance": 0.5,
            "deinterlace_field_order": 0,
            "deinterlace_mode": 0,
            "enabled": true,
            "flags": 0,
            "hotkeys": {},
            "id": "image_source",
            "mixers": 0,
            "monitoring_type": 0,
            "muted": false,
            "name": "ロゴ画像",
            "private_settings": {},
            "push-to-mute": false,
            "push-to-mute-delay": 0,
            "push-to-talk": false,
            "push-to-talk-delay": 0,
            "settings": {
                "file": "",
                "linear_alpha": false,
                "unload": false
            },
            "sync": 0,
            "volume": 1.0
        },
        {
            "balance": 0.5,
            "deinterlace_field_order": 0,
            "deinterlace_mode": 0,
            "enabled": true,
            "flags": 0,
            "hotkeys": {},
            "id": "browser_source",
            "mixers": 0,
            "monitoring_type": 0,
            "muted": false,
            "name": "音声可視化",
            "private_settings": {},
            "push-to-mute": false,
            "push-to-mute-delay": 0,
            "push-to-talk": false,
            "push-to-talk-delay": 0,
            "settings": {
                "url": "data:text/html;charset=utf-8,%3C!DOCTYPE%20html%3E%0A%3Chtml%3E%0A%3Chead%3E%0A%20%20%3Cstyle%3E%0A%20%20%20%20body%20%7B%0A%20%20%20%20%20%20margin%3A%200%3B%0A%20%20%20%20%20%20padding%3A%200%3B%0A%20%20%20%20%20%20background%3A%20transparent%3B%0A%20%20%20%20%20%20display%3A%20flex%3B%0A%20%20%20%20%20%20justify-content%3A%20center%3B%0A%20%20%20%20%20%20align-items%3A%20center%3B%0A%20%20%20%20%7D%0A%20%20%20%20.visualizer%20%7B%0A%20%20%20%20%20%20width%3A%20800px%3B%0A%20%20%20%20%20%20height%3A%20100px%3B%0A%20%20%20%20%20%20display%3A%20flex%3B%0A%20%20%20%20%20%20align-items%3A%20flex-end%3B%0A%20%20%20%20%20%20gap%3A%202px%3B%0A%20%20%20%20%7D%0A%20%20%20%20.bar%20%7B%0A%20%20%20%20%20%20width%3A%208px%3B%0A%20%20%20%20%20%20background%3A%20linear-gradient(to%20top%2C%20%23ff6b6b%2C%20%2351cf66%2C%20%234dabf7)%3B%0A%20%20%20%20%20%20border-radius%3A%202px%3B%0A%20%20%20%20%20%20animation%3A%20pulse%201s%20ease-in-out%20infinite%3B%0A%20%20%20%20%7D%0A%20%20%20%20%40keyframes%20pulse%20%7B%0A%20%20%20%20%20%200%25%20%7B%20height%3A%205px%3B%20%7D%0A%20%20%20%20%20%2050%25%20%7B%20height%3A%2050px%3B%20%7D%0A%20%20%20%20%20%20100%25%20%7B%20height%3A%205px%3B%20%7D%0A%20%20%20%20%7D%0A%20%20%3C%2Fstyle%3E%0A%3C%2Fhead%3E%0A%3Cbody%3E%0A%20%20%3Cdiv%20class%3D%22visualizer%22%3E%0A%20%20%20%20%3Cdiv%20class%3D%22bar%22%20style%3D%22animation-delay%3A%200s%3B%22%3E%3C%2Fdiv%3E%0A%20%20%20%20%3Cdiv%20class%3D%22bar%22%20style%3D%22animation-delay%3A%200.1s%3B%22%3E%3C%2Fdiv%3E%0A%20%20%20%20%3Cdiv%20class%3D%22bar%22%20style%3D%22animation-delay%3A%200.2s%3B%22%3E%3C%2Fdiv%3E%0A%20%20%20%20%3Cdiv%20class%3D%22bar%22%20style%3D%22animation-delay%3A%200.3s%3B%22%3E%3C%2Fdiv%3E%0A%20%20%20%20%3Cdiv%20class%3D%22bar%22%20style%3D%22animation-delay%3A%200.4s%3B%22%3E%3C%2Fdiv%3E%0A%20%20%20%20%3Cdiv%20class%3D%22bar%22%20style%3D%22animation-delay%3A%200.5s%3B%22%3E%3C%2Fdiv%3E%0A%20%20%20%20%3Cdiv%20class%3D%22bar%22%20style%3D%22animation-delay%3A%200.6s%3B%22%3E%3C%2Fdiv%3E%0A%20%20%20%20%3Cdiv%20class%3D%22bar%22%20style%3D%22animation-delay%3A%200.7s%3B%22%3E%3C%2Fdiv%3E%0A%20%20%3C%2Fdiv%3E%0A%3C%2Fbody%3E%0A%3C%2Fhtml%3E",
                "width": 800,
                "height": 100,
                "fps": 30,
                "reroute_audio": false,
                "restart_when_active": false,
                "shutdown": false
            },
            "sync": 0,
            "volume": 1.0
        }
    ],
    "groups": [],
    "transitions": [
        {
            "id": "cut_transition",
            "name": "カット"
        },
        {
            "id": "fade_transition",
            "name": "フェード",
            "settings": {
                "duration": 300
            }
        }
    ],
    "current_transition": "フェード",
    "scene_collection_uuid": "$(uuidgen)",
    "audio_devices": [
        {
            "name": "デスクトップ音声",
            "source_id": "pulse_output_capture",
            "enabled": true
        },
        {
            "name": "マイク音声",
            "source_id": "pulse_input_capture",
            "enabled": true
        }
    ],
    "scenes": [
        {
            "name": "ラジオ配信",
            "uuid": "$(uuidgen)",
            "id": 1,
            "sources": [
                {
                    "name": "背景色",
                    "source_uuid": "$(uuidgen)",
                    "visible": true,
                    "locked": false,
                    "pos": {
                        "x": 0.0,
                        "y": 0.0
                    },
                    "rot": 0.0,
                    "scale": {
                        "x": 1.0,
                        "y": 1.0
                    },
                    "alignment": 5,
                    "bounds_type": 0,
                    "bounds_alignment": 0,
                    "bounds": {
                        "x": 0.0,
                        "y": 0.0
                    },
                    "crop_left": 0,
                    "crop_top": 0,
                    "crop_right": 0,
                    "crop_bottom": 0
                },
                {
                    "name": "タイトル",
                    "source_uuid": "$(uuidgen)",
                    "visible": true,
                    "locked": false,
                    "pos": {
                        "x": 960.0,
                        "y": 300.0
                    },
                    "rot": 0.0,
                    "scale": {
                        "x": 1.0,
                        "y": 1.0
                    },
                    "alignment": 5,
                    "bounds_type": 0,
                    "bounds_alignment": 0,
                    "bounds": {
                        "x": 0.0,
                        "y": 0.0
                    },
                    "crop_left": 0,
                    "crop_top": 0,
                    "crop_right": 0,
                    "crop_bottom": 0
                },
                {
                    "name": "サブタイトル",
                    "source_uuid": "$(uuidgen)",
                    "visible": true,
                    "locked": false,
                    "pos": {
                        "x": 960.0,
                        "y": 600.0
                    },
                    "rot": 0.0,
                    "scale": {
                        "x": 1.0,
                        "y": 1.0
                    },
                    "alignment": 5,
                    "bounds_type": 0,
                    "bounds_alignment": 0,
                    "bounds": {
                        "x": 0.0,
                        "y": 0.0
                    },
                    "crop_left": 0,
                    "crop_top": 0,
                    "crop_right": 0,
                    "crop_bottom": 0
                },
                {
                    "name": "音声可視化",
                    "source_uuid": "$(uuidgen)",
                    "visible": true,
                    "locked": false,
                    "pos": {
                        "x": 560.0,
                        "y": 800.0
                    },
                    "rot": 0.0,
                    "scale": {
                        "x": 1.0,
                        "y": 1.0
                    },
                    "alignment": 5,
                    "bounds_type": 0,
                    "bounds_alignment": 0,
                    "bounds": {
                        "x": 0.0,
                        "y": 0.0
                    },
                    "crop_left": 0,
                    "crop_top": 0,
                    "crop_right": 0,
                    "crop_bottom": 0
                }
            ]
        },
        {
            "name": "待機画面",
            "uuid": "$(uuidgen)",
            "id": 2,
            "sources": [
                {
                    "name": "背景色",
                    "source_uuid": "$(uuidgen)",
                    "visible": true,
                    "locked": false,
                    "pos": {
                        "x": 0.0,
                        "y": 0.0
                    },
                    "rot": 0.0,
                    "scale": {
                        "x": 1.0,
                        "y": 1.0
                    },
                    "alignment": 5,
                    "bounds_type": 0,
                    "bounds_alignment": 0,
                    "bounds": {
                        "x": 0.0,
                        "y": 0.0
                    },
                    "crop_left": 0,
                    "crop_top": 0,
                    "crop_right": 0,
                    "crop_bottom": 0
                }
            ]
        }
    ]
}
EOF

    log "✓ シーンコレクション作成完了"
}

# 音声設定スクリプト作成
create_audio_setup() {
    log "音声設定スクリプト作成中..."
    
    cat > "$SCRIPT_DIR/setup_audio.sh" << 'EOF'
#!/bin/bash
# 音声システム設定スクリプト

# PulseAudio設定
setup_pulseaudio() {
    # PulseAudioが動作していない場合は起動
    if ! pulseaudio --check; then
        pulseaudio --start --log-target=syslog 2>/dev/null || true
        sleep 2
    fi
    
    # 既存のループバック削除
    pactl unload-module module-loopback 2>/dev/null || true
    
    # 仮想音声デバイス作成（必要に応じて）
    pactl load-module module-null-sink sink_name=virtual_output sink_properties=device.description="Virtual_Output" 2>/dev/null || true
    
    # ループバック設定（システム音声をマイク入力にルーティング）
    pactl load-module module-loopback source=virtual_output.monitor sink=alsa_input.pci-0000_00_1f.3.analog-stereo 2>/dev/null || true
    
    echo "音声システム設定完了"
}

# ALSA設定
setup_alsa() {
    # ALSA設定ファイルが存在しない場合は作成
    if [ ! -f "$HOME/.asoundrc" ]; then
        cat > "$HOME/.asoundrc" << 'ALSA_EOF'
pcm.!default {
    type pulse
}
ctl.!default {
    type pulse
}
ALSA_EOF
    fi
}

setup_pulseaudio
setup_alsa
EOF

    chmod +x "$SCRIPT_DIR/setup_audio.sh"
    
    log "✓ 音声設定スクリプト作成完了"
}

# OBS起動スクリプト作成
create_obs_launcher() {
    log "OBS起動スクリプト作成中..."
    
    cat > "$SCRIPT_DIR/start_obs.sh" << EOF
#!/bin/bash
# OBS Studio 起動スクリプト

export DISPLAY=:1

# 音声設定実行
if [ -f "$SCRIPT_DIR/setup_audio.sh" ]; then
    bash "$SCRIPT_DIR/setup_audio.sh"
fi

# OBS Studio起動パラメータ
OBS_ARGS=(
    --startstreaming
    --minimize-to-tray
    --collection "Radio"
    --profile "Radio"
    --scene "ラジオ配信"
    --disable-updater
    --disable-missing-files-check
)

# ログディレクトリ作成
mkdir -p "$SCRIPT_DIR/logs"

echo "OBS Studio 起動中..."
echo "設定プロファイル: Radio"
echo "シーンコレクション: Radio"
echo "配信URL: $STREAM_URL"

# OBS Studio実行
obs "\${OBS_ARGS[@]}" 2>&1 | tee "$SCRIPT_DIR/logs/obs_startup.log" &

OBS_PID=\$!
echo "OBS Studio 起動完了 (PID: \$OBS_PID)"

# プロセス監視（オプション）
if [ "\${1:-}" = "--monitor" ]; then
    while kill -0 \$OBS_PID 2>/dev/null; do
        sleep 30
        if ! pgrep -f obs > /dev/null; then
            echo "OBS プロセスが終了しました"
            break
        fi
    done
fi
EOF

    chmod +x "$SCRIPT_DIR/start_obs.sh"
    
    log "✓ OBS起動スクリプト作成完了"
}

# 設定検証
validate_configuration() {
    log "OBS設定検証中..."
    
    local errors=()
    
    # ストリームキー確認
    if [ "$STREAM_KEY" = "YOUR_YOUTUBE_STREAM_KEY" ]; then
        errors+=("YouTube ストリームキーが設定されていません")
    fi
    
    # ディレクトリ確認
    if [ ! -d "$OBS_CONFIG_DIR" ]; then
        errors+=("OBS設定ディレクトリが作成されていません")
    fi
    
    # 設定ファイル確認
    if [ ! -f "$OBS_PROFILES_DIR/Radio/basic.ini" ]; then
        errors+=("OBSプロファイル設定ファイルが見つかりません")
    fi
    
    if [ ! -f "$OBS_SCENES_DIR/Radio.json" ]; then
        errors+=("OBSシーンコレクションファイルが見つかりません")
    fi
    
    # エラーがある場合は表示
    if [ ${#errors[@]} -gt 0 ]; then
        warn "設定に問題があります:"
        for error in "${errors[@]}"; do
            echo "  - $error"
        done
        return 1
    fi
    
    log "✓ 設定検証完了"
    return 0
}

# 使用方法表示
show_usage() {
    echo -e "${BLUE}OBS Studio 設定スクリプト${NC}"
    echo ""
    echo "使用方法: $0 [オプション]"
    echo ""
    echo "オプション:"
    echo "  --setup     設定ファイル作成（デフォルト）"
    echo "  --validate  設定検証のみ実行"
    echo "  --clean     設定ファイル削除"
    echo "  --help      このヘルプを表示"
    echo ""
    echo "設定後の手順:"
    echo "  1. config.env でYouTubeストリームキーを設定"
    echo "  2. ./start_obs.sh でOBS起動"
    echo "  3. 配信開始の確認"
}

# 設定クリーンアップ
clean_configuration() {
    warn "OBS設定をクリーンアップします..."
    
    read -p "本当に削除しますか？ (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$OBS_CONFIG_DIR"
        rm -f "$SCRIPT_DIR/setup_audio.sh"
        rm -f "$SCRIPT_DIR/start_obs.sh"
        log "✓ クリーンアップ完了"
    else
        log "クリーンアップをキャンセルしました"
    fi
}

# メイン実行
main() {
    case "${1:-setup}" in
        --setup|setup)
            log "OBS Studio 設定開始"
            create_obs_directories
            create_global_config
            create_profile_config
            create_scene_collection
            create_audio_setup
            create_obs_launcher
            
            if validate_configuration; then
                log "✓ OBS Studio 設定完了"
                echo ""
                echo -e "${GREEN}次の手順:${NC}"
                echo "1. config.env でYouTubeストリームキーを設定"
                echo "2. ./start_obs.sh でOBS起動テスト"
                echo "3. ./startup.sh start でシステム全体起動"
            else
                error "設定に問題があります"
            fi
            ;;
        --validate|validate)
            validate_configuration
            ;;
        --clean|clean)
            clean_configuration
            ;;
        --help|help)
            show_usage
            ;;
        *)
            error "不明なオプション: $1"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
