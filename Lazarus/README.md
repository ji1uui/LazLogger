# zLog Lazarus Edition（仮称）

このディレクトリは、既存の Delphi/VCL 版をコピーして条件コンパイルを増やす場所ではなく、
Windows と macOS を同じドメインモデルで支える **新規実装** の起点です。既存版は移行期間中も
保守し、ファイル互換性と競技結果を比較する参照実装として扱います。

## まず読む文書

* [移植・再設計方針](docs/MIGRATION_POLICY.md) — 目的、設計原則、機能範囲、UX、性能、段階移行
* [アーキテクチャ](docs/ARCHITECTURE.md) — 依存方向、コンポーネント境界、並行処理、永続化
* [交信モード／CW・RTTYエンジン](docs/MODE_ENGINE.md) — Hamlib連携、送受信、DSP、遅延・安全性
* [CQRLOGを参考にしたUX提案](docs/CQRLOG_UX_PROPOSAL.md) — 機能候補、画面構成、thread/process分離
* [実施ロードマップ](docs/ROADMAP.md) — フェーズ、完了条件、リスク、意思決定ゲート
* [開発実行計画](docs/DEVELOPMENT_PLAN.md) — 実装順、反復ごとの検証、品質ゲート、進捗管理

## 想定ツールチェーン

* Lazarus / Free Pascal（採用バージョンは Phase 0 で固定）
* LCL。Windows は win32/Win64 widgetset、macOS は Cocoa widgetset
* FPCUnit（ドメイン／ユースケース／アダプターの自動テスト）

## 新規ソースの配置規約

```text
Lazarus/
  app/                 # composition root と .lpi/.lpr（UI から唯一の起動点）
  src/
    domain/            # 純粋 Pascal。LCL、OS、通信、ファイル API を参照しない
    application/       # ユースケース、ポート(interface)、DTO
    infrastructure/    # DB、設定、ネットワーク、時計、ログ実装
    platform/          # windows/ と macos/ のデバイス実装
    presentation/      # LCL Form/Frame、Presenter/ViewModel
  tests/
    unit/              # 高速で決定的なテスト
    integration/       # DB・ファイル・プロトコルの契約テスト
    golden/            # 既存 zLog と結果を比較する fixture
  resources/           # アイコン、翻訳、テーマ（コードと分離）
  docs/
```

ユニット名は `ZLog.<Layer>.<Feature>`、型は PascalCase、interface は `I` 接頭辞を用います。
フォームイベントには表示処理だけを置き、得点計算、重複判定、保存、無線機制御を記述しません。

## 着手時の原則

1. 先に既存ログの読込、重複判定、得点計算を golden test で固定する。
2. `domain -> application -> adapters -> presentation` の依存方向を逆転させない。
3. OS／機器差は interface の背後へ隔離し、macOS で利用不能な機能は明示的な capability として表示する。
4. UI スレッドを通信・保存・集計でブロックしない。
5. 一括置換や DFM→LFM 変換ではなく、縦に薄い機能単位で完成させる。

## 現在の実装

最初の縦割りとして、pure Pascalのcallsign／周波数value object、QSO entity、`ILogQsoUseCase`、repository／clock／IDの
port、in-memory adapter、決定的なunit test、console composition rootを追加しました。LCL画面や永続journalへ進む前に、
UIやOSへ依存しないdomain/application境界を実行可能な形で固定するためです。

次のincrementとしてversion付きbinary payload、CRC32、明示的little-endian encodingを使うappend-only journal adapterを
追加しました。各QSOはflush完了後にだけ受付済みとなり、起動時には完全なrecordだけを再生してprocess停止で残った
末尾の不完全recordを切り詰めます。取得したQSOはrepository内部状態ではなくowned snapshotです。
Callsignとexchangeはdomain内で`UnicodeString`として保持し、journal境界で明示的にUTF-8へ変換するため、日本語を含む
国内contest exchangeもOSのANSI code pageに依存せず再生できます。

console composition rootは現在、実運用時刻をUnix millisecondで返すclock、GUID based ID generator、journal repositoryを
組み立てます。このため`make run`を繰り返しても以前のQSOを再生し、一意なIDで新しいQSOを追記します。

`.github/workflows/lazarus-core.yml`はUbuntu、macOS、WindowsでFree Pascalのcore testをbuildし、journal demoを2回実行して
再起動後の追記を確認します。Pascal実装とは独立したPython parserで件数、record境界、CRC、payloadを照合し、Linuxでは
durable appendのp95/max latencyをJSON artifactとして保存します。LCL導入まではpure Pascal境界を3 OSで継続検証します。

presentationの最初のsliceとして、LCL controlを直接参照しないQSO entry Presenterとimmutable view stateを追加しました。
Presenterはrepositoryを呼ばず、即座に戻る`IQsoSubmissionPort`へdraftを渡します。送信中の二重登録防止、field別validation
feedback、耐久保存の完了通知を受けてからcallsignをclearする状態遷移を先に固定しています。

Submissionのinfrastructure sliceとして、容量を必須指定するthread-safe queueとsingle-consumer work pumpを追加しました。
UI側の`Submit`はmemory queueへの追加だけを行い、repository use caseはworker側の`ProcessNext`で実行します。満杯、cancel、
worker内部障害を型付き結果としてdispatcherへ渡し、無制限queueやUI threadでのjournal flushを防止します。

repositoryのquery viewはsorted ID indexを使い、従来の全件線形探索を廃止しました。CIでは100,000 QSOの追加と10,000件の
分散lookupを測定し、journalのdurable appendとは別のJSON baselineとして保存します。

single-consumer work pumpを所有する停止・join可能なworker threadと、完了通知を蓄えてUI threadから件数制限付きで
drainするcompletion dispatcherを追加しました。workerはrepository処理中にLCL/Viewへ触れず、UI側は1 frameで処理する
completion数を制限できます。shutdownは新規受付停止、worker join、未開始itemのcancelの順に実行します。

Free Pascalがインストール済みの環境では次を実行します。

```bash
make test
make test-tools
make run
make benchmark
make benchmark-memory
make gui
```

`make gui`はLazarus/LCLが導入済みの環境で、最小QSO Entry画面をbuildします。画面はcode-created LCL controlだけを持ち、
Presenterへ入力を渡します。Journal flushはworker threadで実行し、空だったcompletion queueへ結果が入った時だけ
`Application.QueueAsyncCall`を予約します。UI callbackは最大16件ずつ処理し、未処理分だけ次のcallbackを予約するため、
定期pollingによる不要なwake-upと一度の大量描画を避けます。

次は開発実行計画のStep 1を継続し、completion queueのbackpressure/telemetry、kill-pointを全書込境界へ広げた別process
recovery test、QSO Entryのkeyboard/high-DPI/accessibility testを追加します。
