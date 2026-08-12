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
- CPUアーキテクチャ: x64 / arm64 の両対応 (VOICEVOXはCPUアーキを自動判定して取得)
- メモリ 8GB以上推奨 (OBS + VOICEVOX + Ollamaを同居させるため)
- **ディスク空き 10GB以上** (VOICEVOX ENGINEのダウンロード+展開に約6GB使う)
- Python 3.10+

## インストール

以下はまっさらな Ubuntu Server (22.04 / 24.04) にSSH接続した状態を想定した手順です。
GUIは不要で、すべてコマンドラインで完結します。

### ステップ0: リポジトリの取得

```bash
# 作業場所へ (ホームディレクトリ直下に置く例)
cd ~

# リポジトリをクローン
git clone https://github.com/backslash0x5c/AIVtuber.git
cd AIVtuber
```

以降のコマンドはすべて `~/AIVtuber` ディレクトリ内で実行します。

### ステップ1: セットアップスクリプトの実行

```bash
./setup.sh
```

`setup.sh` が以下をすべて自動で行います(冪等なので途中で失敗しても再実行可):

1. APTパッケージ (ffmpeg, mpv, pulseaudio, xvfb, fonts-noto-cjk など)
2. OBS Studio (公式PPA)
3. Ollama
4. VOICEVOX ENGINE (Dockerがあれば初回起動時にイメージ取得、無ければ `scripts/install_voicevox.sh` がLinux CPU版をダウンロード)
5. Python仮想環境 (`venv/`) + 依存パッケージ
6. `.env` の生成 (obs-websocketパスワードを自動生成)
7. systemdユーザーユニットの配置 + linger有効化 (SSHを切っても動き続ける)

途中で `sudo` のパスワードを求められたら入力してください。回線状況によっては
OBS/Ollama/VOICEVOX のダウンロードに数分〜十数分かかります。

### ステップ2: LLMモデルの取得

```bash
# .env で指定したモデル (既定 gemma3:1b) を取得
ollama pull gemma3:1b
```

別のモデルを使いたい場合は、先に `.env` の `OLLAMA_MODEL` を書き換えてから
そのモデル名で `ollama pull` してください。

### ステップ3: YouTube配信情報の設定

YouTube Studio でライブ配信の枠を作成し、次の2つを取得します。

- **ビデオID**: ライブ配信URL `https://www.youtube.com/watch?v=XXXXXXXXXXX` の
  `XXXXXXXXXXX` 部分 (コメント取得に使用)
- **ストリームキー**: YouTube Studio →「ライブ配信」→「ストリーム」タブに表示される
  文字列 (配信先の指定に使用)

`.env` を編集して入力します。

```bash
nano .env
```

```ini
YOUTUBE_VIDEO_ID=XXXXXXXXXXX
YOUTUBE_STREAM_KEY=xxxx-xxxx-xxxx-xxxx-xxxx
```

`OBS_WS_PASSWORD` は `setup.sh` が自動生成済みなので、通常は触る必要はありません
(空欄だとOBSが起動しません)。話者やキャラクター設定など他の項目は任意で、
`.env.example` にすべて説明があります。

### ステップ4 (任意): BGMとアバターの配置

```bash
# BGM: 置かなくても声のみで配信は成立する。置くとシャッフルループ再生される
cp ~/music/*.mp3 bgm/

# アバター: 差分イラスト3枚 (base/mouth_open/eyes_closed) と puppet.json を置く
#   → 「2Dアバターと表情・感情」の章を参照。未設定でも音声のみで配信は動く
mkdir -p avatar/puppet
# (手元PCで用意したPNGとpuppet.jsonを scp などで avatar/puppet/ へ転送)
```

### ステップ5: 各サービスが起動できるか事前確認 (任意だが推奨)

本番起動の前に、依存サービスへ個別に疎通確認しておくと切り分けが楽です。

```bash
# 音声の仮想シンクを作成し、存在を確認
./scripts/setup_audio.sh
pactl list short sinks | grep radio_mix

# VOICEVOX を手動起動して疎通確認 (別ターミナル or 一時的に)
./scripts/run_voicevox.sh &
curl http://127.0.0.1:50021/version   # バージョンが返ればOK

# Ollama の疎通確認
curl http://127.0.0.1:11434/api/tags  # モデル一覧のJSONが返ればOK
```

