# app/cli

CLI 版 `muninn-cli` の起点。GUI と同じ中核ライブラリを使い、取り込み・出力・再計算・検証・ゴールデンテストを行う。LCL を使わない。

- 起点：`muninn-cli.lpr`
- ビルド：`scripts/build.sh`（[AGENTS.md](../../AGENTS.md) 第 6 節）

Unix では `uses` の先頭に `{$IFDEF UNIX}cthreads, cwstring,{$ENDIF}` を置く（[AGENTS.md](../../AGENTS.md) 第 4 節）。

## 使い方

```sh
muninn-cli import --db log.sqlite wsjtx_log.adi
muninn-cli export --db log.sqlite --output log.adi
muninn-cli --version
```

コマンドと終了コードは [ADR 0006](../../docs/adr/0006-cli-and-logbook-adif.md) を参照。取り込みと書き出しの処理は `src/storage/muninn.storage.adiftransfer.pas` にあり、この起点は引数の解釈と終了コードへの対応だけを行う。

関連文書：[04_ARCHITECTURE.md](../../docs/04_ARCHITECTURE.md) 第 6 節
