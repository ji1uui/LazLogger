# tests

| ディレクトリ | 内容 |
|---|---|
| `unit/` | 単体テスト。LCL・OS・通信に依存しない |
| `integration/` | 結合テスト。SQLite、Yata Logic、HamlibComponent（ダミー機種）、HuginnEngine（模擬エンジン） |
| `golden/` | ゴールデンテストの固定データと期待する出力。個人情報を含めない |

テストの仕組みは M0 のタスク T3 で整備する。

関連文書：[05_DEVELOPMENT_PROCESS.md](../docs/05_DEVELOPMENT_PROCESS.md) 第 8 節
