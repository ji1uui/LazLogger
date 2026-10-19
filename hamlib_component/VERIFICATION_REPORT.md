# Verification report — two rounds, nine defects

検証レポート — 2 ラウンド、欠陥 9 件

Round 1: 2026-10-17 · Round 2: 2026-10-18 · Rev.6.1

---

> **Note on this document / 本書についての注記**
>
> An earlier version of this file held the Round 1 account. It was
> overwritten in error at the start of Round 2, before the working tree
> had been checked for prior work, and there was no backup. The Round 1
> section below is reconstructed verbatim from the summary in
> `README.md`, which survived intact; the Round 1 tests, tools and
> source fixes are all present and unaffected. `test/RandomSequenceTest.lpr`
> was overwritten in the same way; the current file is a different
> implementation that re-establishes the property the lost one pinned —
> per-shape callback accounting, including under cancellation — and
> §2.3 says how that was verified.
>
> 本ファイルの以前の版には Round 1 の記録がありました。Round 2 の開始時、
> 作業ツリーに先行作業がないか確認する前に、誤って上書きし、バックアップ
> はありませんでした。下記 Round 1 節は、無傷で残っていた `README.md` の
> 要約から逐語的に再構成したものです。Round 1 のテスト・ツール・ソース
> 修正はすべて存在し、影響を受けていません。
> `test/RandomSequenceTest.lpr` も同様に上書きされました。現在のファイルは
> 別実装であり、失われた版が固定していた性質 — キャンセル時を含む種類ごとの
> コールバック会計 — を再確立しています。その検証方法は §4.3 に記します。

---

## Round 1 — going outside the dummy backend (3 defects)

Every test up to Rev.6.0 talked to Hamlib's in-process dummy rig, which
answers in microseconds and never fails. A verification campaign that
deliberately left that comfort — a simulated Kenwood on a pseudo-serial
port, `rigctld` over TCP with the server killed mid-session, randomized
call sequences, a long soak, Valgrind, and a layer-dependency fitness
function — found three defects that every existing test had passed over.
`VERIFICATION_REPORT.md` has the full account.

1. **A deadlock when a thread was torn down before it was ever
   resumed.** A `TThread` created suspended sits in the RTL's start
   gate: `Terminate` does not reach it and `WaitFor` on it never
   returns. The Worker's destructor waited on its watchdog
   unconditionally, and the Service waited on its Worker
   unconditionally. An application that connected and immediately
   disconnected, or whose `Open` raised after the Worker was
   constructed, froze permanently — no error, no timeout, no way out.
   Fixed by recording whether a thread was resumed and never joining
   one that was not. Pinned by `test/ThreadStartupTest.lpr`.

2. **A leak on the C side of the boundary, invisible to `heaptrc`.**
   `rig_load_all_backends()` is not idempotent — a second call
   allocates a fresh registration record per model and leaks the
   first set, and Hamlib has no unregister-all. The "backends are
   loaded" flag was a field on `THamlibLoader`, and the factory
   builds one loader per `IRigService`, so every service created
   leaked another copy of Hamlib's registration table: 283 blocks,
   4,528 bytes, every time. An application that creates a service per
   connection — as `demo/RigPanel` does — grew by that much on every
   reconnect. Fixed by scoping the flag to the process, which is what
   it was always describing. Measured after the fix: 1, 8 and 24
   services all leak the same constant 4,528 bytes.

3. **The four Rev.6.0 Get commands never reported when cancelled.**
   `CancelAllQueued` and `DrainQueueOnShutdown` each held a copy of the
   same type switch, and both knew only the three Get commands that
   existed when they were written. `GetLevelAsync`, `GetFuncAsync`,
   `GetSplitAsync` and `GetVfoAsync` fell through to the generic
   branch, whose callback field is nil for a typed command: the
   application's callback was never invoked and the dispatch object
   leaked. An application waiting on one of those calls when the rig
   closed waited forever. Fixed by collapsing the two switches into
   one `DeliverCancelledAndFree`. Pinned by
   `test/RandomSequenceTest.lpr`.

**Rev.6.1 — ダミーバックエンドの外に出て見つかった欠陥 3 件**

