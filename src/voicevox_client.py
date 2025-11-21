"""VOICEVOX API連携モジュール"""
import requests
from .config import Config


class VoicevoxClient:
    """VOICEVOXとの連携を管理するクライアント"""

    def __init__(self):
        self.url = Config.VOICEVOX_URL
        self.speaker_id = Config.VOICEVOX_SPEAKER_ID

    def text_to_speech(self, text: str) -> bytes:
        """
        テキストを音声データに変換

        Args:
            text: 音声化するテキスト

        Returns:
            音声データ (WAV形式のバイト列)
        """
        try:
            # 音声クエリの作成
            query_response = requests.post(
                f"{self.url}/audio_query",
                params={
                    "text": text,
                    "speaker": self.speaker_id
                },
                timeout=10
            )
            query_response.raise_for_status()
            query_data = query_response.json()

            # 音声の合成
            synthesis_response = requests.post(
                f"{self.url}/synthesis",
                params={"speaker": self.speaker_id},
                json=query_data,
                timeout=30
            )
            synthesis_response.raise_for_status()

            return synthesis_response.content

        except requests.exceptions.RequestException as e:
            print(f"VOICEVOX API エラー: {e}")
            raise

    def is_available(self) -> bool:
        """
        VOICEVOXサーバーが利用可能かチェック

        Returns:
            利用可能な場合True
        """
        try:
            response = requests.get(f"{self.url}/version", timeout=5)
            return response.status_code == 200
        except requests.exceptions.RequestException:
            return False

    def get_speakers(self) -> list:
        """
        利用可能な話者リストを取得

        Returns:
            話者情報のリスト
        """
        try:
            response = requests.get(f"{self.url}/speakers", timeout=5)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            print(f"話者リスト取得エラー: {e}")
            return []
