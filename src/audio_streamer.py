"""音声ストリーミング配信モジュール"""
import subprocess
import os
import tempfile
from typing import Optional
from .config import Config


class AudioStreamer:
    """FFmpegを使用してYouTubeに静止画+音声をストリーミング配信するクラス"""

    def __init__(self):
        self.stream_url = Config.YOUTUBE_STREAM_URL + Config.YOUTUBE_STREAM_KEY
        self.ffmpeg_process: Optional[subprocess.Popen] = None
        self.temp_dir = tempfile.mkdtemp()
        self.image_path = "image.png"  # 配信用静止画

    def start_stream(self):
        """
        YouTubeへのストリーミングを開始

        静止画と無音のストリームを開始
        """
        try:
            # 静止画が存在するか確認
            if not os.path.exists(self.image_path):
                print(f"警告: {self.image_path} が見つかりません")
                print("静止画なしで音声のみ配信します")
                return self._start_audio_only_stream()

            # 静止画 + 無音のストリームを生成してYouTubeに配信
            ffmpeg_cmd = [
                'ffmpeg',
                '-loop', '1',  # 静止画をループ
                '-i', self.image_path,  # 静止画入力
                '-f', 'lavfi',
                '-i', 'anullsrc=channel_layout=stereo:sample_rate=44100',  # 無音のオーディオソース
                '-c:v', 'libx264',  # H.264ビデオコーデック
                '-preset', 'veryfast',  # エンコード速度優先
                '-b:v', '2500k',  # ビデオビットレート
                '-maxrate', '2500k',
                '-bufsize', '5000k',
                '-pix_fmt', 'yuv420p',  # ピクセルフォーマット
                '-g', '50',  # GOP size
                '-c:a', 'aac',  # AACコーデック
                '-b:a', '128k',  # オーディオビットレート
                '-ar', '44100',  # サンプルレート
                '-f', 'flv',  # FLV形式
                self.stream_url
            ]

            self.ffmpeg_process = subprocess.Popen(
                ffmpeg_cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )

            print("YouTubeストリーミング配信を開始しました（静止画+音声）")
            return True

        except Exception as e:
            print(f"ストリーミング開始エラー: {e}")
            return False

    def _start_audio_only_stream(self):
        """音声のみのストリーム（静止画がない場合）"""
        try:
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

            print("YouTubeストリーミング配信を開始しました（音声のみ）")
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

            # 静止画が存在するか確認
            if not os.path.exists(self.image_path):
                # 静止画がない場合は音声のみ配信
                return self._play_audio_only(temp_audio)

            # FFmpegで静止画+音声をYouTubeに配信
            ffmpeg_cmd = [
                'ffmpeg',
                '-loop', '1',  # 静止画をループ
                '-i', self.image_path,  # 静止画入力
                '-i', temp_audio,  # 音声入力
                '-c:v', 'libx264',  # H.264ビデオコーデック
                '-preset', 'veryfast',  # エンコード速度優先
                '-b:v', '2500k',  # ビデオビットレート
                '-maxrate', '2500k',
                '-bufsize', '5000k',
                '-pix_fmt', 'yuv420p',  # ピクセルフォーマット
                '-g', '50',  # GOP size
                '-c:a', 'aac',  # AACコーデック
                '-b:a', '128k',  # オーディオビットレート
                '-ar', '44100',  # サンプルレート
                '-shortest',  # 短い方に合わせる（音声の長さ）
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

    def _play_audio_only(self, audio_path: str):
        """音声のみを配信（静止画がない場合）"""
        try:
            ffmpeg_cmd = [
                'ffmpeg',
                '-re',  # リアルタイム再生
                '-i', audio_path,  # 入力ファイル
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
            if os.path.exists(audio_path):
                os.remove(audio_path)

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
