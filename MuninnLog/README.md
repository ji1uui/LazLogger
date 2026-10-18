# MuninnLog

Windows / macOS 向けの、新しいアマチュア無線ロギングアプリです。Lazarus / Free Pascal で開発します。
日常の交信、国内外のコンテスト、FT8・RTTY・CW などのデジタル / 電信運用、POTA / SOTA を、一つのログブックで扱います。

現在は設計段階です。このディレクトリにはまだコードがありません。

## 名前と構成要素

| 名前 | 役割 |
|---|---|
| **MuninnLog** | アプリ本体。ログブック、プロファイル、UI、外部連携、プライバシー管理 |
| **Omoikane** | MuninnLog 内のコンテスト機能。規約適用、重複チェック、得点計算、提出用の出力、コンテスト後のログ編集 |
| **Yata Logic（.ylg）** | Omoikane が読み込む、コンテスト規約・アワード定義のパッケージ形式 |
| **HuginnEngine** | 外部の信号処理エンジン。CW / RTTY / PSK / FT4 / FT8 の変復調を担当し、MuninnLog とは `THuginnInterface` で連携する |
| **HamlibComponent** | 別途開発している Hamlib ラッパーの Lazarus パッケージ。MuninnLog の無線機ポートの背後で使う |

Huginn（思考）と Muninn（記憶）は、北欧神話でオーディンに仕える 2 羽のワタリガラスです。
信号を「聴いて考える」エンジンと、交信を「記憶する」ログブックという分担を表します。

## 文書

| 文書 | 内容 |
|---|---|
| [docs/00_DEVELOPMENT_POLICY.md](docs/00_DEVELOPMENT_POLICY.md) | **開発方針（正本）**。ビジョン、原則、2 つのアイデアの統合結果、ロードマップ、決定事項と未決事項 |
| [docs/05_DEVELOPMENT_PROCESS.md](docs/05_DEVELOPMENT_PROCESS.md) | 開発プロセス計画。作業の単位、ブランチと PR、AI エージェントとの協働、CI、テスト、外部コンポーネント連携、リリース、M0 の実行計画 |
| [docs/04_ARCHITECTURE.md](docs/04_ARCHITECTURE.md) | コンポーネント構成、HuginnEngine との境界、Omoikane と Yata Logic、CLI |
| [docs/03_DATA_MODEL.md](docs/03_DATA_MODEL.md) | データモデル（Person / Station / Location / Station Facility / Operation / QSO ほか） |
| [docs/02_PRODUCT_STRATEGY.md](docs/02_PRODUCT_STRATEGY.md) | 製品方針、他アプリから取り入れる点、デザイン原則 |
| [docs/01_CURRENT_STATE_REVIEW.md](docs/01_CURRENT_STATE_REVIEW.md) | 既存の `Lazarus/`（zLog Lazarus Edition 試作）のレビュー |
| [docs/ideas/](docs/ideas/) | 元になったアイデア文書（MuninnLog 構想書 v4.0、Omoikane 実装仕様書）。原文のまま保存 |
| [docs/references/](docs/references/) | 外部コンポーネントの資料（HamlibComponent README Rev.6.0）。原文のまま保存 |

## 予定しているディレクトリ構成

実装を始める時点で作成します。

```text
MuninnLog/
  docs/                 設計文書
  src/
    core/               ドメイン、ユースケース、ポート（LCL・OS・通信に依存しない）
    storage/            SQLite、マイグレーション、バックアップ
    omoikane/           コンテスト規約エンジン、Yata Logic ローダー
    integrations/       HuginnEngine、無線機、WSJT-X / fldigi、オンラインサービス、GPS
    ui/                 LCL の画面と Presenter
  app/
    gui/                GUI 版の起点（.lpi / .lpr）
    cli/                CLI 版の起点（GUI なしのバッチ処理）
  plugins/              Yata Logic の同梱パッケージ
  tests/                単体・結合・ゴールデンテスト
```

## 既存ディレクトリとの関係

- `Lazarus/`：zLog Lazarus Edition の試作。MuninnLog はここを拡張せず、再利用できる設計・コードだけを選んで持ち込みます（[01_CURRENT_STATE_REVIEW.md](docs/01_CURRENT_STATE_REVIEW.md) 第 7 節）。
- `zlog/` ほか：Delphi 版 zLog。仕様の参考として参照するだけで、変更しません。
