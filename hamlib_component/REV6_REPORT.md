# Rev.6.0 report — implementing what applications use, and what that found

Rev.6.0 レポート — アプリケーションが使う機能の実装と、そこで見つかったもの

2026-10-17

---

## 1. What was asked / 依頼内容

> hamlib を活用しているアプリケーションが利用している hamlib の機能を
> 調査して、私たちのコンポーネントの実装のそれらの機能を確認してくだ
> さい。先ほどとは別のサンプルアプリを用意してください。

Three things: survey what real applications call, check our
implementation against that, and build a second sample application
distinct from the first.

3 点です。実アプリケーションが何を呼ぶかを調査すること、それに対して
本コンポーネントの実装を確認すること、そして最初のものとは別の
サンプルアプリケーションを用意すること。

---

## 2. The survey / 調査

`COVERAGE_MATRIX.md` holds it in full. The short version: four
codebases were read — WSJT-X/JS8Call's `HamlibTransceiver.cpp`,
fldigi's `rigclass.cxx`, gpredict's `gtk-rig-ctrl.c` and Hamlib's own
`rigctl_parse.c`. Of the 20 distinct `rig_*` entry points at least one
of them uses, Rev.6.0 implements 17 fully, 2 partially and 1 not at
all (`rig_get_conf`).

全文は `COVERAGE_MATRIX.md` にあります。要約すると、4 つのコードベース
を読みました。WSJT-X/JS8Call の `HamlibTransceiver.cpp`、fldigi の
`rigclass.cxx`、gpredict の `gtk-rig-ctrl.c`、そして Hamlib 自身の
`rigctl_parse.c` です。それらのいずれかが使う 20 個の `rig_*` エントリ
ポイントのうち、Rev.6.0 は 17 を完全に、2 を部分的に実装し、1 つ
(`rig_get_conf`) は未実装です。

The survey changed the plan in one way worth recording. Split
operation had been filed under "later". It is not a later feature: it
is what WSJT-X does for every QSO, and gpredict's satellite doppler
tracking is built on `S` and `I` — `rig_set_split_vfo` and
`rig_set_split_freq` — rather than on `rig_set_freq`. A Hamlib wrapper
without split is a wrapper that cannot be used for the two things
people most often use Hamlib for.

調査は計画を 1 点、記録に値する形で変えました。スプリット運用は
「後回し」に分類していました。これは後回しにできる機能ではありません。
WSJT-X が交信のたびに行うことであり、gpredict のサテライトドップラー
追尾は `rig_set_freq` ではなく `S` と `I` — `rig_set_split_vfo` と
`rig_set_split_freq` — の上に構築されています。スプリットのない Hamlib
ラッパーとは、人々が Hamlib を最もよく使う 2 つの用途に使えないラッパー
です。

---

## 3. What was implemented / 実装したもの

| Area | Public surface | Unit |
|---|---|---|
| Split | `SetSplitAsync`, `GetSplitAsync`, `SetSplitFreqAsync`, `TRigSplitResult` | `HamlibRigCommands.pas` |
| VFO | `SetVfoAsync`, `GetVfoAsync`, `VfoOpAsync`, `TRigVfoOp`, `TRigVfoResult` | `HamlibRigCommands.pas` |
| Levels | `GetLevelAsync`, `SetLevelFloatAsync`, `SetLevelIntAsync`, `TRigLevel` (38), `TRigLevelResult` | `HamlibLevelCodec.pas` |
| Functions | `GetFuncAsync`, `SetFuncAsync`, `TRigFunc` (22) | `HamlibLevelCodec.pas` |
| Capabilities | `GetCapabilities`, `TRigCapabilities` | `HamlibService.pas` |
| Configuration | `AddConfToken` | `HamlibService.pas`, `HamlibWorker.pas` |
| Display | `RigVfoToString` | `HamlibVfoCodec.pas` |

Two decisions inside that are worth stating, because both were
measured rather than assumed.

内部の決定のうち 2 つは述べる価値があります。どちらも仮定ではなく実測
に基づくからです。

**`value_t` is a 16-byte C union passed by value.** On SysV AMD64 it
arrives in two integer registers. Reading an integer level through the
float member produces a plausible-looking number in the hundreds of
millions rather than an error, so `TRigLevelResult.IsFloat` carries the
answer and no caller has to know. `FeatureMatrixTest` round-trips an
integer level (keyer speed, 27 WPM) and a float level (RF power, 0.42)
against the real library specifically to prove the union layout; a
misread float would be immediately visible.

