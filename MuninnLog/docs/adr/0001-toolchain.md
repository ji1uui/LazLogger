# 0001: ツールチェーンの版と CI での導入方法

- 状態：提案（この ADR を含む PR のマージで決定）
- 日付：2026-10-18
- 関連：M0 タスク T2（[05_DEVELOPMENT_PROCESS.md](../05_DEVELOPMENT_PROCESS.md) 第 13 節）、[00_DEVELOPMENT_POLICY.md](../00_DEVELOPMENT_POLICY.md) 決定事項 D13

## 背景

MuninnLog は Windows / macOS を対象とし、CI では Windows / macOS / Linux でビルドとテストを行う。
開発環境と CI で同じ版のコンパイラを使わないと、「手元では通るが CI では通らない」問題が起きる。

既存の `Lazarus/` の CI では、Windows で Chocolatey 経由の Free Pascal の取得が HTTP 504 で失敗し、コアのビルドが一度も実行されていない。

## 選択肢

### コンパイラの版

| 選択肢 | 長所 | 短所 |
|---|---|---|
| **FPC 3.2.2** | 現行の安定版。Lazarus 4.x の公式配布物がこの版でビルドされている。Ubuntu 24.04 と Homebrew で入手できる | 2021 年のリリースで古い |
| FPC 3.2.4（RC） | 新しい | 正式版ではない（Lazarus 4.6 の macOS 版が 3.2.4RC1 でビルドされているという情報があるが、未確認） |
| FPC 開発版（trunk） | 最新の機能 | 安定性が保証されない |

### Lazarus（IDE と LCL）の版

| 選択肢 | 長所 | 短所 |
|---|---|---|
| **Lazarus 4.4** | 4.x の安定版。HamlibComponent の要件（2.2 以上、3.0 以上推奨）を満たす。`setup-lazarus` アクションで導入できる | — |
| Lazarus 4.6 | より新しい修正版 | 公式サイトでの公開と CI での導入方法を未確認 |

### CI での導入方法

| OS | 選択肢 | 判断 |
|---|---|---|
| Linux | Ubuntu 24.04 の apt（`fp-compiler` ほか、FPC 3.2.2） | **採用**。手元の Ubuntu 24.04 で版を確認済み |
| macOS | Homebrew の `fpc`（Apple Silicon にネイティブ対応） | **採用**。`setup-lazarus` は macOS を x64 のみサポートと記載しており、GitHub の macOS ランナー（Apple Silicon）に合わない |
| Windows | `gcarreno/setup-lazarus@v3`（Lazarus 4.4、FPC を同梱） | **採用**。Chocolatey は前回失敗している |

## 決定

- **コンパイラ：** FPC 3.2.2 に固定する。`MuninnLog/scripts/build.sh` は、ほかの版を検出したら失敗する。
- **Lazarus：** 4.4 を使う。GUI のビルドは、GUI のコードができた時点で CI に加える。
- **CI での導入方法：** Linux は apt、macOS は Homebrew、Windows は `setup-lazarus` を使う。

## 結果

- CI の各 OS で、`fpc -iV` が 3.2.2 であることを確認できる。
- Homebrew と apt は配布側の更新で版が変わりうる。版が変わるとビルドスクリプトの版検査で CI が失敗するので、その時点でこの ADR を見直す。
- **見直す条件：**
  - FPC 3.2.4 が正式にリリースされたとき
  - Lazarus 4.6 以降の公開と、CI での導入方法が確認できたとき
  - いずれかの OS で導入が安定しないとき
