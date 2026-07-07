# 2Dモーフィング/アバター駆動ソフト調査 (2026年7月時点)

イラスト・素材は自前で用意する前提で、AITuber配信システムに組み込める
2Dモーフィング技術の選択肢・商用条件・料金をまとめる。

## 比較表

| 技術 | 種別 | 対応OS | 商用利用 | 費用の目安 | 本システムとの統合 |
|---|---|---|---|---|---|
| Live2D Cubism | 業界標準・プロプライエタリ | Editor: Win/Mac<br>SDK: Web/Native/Unity | 条件付き可(下記) | Editor PRO 月2,288円〜(個人)<br>SDK: 小規模無償 | **実装済み** (Webランタイム) |
| Inochi2D系<br>(nijigenerate/nijiexpose) | オープンソース(BSD-2) | Win/**Linux**/Mac | 制限なし | 無料 | 中程度の工数で可能 |
| VTube Studio | Live2Dモデル用配信アプリ | Win/Mac/iOS/Android | 収益化配信は有料版必須 | PC: DLC 1,520円<br>iOS 3,500円 / Android 1,690円 | 不可(Linux非対応) |
| nizima LIVE | Live2D公式配信アプリ | Win/Mac/iOS | 収益化配信は有料プラン | 月550円(年商1000万未満) | 不可(Linux非対応) |
| E-mote / えもふり | プロプロライエタリ(ADV/ゲーム向け) | Editor: Win | 個人・同人のみ無償商用可 | 個人無料 / 法人30万円/年 | 弱い(配信向けランタイムなし) |
| Spine | ゲーム向け2Dスケルタル | Win/Linux/Mac | 可(Editorライセンス必須) | Essential/Professional買切り<br>年商$500k超はEnterprise | 可能だがVTuber向きでない |

## 各論

### Live2D Cubism (最有力・実装済み)

- **Editor** (モデル制作、Win/Mac): FREE版は機能制限あり。PRO版は個人・小規模事業者
  (直近年商1000万円未満)で月2,288円、年間プランで実質月1,309円。年商1000万円以上は
  for business価格。セール(20%OFF等)が定期的にある。
- **SDK** (モデルを動かすランタイム): ダウンロード・開発は無償。作品を「出版」する際、
  個人・小規模事業者(年商1000万円未満)は出版許諾契約が不要=無償。
- **重要な注意 — 拡張性アプリケーション**: 「複数モデルを追加・差し替えできるアバター
  システム・配信アプリ・動画生成ツール」等は*拡張性アプリケーション*と定義され、
  **事業規模にかかわらず事前申請とLive2D社の承認・個別契約が必要**。
  - 本システムのように*自分専用・非配布*のツールで自作/購入モデルを配信する用途は、
    一般的な映像出版に近い扱いと考えられるが、グレーゾーンではあるので
    本格運用前にLive2D社へ確認するのが安全。
  - このリポジトリのように*ツール自体を公開*する場合、SDK本体(Cubism Core)を同梱せず
    利用者が各自ロードする形にしてある(現在の実装はCDNロード方式でこれを満たす)。
- モデル入手: 公式サンプル(桃瀬ひより等・無償)、nizimaやBOOTHで購入、Editorで自作。
  モデルごとの利用規約(配信可・商用可)は別途確認が必要。

### Inochi2D系: nijigenerate / nijiexpose / nijilive (OSS本命)

- Inochi2Dから2024年頃フォークされた **nijigenerate**(エディタ) / **nijiexpose**(配信用) /
  **nijilive**(ランタイムライブラリ) が現在活発に開発されている。旧Inochi Creator/Session
  も入手可能。
- ライセンスは BSD 2-clause。**無料・商用利用の制限なし・売上規模の条件なし**。
- **Linuxネイティブ対応**が最大の強み(VTube Studioとの決定的な違い)。
- PSDからのインポートでメッシュ変形ベースのリグを組む(Live2D Editorに近いワークフロー)。
- 本システムへの統合案: VPS上で nijiexpose をXvfb内で起動し、OBSのウィンドウキャプチャで
  取り込む。トラッキング入力はVMCプロトコル(OSC)を受けられるため、本アプリから
  口パク/まばたき/首の傾きをVMCで送る実装を足せば連動できる(中程度の工数)。
  Webブラウザ内ランタイム(WASM)は実験段階のため、ブラウザソース方式はまだ非推奨。

