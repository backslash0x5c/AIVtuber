"""VOICEVOX クライアント: テキストからWAV音声を生成"""
import logging

import requests

from .config import Config

logger = logging.getLogger(__name__)


class VoicevoxClient:
    def __init__(self, cfg: type[Config] = Config):
        self.cfg = cfg

    def is_ready(self) -> bool:
        try:
            r = requests.get(f"{self.cfg.VOICEVOX_URL}/version", timeout=5)
            return r.ok
        except requests.RequestException:
            return False

    def synthesize(self, text: str) -> bytes:
        """テキストをWAVバイト列に変換する"""
        speaker = self.cfg.VOICEVOX_SPEAKER_ID

        r = requests.post(
            f"{self.cfg.VOICEVOX_URL}/audio_query",
            params={"text": text, "speaker": speaker},
            timeout=self.cfg.VOICEVOX_TIMEOUT,
        )
        r.raise_for_status()
        query = r.json()
        query["speedScale"] = self.cfg.VOICEVOX_SPEED

        r = requests.post(
            f"{self.cfg.VOICEVOX_URL}/synthesis",
            params={"speaker": speaker},
            json=query,
            timeout=self.cfg.VOICEVOX_TIMEOUT,
        )
        r.raise_for_status()
        return r.content
