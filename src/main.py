"""24時間ラジオ対話配信メインプログラム"""
import time
import signal
import sys
from .config import Config
from .youtube_client import YouTubeClient
from .ollama_client import OllamaClient
from .voicevox_client import VoicevoxClient
from .audio_streamer import AudioStreamer


class RadioStreamingBot:
    """ラジオ配信ボットのメインクラス"""

    def __init__(self):
        self.youtube_client = YouTubeClient()
        self.ollama_client = OllamaClient()
        self.voicevox_client = VoicevoxClient()
        self.audio_streamer = AudioStreamer()

        self.running = False
        self.last_comment_time = time.time()

        # シグナルハンドラを設定
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)

    def signal_handler(self, signum, frame):
        """シグナル受信時の処理"""
        print("\n終了シグナルを受信しました。クリーンアップ中...")
        self.stop()
        sys.exit(0)

    def initialize(self):
        """各コンポーネントの初期化"""
        print("=" * 50)
        print("24時間ラジオ対話配信システム")
        print("=" * 50)

        # 設定の検証
        try:
            Config.validate()
        except ValueError as e:
            print(f"\n{e}")
            return False

        # VOICEVOXの確認
        print("\n[1/3] VOICEVOX接続確認中...")
        if not self.voicevox_client.is_available():
            print("エラー: VOICEVOXに接続できません")
            print(f"VOICEVOX URL: {Config.VOICEVOX_URL}")
            print("VOICEVOXが起動しているか確認してください")
            return False
        print("✓ VOICEVOX接続成功")

        # YouTubeチャット接続
        print("\n[2/3] YouTubeライブチャット接続中...")
        try:
            self.youtube_client.connect()
            print("✓ YouTubeライブチャット接続成功")
        except Exception as e:
            print(f"エラー: YouTubeライブチャット接続失敗 - {e}")
            return False

        # Ollama確認
        print("\n[3/4] Ollama接続確認中...")
        try:
            # テストメッセージで確認
            test_response = self.ollama_client.generate_response("こんにちは", is_idle_chat=False)
            if test_response:
                print("✓ Ollama接続成功")
            else:
                print("エラー: Ollamaからの応答がありません")
                return False
        except Exception as e:
            print(f"エラー: Ollama接続失敗 - {e}")
            return False

        # ストリーミング配信開始
        print("\n[4/4] YouTube配信を開始中...")
        if not self.audio_streamer.start_stream():
            print("エラー: ストリーミング配信の開始に失敗しました")
            return False
        print("✓ YouTube配信開始成功")

        print("\n" + "=" * 50)
        print("初期化完了！配信を開始します...")
        print("=" * 50 + "\n")

        return True

    def process_comment(self, comment: dict):
        """
        コメントを処理して応答

        Args:
            comment: コメント情報 {"author": "ユーザー名", "message": "コメント内容"}
        """
        author = comment['author']
        message = comment['message']

        print(f"\n💬 [{author}]: {message}")

        # LLMで応答を生成
        print("🤖 応答を生成中...")
        response = self.ollama_client.generate_response(message)
        print(f"📝 応答: {response}")

        # 音声合成
        print("🎙️ 音声合成中...")
        try:
            audio_data = self.voicevox_client.text_to_speech(response)

            # 音声を配信
            print("📡 音声配信中...")
            self.audio_streamer.play_audio(audio_data)
            print("✓ 配信完了\n")

        except Exception as e:
            print(f"❌ エラー: {e}\n")

        # 最後のコメント時刻を更新
        self.last_comment_time = time.time()

    def generate_idle_chat(self):
        """雑談を生成して配信"""
        print("\n💭 雑談を生成中...")
        chat_text = self.ollama_client.generate_idle_chat()
        print(f"📝 雑談: {chat_text}")

        # 音声合成
        print("🎙️ 音声合成中...")
        try:
            audio_data = self.voicevox_client.text_to_speech(chat_text)

            # 音声を配信
            print("📡 音声配信中...")
            self.audio_streamer.play_audio(audio_data)
            print("✓ 配信完了\n")

        except Exception as e:
            print(f"❌ エラー: {e}\n")

        # 最後のコメント時刻を更新
        self.last_comment_time = time.time()

    def run(self):
        """メインループ"""
        if not self.initialize():
            print("\n初期化に失敗しました。終了します。")
            return

        self.running = True

        try:
            while self.running:
                # YouTubeチャットの状態確認
                if not self.youtube_client.is_alive():
                    print("\n" + "=" * 50)
                    print("⚠️ YouTubeチャット接続が切断されました")
                    print("プログラムを終了します...")
                    print("=" * 50 + "\n")
                    break

                # 新しいコメントを取得
                try:
                    comments = self.youtube_client.get_new_comments()
                except Exception as e:
                    error_msg = str(e)
                    # pytchatのエラーメッセージを検出
                    if "Request interrupted" in error_msg or "切断" in error_msg:
                        print("\n" + "=" * 50)
                        print("⚠️ YouTubeチャット接続が切断されました")
                        print(f"エラー: {error_msg}")
                        print("プログラムを終了します...")
                        print("=" * 50 + "\n")
                        break
                    else:
                        print(f"⚠️ コメント取得エラー: {e}")
                        time.sleep(Config.COMMENT_CHECK_INTERVAL)
                        continue

                if comments:
                    # コメントがある場合は処理
                    for comment in comments:
                        self.process_comment(comment)
                else:
                    # コメントがない場合、一定時間経過したら雑談
                    time_since_last = time.time() - self.last_comment_time
                    if time_since_last >= Config.IDLE_CHAT_INTERVAL:
                        self.generate_idle_chat()

                # 少し待機
                time.sleep(Config.COMMENT_CHECK_INTERVAL)

        except KeyboardInterrupt:
            print("\n\nキーボード割り込みを受信しました。")
        except Exception as e:
            print(f"\n予期しないエラーが発生しました: {e}")
        finally:
            self.stop()

    def stop(self):
        """システムの停止とクリーンアップ"""
        if not self.running:
            return

        print("\n" + "=" * 50)
        print("システムを停止しています...")
        print("=" * 50)

        self.running = False

        # YouTubeチャット切断
        self.youtube_client.disconnect()

        # ストリーミング停止
        self.audio_streamer.stop_stream()

        print("✓ 全てのサービスを停止しました\n")


def main():
    """エントリーポイント"""
    bot = RadioStreamingBot()
    bot.run()


if __name__ == "__main__":
    main()
