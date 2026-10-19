# Rev.4.2 → Rev.5.1 実施報告

優先項目 1（外部値の実行時検証）、2（不変条件のフィットネス関数）、
3（ドメイン型への変換）の実施結果、および
**コンポーネントを利用するアプリケーションを実装しての検証**（第 9 章）。
2026-10-14 / Hamlib 4.5.5・4.6・4.7.2・master 照合、
および実ライブラリ Hamlib 4.5.5 に対する実行検証

---

## 0. 要約

| 項目 | 内容 | 検証状態 |
|---|---|---|
| 1a | バージョンゲート（未検証 Hamlib を起動時に拒否） | 実装・18 検査合格 |
| 1b | `rig_check_backend` によるモデル番号の実行時検証 | 実装・18 検査に含む |
| 1c | `tools/check_abi.py` による ABI 定数の機械照合 | **最大 111 定数 / 4 バージョン / 不一致 0** |
| 2 | スレッド閉じ込めフィットネス関数 | **14 検査合格・自己検査付き** |
| 3a | `TRigMode` + `HamlibModeCodec` | 実装・53 検査に含む |
| 3b | `TRigErrorKind`（コンポーネント固有種別を含む） | 実装・53 検査に含む |
| 3c | 実行時モデルカタログ（`rig_list_foreach_model`） | 実装・53 検査に含む |

副産物として**既存コードの欠陥 5 件**を発見・修正した（§5）。
うち 1 件は「Pull モデルのスナップショットがモードを一切運んでいなかった」
というもので、マニュアルに記載した機能が実際には動作していなかった。

全テスト（13 本）が Release ビルドと
`-Sa -Criot -gh`（アサーション・範囲検査・リークトレース）の双方で合格し、
未解放ブロックは 0 である。

**第 9 章を追加した。** コンポーネントを利用するアプリケーション
（`demo/RigPanel`、LCL GUI）を実装して検証した結果、ユニットテストを
すべて通過していた Rev.5.0 から**さらに欠陥 5 件**が見つかり、修正した。
うち 3 件は実 Hamlib ライブラリに対して動かさなければ発見できない種類の
ものである。これに伴い Rev.5.1 とした。

---

## 1. 項目 1 — 外部値の実行時検証

### 1a / 1b バージョンゲートとモデル検証

前回の報告で述べたとおり、**シンボルが解決できることは ABI 互換を意味しない**。
将来の Hamlib が関数名を保ったまま `pbwidth_t` の幅を変えれば、
`dlsym` は成功し、引数列だけが静かに壊れる。

したがって Rev.5.0 は検証機構と方針決定を分離した。

- **機構**は L1 のローダに置き、`IHamlibDiagnostics` という独立した
  role interface で公開する（`IHamlibLoader` に足さない理由は §4）。
- **方針**はアプリケーション側にある。既定では検証済み範囲外の Hamlib を
  `EHamlibUnsupportedVersion` で拒否し、
  `TRigServiceFactory.AllowUntestedVersion := True` で明示的に解除できる。

モデル番号は `Open` の中で `rig_check_backend` に問い合わせ、
ライブラリが「知らない」と答えた場合に `ERigModelUnknown` を発生させる。
API が無くて答えられない場合と、答えた上で未知の場合を `AAnswered` で
区別しており、API 欠落を「不正なモデル番号」と誤報しない。

### 1c ABI 定数の機械照合

`tools/check_abi.py` は Hamlib の実ヘッダ（GitHub から取得、または
`--headers` でローカル指定）を解析し、本コンポーネントの Pascal 側の値と
照合する。

```
--- checking against Hamlib 4.5.5 ---   109 agreed, 0 mismatched
--- checking against Hamlib 4.6   ---   110 agreed, 0 mismatched
--- checking against Hamlib 4.7.2 ---   111 agreed, 0 mismatched
--- checking against Hamlib master ---  110 agreed, 0 mismatched
```

版ごとの件数差は、その版に存在しない定数を照合対象から外した結果である。
内訳を確認した: 4.5.5 には `RIG_ELIMIT`(21) と `RIG_EACCESS`(22) が無く
（後の版で追加された）、その 2 件が照合対象から外れて 109 件になる。
master の 110 件は、その時点のヘッダに無いモード名が 1 件あることによる。
`TRigErrorKind` はこれら 2 種別を持つが、4.5.5 のライブラリがそれらを
返すことはないため無害である。

