"""オーバーレイ配信サーバ

OBSのブラウザソースが読み込むアバターページ(avatar/index.html)を配信し、
WebSocketで発話状態・字幕・コメントをリアルタイムに送る。
"""
import json
import logging
from pathlib import Path

from aiohttp import WSMsgType, web

from .config import ROOT_DIR, Config

logger = logging.getLogger(__name__)

AVATAR_DIR = ROOT_DIR / "avatar"


class OverlayServer:
    def __init__(self, cfg: type[Config] = Config):
        self.cfg = cfg
        self._clients: set[web.WebSocketResponse] = set()
        self._runner: web.AppRunner | None = None
        # 新規接続時に現在の状態を再現できるよう最後のイベントを保持
        self._snapshot: dict[str, dict] = {}

    async def start(self):
        app = web.Application()
        app.router.add_get("/", self._index)
        app.router.add_get("/config", self._config)
        app.router.add_get("/ws", self._ws_handler)
        app.router.add_static("/static", AVATAR_DIR)
        self._runner = web.AppRunner(app)
        await self._runner.setup()
        site = web.TCPSite(self._runner, self.cfg.OVERLAY_HOST, self.cfg.OVERLAY_PORT)
        await site.start()
        logger.info(
            "オーバーレイサーバ起動: http://%s:%d/",
            self.cfg.OVERLAY_HOST, self.cfg.OVERLAY_PORT,
        )

    async def stop(self):
        for ws in set(self._clients):
            await ws.close()
        if self._runner:
            await self._runner.cleanup()

    async def _index(self, _request: web.Request) -> web.Response:
        return web.FileResponse(AVATAR_DIR / "index.html")

    async def _config(self, _request: web.Request) -> web.Response:
        """オーバーレイページ向けの設定 (Live2Dモデルの有無など)"""
        live2d_url = None
        if self.cfg.LIVE2D_MODEL:
            model_path = AVATAR_DIR / self.cfg.LIVE2D_MODEL
            if model_path.is_file():
                live2d_url = f"/static/{self.cfg.LIVE2D_MODEL}"
            else:
                logger.warning("LIVE2D_MODEL が見つかりません: %s", model_path)
        return web.json_response({"live2d_model": live2d_url})

    async def _ws_handler(self, request: web.Request) -> web.WebSocketResponse:
        ws = web.WebSocketResponse(heartbeat=30)
        await ws.prepare(request)
        self._clients.add(ws)
        logger.info("オーバーレイクライアント接続 (計%d)", len(self._clients))
        try:
            for event in self._snapshot.values():
                await ws.send_json(event)
            async for msg in ws:
                if msg.type in (WSMsgType.ERROR, WSMsgType.CLOSE):
                    break
        finally:
            self._clients.discard(ws)
        return ws

    async def broadcast(self, event: dict):
        self._snapshot[event.get("type", "")] = event
        data = json.dumps(event, ensure_ascii=False)
        for ws in set(self._clients):
            try:
                await ws.send_str(data)
            except Exception:
                self._clients.discard(ws)
