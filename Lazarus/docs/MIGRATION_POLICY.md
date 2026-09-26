# zLog Lazarus Edition 移植・再設計方針

## 1. 目的と非目的

### 目的

* Windows / macOS で同一のコンテストロギング体験を提供する。
* 交信入力から保存までを止めず、長時間運用と高レート運用で予測可能に動作させる。
* UI、競技規約、デバイス、永続化を分離し、変更理由が一つの小さな単位へ整理する。
* zLog の日本国内コンテスト資産と操作速度を維持しつつ、現代的な発見可能性、アクセシビリティ、復旧性を加える。
* 将来のコンテスト定義、無線機、外部連携を本体改造なしで追加できる境界を作る。

### 非目的

* Delphi ソースや DFM を機械的に LCL へ変換すること。
* 初回リリースで既存の全ダイアログを再現すること。
* UI の見栄えのためにキーボード操作速度やログ安全性を犠牲にすること。
* Windows 固有 API を macOS 側で無理に模倣すること。

## 2. 現状調査から得た設計上の課題

リポジトリの静的棚卸しでは `zlog` 以下に Pascal 163 ファイル、DFM 381 ファイルがあり、
`main.pas` は約 16,000 行、`UzLogGlobal.pas` と `UzLogQSO.pas` は各約 5,000 行です。
また、多数の unit が VCL または Windows API、Registry、SetupAPI、OmniRig 等へ直接依存します。
これは品質評価ではなく、段階移行と境界設定が必要であることを示す指標です。

特に次を新設計へ持ち込まないようにします。

* 設定、UI 型、機器状態、競技状態を一つの global unit に集約する。
* QSO エンティティが表示文字列、旧バイナリ形式、ADIF、通信形式を同時に知る。
* 競技ルールの基底クラスが Form を所有し、得点ロジックから UI を生成する。
* フォーム間の global 参照とイベント順序を暗黙のアプリケーション状態にする。
* 固定長レコードのメモリ表現を、そのまま永続形式の契約にする。

## 3. ユーザーニーズの仮説と検証方法

zLog の既存機能と主要なコンテストロガーで一般的なワークフローから、以下を**仮説**とします。
製品要件として確定する前に、利用ログやアンケートではなく、実運用者への観察・インタビューで検証します。

### ペルソナ別 JTBD

| 利用者 | 達成したいこと | 最重要指標 |
|---|---|---|
| 初参加者 | 設定に迷わず正しい交信を記録・提出したい | 初回 QSO までの時間、入力エラー率 |
| zLog 熟練者 | 筋肉記憶を保ち、高レートでもキーボードだけで運用したい | QSO/時、キー操作数、回帰件数 |
| SO2R / DX 利用者 | 2 台の無線機、CW/Voice、spot を安全に連携したい | 応答遅延、誤送信・誤バンド率 |
| マルチオペ | 複数局のログと serial を衝突なく共有したい | 同期遅延、競合・欠落数、復旧時間 |
| 国内コンテスト利用者 | JARL 固有 exchange、マルチ、E-Log を正しく扱いたい | 参照実装との得点一致率 |
| 運営・開発者 | 規約変更と機種追加を安全かつ短期間で配布したい | 変更リードタイム、テスト網羅率 |

### 調査計画

* 初心者、熟練者、SO2R、マルチオペ、アクセシビリティ利用者を各 3 名以上募集する。
* セットアップ、CQ、S&P、訂正、障害復旧、提出までを画面共有で観察する。
* 「欲しい機能」より、直近の失敗、待ち時間、回避策、コンテスト中に触れない設定を聞く。
* 既存 zLog と他ロガーを同じ課題で比較し、キー数・所要時間・誤りを測る。
* 調査結果を `docs/research/` に匿名化して保存し、各機能に根拠と成功指標を紐付ける。

## 4. 機能ポートフォリオ

### MVP（競技中の中核）

1. コンテスト／部門／局情報を検証するセットアップウィザード
2. キーボード中心の QSO 入力、候補、重複警告、編集、取消／復元
3. 正確で説明可能な得点・マルチ計算（「なぜ 0 点か」を表示）
4. 自動保存、クラッシュ復旧、バックアップ、監査履歴
5. Hamlib CAT による周波数・モード追従（まず共通機種の一台運用）
6. CW/RTTY の送受信、メッセージと function key、packet cluster / spot
7. Cabrillo、ADIF、JARL E-Log の import/export と事前検証
8. rate、残り時間、band/mode、接続状態を一目で把握できる dashboard

### 次段階