照合対象は VFO ビット、`HamlibTypes.pas` の生モード定数、
**`HamlibModeCodec.pas` の `MODE_BITS` 表**、エラーコード序数、モデル番号、
C 型幅、および宣言済み検証範囲が対象バージョンを覆っているか。

`MODE_BITS` の照合は **位置で突き合わせる**。末尾コメント（`{ rmUSB }`）を
読むのではなく、`HamlibInterfaces.pas` の `TRigMode` の宣言順を解析して
`MODE_BITS` の値と zip する。表の値だけがずれた場合、コメントは正しそうに
見えたままになるため、コメントを信じる実装ではその誤りを見逃す。

**検出器自体の検証（ネガティブテスト）**：既知の形の誤りを 2 件注入すると

```
MISMATCH  codec mode bit: rmPktUSB is 12, header says 11 for RIG_MODE_PKTUSB
MISMATCH  codec mode bit: rmFMN is 20, header says 21 for RIG_MODE_FMN
109 agreed, 2 mismatched
ABI check FAILED. Do not widen the verified range until this passes.
```

を報告し、復元後は 111/0 に戻る。
（`rmFMN` を 20 にする誤りは実際に起こりやすい。`rig.h` ではビット 20 が
欠番で、`RIG_MODE_FMN` は 21 である。）

### 副次的な発見 — Hamlib の採番規律

4.5.5 と 4.7.2 のモードビットを機械的に差分したところ、
**既存モードの採番変更は 1 件もなかった**。

```
only in 4.5.5:  RIG_MODE_BIT40..BIT46  (予約)
only in 4.7.2:  RIG_MODE_USBD1..D3 (40..42), LSBD1..D3 (43..45), WFMS (46)
```

Hamlib は予約ビットを埋めることでのみ拡張している。これは
「ビット位置の表 + 未知値は `rmUnknown`」という設計が将来も成立しうる
ことの実証的根拠であり、同時に**推測ではなく確認した事実**として記録する。
ただしこれは 2 バージョン間の観察にすぎず、保証ではない。
だからこそ照合を CI に置いている。

---

## 2. 項目 2 — スレッド閉じ込めフィットネス関数

### 何を守るものか

Hamlib の `RIG` 構造体はスレッドセーフと文書化されていない。
キュー + Worker 設計は、ひとえにその構造体へのアクセスを 1 スレッドに
閉じ込めるために存在する。

この閉じ込めは**個々のユニットの性質ではなくアーキテクチャの不変条件**で
あり、通常のユニットテストでは守れない。将来、誰かが getter を
「最適化」して呼び出し元スレッドから直接ハンドルを読んでも、
既存のテストはすべて通ってしまう。

`test/ThreadConfinementTest.lpr` は性質そのものを観測する。
プローブローダが、PRIG ハンドルを受け取る 13 の `IHamlibLoader` メソッド
すべてで `GetCurrentThreadId` を記録する。

### 測定結果

**シナリオ A（3 系統の同時発行下での通常動作）**

```
calls recorded : 171
rig_init / open / close / cleanup : 1 / 1 / 1 / 1
set_freq / get_freq : 30 / 44
set_mode / get_mode / set_ptt : 30 / 30 / 30
distinct threads touching the handle : 1
```

メインスレッド、第 2 のアプリケーションスレッド、ポーリングスレッドの
3 系統から同時にコマンドを発行し、ハンドルに触れたスレッドは
**ちょうど 1 つ**、かつそれは発行側のいずれでもない。

**シナリオ B（watchdog による中断 — 唯一許された例外）**

`TRigWatchdog` は固まった I/O を解除するため、watchdog スレッドから
意図的に `rig_close` を呼ぶ。本シナリオはそれが**唯一**であることを検査する。

```
rig_close calls : 1
watchdog aborted the stuck call : TRUE
calls seen from the watchdog thread : rig_close
distinct threads excluding rig_close : 1
```

watchdog スレッドが触れた呼び出しは `rig_close` のみ。
例外が他の呼び出しに広がれば本テストは失敗する。

**シナリオ C（検出器の自己検査）**

失敗し得ないフィットネス関数は無価値である。将来の改修でプローブが
外れても、シナリオ A と B は "ok" を印字し続けてしまう。
そこでシナリオ C は、検出対象の違反を意図的に犯す（メインスレッドから
ハンドルを直読みする）。

```
distinct threads after the injected violation : 2
[ok] the detector reports two threads when the rule is broken
```

計 **14 / 14 検査合格**、`-Sa -Criot -gh` で未解放ブロック 0。

---

## 3. 項目 3 — ドメイン型への変換