### VTube Studio (参考: VPSでは使えない)

- Live2Dモデル用の定番配信アプリ。Windows/macOS/iOS/Android のみで**Linux非対応**のため
  ヘッドレスVPS構成では使えない(自宅PC配信に切り替える場合の選択肢)。
- PC版は無料+ウォーターマーク除去DLC 1,520円。スマホPro版: iOS 3,500円 / Android 1,690円。
- 商用利用は可だが、**収益化配信(スパチャ等)では有料版/有料DLCの購入が必要**。
  前会計年度の総収入が20万米ドル超の法人は別途企業ライセンス。

### nizima LIVE (参考: VPSでは使えない)

- Live2D公式のトラッキング配信アプリ(Win/Mac/iOS)。Linux非対応。
- 無料版はカメラ連続40分などの制限。有料は年商1000万円未満で月550円、
  1000万円以上で月3,300円。**年商2000万円以上は個別契約**。
- 投げ銭が発生する配信は商用利用扱い=有料プラン必須。

### E-mote / えもふり

- ADVゲーム・ノベルゲーム向けの2Dモーフィング。えもふり(無料版)は
  **個人・同人に限り商用利用可**(法人不可、画像サイズ制限あり)。
  インディーズプラン(年商1000万円未満)無料、中・大企業は30万円/年。
- リアルタイム配信向けのランタイム/トラッキング統合が弱く、VTuber用途には不向き。

### Spine

- ゲーム向け2Dスケルタルアニメーションの定番。Editorは買切り
  (Essential/Professional、価格は公式購入ページ参照)。年商50万米ドル超は
  Enterpriseライセンス必須。ランタイムは公式多数(Webあり)だがEditorライセンス保持が
  利用条件。表情モーフィングよりボーンアニメ向きで、VTuber配信用途のエコシステムはない。

## 推奨

1. **Live2D (実装済みのWebランタイム)** — モデルを購入/依頼/自作して `LIVE2D_MODEL` に
   設定するだけ。個人運用(年商1000万円未満)なら追加費用なし。Editorで自作する場合のみ
   PRO版(月1,309円〜)を検討。本格収益化の前に「拡張性アプリケーション」該当性を
   Live2D社に確認するのが安全。
2. **完全OSSで固めたい場合: nijigenerate + nijiexpose** — 費用ゼロ・商用制限ゼロ・
   Linuxネイティブ。統合(Xvfb + OBSウィンドウキャプチャ + VMC送信)の実装が必要。
3. VTube Studio / nizima LIVE はモバイル・自宅PC配信では優秀だが、
   ヘッドレスLinux VPSという本システムの前提では選択肢にならない。

## 出典

- Live2D 料金/比較: https://www.live2d.com/en/cubism/comparison/ , https://subscbox.com/lv2dprofree-hoho/
- Live2D SDKライセンス: https://www.live2d.com/en/sdk/license/ , https://www.live2d.com/en/sdk/license/expandable/
- 拡張性アプリケーション申請: https://www.live2d.jp/application-publication-license/
- Inochi2D: https://inochi2d.com/ , https://docs.inochi2d.com/en/latest/inochi2d/faq.html
- nijigenerate/nijiexpose: https://github.com/nijigenerate/nijigenerate , https://github.com/nijigenerate/nijilive
- VTube Studio: https://store.steampowered.com/app/1325860/VTube_Studio/
- nizima LIVE 料金: https://nizimalive.com/pricing/
- E-mote: https://emote.mtwo.co.jp/support/faq/ , https://emote.mtwo.co.jp/products/
- Spine: https://esotericsoftware.com/spine-purchase , https://en.esotericsoftware.com/spine-editor-license
