# app/gui

GUI 版の起点（`.lpi` / `.lpr`）。部品を組み立てる（依存性を注入する）だけで、処理を書かない。

Unix では `uses` の先頭に `{$IFDEF UNIX}cthreads, cwstring,{$ENDIF}` を置く（[AGENTS.md](../../AGENTS.md) 第 4 節）。
