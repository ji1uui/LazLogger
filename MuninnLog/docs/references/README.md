# 参考資料

開発者が会話の中で共有した外部資料を、原文のまま保存しています。
誤記、表記の揺れ、途中での途切れも直していません。実装で使うときは、各資料の最新版を正とします。

| ファイル | 内容 | 出典・版 | 注意 |
|---|---|---|---|
| [HamlibComponent_README_Rev6.0.md](HamlibComponent_README_Rev6.0.md) | HamlibComponent（開発者が別途開発中）の README | Rev.6.0 | 開発者が公開を許可済み |
| [ADIF_3.1.8_excerpt.txt](ADIF_3.1.8_excerpt.txt) | ADIF 仕様の抜粋（版の履歴、データ型、列挙型の一部） | ADIF 3.1.8（2026-10-12） | 抜粋。全文は adif.org を参照 |
| [ARRL_DXCC_List_2022-03_excerpt.txt](ARRL_DXCC_List_2022-03_excerpt.txt) | ARRL DXCC リストの冒頭（Spratly Is. から 5H-5I まで） | March 2022 Edition | 全文 |
| [JARL_ward_JCG_JCC_lists_excerpt.txt](JARL_ward_JCG_JCC_lists_excerpt.txt) | JARL の区（政令指定都市の区）、JCG（郡）、JCC（市）のリスト | 各リストの更新日は本文を参照 | 区、郡、市の順で記載 |

## 利用上の注意

- リストの再配布条件（ARRL、JARL）は未確認です。これらから作るアプリ同梱の参照データの扱いは、M1 の前に ADR で決めます。
- JCC・JCG・区には有効期間（消滅日など）があります。参照データには有効期間を持たせ、交信日時で判定します。
- 原文には閉じ引用符の欠落、`Jan.31.1967` のような日付の書式、綴りの誤り、全角空白などが含まれます。取り込み時に検証します。