### 何が漏れていたか

Rev.4.2 までの公開 API は、他プロジェクト所有の値をアプリケーションに
露出させていた。これは Ousterhout の言う **information leakage**、
コナーセンスの語彙では**両端が別リポジトリにある値のコナーセンス**である。

| 漏れ | Rev.4.2 でアプリが書かされていたもの |
|---|---|
| モード | `SetModeAsync(Int64(1) shl 2)` ないし `RIG_MODE_USB` 定数 |
| エラー | `if R.ErrorCode = -6 then` — 符号反転した Hamlib 序数 |
| 機種 | `Open(RIG_MODEL_IC7300, ...)` — 自前ソースに書いた番号 |

3 つ目は実際に失敗した。Rev.4.1 では `RIG_MODEL_IC7300 = 3085` で、
これは IC-705 の番号である。**番号の誤りはコンパイルエラーにならない。**
開くのを拒否されるか、別の無線機のプロトコルで静かに通信する。

### 3a モード — `TRigMode`

47 値の列挙型（`rmUnknown` + 46 モード）を `HamlibInterfaces.pas` に置き、
ビット番号を知るのは `HamlibModeCodec.pas` の `MODE_BITS` 表だけにした。

設計上の判断を 3 点記録する。

1. **未知値は推測しない。** 0、名前の無いビット、複数ビットのマスクは
   いずれも `rmUnknown` を返す。複数ビットのマスクは「現在のモード」では
   なく能力一覧であり、そのうちの 1 つを選ぶのは呼び出し元を誤らせる。
   能力一覧には `SetFromHamlib` が別にある。
2. **生値は捨てない。** `TRigModeResult.RawMode` が報告された `rmode_t` を
   保持する。新しい Hamlib のモードが単に失われることはなく、
   アプリケーションは必要な情報から隔離されない。
3. **`rmUnknown` は送信できない。** `SetModeAsync(rmUnknown)` は
   `EArgumentException` を発生させる。「未知」を意味する `rmode_t` は
   存在しないため、get の値をそのまま set に返すコードは、静かに
   `RIG_MODE_NONE` を送るのではなく明確に失敗する。

`Passband` は `Int64` から `Integer`[Hz] に変えた。通過帯域幅は
C の `long` ではない。`pbwidth_t` が LP64 で `Integer` より広いことは
境界で処理し、収まらない値は「リグ既定」(0) として報告する。
高々数 kHz の値が 2^31 を超えることはないため、もっともらしい誤った
数値に切り詰めるより安全である。

### 3b エラー — `TRigErrorKind`

Hamlib の `RIG_E*` は**正**の序数で、関数はその符号反転を返す。
したがって `-6` が `RIG_EIO` である。この符号の慣習は既知の罠であり、
**本プロジェクトのマニュアルの以前の版はこれを誤っていた**
（「-3 = RIG_EIO」と書いていたが、-3 は `ENOMEM` である）。
アプリケーションに同じ罠を踏ませる API を維持する理由はない。

`TRigResult` は `Error: TRigErrorKind`（分岐用）と
`NativeCode: Integer`（ログ用）に分けた。`TRigFreqResult` と
`TRigModeResult` にも同じ 2 フィールドを追加した。
Rev.4.2 では周波数・モード結果のエラー経路で種別が失われており、
`OnError` に 0 が渡されていた。

**コンポーネント固有の状態に固有の種別を与えた。** Rev.4.2 は
Circuit Breaker の遮断を `OnError(-1, ...)` として報告していたが、
`-1` は Hamlib では `RIG_EINVAL` である。存在しない Hamlib コードを
捏造することは、障害の出所についての虚偽である。

```pascal
rekConnectFailed, rekCircuitOpen, rekNotConnected, rekComponentFault
```

の 4 種を追加し、いずれも `NativeCode = 0` とした。
未知のコードは `rekInternal`（= Hamlib 内部エラー）ではなく
`rekUnrecognised` に写す。未知の数値に分類を捏造すると、新しい Hamlib が
Hamlib のバグのように見えてしまう。

### 3c 機種 — 実行時カタログ

当初は「よく使う機種の表を持つ」案を検討したが、それでは番号を
2 箇所で一致させる問題が残るだけである。ヘッダを確認したところ、
列挙 API は**検証範囲の全バージョン（4.5.5 以降）に存在した**。

```c
int rig_list_foreach_model(int (*cfunc)(const rig_model_t, rig_ptr_t), rig_ptr_t data);
const char *rig_get_caps_cptr(rig_model_t, enum rig_caps_cptr_e);
int rig_load_all_backends(void);
```