* LAN マルチオペ（権威ノード不在時も記録し、再接続時に明示的に競合解決）
* SO2R / 2BSIQ の状態機械、安全 interlock、focus と送信先の強調
* spectrum/band map、RBN 信頼度、callsign history / super check
* 音声録音と QSO 時刻への索引、後日の照合
* contest definition と rig driver の署名付き拡張パッケージ
* 任意の live score 連携（同意、送信内容、停止状態を可視化）

CW/RTTY は外部アプリを呼び出す付加機能ではなく、独立した mode subsystem として実装します。特に RTTY は
MMTTY に依存せず、scalar reference DSP と CPU SIMD を基本に、必要性を計測できた処理だけ GPU backend を追加します。
詳細は [交信モードと CW / RTTY 送受信エンジン方針](MODE_ENGINE.md) を参照してください。

### 整理・廃止候補

LPT、古い Windows 音声 API、UI と密結合した DLL plugin、暗黙の registry 設定は直接移植しません。
利用実態、代替手段、データ移行を確認し、`retain / redesign / replace / retire` の台帳で判断します。

## 5. UX 方針

* **入力面を不動にする:** callsign、sent/received、mode/band、log action の位置を運用中に変えない。
* **段階的開示:** 初心者は必須項目のみ、熟練者は docking panel と command palette で拡張する。
* **状態を色だけに頼らない:** 接続、TX 対象、dupe、新マルチは文字・形・音でも区別する。
* **非破壊:** QSO 編集・削除は履歴付き。dangerous action は送信先を明示し、競技中の modal dialog を減らす。
* **キーボード第一:** 全主要操作に再割当可能な shortcut。IME 状態と focus を明示し、Tab 順を固定する。
* **高 DPI / theme:** OS 標準フォント、light/dark/high-contrast token、拡大しても情報を欠落させない layout。
* **楽しさ:** personal best、rate trend、new multiplier、進捗 milestone を控えめに称賛する。順位や spot 利用を強要せず、集中モードで完全に隠せる。
* **オンボーディング:** demo contest と simulated rig/cluster により、電波を出さずに一連の操作を練習できる。

CQRLOGの統合的なログ運用を参考にしたcallsign card、DX cluster/band map、grayline、QSL/award、online service、
接続センターの提案と、これらを非同期化する設計は
[CQRLOGを参考にした機能・UI・非同期実行の提案](CQRLOG_UX_PROPOSAL.md) にまとめます。

## 6. 品質・性能目標（受入基準）

測定環境は Phase 0 で最低構成 PC/Mac と fixture を固定します。

| 項目 | 目標 |
|---|---|
| callsign 入力から候補／dupe 表示 | p95 50 ms 以下（100,000 QSO） |
| Enter から durable journal 受付 | p95 20 ms 以下、UI block なし |
| QSO 一覧の scroll/filter | p95 frame 16 ms、virtualized view |
| 100,000 QSO の再集計 | 2 秒以下、進捗表示・取消可能 |
| 起動から入力可能 | warm start 2 秒以下 |
| 異常終了 | acknowledged QSO の欠落 0、次回起動で自動検出 |
| 通信断 | logging 継続、状態表示、指数 backoff、手動再接続可能 |
| 正確性 | golden corpus で既存確定結果と 100% 一致、差異は承認記録 |

最適化は計測後に行います。検索 index、incremental score、UI virtualisation、batching、immutable snapshot を
候補とし、共有可変状態や busy loop による見かけの高速化は禁止します。

## 7. セキュリティ、プライバシー、信頼性

* パスワード/token は OS credential store の adapter に保存し、平文設定へ書かない。
* 外部から得る spot、contest package、ネットワークメッセージを未信頼入力として長さ・文字・範囲を検証する。
* 自動更新と plugin は署名、version compatibility、rollback を備えるまで有効化しない。
* diagnostic bundle は preview と redaction を提供し、callsign、位置、token を利用者の同意なく送信しない。
* QSO は append-only journal を先行し、snapshot は再生成可能にする。backup/restore drill を release gate に含める。

## 8. 互換性方針

* 旧バイナリは専用 importer が byte 単位で読み、domain object へ変換する。domain は旧 record layout を知らない。
* ADIF/Cabrillo/JARL は別 adapter とし、round-trip と malformed input を fixture 化する。
* 文字コード、JST/UTC、周波数単位、丸め、QSO ID の仕様を文書化し、推測時は警告と原本保持を行う。
* import 前に必ず dry-run report、件数、警告、hash を表示する。原本を変更しない。

## 9. Definition of Done

各 feature は、ドメインテスト、adapter 契約テスト、Windows/macOS UI smoke test、keyboard/accessibility 確認、
性能 budget、利用者向け説明、migration/rollback を満たして初めて完了です。単に画面が表示された状態を
「移植済み」としません。
