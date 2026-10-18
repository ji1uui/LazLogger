# 参考資料

開発者が会話の中で共有した外部資料を、原文のまま保存しています。
誤記、表記の揺れ、途中での途切れも直していません。実装で使うときは、各資料の最新版を正とします。

| ファイル | 内容 | 出典・版 | 注意 |
|---|---|---|---|
| [HamlibComponent_README_Rev6.0.md](HamlibComponent_README_Rev6.0.md) | HamlibComponent（開発者が別途開発中）の README | Rev.6.0 | 開発者が公開を許可済み |
| [ADIF_3.1.8_excerpt.txt](ADIF_3.1.8_excerpt.txt) | ADIF 仕様（版の履歴、データ型、列挙型、フィールド、ファイル形式） | ADIF 3.1.8（2026-10-12） | 全文 |
| [ARRL_DXCC_List_2022-03_excerpt.txt](ARRL_DXCC_List_2022-03_excerpt.txt) | ARRL DXCC リスト（現行エンティティ、注記、プリフィックスの対照） | March 2022 Edition | 全文 |
| [JARL_ward_JCG_JCC_lists_excerpt.txt](JARL_ward_JCG_JCC_lists_excerpt.txt) | JARL の区（政令指定都市の区）、JCG（郡）、JCC（市）のリスト | 各リストの更新日は本文を参照 | 区、郡、市の順で記載 |
| [ADIF_Japan_CNTY_notes.md](ADIF_Japan_CNTY_notes.md) | 日本の市郡区コード（JCC / JCG / 区）と ADIF の `STATE` / `CNTY` の対応の整理 | 開発者が共有した二次資料 | 下記「検証の結果」を参照 |

## 利用上の注意

- リストの再配布条件（ARRL、JARL）は未確認です。これらから作るアプリ同梱の参照データの扱いは、M1 の前に ADR で決めます。
- JCC・JCG・区には有効期間（消滅日など）があります。参照データには有効期間を持たせ、交信日時で判定します。
- 原文には閉じ引用符の欠落、`Jan.31.1967` のような日付の書式、綴りの誤り、全角空白などが含まれます。取り込み時に検証します。

## 検証の結果：ADIF_Japan_CNTY_notes.md

二次資料のため、ADIF 3.1.8 の全文（`ADIF_3.1.8_excerpt.txt`）と JARL のリストで内容を確かめた。

| 主張 | 結果 | 根拠 |
|---|---|---|
| 日本の `CNTY` は JCC・JCG・区（WAKU）のコード。AJA はそれらを横断するアワード | 正しい | ADIF III.B.22（Japanese Cities 815、Ku 175、Guns 379。ほかに削除済みのコードがある） |
| JCC は 2 桁の都道府県コード ＋ 2 桁または 4 桁、JCG は ＋ 3 桁、区は ＋ 市 2 桁 ＋ 区 2 桁 | 正しい | ADIF III.B.22 の書式欄。例は 0101、100101、01001、010101 |
| 6 桁でも区とは限らない（100101 は東京都千代田区で JCC） | 正しい | ADIF III.B.22 の例、JARL の注記（特別区は 2010-04-01 に市リストへ移行） |
| 日本の `STATE` は 01〜47（東京は 10） | 正しい | ADIF III.B.12「Enumeration for Country Code 339」 |
| 過去の（削除された）コードは交信時点で判定する | 正しい | ADIF II.C：削除された値は、その有効期間内の QSO に限って取り込み・書き出しできる |

MuninnLog での扱いは [ADR 0004](../adr/0004-adif-import-export.md) と [ADR 0005](../adr/0005-japanese-subdivision-reference-data.md) を参照。
