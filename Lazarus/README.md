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

現時点では設計合意用の文書のみです。動作するプロジェクトを置くのは、ロードマップ Phase 0 の
技術検証と ADR 承認後とします。未検証のライブラリ選定を初期ソースへ固定しないためです。
