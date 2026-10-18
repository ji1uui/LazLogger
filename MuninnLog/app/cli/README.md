# app/cli

CLI 版 `muninn-cli` の起点。GUI と同じ中核ライブラリを使い、取り込み・出力・再計算・検証・ゴールデンテストを行う。LCL を使わない。

Unix では `uses` の先頭に `{$IFDEF UNIX}cthreads, cwstring,{$ENDIF}` を置く（[AGENTS.md](../../AGENTS.md) 第 4 節）。

関連文書：[04_ARCHITECTURE.md](../../docs/04_ARCHITECTURE.md) 第 6 節
