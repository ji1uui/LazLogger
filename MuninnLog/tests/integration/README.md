# tests/integration

結合テスト。[tests/README.md](../README.md) を参照。

| ファイル | 内容 |
|---|---|
| `muninn-integration-tests.lpr` | 結合テストのランナー（FPCUnit） |
| `muninn.storage.schema.tests.pas` | SQLite のスキーマとマイグレーション、制約、UTF-8、強制終了後の整合性 |
| `muninn.storage.qsorepository.tests.pas` | QSO の保存と読み出し（列と `qso_field` の使い分け、ユーザー定義フィールド） |
| `muninn.cli.tests.pas` | `muninn-cli` を別プロセスで起動し、ADIF → SQLite → ADIF のゴールデンテストと終了コードを確かめる |
| `muninn-crash-helper.lpr` | 強制終了のテストで使う補助プログラム。トランザクションの途中で自分のプロセスを終了させる |

SQLite のライブラリが必要（[ADR 0003](../../docs/adr/0003-storage-sqlite.md)）。テストは一時ディレクトリに DB を作り、終了時に消す。