Rev.6.0 までのすべてのテストは、マイクロ秒で応答し決して失敗しない
Hamlib のインプロセス・ダミーリグと会話していました。その居心地の良さ
を意図的に離れた検証作業 (擬似シリアルポート上の Kenwood シミュレータ、
途中で kill する `rigctld` への TCP 接続、無作為な呼び出し列、長時間
ソーク、Valgrind、層依存のフィットネス関数) が、既存のすべてのテストが
見逃していた欠陥 3 件を見つけました。詳細は `VERIFICATION_REPORT.md`。

1. **再開される前に破棄されたスレッドでのデッドロック。** サスペンド
   状態で生成された `TThread` は RTL の開始ゲートに留まります。
   `Terminate` は届かず、`WaitFor` は決して戻りません。Worker の
   デストラクタは watchdog を、Service は Worker を、いずれも無条件に
   待っていました。接続直後に切断したアプリ、あるいは Worker 構築後に
   `Open` が例外を投げたアプリは、エラーもタイムアウトも脱出手段もなく
   永久に固まりました。スレッドが再開されたかを記録し、再開されて
   いないものを join しないことで修正。`test/ThreadStartupTest.lpr`
   が固定します。

2. **`heaptrc` に見えない、境界の C 側のリーク。**
   `rig_load_all_backends()` は冪等ではありません。2 回目の呼び出しは
   機種ごとに新しい登録レコードを確保して 1 回目のぶんを漏らし、Hamlib
   に一括解除はありません。「バックエンドはロード済み」フラグは
   `THamlibLoader` のフィールドであり、ファクトリは `IRigService` ごとに
   ローダを 1 つ構築するため、サービスを生成するたびに Hamlib の登録表の
   写しが 1 つ漏れていました。毎回 283 ブロック・4,528 バイトです。
   接続ごとにサービスを生成するアプリ (`demo/RigPanel` がそうです) は、
   再接続のたびその分だけ育ちました。フラグのスコープを、それが元々
   記述していた対象であるプロセス全体にして修正。修正後の実測では、
   サービス 1 個・8 個・24 個のいずれも同じ 4,528 バイトで一定です。

3. **Rev.6.0 の Get コマンド 4 種がキャンセル時に報告しない。**
   `CancelAllQueued` と `DrainQueueOnShutdown` が同じ型スイッチの写しを
   それぞれ持ち、どちらも書かれた時点の Get コマンド 3 種しか知りません
   でした。`GetLevelAsync`、`GetFuncAsync`、`GetSplitAsync`、
   `GetVfoAsync` は汎用分岐に落ちますが、型付きコマンドではその
   コールバックフィールドは nil です。アプリのコールバックは呼ばれず、
   配送オブジェクトは漏れました。リグが閉じられたときそれらを待って
   いたアプリは永久に待ちました。2 つのスイッチを 1 つの
   `DeliverCancelledAndFree` に畳んで修正。
   `test/RandomSequenceTest.lpr` が固定します。

---

## Round 2 — the defect classes the suite still could not reach (6 defects)

### 2.1 How the methods were chosen

> さらに機能に問題がないことを確認する方法とその手順を計画して実行
> してください。

The component already had a test suite that passed: 11 unit tests, two
application-level suites, a 40-check feature test and a 64-check
conformance test against the real library, an ABI checker across four
Hamlib refs, and a thread-confinement fitness function. All green.

本コンポーネントには既に合格しているテスト群がありました。ユニット
テスト 11 件、アプリケーション水準のテスト 2 件、実ライブラリに対する
40 検査の機能テストと 64 検査の適合テスト、4 つの Hamlib リファレンス
に対する ABI 照合、スレッド閉じ込めフィットネス関数。すべて緑でした。

So the question was not "run the tests again". It was: **what class of
defect can the existing suite not reach, and what method reaches it?**
Seven methods were selected on that basis alone.

したがって問いは「テストをもう一度走らせる」ことではありませんでした。
**既存のテスト群が到達できない欠陥の種類は何か、そしてそれに到達する
手法は何か。** 7 つの手法はその基準だけで選びました。

