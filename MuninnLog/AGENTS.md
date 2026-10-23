# MuninnLog 開発エージェント向け指示書

このファイルは、MuninnLog を開発する AI コーディングエージェント（Claude Code、Codex など）と人の開発者が守る規則です。
Claude Code は `CLAUDE.md` 経由でこのファイルを読み込みます。

## 1. 作業を始める前に読むもの

| 文書 | 読む理由 |
|---|---|
| [docs/00_DEVELOPMENT_POLICY.md](docs/00_DEVELOPMENT_POLICY.md) | 決定事項（D 番号）、未決事項（Q 番号）、ロードマップ、品質ゲート |
| [docs/05_DEVELOPMENT_PROCESS.md](docs/05_DEVELOPMENT_PROCESS.md) | 作業の単位、完了の条件、ブランチと PR の規則 |
| [docs/04_ARCHITECTURE.md](docs/04_ARCHITECTURE.md) | コンポーネントの責務と境界 |
| [docs/03_DATA_MODEL.md](docs/03_DATA_MODEL.md) | データモデル |
| 担当する Issue | 目的、範囲、完了条件 |

文書と既存のコードを確認してから変更する。存在しない API、型、ユニット、仕様を推測で使わない。

## 2. ディレクトリと依存の向き

```text
app/gui ─┐
app/cli ─┼─> src/core <─ src/storage
         │       ^  ^─── src/omoikane
         │       └────── src/integrations
         └─> src/ui ──> src/core
```

| ディレクトリ | 置くもの | 依存してよいもの |
|---|---|---|
| `src/core/` | ドメイン、ユースケース、ポート（interface） | RTL と FCL の基本ユニットのみ。LCL・OS の API・ファイル・通信を使わない |
| `src/storage/` | SQLite の実装、マイグレーション、バックアップ | `src/core/`、FCL の SQLite 関連ユニット |
| `src/omoikane/` | 規約エンジン、Yata Logic の読み込み | `src/core/` |
| `src/integrations/` | HuginnEngine、HamlibComponent、WSJT-X / fldigi、GPS、オンラインサービスのアダプター | `src/core/`、各外部コンポーネント |
| `src/ui/` | Presenter と LCL の画面 | `src/core/`。Presenter は LCL に依存しない。LCL を使うのは画面（View）だけ |
| `app/gui/` | GUI 版の起点。部品を組み立てるだけ | すべて |
| `app/cli/` | CLI 版の起点。部品を組み立てるだけ | `src/ui/` 以外のすべて。LCL を使わない |
| `tests/` | テスト | テスト対象のディレクトリ |
| `plugins/` | 同梱する Yata Logic パッケージの元データ | — |

`src/core/` が外側（storage、integrations、ui、LCL）を参照したら設計違反とする。

## 3. 命名

| 対象 | 規則 | 例 |
|---|---|---|
| ユニット | `Muninn.<層>.<機能>` | `Muninn.Core.Qso`、`Muninn.Storage.Sqlite`、`Muninn.Omoikane.Rules` |
| 型 | PascalCase、クラスは `T`、interface は `I` で始める | `TQso`、`IQsoRepository` |
| 単位 | 名前に単位を含める | `FrequencyHz`、`OccurredAtUtcMs` |

## 4. Object Pascal / Lazarus の規則

- `{$mode objfpc}{$H+}` を基本とする。
- Unix で動くプログラム（GUI・CLI・テスト）は、`uses` の先頭に `{$IFDEF UNIX}cthreads, cwstring,{$ENDIF}` を置く。
  - `cthreads` が無いと、スレッドを使う部品（HamlibComponent など）が起動時に停止する。
  - `cwstring` が無いと、`UnicodeUpperCase` などが実行時に失敗する（`Lazarus/` の試作で発生）。
- LCL を使わないプログラム（CLI・テスト）は、その次に `Muninn.Core.Utf8Default` を置く。`string` の文字コードを UTF-8 にする（LCL は GUI で同じことを行う）。
  - これが無いと、Windows や C ロケールで `string` に変換した日本語が失われる。
- リソースの所有は原則として `try..finally` で管理する。`try..except` は回復できる境界でだけ使い、例外を握りつぶさない。
- ワーカースレッドから LCL を直接操作しない。UI への通知は UI スレッドに渡してから行う。
- ロック中に I/O、UI への通知、外部のコールバックを呼ばない。
- 周波数は整数 Hz（`Int64`）、時刻は UTC で保持する。表示時にだけ変換する。
- 列挙型を `Ord()` の値のまま保存しない。保存形式では固定のコード値を使う。
- 受信系の障害ではログ入力を止めない。送信（PTT、CW キーイング）は異常時に必ず止める。

## 5. 作業の進め方