したがって表ではなく**ライブラリ自身への問い合わせ**を実装した。
番号はそれを使う当のバイナリから来るため、取り決め自体が消える。
Hamlib を更新すればアプリを再コンパイルせずに新機種が増える。

実装上の注意点を 2 点記録する。

- **C コールバックの規律。** `rig_list_foreach_model` のコールバックは
  C 呼び出し規約の平関数でなければならず、Pascal 例外を漏らしてはならない。
  C のフレームを巻き戻すと Hamlib のハッシュテーブル走査が中途半端な状態で
  残る。`CollectModelCallback` は全体を `try...except` で囲み、失敗時は
  リストに印を付けて 0 を返す。`src/register.c`(4.7.2) を確認した結果、
  **0 を返すと反復は即座に終了し、0 以外なら継続する**。
- **縮退。** 列挙 API を欠くライブラリでは `IsAvailable = False` の空の
  カタログを返し、例外は出さない。カタログの欠落は UI の機能低下であって
  エラーではない。アプリは機種番号の入力欄にフォールバックすればよい。

バージョンゲートは `CreateModelCatalog` にも適用する。読み取り専用の
問い合わせでも省かない。ABI 不一致は周波数と同じ容易さで、返される
モデル番号を壊すからである。

---

## 4. 設計上の判断の記録

### なぜ新しいメソッドを `IHamlibLoader` に足さないのか

Rev.4.2 で `SetConf` を 1 本足した結果、テストフェイク 4 ファイルが
「No matching implementation for interface method」で壊れた。
これは ISP 違反の**実測されたコスト**である。

そこで検証系は `IHamlibDiagnostics`、列挙系は `IHamlibCatalog` という
独立した role interface に置き、`Supports()` で問い合わせる形にした。
結果として Rev.5.0 の 2 回の機能追加で**既存フェイクの変更は 0 件**で済み、
`IHamlibLoader` のみを実装するローダ（`fakeloader.inc` の `TFakeLoader`）も
有効なまま、カタログ経路は縮退する。この縮退経路も `DomainTypeTest` で
検査している。

### `HamlibInterfaces.pas` が 300〜500 行の規則を超えている件

現在 975 行（うち約 69% がコメントと空行、実コードは約 306 行）である。
規則からの逸脱であり、理由を明示しておく。

Object Pascal に識別子の再エクスポートはない。`uses A` した先の `A` が
`uses B` していても、`B` の識別子は見えない。したがって
「アプリが 1 つの uses で公開型を得られる」ことと「ユニットを小さく保つ」
ことは、この言語では両立しない。公開型を別ユニットに分ければ、
`rvfoA` と `rmUSB` が別の uses 節を要求することになる。

利用者の認知負荷と宣言ファイルの行数を比べ、前者を優先した。
本ユニットは宣言と文書のみで、実行コードを含まない。
**同じ理由で、`HamlibComponent.pas` が「再エクスポートする」という
Rev.4.2 の README と冒頭コメントの記述は誤りであり、訂正した。**
正しい uses 節を README と当該ユニットに明記した。

---

## 5. 作業中に発見した既存コードの欠陥

いずれも項目 1〜3 の作業の副産物であり、依頼された範囲外だが報告する。

### 5-1 Pull モデルのスナップショットがモードを運んでいなかった（重大）

`IRigStateHolder.SetMode` と `SetPtt` に**呼び出し元が存在しなかった**。
周波数のみ `TUserFreqCallbackDispatch` から更新されており、
`IRigService.CurrentState.Mode` / `.Passband` / `.PttActive` は
サービスの全生存期間にわたり初期値のままだった。

Rev.4.0 の改善提案で「同期的な状態スナップショット（Pull モデル）」が
明示的に要求され、マニュアル第 18 章で「複数 VFO の周波数とモードを
UI に反映する」と記述した機能が、実際には周波数しか運んでいなかった。

`TUserModeCallbackDispatch` に `IRigStateHolder` を持たせ、成功時に
スナップショットを更新するようにした。`DomainTypeTest` に退行防止の
検査を 2 件追加した。

`SetPtt` も同様に呼び出し元が存在しなかった。PTT の set には応答値が
無いが、**成功した set は現在リグが何をしているかを教える**。こちらが
指示し、リグが受理した状態そのものであり、これを記録するのは推測ではない。
`IRigService` に PTT の問い合わせ API が無いため、スナップショットの
`PttActive` の情報源はこれだけである。

