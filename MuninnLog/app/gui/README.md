# app/gui

GUI 版の起点（`.lpi` / `.lpr`）。部品を組み立てる（依存性を注入する）だけで、処理を書かない。

`muninn-gui`：`scripts/build-gui.sh` でビルドする（[ADR 0009](../../docs/adr/0009-ui-technology.md)、[ADR 0010](../../docs/adr/0010-gui-logbook-and-settings.md)）。

| 使い方 | 内容 |
|---|---|
| `muninn-gui [<ログブック>]` | ログブックを開いて起動する。省略すると最近使ったログブックを開く |
| `muninn-gui --demo` | T10 の試作のデモデータで起動する（ログブックなし） |
| `muninn-gui --demo --measure <ファイル>` | 反応速度を測り、結果を書き出して終了する |
| `--light` | ライトテーマ |

| ユニット | 内容 |
|---|---|
| `Muninn.App.Settings` | 最近使ったログブックの一覧の読み書き |
| `Muninn.App.Prototype` | デモデータと反応速度の測定 |

Unix では `uses` の先頭に `{$IFDEF UNIX}cthreads, cwstring,{$ENDIF}` を置く（[AGENTS.md](../../AGENTS.md) 第 4 節）。
