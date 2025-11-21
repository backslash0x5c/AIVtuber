"""音声ストリーミング配信モジュール"""
import subprocess
import os
import tempfile
from typing import Optional
from .config import Config


class AudioStreamer:
    """FFmpegを使用してYouTubeに音声をストリーミング配信するクラス"""

    def __init__(self):
        self.stream_url = Config.YOUTUBE_STREAM_URL + Config.YOUTUBE_STREAM_KEY
        self.ffmpeg_process: Optional[subprocess.Popen] = None
        self.temp_dir = tempfile.mkdtemp()

    def start_stream(self):
        """
        YouTubeへのストリーミングを開始

        無音のストリームを開始し、後から音声を追加できるようにする
        """
        try:
            # 無音のオーディオストリームを生成してYouTubeに配信
            ffmpeg_cmd = [
                'ffmpeg',
                '-re',  # リアルタイム配信
                '-f', 'lavfi',
                '-i', 'anullsrc=channel_layout=stereo:sample_rate=44100',  # 無音のオーディオソース
                '-c:a', 'aac',  # AACコーデック
                '-b:a', '128k',  # ビットレート
                '-f', 'flv',  # FLV形式
                self.stream_url
            ]

            self.ffmpeg_process = subprocess.Popen(
                ffmpeg_cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )

            print("YouTubeストリーミング配信を開始しました")
            return True

        except Exception as e:
            print(f"ストリーミング開始エラー: {e}")
            return False

    def play_audio(self, audio_data: bytes):
        """
        音声データを再生してストリーミング配信

        Args:
            audio_data: WAV形式の音声データ
        """
        try:
            # 一時ファイルに音声データを保存
            temp_audio = os.path.join(self.temp_dir, 'temp_audio.wav')
            with open(temp_audio, 'wb') as f:
                f.write(audio_data)

            # FFmpegで音声をYouTubeに配信
            ffmpeg_cmd = [
                'ffmpeg',
                '-re',  # リアルタイム再生
                '-i', temp_audio,  # 入力ファイル
                '-c:a', 'aac',  # AACコーデック
                '-b:a', '128k',  # ビットレート
                '-f', 'flv',  # FLV形式
                self.stream_url
            ]

            process = subprocess.run(
                ffmpeg_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=60
            )

            # 一時ファイルを削除
            if os.path.exists(temp_audio):
                os.remove(temp_audio)

            if process.returncode != 0:
                print(f"音声配信エラー: {process.stderr.decode()}")
                return False

            return True

        except subprocess.TimeoutExpired:
            print("音声配信がタイムアウトしました")
            return False
        except Exception as e:
            print(f"音声再生エラー: {e}")
            return False

    def stop_stream(self):
        """ストリーミングを停止"""
        if self.ffmpeg_process:
            self.ffmpeg_process.terminate()
            self.ffmpeg_process.wait()
            self.ffmpeg_process = None
            print("ストリーミング配信を停止しました")

        # 一時ディレクトリをクリーンアップ
        if os.path.exists(self.temp_dir):
            for file in os.listdir(self.temp_dir):
                os.remove(os.path.join(self.temp_dir, file))
            os.rmdir(self.temp_dir)

    def is_streaming(self) -> bool:
        """
        ストリーミングが実行中かチェック

        Returns:
            実行中の場合True
        """
        if not self.ffmpeg_process:
            return False
        return self.ffmpeg_process.poll() is None