`TUserPttCallbackDispatch` を追加し、`rcsSuccess` のときのみ記録する
ようにした。失敗時は何も記録しない。拒否された set はリグを元の状態に
残し、その状態は我々には分からないからである。検査 2 件を追加した。

なお `rig_get_ptt` を呼ぶ `TGetPttCommand` は L3 に存在するが、
`IRigService` に対応する公開 API が無い。**実機側で手動送信された
場合の PTT 状態は依然として取得できない**。これは残る限界である（§7）。

### 5-2 `test/FakeHamlibLoader.pas` がコンパイルできなかった

Rev.4.2 で `IHamlibLoader` に追加した `SetConf` が実装されておらず、
このユニットは「No matching implementation for interface method」で
コンパイルに失敗していた。ZIP に同梱していたテストユニットが
ビルドできない状態だった（tests は `fakeloader.inc` を使っており、
このファイルを誰も参照していなかったため気づかれなかった）。

`SetConf` を実装し、併せて設定トークンを記録して
`ConfValue['timeout']` で検証できるようにした。

### 5-3 `const` インターフェース引数による参照カウント境界の欠陥

`TRigModelCatalog.Create(const ALoader: IHamlibLoader)` と書いたところ、
`DomainTypeTest` で 32 バイトのリークが出た（`-gh` で検出、
`-gl` の呼び出しトレースで該当行を特定）。

原因は言語仕様である。`const` のインターフェース引数はコンパイラの
一時参照を抑制する。したがって

```pascal
Catalog := TRigModelCatalog.Create(TMyLoader.Create);
```

と書くと、オブジェクトは参照カウント 0 で到着する。
`Supports()` が参照を取って解放することが、偶然その破棄の契機になる。
**カタログ role を実装するローダは解放され、実装しないローダは漏れる**
という、実装した任意インターフェース次第で生存期間が変わる状態だった。

値渡しに変更し、入口で参照を取り出口で解放する決定的な挙動にした。
リークは 0 になった。これは利用者も踏む罠であり、
当該コンストラクタに理由を明記した。

### 5-4 `OnError` のコンポーネント固有コード（§3b に記載）

---

## 6. 検証結果

### テスト（11 本）

| テスト | Release | `-Sa -Criot -gh` | 未解放 |
|---|---|---|---|
| LifecycleTest | OK | OK | 0 |
| DanglingTest | OK | OK | 0 |
| LeakTest / LeakTest2 | OK | OK | 0 / 0 |
| MisuseTest | 生存 | 生存 | 0 |
| ConnectFailTest | OK | OK | 0 |
| TimeoutTest | OK（1015ms で rcsTimeout） | OK | 0 |
| VersionGateTest | 18/18 | 18/18 | 0 |
| **ThreadConfinementTest** | **14/14** | **14/14** | **0** |
| **DomainTypeTest** | **53/53** | **53/53** | **0** |
| PerfTest | 完走 | — | — |

### ABI 照合

4.5.5 / 4.6 / 4.7.2 / master の 4 版に対し **109 / 110 / 111 / 110 件・
不一致 0**。既知の誤りを注入したネガティブテストで検出を確認済み。

### ビルド

`fpc -Mobjfpc -Sh -vwn`（警告・注意を表示）で
**警告 0・注意 0**、7,395 行。

---

## 7. 残る限界（正直な記載）

1. **実機未検証。** 実トランシーバおよび `rigctld` に対する試験は
   一切行っていない。第 1 段タイムアウト（Hamlib の `timeout`/`retry`）の
   効果は実シリアルデバイスなしでは確認できない。
2. **watchdog の `rig_close` は文書化された安全な操作ではない。**
   別スレッドから `rig_close` を呼ぶことは Hamlib の文書で保証されて
   いない。代替は永久ハングであり、そちらを選んだが、
   これはトレードオフであって解決ではない。
3. **カタログは実 Hamlib で未実行。** `rig_list_foreach_model` を呼ぶ
   経路は、ヘッダと `src/register.c` を読んで実装し、フェイクで検証した。
   実ライブラリに対する実行は未了である。
4. **モードビット・エラー序数・型幅はヘッダ照合のみ。** 実行時に
   Hamlib がヘッダ通りに振る舞うことは確認していない。
5. **操作者が実機で手動送信した PTT は検出できない。** スナップショットの
   `PttActive` は本コンポーネント経由の set のみを反映する。`IRigService` に
   PTT 取得 API が無く、ポーラーも周波数しか問い合わせない（§5-1）。
