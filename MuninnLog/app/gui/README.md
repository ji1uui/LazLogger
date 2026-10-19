# app/gui

GUI 版の起点（`.lpi` / `.lpr`）。部品を組み立てる（依存性を注入する）だけで、処理を書かない。

`muninn-gui`（T10 の試作）：`scripts/build-gui.sh` でビルドする。デモデータで起動し、`--light` でライトテーマ、`--measure <ファイル>` で反応速度を測って終了する（[ADR 0009](../../docs/adr/0009-ui-technology.md)）。

Unix では `uses` の先頭に `{$IFDEF UNIX}cthreads, cwstring,{$ENDIF}` を置く（[AGENTS.md](../../AGENTS.md) 第 4 節）。
