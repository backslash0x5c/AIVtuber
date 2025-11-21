"""設定管理モジュール"""
import os
from dotenv import load_dotenv

# .envファイルを読み込み
load_dotenv()

class Config:
    """アプリケーション設定"""

    # YouTube設定
    YOUTUBE_VIDEO_ID = os.getenv('YOUTUBE_VIDEO_ID', '')
    YOUTUBE_STREAM_KEY = os.getenv('YOUTUBE_STREAM_KEY', '')
    YOUTUBE_STREAM_URL = os.getenv('YOUTUBE_STREAM_URL', 'rtmp://a.rtmp.youtube.com/live2/')

    # Ollama設定
    OLLAMA_URL = os.getenv('OLLAMA_URL', 'http://localhost:11434')
    OLLAMA_MODEL = os.getenv('OLLAMA_MODEL', 'gemma2:2b')

    # VOICEVOX設定
    VOICEVOX_URL = os.getenv('VOICEVOX_URL', 'http://localhost:50021')
    VOICEVOX_SPEAKER_ID = int(os.getenv('VOICEVOX_SPEAKER_ID', '1'))

    # 動作設定
    IDLE_CHAT_INTERVAL = int(os.getenv('IDLE_CHAT_INTERVAL', '30'))
    MAX_CONVERSATION_HISTORY = int(os.getenv('MAX_CONVERSATION_HISTORY', '10'))
    COMMENT_CHECK_INTERVAL = int(os.getenv('COMMENT_CHECK_INTERVAL', '5'))

    @classmethod
    def validate(cls):
        """設定の検証"""
        errors = []

        if not cls.YOUTUBE_VIDEO_ID:
            errors.append("YOUTUBE_VIDEO_ID が設定されていません")

        if not cls.YOUTUBE_STREAM_KEY:
            errors.append("YOUTUBE_STREAM_KEY が設定されていません")

        if errors:
            raise ValueError("設定エラー:\n" + "\n".join(errors))

        return True
