#!/usr/bin/env bash
# PulseAudio 仮想シンク(BGM+音声のミキシング先)を作成する。冪等。
set -euo pipefail

SINK_NAME="${MIX_SINK:-radio_mix}"

if ! command -v pactl >/dev/null; then
    echo "エラー: pactl が見つかりません (pulseaudio-utils をインストールしてください)" >&2
    exit 1
fi

# PulseAudioが起動していなければ起動 (pipewire-pulse環境ではそのまま通る)
if ! pactl info >/dev/null 2>&1; then
    pulseaudio --start --exit-idle-time=-1 || true
    sleep 1
fi

if pactl list short sinks | awk '{print $2}' | grep -qx "$SINK_NAME"; then
    echo "仮想シンク $SINK_NAME は既に存在します"
else
    pactl load-module module-null-sink \
        "sink_name=$SINK_NAME" \
        "sink_properties=device.description=$SINK_NAME"
    echo "仮想シンク $SINK_NAME を作成しました"
fi

# 誤って他アプリの音が配信に乗らないよう、既定シンクも仮想シンクにする
pactl set-default-sink "$SINK_NAME" || true