| | Method | The defect class it reaches | Why the existing suite cannot |
|---|---|---|---|
| A | `-O3 -CR` build + **Valgrind memcheck** | uninitialised reads, invalid accesses, leaks inside the C library | heaptrc sees only FPC's heap, and only "was it freed" |
| B | **exhaustiveness** over every enumeration | gaps and collisions in the translation tables | existing tests use the dozen values they happen to need |
| C | **state matrix**: every method × every lifecycle state | undefined behaviour at state boundaries | `MisuseTest` predates Rev.6.0's twelve new methods |
| D | **differential test against `rigctld`** | our reading of Hamlib differing from Hamlib's | self-verification is a closed loop |
| E | **second backend and transport** (`NETRIGCTL` over TCP) | assumptions that only hold for the in-process dummy | every prior test opened model 1 with an empty port |
| F | **randomized property test** | orders nobody thought to write down | hand-written scenarios test imagined orders |
| G | **soak with heap sampling** | slow growth, races under sustained churn | short tests cannot see a slope |

**D is the one that matters most in principle.** Every other test in
this project checks the component against *our own* understanding of
Hamlib. A misreading of the C API produces a test that asserts the
misreading, and the suite goes green. The only way out of that loop is
an oracle written independently of us that is authoritative about what
Hamlib means — Hamlib's own reference client.

**原理的に最も重要なのは D です。** 本プロジェクトの他のすべてのテスト
は、コンポーネントを「我々自身の」Hamlib 理解と照合します。C API の
読み違いは、その読み違いを主張するテストを生み、テスト群は緑になります。
この環から出る唯一の方法は、我々と独立に書かれ、Hamlib の意味について
権威を持つオラクル、すなわち Hamlib 自身の参照クライアントです。

---

### 2.2 What was found / 発見された欠陥

Six further defects, plus one in the project's own ABI fitness function
and one in an existing test. Four of the six could produce wrong behaviour
on the air; two were memory-safety or resource issues.

コンポーネントに 6 件、そのフィットネス関数自体に 1 件、既存テストに
1 件。6 件のうち 4 件は運用上の誤動作を生みえ、2 件はメモリ安全性または
資源の問題でした。

### F-1 — the shortest way to enable split was the dangerous one *(D)*

`IRigService.SetSplitAsync(AEnabled, ATxVfo, ACallback)` declares
`ATxVfo` with a default of `rvfoCurr`. So `SetSplitAsync(True)` told
the rig to transmit on the VFO it was already receiving on. That is not
split: it is transmitting on the DX station's own frequency. The rig
accepted it, the call reported success, and the application believed it
was set up.

`SetVfoAsync(rvfoCurr)` was already refused as meaningless. The far more
dangerous call was accepted, and it was the one with the shorter form.

`SetSplitAsync` の `ATxVfo` は既定値が `rvfoCurr` でした。つまり
`SetSplitAsync(True)` は「既に受信している VFO で送信せよ」とリグに
告げていました。それはスプリットではなく、DX 局自身の周波数で送信する
ことです。リグは受理し、呼び出しは成功を報告し、アプリケーションは設定
できたと信じます。

`SetVfoAsync(rvfoCurr)` は既に無意味として拒否されていました。はるかに
危険な呼び出しのほうが受理され、しかもそちらが短い形でした。

**Fixed**: enabling split with `rvfoCurr` now raises
`EArgumentException` naming what is wrong and what to pass instead.

### F-2 — turning split off destroyed the rig's transmit-VFO record *(D)*

`rig_set_split_vfo` takes a `tx_vfo` even when told to disable, and
whatever is passed is what the rig records. `SetSplitAsync(False)`
passed `RIG_VFO_CURR`, overwriting it. The differential test is what
made this visible: against the identical sequence, `rigctld` answered
`0|VFOB` where the component answered `0|currVFO`.

It matters because the next `SetSplitAsync(True)` would be nominating a
transmit VFO that no longer means anything.

`rig_set_split_vfo` は無効化を指示されるときでも `tx_vfo` を取り、渡した
ものがそのままリグに記録されます。`SetSplitAsync(False)` は
`RIG_VFO_CURR` を渡して上書きしていました。これを可視化したのは差分
テストです。同一の操作列に対し `rigctld` が `0|VFOB` と答えた箇所で、
コンポーネントは `0|currVFO` と答えました。

