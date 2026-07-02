"""24時間AIラジオ配信 メインオーケストレータ

流れ:
  YouTubeコメント/スパチャ取得 (chat_source)
    → ollama で返答生成 (llm)
    → VOICEVOX で音声合成 (tts)
    → PulseAudio仮想シンクへ再生・BGMダッキング (audio)
    → OBSが仮想シンク+アバターページを常時配信 (obs_controller / overlay_server)
"""
import asyncio
import logging
import signal
import time

from .audio import AudioMixer
from .chat_source import ChatMessage, ChatSource
from .config import Config
from .llm import OllamaClient
from .obs_controller import ObsController
from .overlay_server import OverlayServer
from .tts import VoicevoxClient

logger = logging.getLogger("radio")

HEALTH_CHECK_INTERVAL = 30


class RadioApp:
    def __init__(self):
        self.cfg = Config
        self.mixer = AudioMixer(self.cfg)
        self.overlay = OverlayServer(self.cfg)
        self.llm = OllamaClient(self.cfg)
        self.tts = VoicevoxClient(self.cfg)
        self.obs = ObsController(self.cfg) if self.cfg.OBS_ENABLED else None
        self.queue: asyncio.PriorityQueue = asyncio.PriorityQueue()
        self.chat: ChatSource | None = None
        self.last_activity = time.time()
        self._stopping = asyncio.Event()

    # ---- 起動 ---------------------------------------------------------

    async def start(self):
        errors = self.cfg.validate()
        if errors:
            for e in errors:
                logger.error("設定エラー: %s", e)
            raise SystemExit(1)

        logger.info("=== 24時間AIラジオ配信システム 起動 ===")

        self.mixer.ensure_sink()
        await self.overlay.start()

        await self._wait_for("VOICEVOX", self.tts.is_ready)
        await self._wait_for("Ollama", self.llm.is_ready)

        if self.obs:
            logger.info("OBSへ接続中...")
            await asyncio.to_thread(self.obs.connect)
            await asyncio.to_thread(self.obs.setup)
            if self.cfg.AUTO_START_STREAM:
                await asyncio.to_thread(self.obs.ensure_streaming)

        self.chat = ChatSource(self.cfg, asyncio.get_running_loop(), self.queue)
        self.chat.start()

        # 音声経路の疎通確認を兼ねてオープニングを読み上げる
        if self.cfg.OPENING_MESSAGE:
            await self._speak(self.cfg.OPENING_MESSAGE)

        logger.info("初期化完了。コメント待機中...")

    async def _wait_for(self, name: str, check, interval: float = 3.0):
        while not await asyncio.to_thread(check):
            logger.info("%s の起動を待っています...", name)
            await asyncio.sleep(interval)
        logger.info("%s 接続確認OK", name)

    # ---- 発話 ---------------------------------------------------------

    async def _speak(self, text: str):
        await self.overlay.broadcast({"type": "status", "state": "speaking"})
        await self.overlay.broadcast({"type": "reply", "text": text})
        try:
            wav = await asyncio.to_thread(self.tts.synthesize, text)
        except Exception as e:
            logger.error("音声合成に失敗: %s", e)
            await self.overlay.broadcast({"type": "status", "state": "idle"})
            return
        await self.overlay.broadcast({"type": "speech", "state": "start"})
        try:
            await self.mixer.play_wav(wav)
        finally:
            await self.overlay.broadcast({"type": "speech", "state": "end"})
            await self.overlay.broadcast({"type": "status", "state": "idle"})

    # ---- メインループ ---------------------------------------------------

    async def worker(self):
        while not self._stopping.is_set():
            try:
                _, _, msg = await asyncio.wait_for(self.queue.get(), timeout=2.0)
            except asyncio.TimeoutError:
                if time.time() - self.last_activity >= self.cfg.IDLE_CHAT_INTERVAL:
                    await self._idle_chat()
                continue
            await self._process_comment(msg)

    async def _process_comment(self, msg: ChatMessage):
        label = f"スパチャ({msg.amount})" if msg.is_superchat else "コメント"
        logger.info("%s [%s] %s", label, msg.author, msg.message)

        await self.overlay.broadcast({
            "type": "comment",
            "author": msg.author,
            "message": msg.message,
            "superchat": msg.is_superchat,
            "amount": msg.amount,
        })
        await self.overlay.broadcast({"type": "status", "state": "thinking"})

        response = await asyncio.to_thread(
            self.llm.reply, msg.author, msg.message, msg.is_superchat, msg.amount
        )
        logger.info("返答: %s", response)
        await self._speak(response)
        self.last_activity = time.time()

    async def _idle_chat(self):
        logger.info("コメントが無いため雑談します")
        await self.overlay.broadcast({"type": "status", "state": "thinking"})
        text = await asyncio.to_thread(self.llm.idle_talk)
        logger.info("雑談: %s", text)
        await self._speak(text)
        self.last_activity = time.time()

    async def health_check(self):
        """OBS配信の死活監視: 落ちていたら自動で配信を再開する"""
        while not self._stopping.is_set():
            await asyncio.sleep(HEALTH_CHECK_INTERVAL)
            if not self.obs:
                continue
            try:
                await asyncio.to_thread(self.obs.ensure_streaming)
            except Exception as e:
                logger.error("OBS死活監視エラー: %s (再接続を試みます)", e)
                try:
                    await asyncio.to_thread(self.obs.connect, 3)
                    await asyncio.to_thread(self.obs.setup)
                    if self.cfg.AUTO_START_STREAM:
                        await asyncio.to_thread(self.obs.ensure_streaming)
                except Exception as e2:
                    logger.error("OBS再接続失敗: %s", e2)

    # ---- 停止 ---------------------------------------------------------

    async def stop(self):
        if self._stopping.is_set():
            return
        logger.info("停止処理を開始します...")
        self._stopping.set()
        if self.chat:
            self.chat.stop()
        await self.overlay.stop()
        logger.info("停止しました")


async def async_main():
    app = RadioApp()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, app._stopping.set)

    await app.start()
    def _on_task_done(task: asyncio.Task):
        if not task.cancelled() and task.exception():
            logger.error("バックグラウンドタスク異常終了: %s", task.exception())
            app._stopping.set()

    tasks = [
        asyncio.create_task(app.worker()),
        asyncio.create_task(app.health_check()),
    ]
    for t in tasks:
        t.add_done_callback(_on_task_done)
    try:
        await app._stopping.wait()
    finally:
        for t in tasks:
            t.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        await app.stop()


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    asyncio.run(async_main())


if __name__ == "__main__":
    main()
