### ADIF 3.1.8における日本の市郡区コードの取り扱い

DXCC 339（Japan）における `CNTY` / `MY_CNTY` の仕様整理と実装指針

### 1\. 結論

ADIF 3.1.8では、日本（DXCC Entity 339）の第2行政区分（Secondary Administrative Subdivision）として、JARLが定める JCC（市）、JCG（郡）、WAKU（区） のコード体系を採用している。

したがって、`CNTY` / `MY_CNTY` には、JCC・JCG・WAKU番号を接頭辞などで加工せず、そのまま格納することが妥当である。

ただし、実装にあたっては次の原則を守る必要がある。

* コードは数値ではなく文字列として保持し、先頭ゼロを維持する。

* `DXCC` / `MY_DXCC` に基づいて適用するコード体系を決定する。

* JCC・JCG・WAKUの識別は、桁数だけに依存せず、正式なコードリストとの照合によって行う。

* 市町村合併や行政区分変更に対応するため、QSO日時とコードの有効期間を考慮する。

* `STATE` / `MY_STATE` はADIFの第1行政区分の定義に従い、`CNTY` / `MY_CNTY` と独立して検証する。

### 2\. ADIFの行政区分モデル

ADIFは、交信地点をDXCC Entityと2階層の行政区分で表現する。

DXCC Entity

339 — Japan

第1行政区分（Primary Administrative Subdivision）

STATE / MY_STATE — 都道府県

第2行政区分（Secondary Administrative Subdivision）

CNTY / MY_CNTY — 市・郡・区

### 2.1 フィールドの対応

| 区分          | 相手局   | 自局       |
| ----------- | ----- | -------- |
| DXCC Entity | DXCC  | MY_DXCC  |
| 第1行政区分      | STATE | MY_STATE |
| 第2行政区分      | CNTY  | MY_CNTY  |

`CNTY` は名称から米国のCountyを連想させるが、ADIFでは米国以外にも適用される汎用的な第2行政区分フィールドである。

### 2.2 日本の第2行政区分

ADIF 3.1.8の「III.B.22. Secondary Administrative Subdivision Enumeration」では、日本に関連する以下の体系が扱われている。

| 体系   | 対象               | コード例            | 桁数        |
| ---- | ---------------- | --------------- | --------- |
| JCC  | 市                | 0101（札幌市）       | 主に4桁、一部6桁 |
| JCG  | 郡                | 01001（阿寒郡）      | 5桁        |
| WAKU | 区                | 010101（札幌市中央区）  | 6桁        |
| AJA  | 市・郡・区を横断するアワード体系 | JCC/JCG/WAKUを参照 | —         |

AJAは別の独立した行政コード体系ではなく、JCC/JCG/WAKUを利用するアワード上の枠組みとして区別する。

### 3\. コードの解釈と注意点

### 3.1 コードの桁数だけで区分を判定しない

例えば、`010101` は札幌市中央区のWAKUコードである一方、`100101` は東京都千代田区のJCC体系に属するコードとして扱われる。

したがって、6桁だからWAKUであるという判定は成立しない。

推奨する判定順序は以下のとおり。

* `DXCC = 339` を確認する。

* JARLのコードマスタに照合する。

* QSO日時における有効性を確認する。

* `STATE` と地理的整合性を確認する。

* 必要に応じてJCC/JCG/WAKUの分類を内部属性として保持する。

### 3.2 都道府県コードを混同しない

`STATE` はADIFのPrimary Administrative Subdivision Enumerationに従う。

JCC/JCG/WAKU番号の先頭部分が都道府県を表していても、その部分を機械的に切り出して `STATE` に設定するのではなく、ADIFの定義に基づく対応表を利用する。

### 3.3 過去の行政区分を維持する

市町村合併、政令指定都市への移行、行政区の新設・廃止などによって、コードの有効性は変化する。

過去のQSOについては、交信時点で有効だった行政区分を保存し、現在の行政区分へ自動的に書き換えないことが基本である。

なお、過去の行政区分コードを受け入れるかどうかは、ADIF形式としての妥当性と、個々のアワードにおける有効性を分けて判断する必要がある。