これが問題なのは、次の `SetSplitAsync(True)` が、もはや何も意味しない
送信 VFO を指名することになるからです。

**Fixed**: disabling without naming a VFO now reads the existing
nomination and hands it straight back. The read is allowed to fail —
disabling split is a safety operation and must not be blocked by an
inability to read the rig.

### F-3 — capabilities survived a disconnection *(C)*

`GetCapabilities` kept answering `Known = True` after `Close`, so an
application polling it between connections was told the previous
model's capabilities. It was the only query that was not reset on
Close. The second sample application had been blanking its capability
panel by hand on disconnect — the component making every caller do its
clearing for it.

`GetCapabilities` は `Close` の後も `Known = True` を返し続けていたため、
接続の合間にそれを読むアプリケーションは前の機種の能力を告げられて
いました。Close 時にリセットされない唯一の問い合わせでした。2 つ目の
サンプルアプリは切断時に能力パネルを手で空にしていました。コンポーネント
が自分の後始末を全呼び出し側にさせていたということです。

**Fixed**: `Close` clears it.

### F-4 — the snapshot said "not connected" after a successful Open *(F)*

`Open` returned with `IsOpen = True` while `CurrentState.Connected` was
`False`, and it stayed False **indefinitely** — not briefly — because
the worker's announcement travels through `TThread.Queue` and is
delivered only when the application next runs a message pump. A console
program, or a scheduled job, never sees it become true.

`Close` had always updated the snapshot synchronously, so the two ends
of the lifecycle disagreed about whether the snapshot may lag.

`Open` は `IsOpen = True` で戻る一方、`CurrentState.Connected` は
`False` であり、しかも「短時間」ではなく**無期限に** False のままでした。
ワーカーの通知が `TThread.Queue` を通り、アプリケーションが次にメッセージ
ポンプを回したときにしか配送されないからです。コンソールプログラムや
スケジュール実行のジョブでは、永遠に true になりません。

`Close` は以前から同期的に更新していたため、ライフサイクルの両端が
「スナップショットの遅れを許すか」で食い違っていました。

**Fixed**: `Open` records it synchronously before returning.

### F-5 — a use-after-free inside `Close` *(F)* — the serious one

The randomized test crashed with an access violation. Reduced to a
short reproducer (open, poll, leave results queued, `Close`), it
crashed within three rounds, every time.

The mechanism:

1. a poll result travels poller thread → Worker → `TThread.Queue` → UI
   thread;
2. the queued delivery held `@Poller.HandleFreqResult` — a raw method
   pointer bound to the poller instance;
3. `DisablePolling` frees that instance;
4. `Close` calls `DisablePolling` and then `FWorker.WaitFor` — and
   **FPC's `TThread.WaitFor` runs `CheckSynchronize` while it waits**,
   so the queued delivery fires microseconds after its target was
   freed, inside `Close` itself.

ランダム化テストがアクセス違反で落ちました。短い再現コード (open、
ポーリング、結果をキューに残す、`Close`) に縮約すると、毎回 3 周以内に
落ちました。機構は上記 1〜4 のとおりです。要点は、**FPC の
`TThread.WaitFor` が待機中に `CheckSynchronize` を回す**ため、解放された
対象へのキュー済み配送が `Close` の内部で発火することです。

The component's own rule is that anything a queued delivery touches
must either outlive every possible delivery or be held by reference
count — `IRigStateHolder` was already held that way by the dispatch
objects. The poller's handler was the one thing that broke the rule.

コンポーネント自身の規則は「キュー済み配送が触れるものは、あらゆる配送
より長生きするか、参照カウントで保持されるかのいずれかでなければなら
ない」です。`IRigStateHolder` は既に配送オブジェクトがその形で保持して
いました。この規則を破っていた唯一のものがポーラのハンドラでした。

