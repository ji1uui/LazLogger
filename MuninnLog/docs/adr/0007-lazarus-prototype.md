# 0007: 既存の `Lazarus/` の扱い

- 状態：決定（開発者の判断、2026-10-19）
- 日付：2026-10-19
- 関連：M0 タスク T11（[05_DEVELOPMENT_PROCESS.md](../05_DEVELOPMENT_PROCESS.md) 第 13 節）、[00_DEVELOPMENT_POLICY.md](../00_DEVELOPMENT_POLICY.md) 旧未決事項 Q9・決定事項 D19、[01_CURRENT_STATE_REVIEW.md](../01_CURRENT_STATE_REVIEW.md)

## 背景

リポジトリの `Lazarus/` には、zLog Lazarus Edition の試作がある（[01_CURRENT_STATE_REVIEW.md](../01_CURRENT_STATE_REVIEW.md)）。
MuninnLog は新しいアプリとして構築する（D1）。試作には参考になるクラス構成やロジックがある一方で、マージ事故の痕跡や未完成の部分もある。
試作を凍結するか、削除するか、master を修復するかは未決事項 Q9 だった。

## 選択肢

| 選択肢 | 長所 | 短所 |
|---|---|---|
| **参考資料として残す（凍結）** | クラス構成やロジックを読み返せる | 古いコードが残る |
| 削除する | リポジトリが整理される | 参考にできなくなる（履歴からは取り出せる） |
| master を修復して使い続ける | 試作を活かせる | MuninnLog と二重の保守になる |

## 決定

- `Lazarus/` の成果は、**クラス構成やロジックを参考にするだけ**とする。
- MuninnLog から `Lazarus/` のユニットを `uses` したり、ビルドに含めたりしない。
- コードをそのまま写さない。参考にした場合は、MuninnLog の規則（AGENTS.md）に沿って書き直し、テストを付ける。
- `Lazarus/` は修復も削除もしない（凍結）。MuninnLog の CI の対象にもしない。

## 結果

- [04_ARCHITECTURE.md](../04_ARCHITECTURE.md) 第 8 節の「持ち込み」は、この ADR の範囲（考え方の参考）で行う。
- `Lazarus/` に変更が必要になった場合は、この ADR を見直す。