**`value_t` は値渡しの 16 バイト C 共用体です。** SysV AMD64 では整数
レジスタ 2 本で届きます。整数レベルを float メンバ経由で読むと、エラー
ではなく数億という一見もっともらしい値になります。そのため
`TRigLevelResult.IsFloat` が答えを運び、呼び出し側が知る必要はありません。
`FeatureMatrixTest` は共用体のレイアウトを証明するために、整数レベル
(キーヤ速度 27 WPM) と float レベル (RF 出力 0.42) を実ライブラリに対して
往復させています。float の読み違いがあれば即座に目に見えます。

**Conf tokens are applied after the serial port and before the
component's own timeouts.** The ordering is not arbitrary: an
application that sets a token which happens to touch timing must not
silently undo the `TRigTimeoutPolicy` it just selected.

**conf トークンはシリアルポート設定の後、コンポーネント自身のタイム
アウトの前に適用します。** この順序は恣意的ではありません。たまたま
タイミングに触れるトークンを設定したアプリケーションが、今選んだ
`TRigTimeoutPolicy` を黙って取り消してしまってはなりません。

---

## 4. What the second sample found / 2 つ目のサンプルが見つけたもの

This is the part worth reading. `demo2/DxPanel` was built as a
worked example; it found two defects in the component, both of which
had survived every unit test, both samples' predecessors, and a
40 / 40 feature test against the real library.

ここが読む価値のある部分です。`demo2/DxPanel` は実例として作りましたが、
コンポーネントの欠陥を 2 件見つけました。どちらも全ユニットテスト、
両サンプルの先行版、そして実ライブラリに対する 40/40 の機能テストを
生き延びていたものです。

### 4.1 The snapshot asserted a fact it had never been given

The panel displayed its receive frequency from
`CurrentState.VfoAFreq` and showed the transmit frequency. Tracing it
produced this, in `HamlibService.pas`:

パネルは受信周波数を `CurrentState.VfoAFreq` から表示し、送信周波数を
表示しました。追跡した結果、`HamlibService.pas` にこれがありました。

```pascal
procedure TRigService.HandlePollerFreqChanged(Sender: TObject; AFreq: Double);
begin
  UpdateStateFreq(rvfoA, AFreq);     // <-- rvfoA
```

and this, in `HamlibStateHolder.pas`:

```pascal
case AVfo of
  rvfoA, rvfoMain, rvfoCurr: FState.VfoAFreq := AFreq;   // <-- rvfoCurr
```

The poller reads `RIG_VFO_CURR`. Hamlib answers with the frequency of
whichever VFO the rig has selected and never says which one that is.
Both lines treat "the current VFO" as "VFO A".

ポーラが読むのは `RIG_VFO_CURR` です。Hamlib はリグが選択している VFO
の周波数で答え、それがどの VFO かは決して述べません。上記 2 行はどちらも
「現在の VFO」を「VFO A」として扱っています。

Measured, with VFO A on 7.020 MHz and VFO B on 21.300 MHz:

VFO A を 7.020 MHz、VFO B を 21.300 MHz にして実測:

```
--- current VFO = B ---
  VfoAFreq    = 21300000    <-- VFO A is on 7.020 MHz
```

The snapshot reported VFO B's frequency as VFO A's. For a single-VFO
panel this is invisible, which is why it survived Rev.1 through 5.1.
For a split panel it is the difference between the frequency you are
listening on and the frequency you are transmitting on, displayed
under the wrong label.

スナップショットは VFO B の周波数を VFO A のものとして報告していました。
単一 VFO のパネルではこれは見えません。だから Rev.1 から 5.1 まで生き
延びました。スプリットのパネルでは、これは「聞いている周波数」と
「送信している周波数」の違いが、誤ったラベルの下に表示されることを意味
します。

**The fix.** `TRigState` gained `CurrentFreq`, which is what polling
fills. `VfoAFreq` and `VfoBFreq` are now written only by a read that
named the VFO explicitly, so 0 in them means "nobody asked" rather
than "unused". `README.md` carries the one-identifier migration.