**Fixed**: the handler moved into `TRigPollFreqSink`, a reference-counted
object the delivery holds through the new `IRigDeliveryKeepAlive`. It
outlives the poller thread and the `Close`. A `Deactivate` flag turns a
late result into a no-op rather than an announcement about a rig nobody
is polling any more.

### F-6 — 4.5 KB leaked inside libhamlib per Service created *(G, via Valgrind)*

Round 1 had already found that `rig_load_all_backends()` is not
idempotent, and fixed it by scoping the "backends are registered" flag
to the process instead of to the loader instance. That fix is correct
and holds for Services that exist **at the same time**: the library
stays loaded, the flag stays set, and registration happens once.

It cannot hold for Services created **one after another**. Each
`THamlibLoader` dlopens the library; when the last one lets go the
library leaves the process, and `Unload` clears the process-wide flag —
deliberately and correctly, because a reloaded library has an empty
backend table and would otherwise never have its backends registered at
all. So a factory that builds a fresh loader per Service runs a full
load → register → unload cycle per Service, and the registration leaks
every time.

Round 1 は既に `rig_load_all_backends()` が冪等でないことを発見し、
「バックエンド登録済み」フラグの有効範囲をローダ実体からプロセス全体へ
広げて修正していました。その修正は正しく、**同時に存在する** Service に
ついては成立します。ライブラリはロードされたままでフラグも立ったまま、
登録は 1 回です。

**逐次に生成される** Service については成立しません。各
`THamlibLoader` はライブラリを dlopen し、最後の 1 つが手放すとライブラリ
はプロセスから外れ、`Unload` はプロセス全体のフラグを消します。これは
意図的かつ正しい動作です。再ロードされたライブラリのバックエンド表は空で
あり、さもなければ登録が永久に行われないからです。したがって Service
ごとに新しいローダを作るファクトリは、Service ごとに ロード → 登録 →
アンロード の完全なサイクルを回し、そのたびに登録が漏れます。

And Hamlib's `rig_load_all_backends()` is:

```c
int rig_load_all_backends() {
    memset(rig_hash_table, 0, sizeof(rig_hash_table));  /* abandons 283 nodes */
    for (...) rig_load_backend(...);                     /* calloc's 283 more */
}
```

`dlclose` does not reclaim them. Measured over 123 Service lifecycles:
**34,809 lost blocks — exactly 123 × 283**, every one traced to
`EnsureBackendsLoaded`.

FPC's own heap showed **zero** growth throughout, because the leak is on
the C library's heap. Only Valgrind could see it. This is the single
clearest argument for method A.

各 `THamlibLoader` はライブラリを dlopen し、最後の 1 つが手放すと
ライブラリはプロセスから外れます。ファクトリは Service ごとに新しい
ローダを作っていたため、Service の生成ごとに ロード → バックエンド登録
→ アンロード のサイクルが回っていました。そして Hamlib の
`rig_load_all_backends()` は上記のとおり、表を memset してから 283 個を
calloc し直します。`dlclose` はそれらを回収しません。

Service のライフサイクル 123 回で実測: **喪失ブロック 34,809 個、
ちょうど 123 × 283**、そのすべてが `EnsureBackendsLoaded` 由来。

FPC 側の heap はその間ずっと増加**ゼロ**でした。漏れが C ライブラリの
heap 上にあるからです。見えたのは Valgrind だけです。これが手法 A を
採った最も明確な根拠です。

**Fixed**: a factory now shares one loader across every Service it
makes, so the library is loaded once and stays loaded for as long as
the factory lives. Same workload: **556,944 bytes → 18,112 bytes**, and
the remainder is exactly 4 × 283 because that test builds four
factories. One registration per factory instead of per Service.

This completes Round 1's fix rather than replacing it. Nothing about
the flag's scoping was wrong; the avoidable part was running the
load/unload cycle at all. An application that reconnects by calling
`Close` and `Open` on one Service — which is what both sample
applications do — never leaked in either round. The pattern that leaked
was recreating the `IRigService` per connection.

これは Round 1 の修正を置き換えるのではなく完成させるものです。フラグの
有効範囲に誤りはありませんでした。避けられたのは、ロード/アンロードの
サイクルを回すこと自体です。1 つの Service に対し `Close` と `Open` を
呼んで再接続するアプリケーション (両サンプルアプリがそうです) は、どちらの
ラウンドでも漏らしていません。漏れていたのは、接続ごとに `IRigService`
を作り直すパターンです。

