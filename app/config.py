"""設定管理: .env と環境変数から読み込む"""
import os
from pathlib import Path

from dotenv import load_dotenv

ROOT_DIR = Path(__file__).resolve().parent.parent
load_dotenv(ROOT_DIR / ".env")


def _str(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


def _int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except ValueError:
        return default


def _float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)))
    except ValueError:
        return default


def _bool(name: str, default: bool) -> bool:
    return os.getenv(name, str(default)).strip().lower() in ("1", "true", "yes", "on")


class Config:
    # --- YouTube ---
    YOUTUBE_VIDEO_ID = _str("YOUTUBE_VIDEO_ID")
    YOUTUBE_STREAM_KEY = _str("YOUTUBE_STREAM_KEY")
    YOUTUBE_RTMP_SERVER = _str("YOUTUBE_RTMP_SERVER", "rtmp://a.rtmp.youtube.com/live2")

    # --- Ollama ---
    OLLAMA_URL = _str("OLLAMA_URL", "http://127.0.0.1:11434")
    OLLAMA_MODEL = _str("OLLAMA_MODEL", "gemma3:1b")
    OLLAMA_TIMEOUT = _int("OLLAMA_TIMEOUT", 60)
    MAX_HISTORY = _int("MAX_HISTORY", 10)

    # --- VOICEVOX ---
    VOICEVOX_URL = _str("VOICEVOX_URL", "http://127.0.0.1:50021")
    VOICEVOX_SPEAKER_ID = _int("VOICEVOX_SPEAKER_ID", 1)
    VOICEVOX_SPEED = _float("VOICEVOX_SPEED", 1.0)
    VOICEVOX_TIMEOUT = _int("VOICEVOX_TIMEOUT", 60)

    # --- OBS (obs-websocket) ---
    OBS_ENABLED = _bool("OBS_ENABLED", True)
    OBS_WS_HOST = _str("OBS_WS_HOST", "127.0.0.1")
    OBS_WS_PORT = _int("OBS_WS_PORT", 4455)
    OBS_WS_PASSWORD = _str("OBS_WS_PASSWORD")
    AUTO_START_STREAM = _bool("AUTO_START_STREAM", True)

    # --- 映像設定 ---
    VIDEO_WIDTH = _int("VIDEO_WIDTH", 1280)
    VIDEO_HEIGHT = _int("VIDEO_HEIGHT", 720)
    VIDEO_FPS = _int("VIDEO_FPS", 30)
    VIDEO_BITRATE_KBPS = _int("VIDEO_BITRATE_KBPS", 2500)
    AUDIO_BITRATE_KBPS = _int("AUDIO_BITRATE_KBPS", 128)

    # --- 音声ミキシング (PulseAudio) ---
    MIX_SINK = _str("MIX_SINK", "radio_mix")
    BGM_DUCK_PERCENT = _int("BGM_DUCK_PERCENT", 25)   # 発話中のBGM音量(%)
    BGM_VOLUME_PERCENT = _int("BGM_VOLUME_PERCENT", 100)

    # --- オーバーレイ(アバター)配信サーバ ---
    OVERLAY_HOST = _str("OVERLAY_HOST", "127.0.0.1")
    OVERLAY_PORT = _int("OVERLAY_PORT", 8500)
    # avatar/ からの相対パスで .model3.json を指定するとLive2D描画になる
    # 例: LIVE2D_MODEL=live2d/hiyori/hiyori.model3.json
    LIVE2D_MODEL = _str("LIVE2D_MODEL")

    # --- アバター描画モード ---
    # browser  : オーバーレイ(ブラウザソース)内で描画 (Live2D/パペット/PNG立ち絵)
    # inochi2d : nijiexpose(ネイティブ)をVMCプロトコルで駆動し、
    #            OBSの画面キャプチャで取り込む。オーバーレイはUI(字幕等)のみ描画
    AVATAR_MODE = _str("AVATAR_MODE", "browser")
    # VMC(OSC/UDP)の送信先。nijiexpose側の受信設定と合わせる
    VMC_HOST = _str("VMC_HOST", "127.0.0.1")
    VMC_PORT = _int("VMC_PORT", 39540)
    VMC_FPS = _int("VMC_FPS", 30)

    # --- 挙動 ---
    CHARACTER_NAME = _str("CHARACTER_NAME", "ゆめ")
    IDLE_CHAT_INTERVAL = _int("IDLE_CHAT_INTERVAL", 180)  # 秒: コメントが無い時に雑談するまでの時間
    MAX_QUEUE = _int("MAX_QUEUE", 10)                     # 通常コメントの最大待ち行列
    OPENING_MESSAGE = _str(
        "OPENING_MESSAGE",
        "こんにちは、AIラジオ配信始まりました。コメント読み上げていくので、気軽に書き込んでくださいね。",
    )

    @classmethod
    def validate(cls) -> list[str]:
        """致命的な設定不足を返す(空なら問題なし)"""
        errors = []
        if not cls.YOUTUBE_VIDEO_ID:
            errors.append("YOUTUBE_VIDEO_ID が未設定です(コメント取得に必要)")
        if cls.OBS_ENABLED and cls.AUTO_START_STREAM and not cls.YOUTUBE_STREAM_KEY:
            errors.append("YOUTUBE_STREAM_KEY が未設定です(配信開始に必要)")
        if cls.OBS_ENABLED and not cls.OBS_WS_PASSWORD:
            errors.append("OBS_WS_PASSWORD が未設定です(obs-websocket接続に必要)")
        return errors