6. **モード集合の取得 API が無い。** `THamlibModeCodec.SetFromHamlib` は
   能力マスクを展開できるが、`rig_caps` から対応モード一覧を取得する
   経路は実装していない。機種選択後に「この機種が対応するモード」で
   UI を絞る用途には、`rig_get_caps_int` 相当の追加バインドが必要である。
7. **`TRigMode` は 46 モードを網羅するが、将来のモードは `rmUnknown`**
   になる。これは設計上の意図だが、新モードを使いたい利用者は
   `RawMode` を自分で解釈する必要がある。

---

## 8. 移行の影響

公開型が非互換に変わったため、セマンティックバージョニングに従い
メジャーを上げ **Rev.5.0** とした。移行表は `README.md` の
MIGRATION 節に記載した。影響するのは

- `SetModeAsync` の第 1・第 2 引数
- `TRigModeResult` / `TRigResult` / `TRigFreqResult` のフィールド
- `OnError` ハンドラのシグネチャ（引数 1 本増）
- `IRigStateHolder` を自前実装している場合の `SetMode`

生の `RIG_MODE_*` / `RIG_MODEL_*` 定数は逃げ道として残してある。
`HamlibModeToString` は 2 つ目のモード表を持たず、コーデックに委譲する。

---

## 9. アプリケーションを作って検証した結果

ご提案に従い、コンポーネントを利用する実アプリケーション
`demo/RigPanel`（LCL GUI）を実装し、習作サンプルを兼ねた検証を行った。

**結論を先に述べる。ユニットテスト 11 本・計 104 検査をすべて通過していた
Rev.5.0 に対し、アプリケーションを 1 本書いたことで欠陥 5 件が見つかった。**
うち 3 件はユーザに見える不具合、2 件はドキュメントの誤りである。

### 9.1 何を作ったか

| ファイル | 役割 | LCL 依存 |
|---|---|---|
| `RigPanelView.pas` | `IRigView` — ウィンドウが「表示できること」の定義 | なし |
| `RigPanelPresenter.pas` | デモの全挙動（接続・操作・エラー文言・状態更新） | なし |
| `MainForm.pas` | ウィンドウ。コントロール配置とイベント転送のみ | あり |
| `RigPanel.lpr/.lpi` | LCL アプリケーション本体 | あり |
| `ScenarioTest.lpr` | 記録用 View で presenter を一連の操作で駆動（43 検査） | なし |
| `RealHamlibTest.lpr` | **実 Hamlib ライブラリに対する検証**（33 検査） | なし |

設計書が規定する MVP Passive View に従い、判断はすべて presenter に置いた。
その結果 `MainForm.pas` には `if Connected then` が 1 つも無く、各イベント
ハンドラは presenter を呼ぶ 1 行、各 `IRigView` メソッドは数行の代入である。
この分割のおかげで、**アプリの挙動の大半は画面なしでテストできた**。

検証環境には Lazarus 3.0 / LCL(gtk2) と実 Hamlib 4.5.5 を導入し、
`lazbuild` で GUI を実際にビルドし、仮想ディスプレイ上で起動して
ダミーリグ（`RIG_MODEL_DUMMY`）に接続するところまで確認した。

### 9.2 シナリオテストが見つけた欠陥（フェイク使用）

**9.2-1 接続失敗の原因が握り潰されていた（重大）**

ポートが他アプリに使用中（`-RIG_EACCESS`）の状況を作ったところ、
オペレータに表示されたのは

> 「失敗が続いたため休止しています。自動的に再開します」

だった。本当の原因である「ポートが使用中」はどこにも出ない。原因は 2 つ。

1. Worker の接続失敗ハンドラが `ERigError.Kind` を捨て、
   すべてを `rekConnectFailed` として報告していた。
   「ポート使用中」「ケーブル断」「電源オフ」が区別できず、
   アプリは適切な助言を出しようがなかった。
2. 接続失敗が Circuit Breaker を開き、その通知が原因の通知を上書きしていた。

修正: 接続失敗が `ERigError` なら Hamlib の分類をそのまま伝える。
ブレーカは静かに開く（`TripCircuitBreaker(AAnnounce := False)`）。

**9.2-2 接続試行の失敗がアプリから観測できなかった（重大）**

`OnConnectionChanged` は接続成功時と確立済みリンクの喪失時にしか発火せず、
**接続試行が失敗したことを知る手段が存在しなかった**。その結果 UI は
「接続中...」のまま永久に固まる。ユニットテストはサービス API を直接
呼ぶため、UI 状態という概念が無く、この欠落に到達できない。