### F-7 — the ABI checker had a blind spot in itself *(B)*

The same Hamlib error ordinal is declared in four units, with two
different signs (`RIG_ENAVAIL = 11` in `HamlibTypes`,
`RIG_ENAVAIL_CODE = 11` in `HamlibLoader`, `ENAVAIL = -11` in
`HamlibRigCommands`). `check_abi.py` read only `HamlibTypes.pas`, so
**three of the four copies had never been checked against `rig.h`**.
The duplication is deliberate — it keeps the loader from depending on
`HamlibTypes` — but duplication is only acceptable while something
proves the copies agree.

同じ Hamlib のエラー序数が 4 つのユニットで、2 通りの符号で宣言されて
います。`check_abi.py` は `HamlibTypes.pas` しか読んでいなかったため、
**4 つのうち 3 つは一度も `rig.h` と照合されていませんでした**。重複は
意図的 (ローダを `HamlibTypes` に依存させないため) ですが、重複が許される
のは、写しが一致していることを何かが証明している間だけです。

**Fixed**: the checker now verifies every `RIG_E*` ordinal declared
anywhere in `src/`, regardless of sign or unit. Constants checked went
from 110 to 133. The check was then self-tested by deliberately
corrupting one copy and confirming the script fails:

```
MISMATCH  HamlibRigCommands.pas: ENAVAIL = 12, but rig.h says RIG_ENAVAIL = 11
ABI check FAILED.
```

### F-8 — a test that could not fail *(B)*

`LifecycleTest` set a `LoaderFreed` flag in the fake loader's destructor
and never looked at it; three cases reported OK on `ServiceFreed` alone.
A loader outliving its Service — a reference surviving somewhere, the
library never unloaded — would have been recorded and then ignored. The
compiler had been saying so as a note in every build.

`LifecycleTest` は偽ローダのデストラクタで `LoaderFreed` を立て、一度も
参照していませんでした。3 つの事例は `ServiceFreed` だけで OK と報告して
いました。コンパイラは毎回のビルドで note として指摘していました。

**Fixed**: all three cases now require both. All three pass — the
behaviour was always correct, but it had never been verified, and a
check that cannot fail is worse than no check because it reads like one.

---

### 2.3 Defects found in the new tests themselves

Three of the new tests were wrong before the component was. They are
recorded because the corrections are the interesting part.

新しいテストのうち 3 件は、コンポーネントより先にテスト自身が誤って
いました。修正内容こそが興味深いため記録します。

- **Equality was the wrong comparison for the S-meter.** The
  differential test flagged a disagreement on
  `RIG_LEVEL_STRENGTH`. Reading `rigs/dummy/dummy.c` settled it: the
  value is `qrm + (time(NULL) % 32) + (rand() % 4) - att + preamp`,
  with the comment *"make S-Meter jiggle"*. It is deliberately
  non-deterministic, so two processes cannot agree. The step is now a
  bounded check — both answers must be integers in the range the
  formula can produce — with the reason recorded in the table rather
  than in a comment, so an unexplained difference can never be waved
  through.

  **S メータに等値比較は誤りでした。** 差分テストが
  `RIG_LEVEL_STRENGTH` の不一致を報告しました。`dummy.c` を読んで決着:
  値は `qrm + (time(NULL) % 32) + (rand() % 4) - att + preamp` で、
  コメントは *"make S-Meter jiggle"*。意図的に非決定的であり、2 つの
  プロセスが一致することはありえません。現在は範囲検査とし、理由を
  コメントではなく表に記録しています。説明のつかない差異が黙って通る
  ことはなくなります。

