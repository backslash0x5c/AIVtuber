# 24時間AITuberラジオ配信システム

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/license/apache-2-0)
[![Python](https://img.shields.io/badge/python-3.10+-blue.svg)](https://www.python.org/)
[![Platform: Ollama](https://img.shields.io/badge/Platform-Ollama-green.svg)](https://ollama.com/)
[![Voice: VOICEVOX](https://img.shields.io/badge/Voice-VOICEVOX-brightgreen.svg)](https://voicevox.hiroshiba.jp/)
[![OBS](https://img.shields.io/badge/Encoder-OBS%20Studio-302E31.svg)](https://obsproject.com/)

Ubuntu Server (GUIなし・SSHのみ) 上で完結する、YouTube 24時間AIラジオ配信システムです。

```
YouTubeコメント/スパチャ取得 (pytchat)
        ↓
ローカルLLMで返答生成 (Ollama / gemma3:1b)
        ↓
音声合成 (VOICEVOX ENGINE)
        ↓
PulseAudio仮想シンクへ再生 ←──同時に──→ BGM (mpvループ再生)
        ↓  (OSレベルでミキシング・発話中はBGM自動ダッキング)
OBS (Xvfb上でヘッドレス常駐・obs-websocketでCLI制御)
  ├─ 音声: 仮想シンクのモニターをキャプチャ
  └─ 映像: 2Dアバターページ(ブラウザソース: 口パク/字幕/コメント表示)
        ↓
YouTube Live (RTMP)
```

## 旧実装の問題と解決策

旧実装は**発話のたびに配信用ffmpegプロセスを終了→再起動**していたため、

- 発話のたびにRTMP接続が切れて配信が不安定になる
- VOICEVOX音声とBGMの同時再生が構造的に不可能

という問題がありました。新実装では **エンコーダ(OBS)は一度も再起動しません**。

1. PulseAudioの**null sink (`radio_mix`)** を常設する
2. BGMはmpvが `radio_mix` へ**常時ループ再生**する
3. VOICEVOXの音声はpaplayで同じ `radio_mix` へ再生する → **ミキシングはOSが行う**
4. 発話中は `pactl` でBGMのsink-input音量だけを下げる(**ダッキング**)、発話終了で戻す
5. OBSは `radio_mix.monitor` を音声ソースとして**常時配信し続ける**

## システム要件

- Ubuntu Server 22.04 / 24.04 (GUI不要、SSH接続のみで運用可能)
- メモリ 8GB以上推奨 (OBS + VOICEVOX + Ollamaを同居させるため)
- Python 3.10+

## インストール

```bash
git clone <repository-url>
cd radio-streaming
./setup.sh
```

`setup.sh` が以下をすべて行います(冪等なので再実行可):

1. APTパッケージ (ffmpeg, mpv, pulseaudio, xvfb, fonts-noto-cjk など)
2. OBS Studio (公式PPA)
3. Ollama
4. VOICEVOX ENGINE (Dockerがあれば初回起動時にイメージ取得、無ければ `scripts/install_voicevox.sh` がLinux CPU版をダウンロード)
5. Python仮想環境 + 依存パッケージ
6. `.env` の生成 (obs-websocketパスワードを自動生成)
7. systemdユーザーユニットの配置 + linger有効化 (SSHを切っても動き続ける)

### セットアップ後の設定

```bash
# LLMモデルの取得
ollama pull gemma3:1b

# 必須設定の入力
nano .env
#   YOUTUBE_VIDEO_ID=<ライブ配信のビデオID>
#   YOUTUBE_STREAM_KEY=<YouTube Studioの配信キー>

# BGMを置く(任意。無ければ声のみで配信される)
cp ~/music/*.mp3 bgm/
```

## 起動・停止

```bash
# 一括起動 (Xvfb → 仮想シンク → VOICEVOX → OBS → BGM → 本体)
systemctl --user start radio.target

# 状態確認
systemctl --user status 'radio-*'

# メインアプリのログを追う
journalctl --user -u radio-app -f

# 一括停止
systemctl --user stop radio.target

# OS起動時に自動起動 (setup.shでenable済み)
systemctl --user enable radio.target
```

デバッグ時は本体だけ手動起動もできます: `./run.sh`

## 動作の流れ

- 起動するとOBSにシーン(`Radio`)・ブラウザソース(アバター)・音声キャプチャ(`radio_mix.monitor`)・配信先(YouTube RTMP)を**obs-websocket経由で自動構築**し、配信を開始します
- コメントが来ると LLM→VOICEVOX→読み上げ、画面にコメントカードと字幕を表示し、アバターが口パクします
- **スーパーチャットは優先キュー**で必ず処理し、金額に触れて感謝します
- コメントが `IDLE_CHAT_INTERVAL` 秒(既定180秒)無いと自動で雑談します
- 30秒ごとにOBSの配信状態を監視し、落ちていれば自動で配信を再開します
- YouTubeチャット切断時は指数バックオフで自動再接続します

## カスタマイズ

### キャラクター

- 名前: `.env` の `CHARACTER_NAME`
- 性格・口調: リポジトリ直下に `persona.txt` を置くとシステムプロンプトを丸ごと差し替えられます (`{name}` がキャラ名に展開されます)

### 2Dアバターと表情・感情

アバターは静止画ではなく、**連続値パラメータ**(口の開き・口角・目の開き・眉・頬・首の傾き・視線)を毎フレーム補間して動くリグです。コマ送りではなく滑らかに変化します。

- **リップシンク**: VOICEVOXが生成したWAVからサーバ側で音量エンベロープ(50ms刻み)を抽出し、実際の音声に同期して口の開き具合が連続的に追従します
- **感情表現**: LLMが返答の先頭に感情タグ(`[happy]` `[sad]` `[angry]` `[surprised]` `[shy]`)を付け、それに応じて表情プリセットへ滑らかに遷移します(タグは読み上げ・字幕から除去)。一定時間後にneutralへ自然に戻ります

描画は次の優先順で自動選択されます:

1. **Live2D** — `avatar/live2d/` にCubismモデル一式を置き、`.env` で指定:
   ```
   LIVE2D_MODEL=live2d/hiyori/hiyori.model3.json
   ```
   pixi-live2d-display で描画し、`ParamMouthOpenY` `ParamEyeLOpen` `ParamAngleZ` などの標準パラメータを上記のリグで駆動します。モデルに表情(.exp3.json)が定義されていれば感情名(happy等)での切り替えも試みます。
   ※ Cubism CoreはLive2D公式CDNから実行時にロードするため、OBSのブラウザソースがインターネットに出られる必要があります(ライセンス上リポジトリに同梱できないため)
2. **PNG立ち絵** — `avatar/avatar_closed.png` / `avatar_open.png` の2枚を置くと使われます(素材の制約上、口パクのみ2値)
3. **内蔵SVGキャラ** — 何も置かなくても動く既定モード。上記パラメータをすべてSVGの形状に反映(口のパスは開き+口角から毎フレーム再計算)

レイアウトや配色は `avatar/index.html` を直接編集してください。
確認はローカルで `http://127.0.0.1:8500/` を開くだけです(SSHポートフォワード可)。

### 音声

```bash
# 話者一覧
curl -s http://127.0.0.1:50021/speakers | python3 -m json.tool
```

`.env` の `VOICEVOX_SPEAKER_ID` / `VOICEVOX_SPEED` を変更します。

### BGMと音量バランス

- `bgm/` に mp3/ogg/wav/flac/m4a/opus を置くとシャッフルループ再生されます
- 発話中のBGM音量は `BGM_DUCK_PERCENT` (既定25%) で調整します

## トラブルシューティング

### 音が配信に乗らない

```bash
# 仮想シンクの存在確認
pactl list short sinks | grep radio_mix

# 手動でテスト音を流す (配信に音が乗ればOK)
paplay --device=radio_mix /usr/share/sounds/alsa/Front_Center.wav
```

### OBSに接続できない

```bash
systemctl --user status radio-obs
journalctl --user -u radio-obs -n 50
# Xvfbが先に起動しているか
systemctl --user status radio-xvfb
```

`.env` の `OBS_WS_PASSWORD` が空だとOBSは起動しません(`setup.sh` が自動生成します)。

### ブラウザソースで日本語が「豆腐」になる

`fonts-noto-cjk` がインストールされているか確認してください(`setup.sh` に含まれています)。

### VOICEVOX / Ollama に接続できない

```bash
curl http://127.0.0.1:50021/version   # VOICEVOX
curl http://127.0.0.1:11434/api/tags  # Ollama
journalctl --user -u radio-voicevox -n 50
```

### SSHを切ると止まる

```bash
sudo loginctl enable-linger $USER
```

### 配信が始まらない

- `YOUTUBE_STREAM_KEY` が正しいか、YouTube Studio側で配信枠が作られているか確認
- `journalctl --user -u radio-app -f` で `配信を開始します...` の後のエラーを確認

## ファイル構成

```
radio-streaming/
├── app/                      # メインアプリ (Python / asyncio)
│   ├── main.py               #   オーケストレータ・死活監視
│   ├── config.py             #   .env 読み込み
│   ├── chat_source.py        #   YouTubeコメント/スパチャ取得 (優先キュー)
│   ├── llm.py                #   Ollamaクライアント (返答/雑談生成・読み上げ用整形)
│   ├── tts.py                #   VOICEVOXクライアント
│   ├── audio.py              #   PulseAudioミキシング・BGMダッキング
│   ├── obs_controller.py     #   obs-websocketでシーン構築・配信制御
│   ├── overlay_server.py     #   アバターページ配信 + WebSocket
│   └── prompts.py            #   キャラクター設定プロンプト
├── avatar/index.html         # 2Dアバター/字幕/コメントオーバーレイ
├── bgm/                      # BGMファイル置き場
├── scripts/                  # 各サービスのCLIラッパー
├── systemd/user/             # systemdユーザーユニット
├── setup.sh                  # セットアップスクリプト
├── run.sh                    # 手動起動 (デバッグ用)
└── .env.example              # 設定テンプレート
```

## ライセンス

Apache License 2.0 — 詳細は [LICENSE](LICENSE) を参照してください。
VOICEVOXで生成した音声の利用規約は[VOICEVOX公式](https://voicevox.hiroshiba.jp/)に従ってください。
