"""YouTubeライブチャット取得 (pytchat)

別スレッドでポーリングし、asyncioのPriorityQueueへ流し込む。
スーパーチャットは優先度を上げてキュー満杯でも必ず処理する。
接続断は自動で再接続する。
"""
import itertools
import logging
import threading
import time
from dataclasses import dataclass

import pytchat

from .config import Config

logger = logging.getLogger(__name__)

PRIORITY_SUPERCHAT = 0
PRIORITY_NORMAL = 1

_seq = itertools.count()


@dataclass
class ChatMessage:
    author: str
    message: str
    is_superchat: bool = False
    amount: str = ""


class ChatSource:
    def __init__(self, cfg: type[Config], loop: "asyncio.AbstractEventLoop", queue: "asyncio.PriorityQueue"):
        self.cfg = cfg
        self.loop = loop
        self.queue = queue
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self):
        self._thread = threading.Thread(target=self._run, name="chat-source", daemon=True)
        self._thread.start()

    def stop(self):
        self._stop.set()

    # ---- ポーリングスレッド ------------------------------------------

    def _run(self):
        backoff = 5
        while not self._stop.is_set():
            try:
                chat = pytchat.create(video_id=self.cfg.YOUTUBE_VIDEO_ID, interruptable=False)
                logger.info("YouTubeライブチャットに接続しました (video_id=%s)", self.cfg.YOUTUBE_VIDEO_ID)
                backoff = 5
                while chat.is_alive() and not self._stop.is_set():
                    for item in chat.get().sync_items():
                        self._handle_item(item)
                    time.sleep(1)
                if self._stop.is_set():
                    return
                logger.warning("チャット接続が切断されました。再接続します...")
            except Exception as e:
                logger.error("チャット取得エラー: %s (%d秒後に再接続)", e, backoff)
            self._stop.wait(backoff)
            backoff = min(backoff * 2, 120)

    def _handle_item(self, item):
        try:
            is_superchat = item.type in ("superChat", "superSticker")
            msg = ChatMessage(
                author=item.author.name,
                message=item.message or "",
                is_superchat=is_superchat,
                amount=getattr(item, "amountString", "") or "",
            )
        except AttributeError as e:
            logger.warning("コメントの解釈に失敗: %s", e)
            return

        # キューが詰まっている時は通常コメントを間引く(スパチャは必ず積む)
        if not is_superchat and self.queue.qsize() >= self.cfg.MAX_QUEUE:
            logger.info("キュー満杯のためコメントをスキップ: [%s] %s", msg.author, msg.message)
            return

        priority = PRIORITY_SUPERCHAT if is_superchat else PRIORITY_NORMAL
        self.loop.call_soon_threadsafe(
            self.queue.put_nowait, (priority, next(_seq), msg)
        )