- **A drain condition expressed as a duration measures the machine.**
  The property test slept four seconds and asserted everything had been
  delivered; 862 commands were still queued, so it reported 863 "lost"
  callbacks that were merely late — and those then arrived during the
  next phase and were counted there, making that phase report callbacks
  it had never issued. Replaced with a wait on *state*: queue empty and
  no new delivery for a sustained period.

  **掃き出し条件を時間で表すと、測るのはマシンです。** 4 秒 sleep して
  全配送済みと主張したところ、862 コマンドがまだキューにあり、単に遅れて
  いただけの 863 件を「消失」と報告しました。さらにそれらが次フェーズで
  計上され、「発行していないコールバックを受け取った」と報告させました。
  「キューが空で、一定期間新たな配送がない」という*状態*での待機に
  置き換えました。

- **An invariant that is not stated precisely tests the wording, not the
  component.** "The timestamp never goes backwards" fired 233 times:
  `Close` resets the snapshot to `Timestamp = 0`, which is the
  documented "no data yet", and the check then kept comparing against
  the old high-water mark. Restated: zero is a re-baseline; only a
  decrease between two non-zero readings is a violation.

  **精密に述べられていない不変条件が検査するのは、コンポーネントでは
  なくその文言です。** 「タイムスタンプは巻き戻らない」が 233 回発火
  しました。`Close` はスナップショットを `Timestamp = 0` に戻し、それは
  文書化された「まだデータなし」です。述べ直し: 0 は基準の取り直しで
  あり、違反は非零の 2 値間の減少だけです。

---

### 2.4 Results / 結果

### The new tests / 新しいテスト

| Test | Method | Result |
|---|---|---|
| `test/ExhaustivenessTest.lpr` | B | 771 / 771 |
| `test/StateMatrixTest.lpr` | C | 118 / 118 |
| `test/DifferentialTest.lpr` + `tools/differential.py` | D | 21 / 21 steps agree with `rigctld` |
| `test/NetBackendTest.lpr` | E | 12 / 12 over TCP, model 2 |
| `test/RandomSequenceTest.lpr` | F | 8 / 8 on each of 7 seeds |
| `test/StressTest.lpr` | G | 9 / 9 |

### Valgrind / A

| Binary | Invalid or uninitialised accesses | Leaked |
|---|---|---|
| `DomainTypeTest`, `LifecycleTest`, `MisuseTest` (no real Hamlib) | 0 | 0 bytes |
| `FeatureMatrixTest`, `DxConformanceTest` | 0 | 4,528 bytes — one backend registration |
| `RandomSequenceTest` (chaos path) | 0 | 4,528 bytes |
| `StressTest` (123 Service lifecycles) | 0 | 18,112 bytes — 4 factories (was 556,944) |

**No invalid read, invalid write, or use of uninitialised memory
anywhere**, which is the result that matters most for the `value_t`
union: it is a 16-byte C union passed *by value* across the FFI
boundary, and a misread would show here.

**無効な読み取り・書き込み・未初期化メモリの使用はどこにもありません。**
これは `value_t` にとって最も重要な結果です。FFI 境界を値渡しで越える
16 バイトの C 共用体であり、読み違いがあればここに現れます。

### Property-test detail / プロパティテストの詳細

Across seven seeds, phase 2 (cancels, polling toggles and `Close`/`Open`
interleaved at random) delivered **exactly as many callbacks as were
issued**, every time, despite 21–30 mid-run `Close` calls per seed. The
test only requires `delivered ≤ issued` there; equality is a stronger
result than was asked for.

7 つのシードすべてで、フェーズ 2 (キャンセル・ポーリング切り替え・
`Close`/`Open` をランダムに織り交ぜる) は、シードあたり 21〜30 回の
実行中 `Close` にもかかわらず、毎回**発行数とちょうど同じ数**の
コールバックを配送しました。テストが要求するのは
`配送数 ≤ 発行数` だけであり、等号は要求より強い結果です。

### Soak detail / ソークの詳細

Zero heap growth across 110 Service lifecycles, 110 polling toggles with
results in flight, 2,400 cancelled commands, and a 4,000-deep queue
drained completely with the circuit breaker staying closed — a backlog
is correctly not mistaken for a failing rig.

Service のライフサイクル 110 回、結果実行中のポーリング切り替え 110 回、
キャンセル 2,400 件、深さ 4,000 のキューの完全な掃き出しを通じて heap の
増加はゼロ。かつ遮断器は閉じたままでした。滞留が「故障したリグ」と
取り違えられないことが確認できます。