修正: 接続試行の失敗時に `NotifyConnectionChanged(False)` を発火する。
通知順序は「①未接続になった → ②理由 → ③ブレーカ（静かに）」とした。
UI スレッドにはキュー順で届き、アプリは通常最後を表示するためである。

**9.2-3 コマンド拒否の理由が不正確だった**

接続に一度も成功していない状態での全コマンドが
`rekCircuitOpen`（失敗が続いたため休止）として拒否されていた。
ブレーカの事実としては正しいが、一度も接続できていないオペレータには
役に立たない。`ProcessCommand` の事前検査の順序を
「キャンセル → **未接続** → ブレーカ」に変更し、より具体的で行動に
つながる `rekNotConnected` を返すようにした。

### 9.3 実 Hamlib ライブラリが見つけた欠陥

ここからは、フェイクでは原理的に発見できない種類の欠陥である。

**9.3-1 `rigerror()` はエラーメッセージを返さない（重大）**

実ライブラリで PTT が拒否されたとき、`TRigResult.ErrorMsg` に入って
きたのは次のようなものだった。

```
rig_set_cache_mode(37): freqMainA=14074000, modeMainA=PKTUSB, ...
rig_set_cache_mode(37): freqMainB=146000000, modeMainB=, widthMainB=0
（以下、プロトコルトレースが延々と）
 1:rig.c(3279):rig_set_ptt returning(-1) Invalid parameter
```

Hamlib の `src/rig.c`（4.5.5）を読むと理由が判明した。
`rigerror()` はメッセージを**累積デバッグバッファに追記し、
バッファ全体を返す**（最大 15KB）。ヘッダ自身が
`rigerror2() // returns single-line message` と注記している。

これをステータスバーやメッセージボックスに出せば、アプリは壊れて見える。

修正: `rigerror2` を任意シンボルとして束縛し優先使用。無い場合は
`rigerror()` の 1 行目のみを採用する。修正後の表示は
`"Invalid parameter"` の 1 行になった。

**9.3-2 ドキュメントの `'none'` が実際には動かない（重大）**

README と `Open` のコメントは「`RIG_MODEL_DUMMY` には `'none'` を
渡す」と案内し、`Open` は空ポートを例外で拒否していた。
実ライブラリで試すと `rig_open` は

```
rig_open: using network address none
network_open: cannot get host "none": Name or service not known
rig_open returning(-2) Invalid configuration
```

で失敗する。Hamlib は `'none'` を**ネットワークホスト名**として解決する。
つまり**文書化されたダミーリグの開き方は動作しない**。

直接検証した結果、ポート未設定・空文字列・`/dev/null` のいずれでも
`rig_open` は `RIG_OK` を返す。修正: 空ポートを正当な入力として受理し
（Worker は元から空なら `rig_pathname` を設定しない）、文書を訂正した。

**9.3-3 ライブラリがコンソールを埋め尽くす**

実ライブラリをロードした瞬間、バックエンド登録の数十行が、
`rig_open` ごとにプロトコルトレース全体が印字された。Debian ビルドでは
stdout にも出るため、コンソールアプリの出力が破壊され、Windows では
コンソールウィンドウが開き得る。

修正: `rig_set_debug` を任意シンボルとして束縛し、`Load` 成功直後に
`RIG_DEBUG_NONE` を適用。診断が必要なアプリは
`THamlibLoader.SetDebugLevel` で上げられる。

**9.3-4 新しいエラー種別にラベルが無かった**

`RigErrorKindToString` が Rev.5.0 で追加した 5 種別
（`rekUnrecognised`, `rekConnectFailed`, `rekCircuitOpen`,
`rekNotConnected`, `rekComponentFault`）を case に持たず、すべて
`'unrecognised error'` を返していた。

`DomainTypeTest` はこれを検査していたが、**「ラベルが空でないこと」しか
見ていなかった**ためフォールバック文字列で合格していた。弱い検査が
欠陥を隠した実例である。修正とともに、未ラベルの種別は
`'unlabelled error kind %d'` と序数を出すようにし、将来の追加漏れを
追跡可能にした。

### 9.4 GUI を「実際に起動して」見つかったもの

**9.4-1 LCL アプリにも `cthreads` は必要だった**

`RigPanel.lpr` には当初「LCL アプリはウィジェットセットが cthreads を
引き込むため不要」とコメントしていた。ビルドして起動した結果、

```
This binary has no thread support compiled in.
Runtime error 232
```

