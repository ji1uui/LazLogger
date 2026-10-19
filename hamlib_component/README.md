# HamlibComponent — Lazarus Package (Rev.6.1)

Cross-platform Lazarus/Free Pascal wrapper component for the
[Hamlib](https://github.com/Hamlib/Hamlib) amateur radio rig control library.

Lazarus/Free Pascal 用の [Hamlib](https://github.com/Hamlib/Hamlib) アマチュア無線機制御ライブラリ・ラッパーコンポーネント。

## Features / 特徴

- **Cross-platform** — Windows / macOS (Intel & Apple Silicon) / Linux
- **LCL-free core** — works in console programs and unit tests
- **Thread-isolated Worker** — UI is never blocked by Hamlib I/O
- **Use-After-Free elimination** — DeliverAndFree pattern + value-type results
- **ICancellationToken** — RAII-style cancellation
- **Self-defending Service destructor** — survives forgotten Close/CancelAllPending
- **No reference cycles** — the poller uses method pointers, never an interface reference
- **Two-tier command timeout** — Hamlib's own timeout/retry plus a watchdog thread that
  unblocks wedged I/O, so a dead rig can never hang the worker
- **Domain types, not Hamlib values** — `TRigMode`, `TRigErrorKind` and a runtime rig
  catalogue, so application code never hard-codes a number owned by Hamlib
- **ABI verified mechanically** — `tools/check_abi.py` checks up to 111 shared
  constants against the real Hamlib headers for 4.5.5, 4.6, 4.7.2 and master
  (109/110/111/110, zero mismatches); a mismatch is a failed CI run instead of a
  radio that half works
- **Thread confinement proven, not asserted** — `test/ThreadConfinementTest.lpr`
  observes every call that touches the rig handle and fails if more than one thread
  ever does, with the watchdog abort as the single documented exception
- **Version gate** — a Hamlib outside the verified range is refused at startup unless
  the application explicitly opts in
- **Hardware timeout policies** — Default / FastUsb / SlowCat / VerySlowCat
- **Adaptive Circuit Breaker** — handles intermittent CI-V bus delays
- **Pull/Push state model** — both `OnFrequencyChanged` event and `CurrentState` property
- **Split operation, VFO selection and VFO operations** — the surface every
  surveyed Hamlib application leans on; see `COVERAGE_MATRIX.md`
- **Levels and functions** — the S-meter, RF power, noise blanker and the rest,
  with the `value_t` float/integer distinction made explicit in the result type
  rather than left for the caller to guess
- **Capability query, reported honestly** — Hamlib's stable C API exposes five
  fields, so empty sets are documented as "not asked", never "not supported"
- **Conf tokens before Open** — `AddConfToken('ptt_type', 'RIG')`, applied after
  the port and before the component's own timeouts, as WSJT-X and fldigi do

---

## Documentation / ドキュメント

| 文書 | 内容 |
|---|---|
| **`USERS_GUIDE.md`** | **利用ガイド。二つのサンプルを教材に、Hamlib の考え方と本コンポーネントの使い方を説明します。まずここから。** |
| `COVERAGE_MATRIX.md` | 実アプリが使う Hamlib 機能と本実装の対応表 |
| `VERIFICATION_REPORT.md` | 検証手法と、見つかった欠陥の記録 |
| `REV6_REPORT.md` / `REV5_REPORT.md` | 版ごとの設計判断 |

`USERS_GUIDE.md` is the place to start: it explains the component — and
the Hamlib concepts behind it — using `demo/RigPanel` and
`demo2/DxPanel` as the worked examples.

---

## Installation / インストール

1. Open Lazarus IDE
2. **Package → Open Package File (.lpk)** → select `package/HamlibComponent.lpk`
3. Click **Compile**
4. Click **Use → Install** (Lazarus will rebuild)

### The uses clause / uses 節

Object Pascal has no transitive visibility, so `uses HamlibComponent` alone does **not**
make `IRigService` or `rmUSB` visible — earlier revisions of this README claimed it did,
which was wrong. List the units you need:

Object Pascal に推移的な可視性はないため、`uses HamlibComponent` だけでは
`IRigService` や `rmUSB` は見えません。本 README の以前の版はそう書いていましたが
誤りでした。必要なユニットを列挙してください。

```pascal
uses
  HamlibInterfaces,     // types, IRigService, TRigMode, TRigErrorKind
  HamlibFactory,        // TRigServiceFactory
  HamlibErrors,         // exception classes, RigErrorKindToString
  HamlibTimeoutPolicy,  // RigPolicy_FastUsb and friends
  HamlibModeCodec,      // mode display strings (optional)
  HamlibLevelCodec,     // level and function labels (optional)
  HamlibVfoCodec,       // RigVfoToString, RigVfoSelectionMatches (optional)
  HamlibCatalog;        // RigModelInfoToString (optional)
```

The first two are enough for a minimal application.
最小構成では最初の 2 つで足ります。

---

## Requirements / 必要環境

### Lazarus / Free Pascal

- Lazarus 2.2+ (3.0+ recommended)
- Free Pascal 3.2+

**Every Unix program using this component must put `cthreads` first in
`uses` — LCL applications included.** The component uses `TThread`, and
without it the program aborts with runtime error 232 or
"Failed to create OS basic event".

Rev.5.0 of this README said LCL applications did not need it, because the
widgetset normally links it. Building and running the `demo/RigPanel`
application disproved that: on Lazarus 3.0 / FPC 3.2.2 with gtk2 it died
at startup. Some widgetset and version combinations do link it; relying
on that ships an application that starts on the developer's machine and
not on the user's.

**本コンポーネントを使う Unix のプログラムは、LCL アプリも含めて
`uses` の先頭に `cthreads` を置いてください。** 本コンポーネントは
`TThread` を使うため、これがないと実行時エラー 232 または
"Failed to create OS basic event" で停止します。

本 README の Rev.5.0 は「LCL アプリでは不要」と書いていました。
ウィジェットセットが通常リンクするためです。`demo/RigPanel` を
ビルドして実行した結果、それは誤りでした。Lazarus 3.0 / FPC 3.2.2 の
gtk2 では起動時に停止します。リンクされる組み合わせもありますが、
それに頼ると「開発者の環境では起動し、利用者の環境では起動しない」
アプリケーションを出荷することになります。

```pascal
program MyTest;
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}   // ← must come first / 必ず最初に
  Classes, SysUtils, HamlibInterfaces, HamlibFactory;
```

```pascal
program MyLazarusApp;
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}   // ← before Interfaces, too
  Interfaces, Forms,
  MainForm;
```

### Hamlib runtime library

The component loads Hamlib dynamically at runtime. You must install the library yourself:

| OS | Method |
|---|---|
| Windows | Download `hamlib-w64-4.x.x.zip` from Hamlib releases, extract `libhamlib-4.dll` to your application directory or `hamlib/` subdirectory |
| macOS (Apple Silicon) | `brew install hamlib` (installs to `/opt/homebrew/lib/`) |
| macOS (Intel) | `brew install hamlib` (installs to `/usr/local/lib/`) |
| Linux | `sudo apt install libhamlib4` or equivalent |

The component also honors the `VELA_HAMLIB_PATH` environment variable for explicit override.

`VELA_HAMLIB_PATH` 環境変数で明示的なオーバーライドも可能です。

---

## Quick Start / クイックスタート

```pascal
uses
  HamlibInterfaces, HamlibFactory, HamlibErrors, HamlibTimeoutPolicy,
  HamlibModeCodec, HamlibCatalog;

procedure TMainForm.FormCreate(Sender: TObject);
var
  Factory: IRigServiceFactory;
  i:       Integer;
begin
  Factory := TRigServiceFactory.Create;

  { Ask the library which rigs it can drive, instead of hard-coding a
    model number. New rigs then appear when Hamlib is upgraded, with no
    recompile. }
  FCatalog := Factory.CreateModelCatalog;
  if FCatalog.IsAvailable then
    for i := 0 to FCatalog.Count - 1 do
      cmbRig.Items.Add(RigModelInfoToString(FCatalog.Items[i]))
  else
    { An old or trimmed Hamlib cannot enumerate; fall back to an entry field. }
    edtModelNumber.Visible := True;

  FService := Factory.CreateServiceWithPolicy(RigPolicy_FastUsb);
  FService.SetOnError(@HandleRigError);
  FService.SetOnFrequencyChanged(@HandleFreqChanged);
  FService.Open(FCatalog.Items[cmbRig.ItemIndex].ModelNumber, 'COM5');
  FService.EnablePolling(150);
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  // Even if you forget these calls, Service.Destroy will clean up safely.
  // これらの呼び出しを忘れても Service.Destroy が安全に後始末します。
  FService.DisablePolling;
  FService.CancelAllPending;
  FService.Close;
  FService := nil;
end;

procedure TMainForm.btnQsyClick(Sender: TObject);
begin
  // No callback, no VFO — errors route to OnError automatically.
  // コールバック・VFO 指定なしで呼び出し、エラーは OnError に自動経路。
  FService.SetFrequencyAsync(14074000.0);
end;

procedure TMainForm.HandleFreqChanged(Sender: TObject; AFreq: Double);
begin
  lblFreq.Caption := FormatFloat('#,##0.000', AFreq / 1e6) + ' MHz';
end;

procedure TMainForm.btnUsbClick(Sender: TObject);
begin
  // 0 = let the rig pick its default passband for this mode.
  FService.SetModeAsync(rmUSB);
end;

procedure TMainForm.HandleMode(const AResult: TRigModeResult);
begin
  if AResult.Status <> rcsSuccess then Exit;
  // rmUnknown means a mode this binding has no name for; RawMode still
  // carries the value the rig reported.
  lblMode.Caption := THamlibModeCodec.ToDisplayString(AResult.Mode);
end;

procedure TMainForm.HandleRigError(Sender: TObject; AKind: TRigErrorKind;
                                    ANativeCode: Integer; const AMsg: string);
begin
  // Branch on AKind, never on ANativeCode.
  case AKind of
    rekNotConnected, rekConnectFailed:
      lblStatus.Caption := 'Rig not responding — check power and cable';
    rekAccessDenied:
      lblStatus.Caption := 'Serial port is in use by another application';
    rekTimeout:
      lblStatus.Caption := 'Rig timed out';
    rekNotAvailable:
      lblStatus.Caption := 'This rig does not support that function';
  else
    lblStatus.Caption := Format('%s (%s, native %d)',
      [AMsg, RigErrorKindToString(AKind), ANativeCode]);
  end;
end;
```

---

### Split operation / スプリット運用

```pascal
{ Set up split: listen on VFO A, transmit on VFO B.
  Each call is asynchronous; the callback arrives on the UI thread.
  スプリット設定: VFO A で受信し、VFO B で送信します。
  各呼び出しは非同期で、コールバックは UI スレッドに届きます。 }
Service.SetVfoAsync(rvfoA);
Service.SetFrequencyAsync(14023000, rvfoA);
Service.SetSplitAsync(True, rvfoB);
Service.SetSplitFreqAsync(14205000, @HandleSplitSet);
Service.GetSplitAsync(@HandleSplitRead);   // confirm from the rig
```

The order matters: `SetSplitFreqAsync` takes no VFO because it addresses
*the transmit VFO*, which `SetSplitAsync` has just named. If any step can
fail — and over a serial link any of them can — see
`demo2/DxSplitSequence.pas`, which runs exactly this sequence and turns
split off again if it fails after enabling it.

順序が重要です。`SetSplitFreqAsync` が VFO を取らないのは、対象が
「送信 VFO」であり、それを `SetSplitAsync` が今名指ししたところだからです。
いずれかの手順が失敗しうるなら (シリアル回線ではどれも失敗しえます)、
`demo2/DxSplitSequence.pas` を参照してください。まさにこのシーケンスを
実行し、スプリット有効化の後に失敗した場合はスプリットを解除します。

### The S-meter / S メータ

```pascal
Service.GetLevelAsync(rlvStrength, @HandleStrength);

procedure TMyForm.HandleStrength(const AResult: TRigLevelResult);
begin
  if AResult.Status <> rcsSuccess then Exit;   { many rigs answer ENAVAIL }

  { IsFloat says which half of the C union holds the value. Reading an
    integer level as a float gives a number in the hundreds of millions.
    IsFloat は C 共用体のどちら側に値があるかを示します。整数レベルを
    float として読むと数億の値になります。 }
  if AResult.IsFloat then
    ShowMeter(Round(AResult.FloatValue))
  else
    ShowMeter(AResult.IntValue);              { dB relative to S9 }
end;
```

---

## Files / ファイル構成

```
package/
  HamlibComponent.lpk     Lazarus package definition / Lazarus パッケージ定義

src/
  HamlibInterfaces.pas    Public interfaces and types  / 公開 IF と型
  HamlibErrors.pas        Exceptions and CheckRig      / 例外と CheckRig
  HamlibTypes.pas         Mode/Model constants         / モード・モデル定数
  HamlibVfoCodec.pas      VFO value codec              / VFO 値コーデック
  HamlibModeCodec.pas     Mode value codec (TRigMode)  / モード値コーデック
  HamlibLevelCodec.pas    Level/function codec + labels/ レベル・機能コーデック
  HamlibTimeoutPolicy.pas Hardware timeout policies    / ハードウェアポリシー

  HamlibLoader.pas        L1: dynamic loader           / 動的ローダ

  HamlibCancellation.pas  TRigCancellationToken
  HamlibCommandBase.pas   Base command + ResultWindow
  HamlibFreqCommands.pas  Set/Get frequency commands
  HamlibModeCommands.pas  Set/Get mode commands
  HamlibPttCommands.pas   Set/Get PTT commands
  HamlibRigCommands.pas   Level/func/split/VFO commands/ レベル・機能・スプリット
  HamlibCommandQueue.pas  Thread-safe command queue
  HamlibWorker.pas        L3: single-threaded worker

  HamlibWatchdog.pas      L3: tier-2 timeout supervisor
  HamlibPoller.pas        L5: LCL-free polling thread
  HamlibStateHolder.pas   Pull-model state snapshot    / 状態スナップショット
  HamlibCatalog.pas       Runtime rig catalogue        / 実行時リグカタログ

  HamlibDispatch.pas      L4: callback delivery objects
  HamlibService.pas       L4: main facade
  HamlibFactory.pas       L4: dependency injection factory

  HamlibComponent.pas     Master unit (build only)     / マスターユニット
  HamlibRegister.pas      Lazarus IDE registration     / Lazarus IDE 登録

test/
  fakeloader.inc            Minimal IHamlibLoader fake
  FakeHamlibLoader.pas      Richer fake with simulated state
  LifecycleTest.lpr         Open/close/command lifecycle
  DanglingTest.lpr          No callback after destruction
  LeakTest.lpr / LeakTest2  heaptrc leak checks
  MisuseTest.lpr            Deliberate API misuse
  ConnectFailTest.lpr       Connection failure, nil-handle refusal
  TimeoutTest.lpr           Two-tier timeout and watchdog abort
  VersionGateTest.lpr       Version gate and model verification
  ThreadConfinementTest.lpr Thread-confinement fitness function
  ThreadStartupTest.lpr     Threads torn down before they ever ran
  ExhaustivenessTest.lpr    Every value of every public enumeration
  StateMatrixTest.lpr       Every method x every lifecycle state
  DifferentialTest.lpr      Our half of the rigctld differential test
  NetBackendTest.lpr        The component over TCP against model 2
  StressTest.lpr            Sustained churn with the heap sampled
  DomainTypeTest.lpr        TRigMode / TRigErrorKind / catalogue
  RandomSequenceTest.lpr    Random call sequences + invariants
  TransportTest.lpr         Driven over a REAL serial port or TCP
  SoakTest.lpr              Long run; memory, descriptors, threads
  PerfTest.lpr              Queue throughput

demo/
  RigPanelView.pas        IRigView — what the window can display
  RigPanelPresenter.pas   All the demo's behaviour, LCL-free
  MainForm.pas            The window: control placement + event forwarding
  RigPanel.lpr / .lpi     The LCL application (lazbuild RigPanel.lpi)
  ScenarioTest.lpr        The presenter driven through whole sessions
  RealHamlibTest.lpr      The component against the REAL Hamlib library

demo2/
  DxPanelView.pas         IDxView — what the split panel can display
  DxSplitSequence.pas     The split setup as one cancellable, rollback-
                          capable sequence / ロールバック可能なシーケンス
  DxPanelPresenter.pas    All of DxPanel's behaviour, LCL-free
  DxMainForm.pas          The window: controls, event forwarding, S-meter
  DxPanel.lpr / .lpi      The LCL application (lazbuild DxPanel.lpi)
  FeatureMatrixTest.lpr   Every Rev.6.0 call against the REAL library
  DxConformanceTest.lpr   The calls composed into an operation that can
                          fail halfway / 途中で失敗しうる操作への合成

tools/
  check_abi.py            Checks the shared constants against Hamlib's
                          own headers / 共有定数を Hamlib 実ヘッダと照合
  check_layers.py         Layer-dependency fitness function: LCL-free
                          core, no upward reach, pure codecs, no cycles
                          / 層依存のフィットネス関数
  rigsim.py               A Kenwood TS-2000 CAT simulator on a pseudo
                          terminal, which can be told to go silent,
                          answer late, truncate or emit garbage
                          / 擬似端末上の Kenwood CAT シミュレータ
  differential.py         Runs the same sequence through Hamlib's own
                          rigctld and compares the answers
                          / 同一操作列を rigctld に流して突き合わせ
  run_transport_tests.py  Drives TransportTest over socat/rigctld with
                          faults injected on purpose
                          / 障害を注入して TransportTest を駆動
```

### The sample applications / サンプルアプリケーション

`demo/RigPanel` is a small rig-control panel built on this component. It
exists for two reasons: as a worked example of the structure the design
document prescribes (MVP Passive View — the form only places controls and
forwards events), and as a test of the component *as a component*.

The second reason earned its keep. Building an application around the
component found five defects that none of the unit tests had reached,
including one that made every command after a failed connection report
"paused after repeated failures" instead of the actual cause. See
`REV5_REPORT.md` section 9.

`demo/RigPanel` は本コンポーネントの上に作った小さなリグ制御パネルです。
存在理由は 2 つあります。設計書が規定する構造 (MVP Passive View。フォームは
コントロール配置とイベント転送のみ) の実例であること、そしてコンポーネントを
「コンポーネントとして」試すテストであることです。

後者は十分に元を取りました。コンポーネントの周りにアプリを作ったことで、
どのユニットテストも到達していなかった欠陥 5 件が見つかりました。接続失敗後の
全コマンドが本当の原因ではなく「失敗が続いたため休止」と報告していた問題も
その 1 つです。詳細は `REV5_REPORT.md` の第 9 章を参照してください。

```sh
cd demo
lazbuild RigPanel.lpi        # needs Lazarus; the rest needs only FPC
./RigPanel                   # or: ./RigPanel --model=1 --port=
                             # model 1 = Hamlib's dummy rig, no hardware

fpc -Mobjfpc -Sh -Fu../src -FE. ScenarioTest.lpr   && ./ScenarioTest
fpc -Mobjfpc -Sh -Fu../src -FE. RealHamlibTest.lpr && ./RealHamlibTest
```

`RealHamlibTest` is the only test that puts the Pascal declarations of the
C functions in front of the real library; it skips cleanly when Hamlib is
not installed.

`RealHamlibTest` は、C 関数の Pascal 宣言を実ライブラリの前に立たせる唯一の
テストです。Hamlib が未インストールの環境では正常にスキップします。

---

`demo2/DxPanel` is the second sample, and it is deliberately not a second
rig-control panel. RigPanel exercises *independent* commands: set a
frequency, read a mode, key the PTT — each one succeeds or fails on its
own and nothing is left half-done. DxPanel is built around the shape
RigPanel never had:

- a frequency **pair**, which is what split operation is;
- a **multi-step operation that can fail halfway** and must then undo what
  it already did (`DxSplitSequence`): selecting a VFO, setting the receive
  frequency, enabling split, setting the transmit frequency, reading it
  back. A failure after split is enabled leaves a rig that will transmit
  on a frequency nobody chose, so the sequence turns split off again
  before it reports the failure;
- a **level read on a timer** with application-level back-pressure, so a
  slow rig cannot be made to accumulate meter requests;
- a float level **set** (RF power, 0..1) next to an integer level **read**
  (the S-meter, dB relative to S9), because the component's float/integer
  distinction is only tested by using both;
- `rig_get_caps_int` displayed honestly, **including what it cannot say**.

It earned its keep the same way the first one did: it found two defects
in the component. See `REV6_REPORT.md` section 4.

`demo2/DxPanel` は 2 つ目のサンプルで、意図的に「2 つ目のリグ制御パネル」
にはしていません。RigPanel が検査するのは「独立した」コマンドです。周波数を
設定し、モードを読み、PTT を押す。各々が単独で成否を決め、中途半端に残る
ものはありません。DxPanel は RigPanel に無かった形を軸にしています。

- 周波数の「対」。スプリット運用とはそれです。
- **途中で失敗しうる多段操作**と、その場合に既に行ったことを取り消す責務
  (`DxSplitSequence`)。VFO 選択、受信周波数の設定、スプリット有効化、送信
  周波数の設定、読み戻し。スプリット有効化の後に失敗すると、誰も選んで
  いない周波数で送信するリグが残ります。そのためシーケンスは、失敗を報告
  する前にスプリットを解除します。
- **タイマによるレベル読み取り**とアプリ水準のバックプレッシャ。遅いリグに
  対してメータ要求が溜まらないようにします。
- float レベルの**設定** (RF 出力、0..1) と整数レベルの**読み取り**
  (S メータ、S9 基準の dB)。コンポーネントの float/整数の区別は、両方を
  使って初めて検査されるからです。
- `rig_get_caps_int` を正直に表示します。**答えられないことも含めて**。

1 つ目と同じ形で元を取りました。コンポーネントの欠陥を 2 件見つけています
(`REV6_REPORT.md` 第 4 章)。

```sh
cd demo2
lazbuild DxPanel.lpi
./DxPanel --model=1 --port= --setup=14.023,14.205

fpc -Mobjfpc -Sh -Sa -Criot -gh -Fu../src -Fu. -FE. FeatureMatrixTest.lpr
./FeatureMatrixTest          # 40 / 40
fpc -Mobjfpc -Sh -Sa -Criot -gh -Fu../src -Fu. -FE. DxConformanceTest.lpr
./DxConformanceTest          # 64 / 64
```

**A note on the dummy backend.** Running `--setup=` against model 1 leaves
the RX display reading the transmit frequency. That is not the panel and
not the component: Hamlib's `dummy_set_split_freq` calls `dummy_set_freq`
with the VFO it was passed, so on the dummy rig setting the split
transmit frequency also moves the selected VFO. A real backend addresses
its transmit VFO instead. The panel shows what the rig reports, which is
the only thing it can honestly do.

**ダミーバックエンドについての注記。** モデル 1 に対して `--setup=` を
実行すると、RX 表示が送信周波数になります。これはパネルの問題でもコンポー
ネントの問題でもありません。Hamlib の `dummy_set_split_freq` は渡された
VFO で `dummy_set_freq` を呼ぶため、ダミーリグではスプリット送信周波数の
設定が選択中の VFO も動かします。実機のバックエンドは代わりに自身の送信
VFO を対象とします。パネルはリグが報告する内容を表示しており、それが正直に
できる唯一のことです。

### Running the tests / テストの実行

```sh
cd test
fpc -Mobjfpc -Sh -Sa -Criot -gh -Fu../src -FE. DomainTypeTest.lpr && ./DomainTypeTest
python3 ../tools/check_abi.py --ref 4.5.5 --ref 4.6 --ref 4.7.2 --ref master
```

`-Sa` enables assertions, `-Criot` range and overflow checks, `-gh` the leak
trace. All tests pass with zero unfreed blocks under those flags.

`-Sa` はアサーション、`-Criot` は範囲・オーバーフロー検査、`-gh` はリーク
トレースを有効にします。全テストがこれらのフラグ下で未解放ブロック 0 で
通ります。

The full suite at Rev.6.0, all with zero unfreed blocks:

Rev.6.0 時点の全テスト。いずれも未解放ブロック 0:

| Test | Covers | Result |
|---|---|---|
| `test/*.lpr` (11 tests) | lifecycle, leaks, misuse, timeouts, version gate, thread confinement, domain types, throughput | all OK |
| `examples/SmokeTest` | the minimal application shape | OK |
| `demo/ScenarioTest` | the presenter driven through whole sessions, no LCL | 43 / 43 |
| `demo/RealHamlibTest` | the Rev.5.x surface against the REAL library | 33 / 33 |
| `demo2/FeatureMatrixTest` | every Rev.6.0 call against the REAL library | 40 / 40 |
| `demo2/DxConformanceTest` | those calls composed into a failure-capable operation | 64 / 64 |
| `test/ThreadStartupTest` | every path by which a thread can be torn down before it ran | 8 / 8 |
| `test/RandomSequenceTest` | random call sequences, exact per-shape callback accounting | 13 / 13 × 3 seeds |
| `tools/run_transport_tests.py` | a real serial port and TCP, with faults injected | 8 / 8 scenarios |
| `test/SoakTest` | a long run: memory, descriptors, thread count | see `VERIFICATION_REPORT.md` |
| Valgrind memcheck | memory errors on the C side of the FFI boundary | 0 errors |
| `tools/check_layers.py` | 5 architectural rules, each mutation-tested | 0 violations |
| `tools/check_abi.py` | up to 133 constants vs `rig.h` at 4 refs, every unit | 0 mismatched |
| `test/ExhaustivenessTest` | every value of every public enumeration | 771 / 771 |
| `test/StateMatrixTest` | every method × every lifecycle state | 118 / 118 |
| `test/DifferentialTest` + `tools/differential.py` | our reading of Hamlib vs Hamlib's own client | 21 / 21 agree |
| `test/NetBackendTest` | a second backend and a non-serial transport | 12 / 12 |
| `test/StressTest` | sustained churn with the heap sampled | 9 / 9, zero growth |

---

## Architecture / アーキテクチャ

See the design document `HamlibWrapper_Design_Rev4.md` for the full
5-layer architecture, design rationale, and trade-offs analysis.

5 層アーキテクチャ・設計根拠・トレードオフの完全な分析は
設計書 `HamlibWrapper_Design_Rev4.md` を参照してください。

---

## License / ライセンス

MIT — see LICENSE file.

---

## Version / バージョン

Rev.6.1 / 2026-10-18

### Rev.6.1 — nine defects found by two verification rounds

#### Round 1 — going outside the dummy backend (3 defects)

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

#### Round 2 — the defect classes the first round still could not reach (6 defects)

Round 1 left the component passing everything it had. Round 2 asked a
different question — *which defect classes can that suite not reach?* —
and built six methods to reach them: an exhaustiveness sweep over every
public enumeration, a state matrix of every method against every
lifecycle state, a **differential test against Hamlib's own `rigctld`**,
a second backend over TCP, a randomized property test, and a soak with
the heap sampled. Six more defects. Full account in
`VERIFICATION_REPORT.md`; the three worth naming here:

4. **`SetSplitAsync(True)` nominated the receive VFO as the transmit
   VFO.** `ATxVfo` defaults to `rvfoCurr`, so the shortest form of the
   call told the rig to transmit on the VFO it was already receiving
   on. The rig accepted it and the call reported success, so an
   application set up to work a DX station would have transmitted on
   that station's own frequency. `SetVfoAsync(rvfoCurr)` had always
   been refused as meaningless; the far more dangerous call was the one
   that was allowed. Now refused.

5. **Turning split off destroyed the rig's record of which VFO
   transmits**, because `rig_set_split_vfo` takes a `tx_vfo` even when
   disabling and `rvfoCurr` was being passed. Found by running the same
   sequence through Hamlib's own client and comparing: `rigctld`
   answered `0|VFOB` where the component answered `0|currVFO`.
   Disabling now reads the existing nomination and hands it back.

6. **A use-after-free inside `Close`.** A queued poll result held a raw
   method pointer into the poller thread; `DisablePolling` frees that
   thread, and FPC's `TThread.WaitFor` runs `CheckSynchronize` while it
   waits — so the delivery fired microseconds after its target was
   freed, inside `Close` itself. Reduced to a short reproducer that
   crashed within three rounds every time. The handler now lives in a
   reference-counted sink that the delivery holds.

Also: capabilities no longer survive a `Close`; `Open` records the
connection in the snapshot synchronously instead of leaving it to the
next message pump; a factory shares one loader across the Services it
makes, which completes Round 1's registration fix for the
create-a-Service-per-connection pattern (556,944 → 18,112 bytes over
the same workload); `check_abi.py` now checks every `RIG_E*` constant
in every unit rather than only the canonical table (110 → 133); and
`LifecycleTest` now asserts the flag it had been recording and ignoring.

**No public type changed.** One call became stricter and one interface
was added (`IRigDeliveryKeepAlive`), so an application built on Rev.6.0
needs no change unless it relied on the behaviour that is now refused —
in which case it was transmitting on its receive frequency.

**Round 2 — 1 回目でもなお到達できなかった欠陥の種類 (6 件)**

Round 1 を終えた時点で、コンポーネントは手持ちのテストにすべて合格して
いました。Round 2 は別の問い —— *そのテスト群が到達できない欠陥の種類は
何か* —— を立て、到達するための手法を 6 つ作りました。公開列挙型の網羅
走査、全メソッド × 全ライフサイクル状態の行列、**Hamlib 自身の
`rigctld` との差分テスト**、TCP 経由の第 2 バックエンド、ランダム化
プロパティテスト、heap を標本化するソーク。さらに 6 件の欠陥。詳細は
`VERIFICATION_REPORT.md`。ここで名指しすべき 3 件は上記 4〜6 です。

その他: 能力情報が `Close` を越えて残らなくなりました。`Open` は接続を
次のメッセージポンプ任せにせず同期的にスナップショットへ記録します。
ファクトリが Service 間でローダを共有し、接続ごとに Service を作る
パターンについて Round 1 の登録修正を完成させました (同一負荷で
556,944 → 18,112 バイト)。`check_abi.py` は正典表だけでなく全ユニットの
`RIG_E*` 定数を照合します (110 → 133)。`LifecycleTest` は記録したまま
無視していたフラグを検査するようになりました。

**公開型の変更はありません。**

### Rev.6.0 — the surface applications actually use

Rev.5.1 covered frequency, mode and PTT. That is enough for a panel and
not enough for a station. `COVERAGE_MATRIX.md` records what the
applications that already depend on Hamlib actually call — WSJT-X /
JS8Call, fldigi, gpredict and Hamlib's own `rigctl`, read from source —
and Rev.6.0 implements it:

- **split operation**: `SetSplitAsync`, `GetSplitAsync`, `SetSplitFreqAsync`
- **VFO selection and operations**: `SetVfoAsync`, `GetVfoAsync`,
  `VfoOpAsync` with `TRigVfoOp`
- **levels**: `GetLevelAsync`, `SetLevelFloatAsync`, `SetLevelIntAsync`,
  `TRigLevel` (38 values) and `THamlibLevelCodec`
- **functions**: `GetFuncAsync`, `SetFuncAsync`, `TRigFunc` (22 values)
- **capabilities**: `GetCapabilities` → `TRigCapabilities`
- **conf tokens**: `AddConfToken`, applied after the port and before the
  component's own timeouts, so a token cannot silently undo a policy
- `RigVfoToString`, because both samples had written their own

**MIGRATION from Rev.5.1 — `TRigState` / Rev.5.1 からの移行**

One field changed meaning, and it changed because it was wrong:

```pascal
// Rev.5.1
Freq := Service.CurrentState.VfoAFreq;   // the polled frequency

// Rev.6.0
Freq := Service.CurrentState.CurrentFreq;  // the polled frequency
```

Polling asks the rig for `RIG_VFO_CURR` and is told the frequency of
whichever VFO the rig has selected — never which one that is. Filing
that under `VfoAFreq` made the snapshot assert a fact it was never
given: with VFO B selected, it reported VFO B's frequency as VFO A's.
In `Rev.6.0`, `CurrentFreq` holds the polled value, and `VfoAFreq` /
`VfoBFreq` are written **only** by a read that named the VFO
explicitly — so 0 in those fields means "nobody asked", not "unused".

ポーリングはリグに `RIG_VFO_CURR` を尋ね、リグが選択している VFO の周波数
を受け取ります。それがどの VFO かは決して告げられません。それを `VfoAFreq`
に格納することは、与えられていない事実をスナップショットに主張させることで
した。VFO B を選択していると、VFO B の周波数が VFO A のものとして報告されて
いました。Rev.6.0 では `CurrentFreq` がポーリング値を保持し、`VfoAFreq` /
`VfoBFreq` は VFO を明示した読み取りによって**のみ**書かれます。これらが 0
なのは「誰も尋ねていない」であり「未使用」ではありません。

A single-VFO application changes one identifier. An application that was
reading `VfoAFreq` as "VFO A" was being told something untrue and should
now read `CurrentFreq`, or call `GetFrequencyAsync(rvfoA)` if it really
means VFO A.

単一 VFO のアプリケーションは識別子 1 つの変更で済みます。`VfoAFreq` を
「VFO A」として読んでいたアプリケーションは誤った情報を与えられていました。
今後は `CurrentFreq` を読むか、本当に VFO A を意味するなら
`GetFrequencyAsync(rvfoA)` を呼んでください。

### Rev.5.1 — found by building an application on the component

Writing `demo/RigPanel` and running it against the real Hamlib library
found five defects that the 11 unit tests (104 checks) had all passed over:

| Fixed | What was wrong |
|---|---|
| Connect failures lost their cause | Every failure was reported as `rekConnectFailed`, so "port in use" and "cable unplugged" were indistinguishable. The Hamlib classification is now preserved. |
| A failed connection attempt was unobservable | `OnConnectionChanged` fired only on success or on losing an established link, so an application could never leave its "Connecting..." state. It now fires on a failed attempt too. |
| Commands after a failed connect blamed the breaker | Reordered: not-connected is checked before the circuit breaker, so the kind is the actionable `rekNotConnected`. |
| `ErrorMsg` could be 15 KB of trace | Hamlib's `rigerror()` returns its accumulated debug buffer. The loader now prefers `rigerror2()`, the single-line form. |
| `Open(model, 'none')` could not work | Hamlib resolves `'none'` as a network host name. An empty port is now accepted, which is the correct form for the dummy and network backends. |

Also: Hamlib's debug output is silenced at load time (`THamlibLoader.SetDebugLevel`
raises it again if you want it), the five error kinds added in Rev.5.0 finally have
labels, and the README's claim that LCL applications do not need `cthreads` is
corrected — the demo proved otherwise at startup.

### Rev.5.1 — アプリケーションを作って見つかったもの

`demo/RigPanel` を書き、実 Hamlib ライブラリに対して実行したところ、
ユニットテスト 11 本・104 検査がすべて通過していた状態から欠陥 5 件が
見つかりました。詳細は `REV5_REPORT.md` の第 9 章にあります。

### Rev.5.0

The major version moves because the public types changed incompatibly.
公開型が非互換に変わったため、メジャーバージョンを上げています。

### MIGRATION from Rev.4.2 / Rev.4.2 からの移行

| Rev.4.2 | Rev.5.0 | Why / 理由 |
|---|---|---|
| `SetModeAsync(RIG_MODE_USB, 2700)` | `SetModeAsync(rmUSB, 2700)` | The bitmask belonged to Hamlib's header, not to your source |
| `TRigModeResult.Mode: Int64` | `.Mode: TRigMode` + `.RawMode: Int64` | Named value for logic, raw value kept for diagnostics |
| `TRigModeResult.Passband: Int64` | `.Passband: Integer` | A passband is Hz, and it is not a C `long` |
| `TRigResult.ErrorCode: Integer` | `.Error: TRigErrorKind` + `.NativeCode: Integer` | Branch on the kind; the number is for logs |
| `OnError(Sender, ACode, AMsg)` | `OnError(Sender, AKind, ANativeCode, AMsg)` | Same reason |
| `Open(RIG_MODEL_IC7300, ...)` | `Open(Catalog.Items[i].ModelNumber, ...)` | The constants were wrong in Rev.4.1; asking the library cannot be |
| `IRigStateHolder.SetMode(Int64, Int64)` | `SetMode(TRigMode, Integer, Int64)` | Internal; only matters if you implemented the interface |

The raw `RIG_MODE_*` and `RIG_MODEL_*` constants in `HamlibTypes.pas` are still
there as an escape hatch, and `HamlibModeToString` now delegates to the codec
rather than keeping a second table. `RIG_MODEL_*` constants remain checked by
`tools/check_abi.py`, but new code should use the catalogue.

`HamlibTypes.pas` の生の `RIG_MODE_*` / `RIG_MODEL_*` 定数は逃げ道として
残してあり、`HamlibModeToString` は 2 つ目の表を持たずコーデックに委譲します。
`RIG_MODEL_*` は `tools/check_abi.py` の照合対象のままですが、新規コードは
カタログを使ってください。

### Also fixed in Rev.5.0 / Rev.5.0 でのその他の修正

- `IRigService.CurrentState` never carried the mode or passband: nothing called
  `IRigStateHolder.SetMode`, so those fields held their initial values for the
  whole life of the service. The mode dispatcher now updates the snapshot, and
  `DomainTypeTest` checks it.
  `IRigService.CurrentState` はモードと帯域幅を一切運んでいませんでした。
  `IRigStateHolder.SetMode` の呼び出し元が存在せず、両フィールドはサービスの
  全生存期間にわたり初期値のままでした。
- `test/FakeHamlibLoader.pas` did not compile: it was missing `SetConf`, added to
  `IHamlibLoader` in Rev.4.2. It now also records configuration tokens.
- `OnError` reported `-1` for a tripped circuit breaker — a Hamlib code that means
  `RIG_EINVAL`. Component-level conditions now have their own kinds
  (`rekCircuitOpen`, `rekConnectFailed`, `rekNotConnected`, `rekComponentFault`).
- The Rev.4.2 claim that `HamlibComponent.pas` re-exports the API was false and
  is corrected above.

### Earlier reports / 過去のレポート

- `OPTIMIZATION_REPORT.md` — Rev.4.0 → Rev.4.1 の修正と実測効果
- `API_VERIFICATION_AND_TIMEOUT.md` — Hamlib 実ヘッダとの照合結果と
  二段タイムアウトの設計・実測（Rev.4.1 → Rev.4.2）
- `REV5_REPORT.md` — Rev.4.2 → Rev.5.0（外部値の実行時検証、
  フィットネス関数、ドメイン型への移行）