**修正。** `TRigState` に `CurrentFreq` を追加し、ポーリングはこれを
埋めます。`VfoAFreq` と `VfoBFreq` は VFO を明示した読み取りによっての
み書かれるようになり、0 は「未使用」ではなく「誰も尋ねていない」を意味
します。識別子 1 つの移行手順は `README.md` にあります。

**The general lesson.** This is a type whose invariant was never
restated when its domain widened. In Rev.1 "the frequency" and "VFO A"
were the same thing and the field name recorded that correctly. Rev.6.0
added split without going back to ask whether the old name still meant
what it said. A field name is a claim; widening the domain is the
moment to re-read every claim the type makes.

**一般的な教訓。** これは、対象領域が広がったときに不変条件が述べ直され
なかった型です。Rev.1 では「周波数」と「VFO A」は同じものであり、
フィールド名はそれを正しく記録していました。Rev.6.0 はスプリットを追加
するにあたり、古い名前が今も言葉どおりの意味かを問い直しませんでした。
フィールド名は主張です。対象領域を広げる時点こそ、型が行うすべての主張
を読み直すべき時です。

### 4.2 A test that could not fail

`test/LifecycleTest.lpr` kept a `LoaderFreed` flag, set it in the fake
loader's destructor, and never looked at it. Three tests printed
`ServiceFreed` and reported OK on that alone. A loader that outlived
its service — a reference surviving somewhere, the library never
unloaded — would have been recorded and then ignored.

`test/LifecycleTest.lpr` は `LoaderFreed` フラグを持ち、偽ローダの
デストラクタで設定し、一度も参照していませんでした。3 つのテストは
`ServiceFreed` だけを表示し、それだけで OK と報告していました。サービス
より長く生き残ったローダ (どこかに残る参照、決してアンロードされない
ライブラリ) は、記録されたうえで無視されていたはずです。

The compiler had been saying so, as a note, in every build:
`Local variable "LoaderFreed" is assigned but never used`. A note
rather than a warning, in a project whose other 10 000 lines produce
neither.

コンパイラは毎回のビルドでそれを note として述べていました。
`Local variable "LoaderFreed" is assigned but never used`。警告ではなく
note であり、他の 1 万行がどちらも出さないプロジェクトの中で。

**The fix.** The three cases now require `ServiceFreed and
LoaderFreed`. All three pass, so the behaviour was always correct —
but it was never verified, and a check that cannot fail is worse than
no check, because it reads like one.

**修正。** 3 つの事例は `ServiceFreed and LoaderFreed` を要求するように
なりました。3 つとも通るので挙動は元から正しかったのですが、検証されて
いませんでした。失敗しえない検査は検査が無いより悪いものです。検査に
見えるからです。

---

## 5. Why DxPanel is not a second RigPanel / DxPanel が 2 つ目の RigPanel でない理由

A second sample that exercised the same shape as the first would have
found the same class of defect, which is to say none. RigPanel issues
*independent* commands: each succeeds or fails alone and nothing is
left half-done.

最初と同じ形を検査する 2 つ目のサンプルは、同じ種類の欠陥しか見つけ
られません。つまり何も見つけられません。RigPanel が発行するのは
「独立した」コマンドです。各々が単独で成否を決め、中途半端に残るものは
ありません。

DxPanel is built on the shape RigPanel does not have: **a multi-step
operation that can fail halfway**. Setting a rig up for split means
four ordered commands and a read-back, and a failure after the third
leaves a rig in split with a transmit frequency that was never set —
so the next time the operator keys up, they transmit somewhere they
did not choose. `DxSplitSequence` therefore disables split again when
it fails after having enabled it, and says so in the message.

DxPanel は RigPanel が持たない形の上に作られています。**途中で失敗
しうる多段操作**です。リグをスプリット状態にするには、順序のある 4 つの
コマンドと読み戻しが必要で、3 番目の後の失敗は、送信周波数が未設定の
ままスプリット状態のリグを残します。すると次にオペレータが送信した
とき、自分が選んでいない場所で電波を出します。そのため
`DxSplitSequence` は、有効化の後に失敗した場合はスプリットを解除し、
そのことをメッセージで述べます。

Three design points inside it:

内部の設計上の要点は 3 つです。

