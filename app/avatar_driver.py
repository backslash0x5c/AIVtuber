"""サーバ側アバタードライバ (AVATAR_MODE=inochi2d 用)

ブラウザ描画モードではオーバーレイJSが行っている
「音量エンベロープ→口パク」「まばたき」「感情→表情」「アイドル時の揺れ」を
サーバ側で毎フレーム計算し、VMCプロトコルで nijiexpose 等へ送信する。

送信するブレンドシェイプ名 (nijiexpose側でパペットのパラメータに紐づける):
  A          : 口の開き (リップシンク)
  Blink      : まばたき (1=閉じ)
  Joy / Sorrow / Angry / Surprised / Shy : 感情 (排他的に0..1でクロスフェード)
頭ボーン "Head" にはZ軸回転(傾き+揺れ)を送る。
"""
import asyncio
import logging
import math
import random
import time

from .config import Config
from .vmc_sender import VMCSender

logger = logging.getLogger(__name__)

# 感情 → VMCブレンドシェイプ名 (neutralは全感情0)
EMOTION_BLENDS = {
    "happy": "Joy",
    "sad": "Sorrow",
    "angry": "Angry",
    "surprised": "Surprised",
    "shy": "Shy",
}

# 感情ごとの首の傾き(度)。ブラウザ版のEMOTIONSプリセットと同じ値
EMOTION_TILT = {
    "neutral": 0.0, "happy": 3.0, "sad": -3.0,
    "angry": 0.0, "surprised": 0.0, "shy": 4.0,
}

EMOTION_HOLD_SEC = 8.0   # 感情を保持してneutralへ戻すまでの時間
BLINK_CLOSE_SEC = 0.09   # まばたきで閉じている時間


class AvatarDriver:
    def __init__(self, cfg: type[Config] = Config):
        self.cfg = cfg
        self.sender = VMCSender(cfg.VMC_HOST, cfg.VMC_PORT)

        # 口パク (エンベロープ再生)
        self._envelope: list[int] | None = None
        self._env_frame_ms = 50
        self._env_start = 0.0
        self._mouth = 0.0

        # まばたき
        self._blink = 0.0
        self._blink_until = 0.0
        self._next_blink = time.monotonic() + 2.0

        # 感情
        self._emotion = "neutral"
        self._emotion_until = 0.0
        self._blend_values = {name: 0.0 for name in EMOTION_BLENDS.values()}
        self._tilt = 0.0

    # ---- イベント (main.py から呼ばれる) --------------------------------

    def on_speech_start(self, envelope: list[int], frame_ms: int, emotion: str):
        self._envelope = envelope or None
        self._env_frame_ms = frame_ms
        self._env_start = time.monotonic()
        self.set_emotion(emotion)

    def on_speech_end(self):
        self._envelope = None

    def set_emotion(self, emotion: str):
        self._emotion = emotion if emotion in EMOTION_TILT else "neutral"
        self._emotion_until = time.monotonic() + EMOTION_HOLD_SEC

    # ---- 毎フレーム計算 --------------------------------------------------

    def _mouth_target(self, now: float) -> float:
        if not self._envelope:
            return 0.0
        pos = (now - self._env_start) * 1000.0 / self._env_frame_ms
        i = int(pos)
        if i < 0 or i >= len(self._envelope):
            return 0.0
        a = self._envelope[i] / 100.0
        b = (self._envelope[i + 1] / 100.0) if i + 1 < len(self._envelope) else 0.0
        return a + (b - a) * (pos - i)

    def _tick(self, now: float, dt: float):
        fast = 1.0 - math.exp(-dt * 22.0)
        slow = 1.0 - math.exp(-dt * 7.0)

        # 口
        self._mouth += (self._mouth_target(now) - self._mouth) * fast

        # まばたき
        if now >= self._next_blink:
            self._blink_until = now + BLINK_CLOSE_SEC
            self._next_blink = now + 2.5 + random.random() * 3.5
        blink_target = 1.0 if now < self._blink_until else 0.0
        self._blink += (blink_target - self._blink) * fast

        # 感情 (保持時間を過ぎたらneutralへ)
        if self._emotion != "neutral" and now >= self._emotion_until:
            self._emotion = "neutral"
        active = EMOTION_BLENDS.get(self._emotion)
        for name in self._blend_values:
            target = 1.0 if name == active else 0.0
            self._blend_values[name] += (target - self._blend_values[name]) * slow

        # 首の傾き = 感情プリセット + アイドル時の揺れ(複数周期のサイン合成)
        sway = math.sin(now * 0.42) * 1.6 + math.sin(now * 0.13) * 1.0
        tilt_target = EMOTION_TILT.get(self._emotion, 0.0)
        self._tilt += (tilt_target - self._tilt) * slow

        blends = {"A": self._mouth, "Blink": self._blink, **self._blend_values}
        self.sender.send_frame(blends, head_tilt_deg=self._tilt + sway)

    # ---- メインループ ------------------------------------------------------

    async def run(self):
        logger.info(
            "アバタードライバ起動: VMC送信先 %s:%d (%dfps)",
            self.cfg.VMC_HOST, self.cfg.VMC_PORT, self.cfg.VMC_FPS,
        )
        interval = 1.0 / max(1, self.cfg.VMC_FPS)
        last = time.monotonic()
        try:
            while True:
                now = time.monotonic()
                self._tick(now, min(0.1, now - last))
                last = now
                await asyncio.sleep(interval)
        finally:
            self.sender.close()
