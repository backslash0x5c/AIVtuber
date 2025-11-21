"""音声ストリーミング配信モジュール"""
import subprocess
import os
import tempfile
import threading
import queue
import time
from typing import Optional
from .config import Config


class AudioStreamer:
    """FFmpegを使用してYouTubeに静止画+音声をストリーミング配信するクラス"""

    def __init__(self):
        self.stream_url = Config.YOUTUBE_STREAM_URL + Config.YOUTUBE_STREAM_KEY
        self.ffmpeg_process: Optional[subprocess.Popen] = None
        self.temp_dir = tempfile.mkdtemp()
        self.image_path = "image.png"  # 配信用静止画
        self.fifo_path = os.path.join(self.temp_dir, 'audio_pipe.fifo')
        self.audio_queue = queue.Queue()
        self.audio_thread: Optional[threading.Thread] = None
        self.running = False

    def _generate_silence(self, duration_seconds: float, sample_rate: int = 44100) -> bytes:
        """
        無音のWAVデータを生成

        Args:
            duration_seconds: 無音の長さ（秒）
            sample_rate: サンプルレート

        Returns:
            WAV形式の無音データ
        """
        num_samples = int(duration_seconds * sample_rate)
        # 16-bit PCM, stereo
        silence_data = b'\x00\x00' * num_samples * 2

        # WAVヘッダーを作成
        import struct
        channels = 2
        sample_width = 2  # 16-bit
        byte_rate = sample_rate * channels * sample_width
        block_align = channels * sample_width
        data_size = len(silence_data)

        wav_header = struct.pack('<4sI4s4sIHHIIHH4sI',
            b'RIFF',
            36 + data_size,
            b'WAVE',
            b'fmt ',
            16,  # fmt chunk size
            1,   # PCM
            channels,
            sample_rate,
            byte_rate,
            block_align,
            sample_width * 8,
            b'data',
            data_size
        )

        return wav_header + silence_data

    def _audio_writer_thread(self):
        """音声データをFIFOに書き込むバックグラウンドスレッド"""
        try:
            with open(self.fifo_path, 'wb') as fifo:
                while self.running:
                    try:
                        # キューから音声データを取得（タイムアウト0.1秒）
                        audio_data = self.audio_queue.get(timeout=0.1)
                        # 音声データをFIFOに書き込み
                        fifo.write(audio_data)
                        fifo.flush()
                    except queue.Empty:
                        # キューが空の場合は短い無音を送る
                        silence = self._generate_silence(0.1)
                        fifo.write(silence)
                        fifo.flush()
        except Exception as e:
            print(f"音声書き込みスレッドエラー: {e}")

    def start_stream(self):
        """
        YouTubeへのストリーミングを開始

        静止画と音声（FIFOから）のストリームを開始
        """
        try:
            # FIFOを作成
            if os.path.exists(self.fifo_path):
                os.remove(self.fifo_path)
            os.mkfifo(self.fifo_path)

            # 音声書き込みスレッドを開始
            self.running = True
            self.audio_thread = threading.Thread(target=self._audio_writer_thread, daemon=True)
            self.audio_thread.start()

            # 静止画が存在するか確認
            if not os.path.exists(self.image_path):
                print(f"警告: {self.image_path} が見つかりません")
                print("静止画なしで音声のみ配信します")
                return self._start_audio_only_stream()

            # FFmpegコマンドを構築
            # 静止画をループし、FIFOから音声を読み取る
            ffmpeg_cmd = [
                'ffmpeg',
                '-loop', '1',  # 静止画をループ
                '-i', self.image_path,  # 静止画入力
                '-f', 'wav',  # WAV形式
                '-i', self.fifo_path,  # FIFOから音声を読み取り
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
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )

            print("YouTubeストリーミング配信を開始しました（静止画+音声）")
            return True

        except Exception as e:
            print(f"ストリーミング開始エラー: {e}")
            self.running = False
            return False

    def _start_audio_only_stream(self):
        """音声のみのストリーム（静止画がない場合）"""
        try:
            ffmpeg_cmd = [
                'ffmpeg',
                '-f', 'wav',  # WAV形式
                '-i', self.fifo_path,  # FIFOから音声を読み取り
                '-c:a', 'aac',  # AACコーデック
                '-b:a', '128k',  # ビットレート
                '-ar', '44100',  # サンプルレート
                '-f', 'flv',  # FLV形式
                self.stream_url
            ]

            self.ffmpeg_process = subprocess.Popen(
                ffmpeg_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )

            print("YouTubeストリーミング配信を開始しました（音声のみ）")
            return True

        except Exception as e:
            print(f"ストリーミング開始エラー: {e}")
            self.running = False
            return False

    def play_audio(self, audio_data: bytes):
        """
        音声データをストリーミング配信にキューイング

        Args:
            audio_data: WAV形式の音声データ
        """
        try:
            if not self.running:
                print("警告: ストリーミングが開始されていません")
                return False

            # 音声データをキューに追加
            self.audio_queue.put(audio_data)
            return True

        except Exception as e:
            print(f"音声キューイングエラー: {e}")
            return False

    def stop_stream(self):
        """ストリーミングを停止"""
        # 音声書き込みスレッドを停止
        self.running = False
        if self.audio_thread:
            self.audio_thread.join(timeout=2)
            self.audio_thread = None

        # FFmpegプロセスを停止
        if self.ffmpeg_process:
            self.ffmpeg_process.terminate()
            self.ffmpeg_process.wait()
            self.ffmpeg_process = None
            print("ストリーミング配信を停止しました")

        # FIFOを削除
        if os.path.exists(self.fifo_path):
            os.remove(self.fifo_path)

        # 一時ディレクトリをクリーンアップ
        if os.path.exists(self.temp_dir):
            for file in os.listdir(self.temp_dir):
                file_path = os.path.join(self.temp_dir, file)
                if os.path.isfile(file_path):
                    os.remove(file_path)
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
