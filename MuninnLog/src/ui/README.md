# src/ui

Presenter と LCL の画面（View）を置く。

- Presenter は LCL に依存しない。テストから画面なしで動かせるようにする
- 画面は部品の配置とイベントの転送だけを行う。保存・通信・計算をしない
- UI の状態は UI スレッドだけで更新する
- ユニット名：`Muninn.UI.<機能>`
- 画面の技術は LCL＋独自描画（[ADR 0009](../../docs/adr/0009-ui-technology.md)）

| ユニット | LCL | 内容 |
|---|---|---|
| `Muninn.UI.QsoEntry` | 使わない | 入力欄の Presenter（検査、パーシャルチェック、重複、記録） |
| `Muninn.UI.Bandmap` | 使わない | バンドマップのモデル（位置の変換、ラベルの配置、ズーム） |
| `Muninn.UI.Clock` | 使わない | 反応速度の測定用のマイクロ秒カウンター |
| `Muninn.UI.Theme` | 使う | 独自描画の色（ダーク / ライト） |
| `Muninn.UI.BandmapView` | 使う | 独自描画のバンドマップ |
| `Muninn.UI.MainForm` | 使う | 試作の画面 |

LCL を使わないユニットは単体テスト（`tests/unit`）から試験する。LCL を使うユニットは単体テストから参照しない。