- **A state machine, not nested callbacks.** FPC 3.2.2 has no
  anonymous methods, so a callback chain would be five named methods
  each calling the next, and the order of the sequence would exist
  only as a path through the code — the shape in which "did we
  remember to undo step 3?" cannot be answered by reading. `Advance()`
  is the one place the order lives; `FSplitEnabled` is the one record
  of what needs undoing.
  **入れ子のコールバックではなく状態機械。** FPC 3.2.2 に匿名メソッド
  はないため、コールバック連鎖は「次を呼ぶ名前付きメソッド 5 つ」に
  なり、順序はコード中の経路としてしか存在しなくなります。それは
  「手順 3 を取り消し忘れていないか」が読んでは答えられない形です。
  順序が存在するのは `Advance()` だけ、取り消すべきものの記録は
  `FSplitEnabled` だけです。

- **Every step handler begins by checking it is still that step.** A
  queued command cannot be un-issued; `Abort` cancels the token but
  the result may still arrive, and a command that completed just
  before the cancel reports success. Without the guard an aborted
  sequence quietly resumes — a defect that appears only when the
  operator aborts at exactly the wrong moment.
  **各ステップハンドラは「まだ自分のステップか」の確認から始まります。**
  キューに入ったコマンドは取り消せません。`Abort` はトークンをキャンセル
  しますが結果は届きえますし、キャンセル直前に完了したコマンドは成功を
  報告します。ガードがないと、中断したシーケンスが黙って再開します。
  オペレータがまさに最悪の瞬間に中断したときにだけ現れる欠陥です。

- **Back-pressure on the meter.** The panel reads the S-meter on a
  250 ms timer and drops a tick if the previous read has not returned.
  Without that, a stalled serial link turns the panel into a request
  generator and the operator waits for a hundred stale meter reads to
  drain before their next command runs. For a meter, dropping is
  correct: only the newest reading is wanted.
  **メータのバックプレッシャ。** パネルは 250 ms タイマで S メータを
  読み、前の読み取りが戻っていなければティックを捨てます。これがないと、
  詰まったシリアル回線はパネルを要求生成器に変え、オペレータは次の
  コマンドが動くまでに古いメータ読み取り 100 件の消化を待ちます。
  メータにとって捨てるのが正解です。欲しいのは最新の値だけです。

`demo2/DxConformanceTest.lpr` drives all of this against the real
library through a recording view: 64 checks, including abort before
the dangerous step, abort after it, stale callbacks after an abort,
the meter's back-pressure, and the §4.1 regression.

`demo2/DxConformanceTest.lpr` は、記録用 view を通してこれらすべてを実
ライブラリに対して駆動します。検査 64 件。危険なステップの前の中断、
その後の中断、中断後の遅延コールバック、メータのバックプレッシャ、
そして §4.1 の退行検査を含みます。

---

## 6. A Hamlib behaviour worth recording / 記録に値する Hamlib の挙動

Running DxPanel's split setup against model 1 leaves the receive
display reading the transmit frequency. It is neither the panel nor
the component. In Hamlib 4.5.5:

DxPanel のスプリット設定をモデル 1 に対して実行すると、受信表示が送信
周波数になります。パネルの問題でもコンポーネントの問題でもありません。
Hamlib 4.5.5 では:

```c
/* rig.c, rig_set_split_freq */
retcode = caps->set_split_freq(rig, vfo, tx_freq);   /* vfo, not tx_vfo */

/* rigs/dummy/dummy.c */
static int dummy_set_split_freq(RIG *rig, vfo_t vfo, freq_t tx_freq)
{
    retval = dummy_set_freq(rig, vfo, tx_freq);      /* moves the CURRENT VFO */
    priv->curr->tx_freq = tx_freq;
```

`rig.c` passes the caller's `vfo` — `RIG_VFO_CURR` — to the backend
rather than the transmit VFO it just resolved, and the dummy backend
duly moves the selected VFO. A real backend addresses its own transmit
VFO instead. The panel displays what the rig reports, which is the
only thing it can honestly do.

`rig.c` は、解決したばかりの送信 VFO ではなく呼び出し側の `vfo`
(`RIG_VFO_CURR`) をバックエンドへ渡し、ダミーバックエンドは素直に選択中
の VFO を動かします。実機のバックエンドは代わりに自身の送信 VFO を対象と
します。パネルはリグが報告する内容を表示しており、それが正直にできる
唯一のことです。