1. **同じファイルを複数のエージェントに並行して触らせない。** 作業ブランチはタスクごとに分けなくてよい。同じブランチを使い続ける場合は、PR がマージされたら master から作り直し、1 つの PR に 1 つの論点を保つ。
2. **1 PR = 1 つの論点。** 整形、改名、無関係なリファクタリングを混ぜない。
3. **必要な最小の変更にする。** 将来の用途のためだけの抽象化を加えない。
4. **コンフリクトを解決したら、push する前にビルドとテストを実行する。** 両側のコードを残したままにしない。
5. **設計の決定は人が行う。** 決定事項（D 番号）・未決事項（Q 番号）を変える必要があれば、PR で提案し、開発者の承認を待つ。
6. **設計に影響する変更は、同じ PR で設計文書を更新する。**
7. **公開してよいかを確認する。** このリポジトリは公開されている。未公開の資料、資格情報、個人情報をコミットしない。

## 6. ビルドとテスト

ツールチェーンは [ADR 0001](docs/adr/0001-toolchain.md) で固定している（FPC 3.2.2、Lazarus 4.4）。

| 項目 | 方法 |
|---|---|
| ビルド | `MuninnLog/scripts/build.sh`。`build/muninn-cli` ができる。FPC が 3.2.2 でなければ失敗する |
| GUI のビルド | `MuninnLog/scripts/build-gui.sh`。Lazarus 4.4 の lazbuild で `build/muninn-gui` ができる。lazbuild が PATH に無ければ `LAZBUILD=<パス>`、Lazarus の場所は `LAZARUS_DIR=<ディレクトリ>` で指定する（[ADR 0009](docs/adr/0009-ui-technology.md)）。`muninn-gui [<ログブック>]` で起動する。設定は OS ごとの場所（`MUNINN_CONFIG_DIR` で変更可、[ADR 0010](docs/adr/0010-gui-logbook-and-settings.md)）。`muninn-gui --demo --measure <ファイル>` で反応速度を測る |
| 動作確認 | `MuninnLog/build/muninn-cli --version`。ADIF の取り込みと書き出しは `muninn-cli import --db <ログブック> <ファイル.adi>`、`muninn-cli export --db <ログブック> --output <ファイル.adi>`（[ADR 0006](docs/adr/0006-cli-and-logbook-adif.md)） |
| テスト | `MuninnLog/scripts/test.sh`。FPCUnit（[ADR 0002](docs/adr/0002-unit-test-framework.md)）で単体テストと結合テストのランナーをビルドして実行する。1 件でも失敗すれば終了コード 1。`MUNINN_TEST_RESULTS_DIR=<ディレクトリ>` を指定すると、`unit.xml` と `integration.xml` にも結果を書き出す。結合テストの前に `muninn-cli` もビルドし、別プロセスとして試験する |
| SQLite | 結合テストと保存処理は SQLite 3.37.0 以降のライブラリを実行時に読み込む（[ADR 0003](docs/adr/0003-storage-sqlite.md)）。見つからない場合は `MUNINN_SQLITE_LIBRARY=<ライブラリのパス>` を指定する |
| Hamlib | 無線機のテストは HamlibComponent（`../hamlib_component/src`）を参照し、Hamlib 4.5〜4.7 のダミー機種を使う（[ADR 0008](docs/adr/0008-radio-port-hamlib.md)）。ライブラリが無ければそのテストは無視される。`MUNINN_REQUIRE_HAMLIB=1` で失敗にする（CI はこれを指定する） |
| CI | `.github/workflows/muninnlog-ci.yml`。Windows / macOS / Linux でビルド、単体テスト、結合テスト、動作確認、GUI のビルドと反応速度の測定を行う。テスト結果の XML は成果物（artifact）として保存する。合格がマージ条件 |

Windows では Git Bash などの bash から `scripts/build.sh` を実行する。

### テストの書き方

- 単体テストは `tests/unit/`、SQLite などを使うテストは `tests/integration/` に置く。ユニット名は `<テスト対象のユニット名>.Tests`（例：`Muninn.Core.Version.Tests`）とする。
- `TTestCase` を継承し、`initialization` 節で `RegisterTest` を呼ぶ。
- 新しいテストユニットは、ランナー（`tests/unit/muninn-unit-tests.lpr` または `tests/integration/muninn-integration-tests.lpr`）の `uses` に追加する。
- 日本語などの非 ASCII 文字列を含むユニットには `{$codepage utf8}` を書く。

## 7. 完了の報告

PR の本文には、テンプレート（`.github/pull_request_template.md`）に沿って次を書く。

- 実行したビルド・テストのコマンドと結果、CI のリンク
- 実機で確認した OS と内容（利用者に見える変更の場合）
- 未検証の項目（「未検証」と明記する）

実行していない検証を成功と書かない。現在の OS だけで成功しても「全 OS で確認済み」と書かない。
