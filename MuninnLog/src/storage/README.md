# src/storage

SQLite によるログブックの保存、スキーマのマイグレーション、バックアップを置く。`src/core/` のポートを実装する。

- 依存してよいもの：`src/core/`、FCL の SQLite 関連ユニット
- ユニット名：`Muninn.Storage.<機能>`

| ユニット | 内容 |
|---|---|
| `Muninn.Storage.Sqlite` | SQLite の C API の薄いラッパー（`TSqliteDatabase`、`TSqliteStatement`、`ESqliteError`） |
| `Muninn.Storage.Schema` | スキーマとマイグレーション。`OpenLogDatabase` で DB を開き、最新の版に移行する |
| `Muninn.Storage.QsoRepository` | QSO の保存と読み出し。ADIF の値・データ型・順序を失わない（ADR 0006） |
| `Muninn.Storage.AdifTransfer` | ADIF ファイルの取り込み（1 トランザクション）と書き出し |

方針は [ADR 0003](../../docs/adr/0003-storage-sqlite.md) を参照。

関連文書：[00_DEVELOPMENT_POLICY.md](../../docs/00_DEVELOPMENT_POLICY.md) 決定事項 D10、[03_DATA_MODEL.md](../../docs/03_DATA_MODEL.md)
