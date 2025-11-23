"""音声ストリーミング配信モジュール"""
import subprocess
import os
import tempfile
import threading
import queue
import time
import wave
from typing import Optional
from .config import Config


class AudioStreamer:
    """FFmpegを使用してYouTubeに静止画+音声をストリーミング配信するクラス

    連続ストリーミング方式：
    - 名前付きパイプ（FIFO）を使用して単一の連続ストリームを維持
    - 音声キューに基づいて動的に音声を注入
    - ストリームの切り替えなし
    """

    def __init__(self):
        self.stream_url = Config.YOUTUBE_STREAM_URL + Config.YOUTUBE_STREAM_KEY
        self.ffmpeg_process: Optional[subprocess.Popen] = None
        self.temp_dir = tempfile.mkdtemp()
        self.image_path = "image.png"  # 配信用静止画

        # 連続ストリーミング用の設定
        self.audio_fifo_path = os.path.join(self.temp_dir, 'audio_fifo.wav')
        self.audio_queue = queue.Queue()
        self.feeder_thread: Optional[threading.Thread] = None
        self.is_running = False

        # オーディオ設定
        self.sample_rate = 44100
        self.channels = 2
        self.sample_width = 2  # 16-bit

    def _create_audio_fifo(self):
        """名前付きパイプ（FIFO）を作成"""
        try:
            if os.path.exists(self.audio_fifo_path):
                os.remove(self.audio_fifo_path)
            os.mkfifo(self.audio_fifo_path)
            print(f"Audio FIFO作成: {self.audio_fifo_path}")
            return True
        except Exception as e:
            print(f"FIFO作成エラー: {e}")
            return False

    def _generate_silence(self, duration_seconds: float) -> bytes:
        """指定秒数の無音データを生成

        Args:
            duration_seconds: 無音の長さ（秒）

        Returns:
            WAV形式の無音データ
        """
        num_samples = int(self.sample_rate * duration_seconds)
        silence = b'\x00' * (num_samples * self.channels * self.sample_width)
        return silence

    def _audio_feeder(self):
        """オーディオフィーダースレッド

        音声キューを監視し、FIFOに連続的にデータを書き込む：
        - キューが空の場合：無音チャンクを書き込み
        - キューにデータがある場合：実際の音声を書き込み
        """
        print("オーディオフィーダースレッド開始")

        try:
            # FIFOを書き込みモードでオープン（ブロッキング）
            with open(self.audio_fifo_path, 'wb') as fifo:
                # WAVヘッダーを書き込み（連続ストリームとして）
                # 注: データサイズは不定（0xFFFFFFFF）
                self._write_wav_header(fifo, data_size=0xFFFFFFFF)

                while self.is_running:
                    try:
                        # キューから音声データを取得（タイムアウト付き）
                        audio_data = self.audio_queue.get(timeout=0.1)

                        if audio_data is None:
                            # 終了シグナル
                            break

                        print(f"音声データをFIFOに書き込み中 ({len(audio_data)} bytes)")

                        # WAVファイルから実際のオーディオデータを抽出
                        # （WAVヘッダーをスキップ）
                        audio_samples = self._extract_wav_samples(audio_data)
                        fifo.write(audio_samples)
                        fifo.flush()

                        print("音声データ書き込み完了")

                    except queue.Empty:
                        # キューが空の場合は無音を書き込み
                        silence = self._generate_silence(0.1)  # 100msの無音
                        fifo.write(silence)
                        fifo.flush()

        except Exception as e:
            print(f"オーディオフィーダーエラー: {e}")
        finally:
            print("オーディオフィーダースレッド終了")

    def _write_wav_header(self, file, data_size: int):
        """WAVヘッダーを書き込む

        Args:
            file: 書き込み先ファイルオブジェクト
            data_size: データサイズ（バイト）、連続ストリームの場合は0xFFFFFFFF
        """
        import struct

        # RIFFヘッダー
        file.write(b'RIFF')
        file.write(struct.pack('<I', data_size + 36 if data_size != 0xFFFFFFFF else 0xFFFFFFFF))
        file.write(b'WAVE')

        # fmtチャンク
        file.write(b'fmt ')
        file.write(struct.pack('<I', 16))  # fmtチャンクサイズ
        file.write(struct.pack('<H', 1))   # PCMフォーマット
        file.write(struct.pack('<H', self.channels))
        file.write(struct.pack('<I', self.sample_rate))
        byte_rate = self.sample_rate * self.channels * self.sample_width
        file.write(struct.pack('<I', byte_rate))
        block_align = self.channels * self.sample_width
        file.write(struct.pack('<H', block_align))
        file.write(struct.pack('<H', self.sample_width * 8))  # bits per sample

        # dataチャンク
        file.write(b'data')
        file.write(struct.pack('<I', data_size))

    def _extract_wav_samples(self, wav_data: bytes) -> bytes:
        """WAVファイルからサンプルデータを抽出

        Args:
            wav_data: WAV形式の音声データ

        Returns:
            生のPCMサンプルデータ
        """
        try:
            import io
            with wave.open(io.BytesIO(wav_data), 'rb') as wav:
                return wav.readframes(wav.getnframes())
        except Exception as e:
            print(f"WAVサンプル抽出エラー: {e}")
            # エラー時はヘッダーをスキップして残りを返す（簡易フォールバック）
            return wav_data[44:] if len(wav_data) > 44 else b''

    def start_stream(self):
        """
        YouTubeへのストリーミングを開始

        連続ストリーミング方式：
        1. FIFOパイプを作成
        2. オーディオフィーダースレッドを起動
        3. FFmpegをFIFOから読み取るように起動
        """
        try:
            # 静止画が存在するか確認
            if not os.path.exists(self.image_path):
                print(f"警告: {self.image_path} が見つかりません")
                print("静止画なしで音声のみ配信します")
                return self._start_audio_only_stream()

            # FIFOパイプを作成
            if not self._create_audio_fifo():
                return False

            # オーディオフィーダースレッドを開始
            self.is_running = True
            self.feeder_thread = threading.Thread(target=self._audio_feeder, daemon=True)
            self.feeder_thread.start()

            # FFmpegをFIFOから読み取るように起動
            ffmpeg_cmd = [
                'ffmpeg',
                '-loop', '1',  # 静止画をループ
                '-i', self.image_path,  # 静止画入力
                '-f', 'wav',  # WAV形式で読み取り
                '-i', self.audio_fifo_path,  # FIFOパイプから音声入力
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

            print("YouTubeストリーミング配信を開始しました（連続ストリーミングモード）")
            return True

        except Exception as e:
            print(f"ストリーミング開始エラー: {e}")
            self.is_running = False
            return False

    def _start_audio_only_stream(self):
        """音声のみのストリーム（静止画がない場合）

        連続ストリーミング方式：
        FIFOパイプから音声を読み取る
        """
        try:
            # FIFOパイプを作成
            if not self._create_audio_fifo():
                return False

            # オーディオフィーダースレッドを開始
            self.is_running = True
            self.feeder_thread = threading.Thread(target=self._audio_feeder, daemon=True)
            self.feeder_thread.start()

            # FFmpegをFIFOから読み取るように起動（音声のみ）
            ffmpeg_cmd = [
                'ffmpeg',
                '-f', 'wav',  # WAV形式で読み取り
                '-i', self.audio_fifo_path,  # FIFOパイプから音声入力
                '-c:a', 'aac',  # AACコーデック
                '-b:a', '128k',  # ビットレート
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

            print("YouTubeストリーミング配信を開始しました（音声のみ、連続ストリーミングモード）")
            return True

        except Exception as e:
            print(f"ストリーミング開始エラー: {e}")
            self.is_running = False
            return False

    def play_audio(self, audio_data: bytes):
        """
        音声データを再生してストリーミング配信

        連続ストリーミング方式：
        - 音声データをキューに追加するだけ
        - フィーダースレッドが自動的にFIFOに書き込む
        - ストリームの切り替えなし

        Args:
            audio_data: WAV形式の音声データ
        """
        try:
            if not self.is_running:
                print("警告: ストリーミングが開始されていません")
                return False

            print("音声データをキューに追加中...")
            self.audio_queue.put(audio_data)
            print("音声データをキューに追加しました（切り替えなし）")

            return True

        except Exception as e:
            print(f"音声キュー追加エラー: {e}")
            return False

    def stop_stream(self):
        """ストリーミングを停止

        連続ストリーミング方式：
        1. フィーダースレッドを停止
        2. FFmpegプロセスを終了
        3. FIFOとテンポラリディレクトリをクリーンアップ
        """
        print("ストリーミング停止中...")

        # フィーダースレッドを停止
        if self.is_running:
            self.is_running = False
            # 終了シグナルをキューに追加
            self.audio_queue.put(None)

            if self.feeder_thread and self.feeder_thread.is_alive():
                self.feeder_thread.join(timeout=5)
                print("オーディオフィーダースレッドを停止しました")

        # FFmpegプロセスを終了
        if self.ffmpeg_process:
            self.ffmpeg_process.terminate()
            try:
                self.ffmpeg_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.ffmpeg_process.kill()
            self.ffmpeg_process = None
            print("FFmpegプロセスを停止しました")

        # 一時ディレクトリをクリーンアップ
        if os.path.exists(self.temp_dir):
            for file in os.listdir(self.temp_dir):
                file_path = os.path.join(self.temp_dir, file)
                if os.path.isfile(file_path):
                    os.remove(file_path)
            # FIFOも削除
            if os.path.exists(self.audio_fifo_path):
                try:
                    os.remove(self.audio_fifo_path)
                except Exception:
                    pass
            os.rmdir(self.temp_dir)
            print("一時ファイルをクリーンアップしました")

        print("ストリーミング配信を停止しました")

    def is_streaming(self) -> bool:
        """
        ストリーミングが実行中かチェック

        Returns:
            実行中の場合True
        """
        if not self.ffmpeg_process:
            return False
        return self.ffmpeg_process.poll() is None
