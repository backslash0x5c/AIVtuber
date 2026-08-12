"""OBS制御 (obs-websocket v5)

ヘッドレスOBSに対して:
  - シーン/ソース(アバター用ブラウザソース + 仮想シンクの音声キャプチャ)を自動構築
  - 配信先(YouTube RTMP)と映像/出力設定を投入
  - 配信の開始と死活監視(落ちていたら再開)

obs-websocketのリクエストは obsws-python の send() で公式リクエスト名のまま呼ぶ。
"""
import logging
import time

import obsws_python as obs

from .config import Config

logger = logging.getLogger(__name__)

SCENE_NAME = "Radio"
BROWSER_INPUT = "Avatar"
AUDIO_INPUT = "RadioMix"


class ObsController:
    def __init__(self, cfg: type[Config] = Config):
        self.cfg = cfg
        self.client: obs.ReqClient | None = None

    # ---- 接続 -------------------------------------------------------

    def connect(self, retries: int = 30, interval: float = 2.0):
        # obsws_python は接続失敗のたびにスタックトレースを出力し、待機中のログが
        # 埋まって本当の原因(OBS側のログ)が読めなくなるため抑制する
        logging.getLogger("obsws_python.baseclient").setLevel(logging.CRITICAL)

        last_error = None
        for attempt in range(1, retries + 1):
            try:
                self.client = obs.ReqClient(
                    host=self.cfg.OBS_WS_HOST,
                    port=self.cfg.OBS_WS_PORT,
                    password=self.cfg.OBS_WS_PASSWORD,
                    timeout=10,
                )
                version = self.client.send("GetVersion")
                logger.info("OBS接続成功 (OBS %s)", version.obs_version)
                return
            except Exception as e:
                last_error = e
                # 毎回出すとうるさいので数回に1度だけ進捗を出す
                if attempt == 1 or attempt % 10 == 0:
                    logger.info(
                        "OBSの起動を待っています... (%d/%d) %s",
                        attempt, retries, type(e).__name__,
                    )
                time.sleep(interval)

        raise ConnectionError(
            f"OBS(obs-websocket)に接続できません: {last_error}\n"
            f"  OBSが {self.cfg.OBS_WS_HOST}:{self.cfg.OBS_WS_PORT} で待ち受けていません。\n"
            f"  OBS側のログを確認してください: "
            f"journalctl --user -u radio-obs -n 50 --no-pager"
        )

    def _send(self, request: str, data: dict | None = None):
        return self.client.send(request, data)

    # ---- シーン構築 ---------------------------------------------------

    def setup(self):
        """シーン・ソース・配信設定を冪等に構築する"""
        self._setup_video()
        self._setup_scene()
        self._setup_sources()
        self._remove_default_audio()
        self._send("SetCurrentProgramScene", {"sceneName": SCENE_NAME})
        self._setup_output()
        if self.cfg.YOUTUBE_STREAM_KEY:
            self._setup_stream_service()

    def _setup_video(self):
        self._send("SetVideoSettings", {
            "fpsNumerator": self.cfg.VIDEO_FPS,
            "fpsDenominator": 1,
            "baseWidth": self.cfg.VIDEO_WIDTH,
            "baseHeight": self.cfg.VIDEO_HEIGHT,
            "outputWidth": self.cfg.VIDEO_WIDTH,
            "outputHeight": self.cfg.VIDEO_HEIGHT,
        })

    def _setup_scene(self):
        scenes = self._send("GetSceneList").scenes
        if not any(s["sceneName"] == SCENE_NAME for s in scenes):
            self._send("CreateScene", {"sceneName": SCENE_NAME})
            logger.info("シーン %s を作成しました", SCENE_NAME)

    def _input_exists(self, name: str) -> bool:
        inputs = self._send("GetInputList").inputs
        return any(i["inputName"] == name for i in inputs)

    def _setup_sources(self):
        overlay_url = f"http://{self.cfg.OVERLAY_HOST}:{self.cfg.OVERLAY_PORT}/"
        if not self._input_exists(BROWSER_INPUT):
            self._send("CreateInput", {
                "sceneName": SCENE_NAME,
                "inputName": BROWSER_INPUT,
                "inputKind": "browser_source",
                "inputSettings": {
                    "url": overlay_url,
                    "width": self.cfg.VIDEO_WIDTH,
                    "height": self.cfg.VIDEO_HEIGHT,
                    "fps": self.cfg.VIDEO_FPS,
                    "reroute_audio": False,
                    "restart_when_active": False,
                    "shutdown": False,
                },
                "sceneItemEnabled": True,
            })
            logger.info("ブラウザソース %s を作成しました (%s)", BROWSER_INPUT, overlay_url)
        else:
            self._send("SetInputSettings", {
                "inputName": BROWSER_INPUT,
                "inputSettings": {
                    "url": overlay_url,
                    "width": self.cfg.VIDEO_WIDTH,
                    "height": self.cfg.VIDEO_HEIGHT,
                },
                "overlay": True,
            })

        monitor = f"{self.cfg.MIX_SINK}.monitor"
        if not self._input_exists(AUDIO_INPUT):
            self._send("CreateInput", {
                "sceneName": SCENE_NAME,
                "inputName": AUDIO_INPUT,
                "inputKind": "pulse_input_capture",
                "inputSettings": {"device_id": monitor},
                "sceneItemEnabled": True,
            })
            logger.info("音声キャプチャ %s を作成しました (%s)", AUDIO_INPUT, monitor)
        else:
            self._send("SetInputSettings", {
                "inputName": AUDIO_INPUT,
                "inputSettings": {"device_id": monitor},
                "overlay": True,
            })

    def _remove_default_audio(self):
        """既定のデスクトップ音声/マイクを外して音の二重取り込みを防ぐ"""
        for name in ("Desktop Audio", "デスクトップ音声", "Mic/Aux", "マイク"):
            if self._input_exists(name):
                try:
                    self._send("RemoveInput", {"inputName": name})
                    logger.info("既定の音声ソース %s を削除しました", name)
                except Exception as e:
                    logger.warning("%s の削除に失敗: %s", name, e)

    def _setup_output(self):
        params = [
            ("Output", "Mode", "Simple"),
            ("SimpleOutput", "VBitrate", str(self.cfg.VIDEO_BITRATE_KBPS)),
            ("SimpleOutput", "ABitrate", str(self.cfg.AUDIO_BITRATE_KBPS)),
            ("SimpleOutput", "StreamEncoder", "x264"),
            ("SimpleOutput", "Preset", "veryfast"),
        ]
        for category, name, value in params:
            self._send("SetProfileParameter", {
                "parameterCategory": category,
                "parameterName": name,
                "parameterValue": value,
            })

    def _setup_stream_service(self):
        self._send("SetStreamServiceSettings", {
            "streamServiceType": "rtmp_custom",
            "streamServiceSettings": {
                "server": self.cfg.YOUTUBE_RTMP_SERVER,
                "key": self.cfg.YOUTUBE_STREAM_KEY,
                "use_auth": False,
            },
        })
        logger.info("配信先を設定しました (%s)", self.cfg.YOUTUBE_RTMP_SERVER)

    # ---- 配信制御 -----------------------------------------------------

    def stream_active(self) -> bool:
        return bool(self._send("GetStreamStatus").output_active)

    def ensure_streaming(self):
        """配信していなければ開始する(死活監視から定期的に呼ばれる)"""
        if self.stream_active():
            return
        logger.info("配信を開始します...")
        self._send("StartStream")

    def stop_streaming(self):
        try:
            if self.stream_active():
                self._send("StopStream")
        except Exception as e:
            logger.warning("配信停止に失敗: %s", e)
