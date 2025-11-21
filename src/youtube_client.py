"""YouTubeコメント取得モジュール"""
import pytchat
from typing import List, Dict, Optional
from .config import Config


class YouTubeClient:
    """YouTubeライブチャットからコメントを取得するクライアント"""

    def __init__(self):
        self.video_id = Config.YOUTUBE_VIDEO_ID
        self.chat = None
        self.is_connected = False

    def connect(self):
        """ライブチャットに接続"""
        try:
            self.chat = pytchat.create(video_id=self.video_id)
            self.is_connected = True
            print(f"YouTubeライブチャットに接続しました (Video ID: {self.video_id})")
        except Exception as e:
            print(f"YouTubeライブチャット接続エラー: {e}")
            self.is_connected = False
            raise

    def disconnect(self):
        """ライブチャットから切断"""
        if self.chat:
            self.chat.terminate()
            self.is_connected = False
            print("YouTubeライブチャットから切断しました")

    def get_new_comments(self) -> List[Dict[str, str]]:
        """
        新しいコメントを取得

        Returns:
            コメントのリスト [{"author": "ユーザー名", "message": "コメント内容"}, ...]

        Raises:
            Exception: チャット接続エラー時
        """
        if not self.is_connected or not self.chat:
            return []

        comments = []
        try:
            if self.chat.is_alive():
                # 新しいコメントを取得
                for c in self.chat.get().sync_items():
                    comments.append({
                        "author": c.author.name,
                        "message": c.message
                    })
        except Exception as e:
            error_msg = str(e)
            print(f"コメント取得エラー: {error_msg}")
            self.is_connected = False
            # エラーを再raiseして上位で処理できるようにする
            raise

        return comments

    def is_alive(self) -> bool:
        """
        チャット接続が生きているかチェック

        Returns:
            接続が有効な場合True
        """
        if not self.chat:
            return False
        return self.chat.is_alive()

    def reconnect(self):
        """チャットに再接続"""
        print("YouTubeライブチャットに再接続を試みています...")
        self.disconnect()
        try:
            self.connect()
            return True
        except Exception as e:
            print(f"再接続に失敗しました: {e}")
            return False
