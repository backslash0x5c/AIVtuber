#!/usr/bin/env python3
"""avatar/puppet/ のパペットアセットを検証するツール

使い方:
    python3 scripts/validate_puppet.py

チェック内容:
  - puppet.json が正しいJSONか
  - 各レイヤーPNGが存在するか
  - 全レイヤーのキャンバスサイズが一致しているか
  - role / emotion の値が有効か
  - 口・目のペア (open/closed) が揃っているか
"""
import json
import struct
import sys
from pathlib import Path

PUPPET_DIR = Path(__file__).resolve().parent.parent / "avatar" / "puppet"
VALID_ROLES = {"eyes_open", "eyes_closed", "mouth_open", "mouth_closed", "blush"}
VALID_EMOTIONS = {"neutral", "happy", "sad", "angry", "surprised", "shy"}


def png_size(path: Path) -> tuple[int, int] | None:
    """PNGヘッダから (width, height) を読む"""
    with open(path, "rb") as f:
        header = f.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        return None
    width, height = struct.unpack(">II", header[16:24])
    return width, height


def main() -> int:
    errors: list[str] = []
    warnings: list[str] = []

    spec_path = PUPPET_DIR / "puppet.json"
    if not spec_path.exists():
        print(f"エラー: {spec_path} がありません")
        print("README「2Dアバターと表情・感情」のレイヤー仕様を参照して作成してください")
        return 1

    try:
        spec = json.loads(spec_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(f"エラー: puppet.json がJSONとして不正です: {e}")
        return 1

    layers = spec.get("layers")
    if not isinstance(layers, list) or not layers:
        print("エラー: puppet.json に layers 配列がありません")
        return 1

    sizes: dict[tuple[int, int], list[str]] = {}
    roles_seen: set[str] = set()

    for i, layer in enumerate(layers):
        name = layer.get("src", f"(index {i})")
        if "src" not in layer:
            errors.append(f"layers[{i}]: src がありません")
            continue

        path = PUPPET_DIR / layer["src"]
        if not path.exists():
            errors.append(f"{name}: ファイルが存在しません")
            continue
        size = png_size(path)
        if size is None:
            errors.append(f"{name}: PNGとして読めません")
            continue
        sizes.setdefault(size, []).append(name)

        role = layer.get("role", "")
        if role:
            if role not in VALID_ROLES:
                errors.append(f"{name}: 不明なrole '{role}' (有効: {', '.join(sorted(VALID_ROLES))})")
            roles_seen.add(role)

        emotion = layer.get("emotion", "")
        if emotion and emotion not in VALID_EMOTIONS:
            errors.append(f"{name}: 不明なemotion '{emotion}' (有効: {', '.join(sorted(VALID_EMOTIONS))})")

    if len(sizes) > 1:
        detail = " / ".join(f"{w}x{h}: {', '.join(names)}" for (w, h), names in sizes.items())
        errors.append(f"レイヤーのキャンバスサイズが揃っていません ({detail})")

    for a, b in (("mouth_open", "mouth_closed"), ("eyes_open", "eyes_closed")):
        if (a in roles_seen) != (b in roles_seen):
            warnings.append(f"{a} と {b} は片方だけだとクロスフェードできません")
    if "mouth_open" not in roles_seen:
        warnings.append("mouth_open レイヤーが無いため口パクしません")
    if "eyes_open" not in roles_seen:
        warnings.append("eyes_open レイヤーが無いためまばたきしません")

    for e in errors:
        print(f"エラー: {e}")
    for w in warnings:
        print(f"警告: {w}")
    if not errors:
        size = next(iter(sizes), None)
        print(f"OK: {len(layers)}レイヤー" + (f" ({size[0]}x{size[1]})" if size else ""))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
