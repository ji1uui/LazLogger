# src/core

ドメイン（QSO、プロファイル、Operation）、ユースケース、ポート（interface）を置く。

- 依存してよいもの：RTL と FCL の基本ユニットのみ
- 依存してはいけないもの：LCL、OS の API、ファイル・ネットワークの直接操作、`src/` の他のディレクトリ
- ユニット名：`Muninn.Core.<機能>`

関連文書：[03_DATA_MODEL.md](../../docs/03_DATA_MODEL.md)、[04_ARCHITECTURE.md](../../docs/04_ARCHITECTURE.md) 第 2 節