確認できたら、手動起動したVOICEVOXは一旦停止して構いません (この後 systemd が管理します)。

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

### 初回起動後の確認

```bash
# 全ユニットが running / active になっているか
systemctl --user status 'radio-*' --no-pager

# 本体のログでエラーが出ていないか (Ctrl+Cで抜ける)
journalctl --user -u radio-app -f
```

正常なら本体ログに「初期化完了。コメント待機中...」と表示され、YouTube Studio 側の
プレビューに映像と音声が乗り始めます。オープニングの読み上げが聞こえれば
音声経路もOKです。映像や音が出ない場合は末尾の「トラブルシューティング」を参照してください。

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

描画は次の優先順で自動選択されます。**メインはレイヤードPNGパペット**で、アセット未設定のあいだは画面に案内プレースホルダーが表示されます(音声のみで配信自体は動きます)。

1. **Live2D** — `avatar/live2d/` にCubismモデル一式を置き、`.env` で指定:
   ```
   LIVE2D_MODEL=live2d/hiyori/hiyori.model3.json
   ```
   pixi-live2d-display で描画し、`ParamMouthOpenY` `ParamEyeLOpen` `ParamAngleZ` などの標準パラメータを上記のリグで駆動します。モデルに表情(.exp3.json)が定義されていれば感情名(happy等)での切り替えも試みます。
   モデルの入手先の例: [Live2D公式サンプルモデル集](https://www.live2d.com/learn/sample/)(桃瀬ひより等が無償配布)、BOOTHなどの販売モデル、Live2D Cubism Editorでの自作。ライセンス条件は各モデルの規約に従ってください。
   ※ Cubism CoreはLive2D公式CDNから実行時にロードするため、OBSのブラウザソースがインターネットに出られる必要があります(ライセンス上リポジトリに同梱できないため)
2. **レイヤードPNGパペット(メインの描画モード)** — お気に入りの絵柄のイラスト(自作・依頼・AI生成)をレイヤー分割したPNG群を `avatar/puppet/` に置くと、Live2D Editor なしでLive2D風に動きます。視差・首の傾き・呼吸・髪の揺れに加え、目・口・感情差分は**opacityクロスフェード**で滑らかに切り替わります。

   `avatar/puppet/puppet.json` の例:
   ```json
   {
     "layers": [
       {"src": "back_hair.png",    "depth": -0.3},
       {"src": "body.png"},
       {"src": "face.png",         "head": true},
       {"src": "eyes_open.png",    "head": true, "role": "eyes_open"},
       {"src": "eyes_closed.png",  "head": true, "role": "eyes_closed"},
       {"src": "mouth_closed.png", "head": true, "role": "mouth_closed"},
       {"src": "mouth_open.png",   "head": true, "role": "mouth_open"},
       {"src": "blush.png",        "head": true, "role": "blush"},
       {"src": "tears.png",        "head": true, "emotion": "sad"},
       {"src": "sparkle_eyes.png", "head": true, "emotion": "happy"},
       {"src": "front_hair.png",   "head": true, "depth": 0.15}
     ]
   }
   ```
   - 各PNGは**同じキャンバスサイズ**で透過書き出し(Krita/Photoshop/CLIP STUDIOのレイヤー書き出しでOK)
   - `head: true` = 頭と一緒に傾く・揺れる / 省略 = 体(揺れ弱め)
   - `depth` = 視差の強さ(奥は負、手前は正。前髪 0.1〜0.2 が目安)
   - `role` = `eyes_open` `eyes_closed` `mouth_open` `mouth_closed` `blush` — リップシンク・まばたき・頬の赤みをクロスフェードで駆動
   - `emotion` = `happy` `sad` `angry` `surprised` `shy` — その感情のときだけフェードインする差分レイヤー(涙・目の輝き・怒りマーク等)。LLMの感情タグと連動します
   - 最低構成は `face.png`(全身1枚でも可) + `mouth_open/closed` の3枚。目や差分は後から足せます

   配置後はチェックツールで検証できます:
   ```bash
   python3 scripts/validate_puppet.py
   ```
3. **PNG立ち絵** — `avatar/avatar_closed.png` / `avatar_open.png` の2枚だけでも動きます(素材の制約上、口パクのみ2値)

### 差分イラスト3枚方式 (推奨・いちばん簡単)

パーツの切り抜きは不要です。**同じ構図の差分イラストを全画像のまま**用意するだけで動きます。
プログラムが絵を描き足すことは一切なく、画面に映るのは用意したイラストそのものです。

1. 次の3枚を用意する(すべて同じキャンバスサイズ・同じ構図・背景透過PNG):
   - `base.png` — 口を閉じて目を開けた絵 (基本の立ち絵)
   - `mouth_open.png` — 口だけ開けた絵 (全画像のままでOK)
   - `eyes_closed.png` — 目だけ閉じた絵 (全画像のままでOK)

   差分の作り方: 絵師に差分込みで依頼する / ペイントソフトで口・目だけ描き替える /
   AI画像生成ならinpainting(部分再生成)で「口を開ける」「目を閉じる」と指定するのが確実です。
2. `avatar/puppet/` に置いて `puppet.json` を書く:
   ```json
   {
     "layers": [
       {"src": "base.png",        "head": true},
       {"src": "mouth_open.png",  "head": true, "role": "mouth_open"},
       {"src": "eyes_closed.png", "head": true, "role": "eyes_closed"}
     ]
   }
   ```
   差分同士は同じ絵なので、クロスフェードしても変化した部分(口・目)だけが動いて見えます。
3. `python3 scripts/validate_puppet.py` で確認し、`http://127.0.0.1:8500/` で動きを見る
   (SSHポートフォワード可)

補足:
- `eyes_closed.png` が全画像のままだと、発話中のまばたきの一瞬(約0.1秒)だけ口が閉じ絵に
  戻ります。気になる場合は、目の周り以外をざっくり消しゴムで消した透過PNGにしてください
  (正確な切り抜きは不要)
- 口を開けた絵しか無い場合は、それを `mouth_open.png` にして、inpainting等で
  口を閉じた版を作り `base.png` にするのが手数最少です

### パーツ分割方式 (視差で立体感を出したい場合)

レイヤーを細かく分けるほどLive2D的な奥行きが出ます。Krita / CLIP STUDIO / Photoshop で
パーツごとに分け、**キャンバスサイズのまま**透過PNG書き出しして、前述のレイヤー仕様
(`head` / `depth` / `role` / `emotion`)を `puppet.json` に書いてください。
(後ろ髪 / 体 / 顔 / 閉じた目 / 開いた口 / 閉じた口 / 前髪 など)

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

### まず状況をまとめて確認する

```bash
./scripts/diagnose.sh
```

各サービスの状態・OBSの有無とバージョン・待ち受けポート・Xvfb・OpenGL・
`radio-obs` と `radio-app` のログをまとめて出力します(鍵やパスワードの値は伏せられます)。

### 配信が始まらない / `ConnectionRefusedError` で OBS に繋がらない

アプリのログに `OBSが 127.0.0.1:4455 で待ち受けていません` と出る場合、
**OBS本体が起動できていません**(アプリ側の問題ではありません)。原因はOBSのログにあります。

```bash
journalctl --user -u radio-obs -n 50 --no-pager
```

よくある原因:

- **OBSは起動しているのにログが `Crash or unclean shutdown detected` で止まる** —
  OBSは起動時に `~/.config/obs-studio/.sentinel/run_<UUID>` を作り、正常終了時に
  消します。前回分が残っていると「前回異常終了しました」の**モーダルダイアログ**を
  表示して応答を待ちます。ヘッドレスでは誰も押せないため永久に固まり、
  obs-websocketも起動しません(CPU使用がほぼ0のまま、`systemctl stop` にも
  応答しないのが特徴)。しかも固まったOBSはSIGKILLで止めるしかなく、それが
  また痕跡を残すため、放置すると抜け出せません。
  `run_obs.sh` が起動前にこのファイルを削除します。手動で消す場合:
  ```bash
  systemctl --user stop radio-obs
  pkill -9 obs
  rm -f ~/.config/obs-studio/.sentinel/run_*
  systemctl --user start radio-obs
  ```
  ※ `--disable-shutdown-check` はOBS 32系のこのコードパスでは参照されないため
  効きません(センチネル自体を無効化するオプションも存在しません)。
- **OBSが数秒〜十数秒でクラッシュする(`GPU process isn't usable. Goodbye.`)** —
  ブラウザソースの中身はChromium(CEF)で、**root実行時は `--no-sandbox` が無いと
  子プロセスを起動できず**、OBSごと落ちます
  (`Running as root without --no-sandbox is not supported`)。
  `run_obs.sh` はroot実行を検出して自動で付与します。`git pull` 後に再起動してください。
  それでもGPUプロセスが落ちる場合は `.env` に次を追加します:
  ```ini
  OBS_EXTRA_ARGS=--disable-gpu
  ```
  (ただしWebGLがソフトウェア描画になるため、Live2Dを使う場合は動作を確認してください)
- **obs-websocketのサーバーが無効** — OBSは起動しているのに4455番が待ち受けに
  現れない場合はこれです。`--websocket_port` / `--websocket_password` は値を
  上書きするだけで**サーバーを有効化しません**(`server_enabled` の既定値は false)。
  `run_obs.sh` が起動時に
  `~/.config/obs-studio/plugin_config/obs-websocket/config.json` へ
  `server_enabled: true` を書き込むので、**OBSを再起動**してください:
  ```bash
  systemctl --user restart radio-obs
  ```
- **OBSが未インストール** — `command -v obs` で確認。arm64環境では公式PPAに
  パッケージが無いため、Ubuntu標準リポジトリ版が入っているか確認してください
- **OpenGLの初期化失敗** — GPU非搭載VPSでは `Failed to initialize video` 等で
  落ちることがあります。`sudo apt install -y mesa-utils libgl1-mesa-dri` を入れ、
  `DISPLAY=:99 glxinfo | grep "OpenGL version"` が返るか確認してください
  (`run_obs.sh` は `LIBGL_ALWAYS_SOFTWARE=1` を設定済みです)
- **Xvfbが動いていない** — `systemctl --user status radio-xvfb` を確認

### `.env` が無い / `OBS_WS_PASSWORD` が見つからない

`OBS_WS_PASSWORD` は **`setup.sh` がリポジトリ直下の `.env` に自動生成**します
(`.env.example` をコピーして 24文字のランダム文字列を書き込む)。
OBSにはCLI引数 `--websocket_password` で渡されるので、**OBS側の設定作業は不要**です。

```bash
# 生成された値の確認
grep OBS_WS_PASSWORD ~/AIVtuber/.env
```

`.env` 自体が無い場合、**`setup.sh` が途中で失敗して `.env` 作成まで到達していません**。
`setup.sh` は冪等なので、原因を解消してから再実行すれば作成されます。

```bash
cd ~/AIVtuber && ./setup.sh
```

手動で作る場合は以下でも同じです。

```bash
cp .env.example .env
WS_PW=$(head -c 256 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-24)
sed -i "s/^OBS_WS_PASSWORD=.*/OBS_WS_PASSWORD=$WS_PW/" .env
grep OBS_WS_PASSWORD .env   # 24文字入っていることを確認
```

値は自分で決めた文字列でも構いません(OBSと本アプリが同じ値を使えばよいだけです)。
変更した場合は `systemctl --user restart radio-obs radio-app` で再起動してください。

### VOICEVOXのインストールが `curl: (23) Failure writing output to destination` で失敗する

ダウンロード先の**空き容量が尽きた**ときのエラーです(多くはRAM上の `/tmp` が満杯)。
本スクリプトは作業ディレクトリをリポジトリ配下(永続ディスク)に置き、不要な `.vvpp` は
取得しないので、最新版に更新してから再実行してください。

```bash
# 空き容量の確認 (10GB以上が望ましい)
df -h ~ /tmp

# 失敗した残骸を掃除
rm -rf ~/AIVtuber/.voicevox_dl /tmp/tmp.*   # /tmp.* は自分の作業残骸のみ

# 最新スクリプトに更新して再実行
cd ~/AIVtuber && git pull
./scripts/install_voicevox.sh
```

ディスクを増やせない場合は、別の大きいディスクに逃がせます:

```bash
VOICEVOX_DL_DIR=/mnt/data/voicevox_dl ./scripts/install_voicevox.sh
```

Dockerが使える環境なら、そもそもこのダウンロードは不要です(初回起動時に
`scripts/run_voicevox.sh` がイメージを取得します。ただしイメージのarm64対応は要確認)。

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
AIVtuber/
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
