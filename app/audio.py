"""PulseAudio 仮想シンクによる音声ミキシング

旧実装は発話のたびに配信用ffmpegを再起動していたため、配信が途切れ
BGMとの同時再生も不可能だった。新実装では:

  - null sink (radio_mix) を常設し、BGM(mpv)と音声(paplay)を同時に流し込む
  - ミキシングはPulseAudioが行い、OBSは radio_mix.monitor を取り込むだけ
  - 発話中は pactl でBGMのsink-input音量を下げる(ダッキング)

これによりエンコーダ(OBS)は一切再起動されず、配信は途切れない。
"""
import array
import asyncio
import io
import logging
import re
import subprocess
import tempfile
import wave
from pathlib import Path

from .config import Config

logger = logging.getLogger(__name__)

# リップシンク用エンベロープの1フレームあたりの長さ(ms)
ENVELOPE_FRAME_MS = 50


def mouth_envelope(wav_data: bytes, frame_ms: int = ENVELOPE_FRAME_MS) -> list[int]:
    """WAVから口パク用の音量エンベロープ(0-100)を抽出する

    フレームごとのRMSをピーク正規化した値。オーバーレイ側が再生開始時刻と
    突き合わせて口の開き具合を連続的に補間する。
    """
    try:
        with wave.open(io.BytesIO(wav_data)) as w:
            n_channels = w.getnchannels()
            sampwidth = w.getsampwidth()
            raw = w.readframes(w.getnframes())
            framerate = w.getframerate()
    except (wave.Error, EOFError) as e:
        logger.warning("エンベロープ抽出失敗(WAV解析): %s", e)
        return []
    if sampwidth != 2:  # VOICEVOXは16bit PCM
        return []

    samples = array.array("h")
    samples.frombytes(raw[: len(raw) - len(raw) % 2])
    if n_channels > 1:
        samples = samples[::n_channels]

    per_frame = max(1, int(framerate * frame_ms / 1000))
    rms_values = []
    for i in range(0, len(samples), per_frame):
        chunk = samples[i : i + per_frame]
        if not chunk:
            break
        rms_values.append((sum(s * s for s in chunk) / len(chunk)) ** 0.5)

    peak = max(rms_values, default=0)
    if peak <= 0:
        return [0] * len(rms_values)
    return [round(min(1.0, v / peak) * 100) for v in rms_values]


class AudioMixer:
    def __init__(self, cfg: type[Config] = Config):
        self.cfg = cfg
        self.sink = cfg.MIX_SINK

    # ---- シンク管理 -------------------------------------------------

    def ensure_sink(self):
        """仮想シンクが無ければ作成する(冪等)"""
        result = subprocess.run(
            ["pactl", "list", "short", "sinks"],
            capture_output=True, text=True, check=True,
        )
        for line in result.stdout.splitlines():
            fields = line.split("\t")
            if len(fields) >= 2 and fields[1] == self.sink:
                logger.info("仮想シンク %s は既に存在します", self.sink)
                return
        subprocess.run(
            [
                "pactl", "load-module", "module-null-sink",
                f"sink_name={self.sink}",
                f"sink_properties=device.description={self.sink}",
            ],
            check=True,
        )
        logger.info("仮想シンク %s を作成しました", self.sink)

    # ---- BGM ダッキング ---------------------------------------------

    def _bgm_sink_input_ids(self) -> list[str]:
        """mpv(BGMプレイヤー)のsink-input IDを列挙する"""
        result = subprocess.run(
            ["pactl", "list", "sink-inputs"],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            return []
        ids = []
        current_id = None
        for line in result.stdout.splitlines():
            m = re.match(r"^(?:Sink Input|シンク入力) #(\d+)", line.strip())
            if m:
                current_id = m.group(1)
            elif current_id and "application.process.binary" in line and '"mpv"' in line:
                ids.append(current_id)
        return ids

    def _set_bgm_volume(self, percent: int):
        for input_id in self._bgm_sink_input_ids():
            subprocess.run(
                ["pactl", "set-sink-input-volume", input_id, f"{percent}%"],
                capture_output=True,
            )

    # ---- 音声再生 ---------------------------------------------------

    async def play_wav(self, wav_data: bytes):
        """WAVを仮想シンクに再生する(再生完了までawait)。再生中はBGMをダッキング"""
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            f.write(wav_data)
            wav_path = f.name
        try:
            self._set_bgm_volume(self.cfg.BGM_DUCK_PERCENT)
            proc = await asyncio.create_subprocess_exec(
                "paplay", "--device", self.sink, wav_path,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.PIPE,
            )
            _, stderr = await proc.communicate()
            if proc.returncode != 0:
                logger.error("paplay失敗: %s", stderr.decode(errors="replace").strip())
        finally:
            self._set_bgm_volume(self.cfg.BGM_VOLUME_PERCENT)
            Path(wav_path).unlink(missing_ok=True)
