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
        self.bgm_path = "Egoist_2.mp3"  # BGM音楽ファイル
        self.bgm_volume = 0.3  # BGMのみの時の音量（30%）
        self.bgm_volume_with_voice = 0.15  # 会話中のBGM音量（15%）

    def start_stream(self):
        """
        YouTubeへのストリーミングを開始

        静止画とBGMのストリームを開始
        """
        try:
            # 静止画が存在するか確認
            if not os.path.exists(self.image_path):
                print(f"警告: {self.image_path} が見つかりません")
                print("静止画なしで音声のみ配信します")
                return self._start_audio_only_stream()

            # BGMが存在するか確認
            if not os.path.exists(self.bgm_path):
                print(f"警告: {self.bgm_path} が見つかりません")
                print("BGMなしで配信します")
                return self._start_stream_without_bgm()

            # 静止画 + BGMのストリームを生成してYouTubeに配信
            ffmpeg_cmd = [
                'ffmpeg',
                '-loop', '1',  # 静止画をループ
                '-i', self.image_path,  # 静止画入力
                '-stream_loop', '-1',  # BGMを無限ループ
                '-i', self.bgm_path,  # BGM入力
                '-filter_complex', f'[1:a]volume={self.bgm_volume}[a]',  # BGM音量調整
                '-map', '0:v',  # ビデオは静止画から
                '-map', '[a]',  # オーディオはフィルター処理後のBGM
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

            print("YouTubeストリーミング配信を開始しました（静止画+BGM）")
            return True

        except Exception as e:
            print(f"ストリーミング開始エラー: {e}")
            return False

    def _start_stream_without_bgm(self):
        """BGMなしでストリームを開始（フォールバック）"""
        try:
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

            print("YouTubeストリーミング配信を開始しました（静止画のみ）")
            return True

        except Exception as e:
            print(f"ストリーミング開始エラー: {e}")
            return False

    def _start_audio_only_stream(self):
        """音声のみのストリーム（静止画がない場合）"""
        try:
            # BGMが存在するか確認
            if not os.path.exists(self.bgm_path):
                print(f"警告: {self.bgm_path} が見つかりません")
                print("BGMなしで配信します")
                # BGMなしで無音配信
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
            else:
                # BGMありで配信
                ffmpeg_cmd = [
                    'ffmpeg',
                    '-stream_loop', '-1',  # BGMを無限ループ
                    '-i', self.bgm_path,  # BGM入力
                    '-filter_complex', f'[0:a]volume={self.bgm_volume}[a]',  # BGM音量調整
                    '-map', '[a]',
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

            print("YouTubeストリーミング配信を開始しました（音声のみ）")
            return True

        except Exception as e:
            print(f"ストリーミング開始エラー: {e}")
            return False

    def play_audio(self, audio_data: bytes):
        """
        音声データを再生してストリーミング配信

        一時的にストリームを停止し、音声付きで再開してから、再びBGMストリームに戻す

        Args:
            audio_data: WAV形式の音声データ
        """
        try:
            # 一時ファイルに音声データを保存
            temp_audio = os.path.join(self.temp_dir, 'temp_audio.wav')
            with open(temp_audio, 'wb') as f:
                f.write(audio_data)

            # 現在のストリームを一時停止
            print("音声再生のため一時的にストリームを切り替え中...")
            was_streaming = self.is_streaming()
            if was_streaming:
                self.ffmpeg_process.terminate()
                self.ffmpeg_process.wait(timeout=2)

            # 静止画が存在するか確認
            if not os.path.exists(self.image_path):
                # 静止画がない場合は音声のみ配信
                success = self._play_audio_only(temp_audio)
            else:
                # 静止画+音声で配信
                success = self._play_audio_with_image(temp_audio)

            # 一時ファイルを削除
            if os.path.exists(temp_audio):
                os.remove(temp_audio)

            # BGMストリームを再開
            if was_streaming:
                self.start_stream()

            return success

        except Exception as e:
            print(f"音声再生エラー: {e}")
            # エラー時もストリームを再開
            if self.is_streaming():
                self.start_stream()
            return False

    def _play_audio_with_image(self, audio_path: str):
        """静止画+音声+BGMを配信"""
        try:
            # BGMが存在するか確認
            if not os.path.exists(self.bgm_path):
                # BGMなしで会話音声のみ配信
                ffmpeg_cmd = [
                    'ffmpeg',
                    '-loop', '1',  # 静止画をループ
                    '-i', self.image_path,  # 静止画入力
                    '-i', audio_path,  # 音声入力
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
            else:
                # BGMと会話音声をミックスして配信
                ffmpeg_cmd = [
                    'ffmpeg',
                    '-loop', '1',  # 静止画をループ
                    '-i', self.image_path,  # 静止画入力
                    '-stream_loop', '-1',  # BGMをループ
                    '-i', self.bgm_path,  # BGM入力
                    '-i', audio_path,  # 音声入力
                    '-filter_complex',
                    f'[1:a]volume={self.bgm_volume_with_voice}[bgm];'  # BGM音量を下げる
                    f'[2:a]volume=1.0[voice];'  # 会話音声は100%
                    f'[bgm][voice]amix=inputs=2:duration=shortest:dropout_transition=2[a]',  # ミックス
                    '-map', '0:v',  # ビデオは静止画
                    '-map', '[a]',  # オーディオはミックス後
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

            process = subprocess.run(
                ffmpeg_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=60
            )

            if process.returncode != 0:
                stderr = process.stderr.decode()
                # 既に他の接続があるエラーは無視（ストリーム切り替え中の一時的なエラー）
                if "already publishing" not in stderr.lower():
                    print(f"音声配信エラー: {stderr}")
                return False

            return True

        except subprocess.TimeoutExpired:
            print("音声配信がタイムアウトしました")
            return False
        except Exception as e:
            print(f"音声配信エラー: {e}")
            return False

    def _play_audio_only(self, audio_path: str):
        """音声のみを配信（静止画がない場合）"""
        try:
            # BGMが存在するか確認
            if not os.path.exists(self.bgm_path):
                # BGMなしで会話音声のみ配信
                ffmpeg_cmd = [
                    'ffmpeg',
                    '-re',  # リアルタイム再生
                    '-i', audio_path,  # 入力ファイル
                    '-c:a', 'aac',  # AACコーデック
                    '-b:a', '128k',  # ビットレート
                    '-f', 'flv',  # FLV形式
                    self.stream_url
                ]
            else:
                # BGMと会話音声をミックス
                ffmpeg_cmd = [
                    'ffmpeg',
                    '-stream_loop', '-1',  # BGMをループ
                    '-i', self.bgm_path,  # BGM入力
                    '-i', audio_path,  # 音声入力
                    '-filter_complex',
                    f'[0:a]volume={self.bgm_volume_with_voice}[bgm];'
                    f'[1:a]volume=1.0[voice];'
                    f'[bgm][voice]amix=inputs=2:duration=shortest:dropout_transition=2[a]',
                    '-map', '[a]',
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

            if process.returncode != 0:
                stderr = process.stderr.decode()
                if "already publishing" not in stderr.lower():
                    print(f"音声配信エラー: {stderr}")
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
