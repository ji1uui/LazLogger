# src/integrations

外部とつながるアダプターを置く。`src/core/` のポートを実装する。

| 対象 | 内容 |
|---|---|
| HamlibComponent | 無線機ポートの実装 `Muninn.Integrations.Hamlib`（[04_ARCHITECTURE.md](../../docs/04_ARCHITECTURE.md) 第 4 節、[ADR 0008](../../docs/adr/0008-radio-port-hamlib.md)）。ビルドには `-Fu../hamlib_component/src` が必要 |
| HuginnEngine | `THuginnInterface` の実装（同 第 3 節） |
| WSJT-X / fldigi / MMTTY | 外部アプリとの連携 |
| GPS、オンラインサービス | 同意が前提（決定事項 D11） |

- 依存してよいもの：`src/core/`、各外部コンポーネント
- 依存してはいけないもの：LCL
- ユニット名：`Muninn.Integrations.<対象>`
