"""VMCプロトコル(OSC/UDP)送信

nijiexpose / Inochi Session / VSeeFace などVMC対応アプリに、
ブレンドシェイプ値(口・まばたき・感情)と頭ボーンの回転を送る。

OSCのエンコードは依存ライブラリなしの最小実装。
仕様: https://protocol.vmc.info/ (Marionette向けメッセージ)
"""
import math
import socket
import struct
import time


def _pad4(data: bytes) -> bytes:
    return data + b"\x00" * ((4 - len(data) % 4) % 4)


def encode_message(address: str, *args) -> bytes:
    """OSCメッセージを1つエンコードする(int/float/str対応)"""
    tags = ","
    payload = b""
    for a in args:
        if isinstance(a, float):
            tags += "f"
            payload += struct.pack(">f", a)
        elif isinstance(a, bool):  # boolはintより先に判定
            raise TypeError("OSCにboolは送れません")
        elif isinstance(a, int):
            tags += "i"
            payload += struct.pack(">i", a)
        elif isinstance(a, str):
            tags += "s"
            payload += _pad4(a.encode("utf-8") + b"\x00")
        else:
            raise TypeError(f"未対応のOSC引数型: {type(a)}")
    return (
        _pad4(address.encode("ascii") + b"\x00")
        + _pad4(tags.encode("ascii") + b"\x00")
        + payload
    )


def encode_bundle(messages: list[bytes]) -> bytes:
    """OSCバンドル(即時実行タイムタグ)にまとめる"""
    out = _pad4(b"#bundle\x00") + struct.pack(">Q", 1)  # timetag=1: immediately
    for m in messages:
        out += struct.pack(">I", len(m)) + m
    return out


class VMCSender:
    """VMC Marionetteへ毎フレームの状態を送るUDPクライアント"""

    def __init__(self, host: str, port: int):
        self.addr = (host, port)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._t0 = time.monotonic()

    def send_frame(self, blends: dict[str, float], head_tilt_deg: float = 0.0):
        """1フレーム分のブレンドシェイプと頭ボーン回転を送信する

        Args:
            blends: ブレンドシェイプ名→値(0..1)。例 {"A": 0.6, "Blink": 0.0, "Joy": 1.0}
            head_tilt_deg: 首の傾き(Z軸回転, 度)
        """
        msgs = []
        for name, value in blends.items():
            msgs.append(encode_message(
                "/VMC/Ext/Blend/Val", name, float(max(0.0, min(1.0, value)))
            ))
        msgs.append(encode_message("/VMC/Ext/Blend/Apply"))

        # 頭ボーン: Z軸回転のクォータニオン
        rad = math.radians(head_tilt_deg)
        qz, qw = math.sin(rad / 2), math.cos(rad / 2)
        msgs.append(encode_message(
            "/VMC/Ext/Bone/Pos", "Head",
            0.0, 0.0, 0.0,          # 位置
            0.0, 0.0, float(qz), float(qw),  # 回転(クォータニオン)
        ))

        # 稼働情報(受信側のタイムアウト回避)
        msgs.append(encode_message("/VMC/Ext/OK", 1))
        msgs.append(encode_message("/VMC/Ext/T", float(time.monotonic() - self._t0)))

        try:
            self.sock.sendto(encode_bundle(msgs), self.addr)
        except OSError:
            pass  # 受信側不在は無視(UDPなので配信自体は継続)

    def close(self):
        self.sock.close()