### 4\. ADIFレコードの記述例

### 4.1 札幌市

```adif
<DXCC:3>339
<STATE:2>01
<CNTY:4>0101
```

### 4.2 札幌市中央区

```adif
<DXCC:3>339
<STATE:2>01
<CNTY:6>010101
```

### 4.3 東京都千代田区

```adif
<DXCC:3>339
<STATE:2>10
<CNTY:6>100101
```

これらは関連フィールドの抜粋であり、完全なADIFログレコードには所定のヘッダー、レコード終端などが必要である。

自局の所在地を表す場合は、対応する `MY_DXCC`、`MY_STATE`、`MY_CNTY` を使用する。

### 5\. ログ管理アプリケーションの実装設計

ADIFとの相互運用性を確保しながら、日本国内のアワード処理や過去ログ管理を実現するためには、内部地理データモデルとADIF入出力モデルを分離する設計が望ましい。

### 5.1 推奨データモデル

| 属性                | データ型        | 用途               |
| ----------------- | ----------- | ---------------- |
| DXCC              | Integer     | DXCC Entity      |
| StateCode         | String      | ADIF第1行政区分       |
| SubdivisionScheme | Enum        | JCC / JCG / WAKU |
| SubdivisionCode   | String      | JARLの番号          |
| SubdivisionName   | String      | 市・郡・区の名称         |
| ValidFrom         | Date        | 有効開始日            |
| ValidTo           | Date / Null | 有効終了日            |
| SourceVersion     | String      | コードマスタの版         |

ADIFにエクスポートする際には、`SubdivisionCode` を `CNTY` または `MY_CNTY` にマッピングする。

### 5.2 インポート時の検証

ADIFインポート

DXCCの判定

339の場合、日本のコード体系を適用

コードマスタとの照合

JCC / JCG / WAKUの識別

時間的・地理的整合性検証

QSO日時・STATE・コード有効期間

内部データモデルへ格納

照合できないコードを受信した場合は、元のADIF値を保持したうえで検証状態を記録し、データを失わない設計とする。

### 5.3 エクスポート時の原則

* 正式なコードを変更せずに出力する。

* `JCC-`、`JCG-`、`WAKU-` などの接頭辞は付加しない。

* 先頭ゼロを削除しない。

* ADIFのフィールド長は出力する文字列のバイト数に従って設定する。

* `CNTY_ALT` をJCC/JCG/WAKUの併記用として安易に流用しない。

### 6\. 実装方針の最終判断

| 設計判断                       | 推奨   |
| -------------------------- | ---- |
| CNTY にJCC/JCG/WAKU番号を直接格納  | 採用   |
| MY_CNTY に自局の番号を直接格納        | 採用   |
| 独自のADIF JCC / JCG フィールドを追加 | 原則不要 |
| JCC/JCG/WAKUの区分を内部で管理      | 推奨   |
| 桁数だけで区分を判定                 | 非推奨  |
| QSO日時によるコード有効性検証           | 推奨   |
| 地理コードマスタの版管理               | 推奨   |
| ADIF値と内部データモデルの分離          | 推奨   |

### 7\. 参照仕様

* [ADIF 3.1.8 — Annotated Specification](https://www.adif.org.uk/318/ADIF_318_annotated.htm?utm_source=chatgpt.com)

* [ADIF公式サイト](https://adif.org/?utm_source=chatgpt.com)

* [JARL 市郡区番号資料](https://www.jarl.org/Japanese/A_Shiryo/A-2_jcc-jcg/jcc.htm?utm_source=chatgpt.com)

総括

日本の市郡区コードは、ADIF 3.1.8が定める第2行政区分として `CNTY` / `MY_CNTY` に格納できる。独自フィールドを追加するよりも、ADIF標準を優先することでログ交換の互換性を確保できる。

一方、ADIFフィールドだけでは行政区分の種類、歴史的な変更、アワード上の有効性まで十分に表現できないため、アプリケーション内部ではJCC/JCG/WAKUの区分と有効期間を管理することが望ましい。

この構成を採用すれば、ADIF互換性を維持しながら、JCC・JCG・WAKU・AJAのアワード管理にも拡張しやすい設計となる。