---

### 2.5 Restoring what the overwritten test covered

`test/RandomSequenceTest.lpr` now keeps its accounting **per command
shape**, not only in total, which is the property the lost version
pinned. A total alone cannot see a defect that loses every callback of
one kind while the others cover for it in the sum — and that is exactly
Round 1's third defect, where the four Rev.6.0 Get commands fell
through a cancellation path that knew only the shapes existing when it
was written.

A dedicated phase issues twelve of each of the fourteen shapes, cancels
them all before they can run, and requires each shape to balance
individually. The phase also counts how many results came back as
`rcsCancelled` and fails if none did, because a phase in which every
command happened to finish before the cancel landed would pass while
testing nothing. Measured: **168 issued, 168 delivered, 168 of them
`rcsCancelled`, all 14 shapes balanced**.

`test/RandomSequenceTest.lpr` は会計を合計だけでなく**コマンドの種類
ごと**に保持します。これが失われた版の固定していた性質です。合計だけ
では、ある種類のコールバックを全部失いながら他の種類が合計を埋めて
しまう欠陥が見えません。それこそ Round 1 の 3 件目、書かれた時点の種類
しか知らないキャンセル経路に Rev.6.0 の Get コマンド 4 種が落ちていた
事例です。

専用フェーズが 14 種類それぞれを 12 個ずつ発行し、実行される前にすべて
キャンセルし、種類ごとに収支が合うことを要求します。さらに
`rcsCancelled` で戻った件数を数え、0 件なら失敗させます。すべての
コマンドがキャンセル到達前に偶然完了したフェーズは、何も検査せずに合格
してしまうからです。実測: **発行 168、配送 168、うち `rcsCancelled`
168、14 種類すべて収支一致**。

---

## What is still not verified / なお未検証のこと

Unchanged, and worth repeating because none of this work touched it:

- **No real transceiver.** Everything runs against Hamlib's dummy
  backend or `rigctld` in front of it. Serial timing, CI-V bus
  contention and per-model quirks are untested.
- **The tier-1 timeout cannot be verified without hardware.** A dummy
  rig never fails to answer.
- **The watchdog's cross-thread `rig_close`** remains the single
  documented exception to thread confinement and a recorded risk.
- **One platform.** Linux / FPC 3.2.2 / x86-64. Windows and macOS are
  unexercised, and F-5 was a threading defect — the class most likely
  to behave differently elsewhere.
- **`rig_get_conf`** is still the one gap in the set of calls the
  surveyed applications use (`COVERAGE_MATRIX.md` §4.1).

実機なし、第 1 段タイムアウト、ウォッチドッグのスレッド跨ぎ
`rig_close`、単一プラットフォーム (F-5 はスレッド関連の欠陥であり、
他環境で挙動が変わりやすい種類です)、`rig_get_conf` 未実装。

---

## How to re-run / 再実行方法

```sh
# A — Valgrind (build without -gh; heaptrc and valgrind conflict)
fpc -Mobjfpc -Sh -O3 -CR -Criot -Sa -gv -gl -Fusrc -FEout test/StressTest.lpr
valgrind --tool=memcheck --track-origins=yes --leak-check=full ./out/StressTest

# B, C, F, G
for t in ExhaustivenessTest StateMatrixTest RandomSequenceTest StressTest; do
  fpc -Mobjfpc -Sh -Sa -Criot -gh -Fusrc -FEout test/$t.lpr && ./out/$t
done
./out/RandomSequenceTest 42 3000        # any seed; a failure prints its seed

# D — differential against Hamlib's own client
fpc -Mobjfpc -Sh -Sa -Criot -gh -Fusrc -FEout test/DifferentialTest.lpr
python3 tools/differential.py --binary ./out/DifferentialTest

# E — second backend and transport
rigctld -m 1 -t 4598 &
fpc -Mobjfpc -Sh -Sa -Criot -gh -Fusrc -FEout test/NetBackendTest.lpr
./out/NetBackendTest 127.0.0.1:4598

# the ABI checker, now covering every unit
python3 tools/check_abi.py
```
