# tests/golden

ゴールデンテストの固定データと期待する出力。個人情報（実在の局の交信記録など）を含めない。[tests/README.md](../README.md) を参照。

| ディレクトリ | 内容 |
|---|---|
| `adif/` | ADIF の取り込み・書き出し（[ADR 0004](../../docs/adr/0004-adif-import-export.md)）。`<名前>.adi` が入力、`<名前>.expected.adi` が期待する出力、`<名前>.issues.txt` が期待する警告とエラー、`<名前>.cli-expected.adi` が `muninn-cli` で SQLite を経由した出力（作成日時と版の行を除く。ADR 0006） |

- テストは `Muninn.Core.AdifQso.Tests`（`*.expected.adi`、`*.issues.txt`）と `Muninn.Cli.Tests`（`*.cli-expected.adi`）にある。
- 固定データのディレクトリは `MUNINN_GOLDEN_DIR` で変えられる（既定は `tests/golden/adif`）。
- 期待する出力を作り直すときは、`MUNINN_UPDATE_GOLDEN=1 scripts/test.sh` を実行し、差分を確認してからコミットする。
- 改行コードを変えないよう、`.gitattributes` でテキスト変換を止めている。
- 現在のデータは合成したもの（コールサインは架空）。実際のロガーの出力例を加えるときは、個人情報を匿名化する。