Our call matches what `rigctl` does, so this is documented rather than
worked around. Working around it would mean guessing which backends
behave which way.

本コンポーネントの呼び出しは `rigctl` と同じであるため、回避策ではなく
文書化を選びました。回避するには、どのバックエンドがどう振る舞うかを
当て推量する必要があります。

---

## 7. Verification / 検証

| Test | Covers | Result |
|---|---|---|
| `test/*.lpr` (11) | lifecycle, leaks, misuse, timeouts, version gate, thread confinement, domain types, throughput | all OK |
| `examples/SmokeTest` | the minimal application shape | OK |
| `demo/ScenarioTest` | the first presenter through whole sessions, no LCL | 43 / 43 |
| `demo/RealHamlibTest` | the Rev.5.x surface against the REAL library | 33 / 33 |
| `demo2/FeatureMatrixTest` | every Rev.6.0 call against the REAL library | 40 / 40 |
| `demo2/DxConformanceTest` | those calls composed into a failure-capable operation | 64 / 64 |
| `tools/check_abi.py` | constants vs `rig.h` at 4.5.5, 4.6, 4.7.2, master | 0 mismatched |

All built with `-Sa -Criot -gh`: assertions, range and overflow
checks, leak trace. Zero unfreed blocks everywhere. The package
compiles with `-vwn` (warnings and notes shown) producing neither.

すべて `-Sa -Criot -gh` (アサーション、範囲・オーバーフロー検査、リーク
トレース) でビルドしています。未解放ブロックはどこにもありません。
パッケージは `-vwn` (警告と note を表示) でビルドして、どちらも出ません。

Both GUI applications build with `lazbuild` and run under Lazarus 3.0 /
FPC 3.2.2 with LCL(gtk2); screenshots are in `demo/` and `demo2/`.

両方の GUI アプリケーションは `lazbuild` でビルドでき、Lazarus 3.0 /
FPC 3.2.2 の LCL(gtk2) 上で動作します。スクリーンショットは `demo/` と
`demo2/` にあります。

---

## 8. What is still not verified / なお未検証のこと

Unchanged from Rev.5.1, and worth repeating because none of this
revision's work touched it:

Rev.5.1 から変わっておらず、本リビジョンの作業がいずれも触れていない
ため、繰り返す価値があります。

- **No real transceiver.** Every test runs against Hamlib's dummy
  backend. Serial timing, CI-V bus contention, and per-model quirks
  below the dummy rig are untested.
  **実機なし。** すべてのテストは Hamlib のダミーバックエンドに対して
  実行されます。シリアルのタイミング、CI-V バスの競合、ダミーリグより
  下の機種固有の癖は未検査です。
- **The tier-1 timeout cannot be verified without hardware.** A dummy
  rig never fails to answer.
  **第 1 段タイムアウトはハードウェアなしに検証できません。** ダミー
  リグが答えないことはありません。
- **The watchdog's cross-thread `rig_close` is not documented-safe.**
  It is the single documented exception to thread confinement and
  remains a deliberate, recorded risk.
  **ウォッチドッグのスレッド跨ぎ `rig_close` は文書上の安全保証があり
  ません。** スレッド閉じ込めの唯一の文書化された例外であり、意図的に
  記録されたリスクのままです。
- **`TRigCapabilities`'s level, function and VFO-operation sets are
  always empty**, because Hamlib exposes five capability fields through
  its stable C API. Empty means "not asked". The only reliable way to
  learn whether a rig does something is to ask it and read the error.
  **`TRigCapabilities` のレベル・機能・VFO 操作の集合は常に空です。**
  Hamlib が安定 C API で公開する能力フィールドは 5 つだからです。空は
  「問い合わせていない」を意味します。リグがある機能に対応するかを確実に
  知る唯一の方法は、尋ねてエラーを読むことです。
- **`rig_get_conf` is not implemented.** It is the one gap in the set
  of calls the surveyed applications use; see `COVERAGE_MATRIX.md`
  §4.1.
  **`rig_get_conf` は未実装です。** 調査対象アプリケーションが使う呼び
  出しの集合における唯一の欠落です (`COVERAGE_MATRIX.md` §4.1)。