で即死した（Lazarus 3.0 / FPC 3.2.2 / gtk2）。README の
「LCL アプリでは不要」という記述も同じ誤りである。
**コンパイルは通り、起動して初めて分かる種類の誤り**であった。
`{$IFDEF UNIX}cthreads,{$ENDIF}` を `Interfaces` の前に置き、
README を訂正した。

**9.4-2 表示の崩れ**

`rig_version()` は既に `"Hamlib"` で始まるため、`'Hamlib %s'` と整形
すると `"Hamlib Hamlib 4.5.5 Apr 05 ... SHA=6eecd3"` となりラベルから
溢れた。デモ側の修正（`DescribeLibrary`）。デバッガでは正しく読める
文字列が、画面では破綻する例である。

### 9.5 なぜユニットテストでは見つからなかったのか

| 欠陥 | ユニットテストが到達できない理由 |
|---|---|
| 9.2-1 原因の握り潰し | フェイクは「ポート使用中」を再現できるが、**メッセージの有用性**を判定する主体がテストに無い |
| 9.2-2 試行失敗が観測不能 | テストに「UI 状態」が無く、固まることが観測できない |
| 9.2-3 拒否理由の不正確 | 拒否されたこと自体は検査していた。**どう拒否されたか**は誰も問わなかった |
| 9.3-1 `rigerror` | フェイクは短い文字列を返す。実装者が自分で決めた戻り値を自分で検査していた |
| 9.3-2 `'none'` | フェイクはポート名を無視する。**文書の誤りをフェイクが追認していた** |
| 9.3-3 デバッグ出力 | フェイクは何も印字しない |
| 9.3-4 ラベル欠落 | 検査が「空でない」としか見ていなかった |
| 9.4-1 `cthreads` | コンソールテストは既に対処済みで、GUI の経路が未検証だった |

共通する構造は 1 つである。**フェイクは「自分が書いた想定」を返すため、
想定そのものが誤っている場合に沈黙する。** 実ライブラリと実 UI だけが
その想定に異議を唱えられる。

### 9.6 アプリケーション層の検証結果

| テスト | 内容 | 結果 |
|---|---|---|
| `ScenarioTest` | 通常操作 / 順序外操作 / 失敗系 / 未知モード | **43 / 43** |
| `RealHamlibTest` | 実 Hamlib 4.5.5 に対する ABI と全経路 | **33 / 33** |
| `RigPanel` (GUI) | lazbuild でビルド、仮想ディスプレイで起動・接続 | 動作確認 |

`RealHamlibTest` は、本プロジェクトで唯一 **C 関数の Pascal 宣言を
実ライブラリの前に立たせる**テストである。確認できたこと:

- `freq_t` = C `double`: 14,074,000 Hz を設定し、同じ値が返る
- `rmode_t` = 64bit: `rmUSB`（ビット 2）と `rmPktUSB`（ビット 11）が往復
- `pbwidth_t` = C `long`: 2400 Hz が正しく往復（LP64 で幅が異なる型）
- `rig_list_foreach_model` の **C → Pascal コールバック**が 283 機種を列挙
- `rig_get_caps_cptr` がメーカー名・機種名・成熟度を返す
- かつてハードコードしていた番号をライブラリ自身が追認:
  IC-7300 = 3073、FT-991 = 1035、K3 = 2029、**3085 = IC-705**
  （Rev.4.1 が IC-7300 としていた番号）

`-Sa -Criot -gh` 付きで実行しても未解放ブロックは 0 である。
C コールバックを伴う経路でもリークが無いことを含む。

### 9.7 残る課題（新たに判明したもの）

1. **任意の Hamlib conf トークンを設定する API が無い。** 実機では
   `ptt_type`、`rts_state`、`data_bits`、`stop_bits` などの設定が必要に
   なる。`IHamlibLoader.SetConf` は内部用で、`IRigService` から到達でき
   ない。実際、ダミーリグの PTT が `-RIG_EINVAL` になるのは
   `ptt_type` が未設定だからである（Hamlib 側の仕様）。
   **実機対応には追加が必要**と判断する。
2. **機種が対応するモードの一覧を取得できない。** デモのモード欄は
   固定の 8 種である。`rig_get_caps_int` 相当の束縛を追加すれば
   選択肢を機種に合わせて絞れる。
3. **実トランシーバでの検証は依然として未実施。** ダミーリグは
   シリアル I/O を行わないため、第 1 段タイムアウト（Hamlib の
   `timeout`/`retry`）と watchdog の実効性は実機でしか確認できない。
