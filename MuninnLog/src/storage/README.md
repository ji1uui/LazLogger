# src/storage

SQLite によるログブックの保存、スキーマのマイグレーション、バックアップを置く。`src/core/` のポートを実装する。

- 依存してよいもの：`src/core/`、FCL の SQLite 関連ユニット
- ユニット名：`Muninn.Storage.<機能>`

関連文書：[00_DEVELOPMENT_POLICY.md](../../docs/00_DEVELOPMENT_POLICY.md) 決定事項 D10、[03_DATA_MODEL.md](../../docs/03_DATA_MODEL.md)
