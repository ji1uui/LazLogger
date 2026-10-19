# HamlibComponent Rev.4.0 — ソースコードレビュー結果

**レビュー実施日**: 2026-05-06
**対象**: HamlibComponent_Rev4.zip（19 ユニット / 4,286 行）
**検証環境**: FPC 3.2.2 (x86_64-linux)、heaptrc によるリーク検出、実行可能テストによる実証

---

## サマリ

コンパイルは 0 エラーで通りますが、**実行して初めて現れる欠陥が 4 件**あります。
うち 3 件は Rev.4.0 で新たに追加された機能（自己防衛デストラクタ、Poller 隠蔽）に起因します。

| # | 深刻度 | 問題 | 実証方法 | 影響 |
|---|---|---|---|---|
| 1 | **P0** | Service ⇄ Poller の循環参照 | LifecycleTest TEST 3 | 自己防衛デストラクタが動かない。スレッド・シリアルポートが永久に解放されない |
| 2 | **P0** | `Enqueue(nil)` が自身の Assert に抵触 | `-Sa` ビルドで実行 | **Debug ビルドでは `Close` が必ず例外で落ちる** |
| 3 | **P0** | 接続失敗時に `FRig = nil` のままコマンド実行 | コード解析 | 実 Hamlib で `rig_set_freq(NULL,…)` → セグフォルト |
| 4 | **P1** | 公開 API の引数検証が `Assert` のみ | MisuseTest | Release ビルドで `EAccessViolation`。`ERigServiceClosed` は宣言のみで未使用 |
| 5 | P2 | `TThreadList` の `dupIgnore` | DupTest | Enqueue が O(n)。キューが深いと O(n²) |
| 6 | P2 | `Dequeue` のロストウェイクアップ | コード解析 | 1 コマンドあたり最大 100ms の余計な遅延 |
| 7 | P2 | Poller のパラメータが非アトミック | コード解析 | `FThresholdHz`(Double) の破れ読み |
| 8 | P3 | Linux/コンソールで `cthreads` 必須 | 実行時エラー 232 | マニュアル未記載 |

---

## P0-1: Service ⇄ Poller の循環参照（最重要）

### 実証

```
TEST 1: Open/Close without EnablePolling
    >> TRigService.Destroy CALLED
    RESULT: OK

TEST 2: EnablePolling then Close
    >> TRigService.Destroy CALLED
    RESULT: OK

TEST 3: EnablePolling, user FORGETS Close
    ServiceFreed = FALSE
    RESULT: *** LEAK - destructor never ran ***
```

heaptrc の測定結果:

```
44 memory blocks allocated : 2731/2768
28 memory blocks freed     : 1337/1368
16 unfreed memory blocks : 1394
```

### 原因

`HamlibService.pas:285`

```pascal
FPoller := TRigPollerThread.Create(Self, AIntervalMs);
                                   ^^^^
```

`Self` は `TRigService`（`TInterfacedObject` 派生）です。これが
`TRigPollerThread.Create(AService: IRigService; …)` の**インターフェース型引数**に渡るため、
暗黙の `_AddRef` が走ります。

```
TRigService ──(素のポインタ FPoller、参照カウント +0)──► TRigPollerThread
TRigPollerThread ──(FService: IRigService、参照カウント +1)──► TRigService
                                                    ↑ 循環
```

さらに `TRigPollerThread.Execute` の `ServiceCopy := FService`（`HamlibPoller.pas:152`）で
もう 1 回 AddRef されます。

結果として、利用者が `FService := nil` としても参照カウントが 0 にならず、
**`TRigService.Destroy` が一度も呼ばれません**。Rev.4.0 の目玉である
「自己防衛デストラクタ（K4）」が機能していないことになります。

`Close` を明示的に呼ぶと `DisablePolling` → `FPoller.Free` → `_Release` が走るため
問題が表面化しません。つまり **「呼び忘れても安全」という設計意図と逆に、
呼び忘れたときだけ壊れる** 状態です。

### 影響

- メモリリーク（1 接続あたり約 1.4KB）
- **ポーラースレッドが永久に走り続ける** — 実機ではシリアルポートに延々とコマンドを送出
- Worker スレッドも生き続け、シリアルポートが解放されない
- 長時間運用アプリでリグ再接続が不可能になる

### 修正案

Poller が Service をインターフェースで持たないようにします。メソッドポインタは
参照カウントを増やさないため、これが最も簡潔です。

```pascal
{ HamlibPoller.pas — インターフェース参照を廃止 }
type
  { Service 側が実装する「1 回ポーリングせよ」のトリガ }
  TPollTickProc = procedure(ACallback: TRigPollerFreqCallback) of object;
  TPollCanRunFunc = function: Boolean of object;

  TRigPollerThread = class(TThread)
  private
    FOnPollTick:  TPollTickProc;    { メソッドポインタ = AddRef しない }
    FCanRun:      TPollCanRunFunc;
    …
  public
    constructor Create(AOnPollTick: TPollTickProc;
                       ACanRun: TPollCanRunFunc;
                       AIntervalMs: Cardinal = 200);
  end;

procedure TRigPollerThread.Execute;
begin
  while not Terminated do
  begin
    if Assigned(FCanRun) and FCanRun() then
      FOnPollTick(FInternalFreqCb);
    RTLEventResetEvent(FStopEvent);
    RTLEventWaitFor(FStopEvent, FIntervalMs);
  end;
end;
```

```pascal
{ HamlibService.pas }
procedure TRigService.EnablePolling(AIntervalMs: Cardinal);
begin
  …
  FPoller := TRigPollerThread.Create(@DoPollTick, @CanPoll, AIntervalMs);
  …
end;

function TRigService.CanPoll: Boolean;
begin
  Result := FOpen and Assigned(FWorker) and (FWorker.QueueDepth < 3);
end;

procedure TRigService.DoPollTick(ACallback: TRigPollerFreqCallback);
begin
  GetFrequencyAsync(rvfoCurr, ACallback);
end;
```

この変更後、TEST 3 でも `Destroy` が正しく呼ばれることを再検証してください。

---

## P0-2: `Enqueue(nil)` が自身の Assert に抵触

### 実証

`-Sa`（アサーション有効 = Lazarus の Debug ビルド既定）でビルドして実行:

```
TEST 1: Open/Close without EnablePolling
    >> TRigService.Destroy CALLED
An unhandled exception occurred at $00000000004921E0:
EAssertionFailed: Cannot enqueue nil command (HamlibCommandQueue.pas, line 106)
```

### 原因

```pascal
{ HamlibCommandQueue.pas:104-108 }
procedure TCommandQueue.Enqueue(ACmd: TRigCommand);
begin
  Assert(Assigned(ACmd), 'Cannot enqueue nil command');   ← nil を拒否
  FList.Add(ACmd);
  RTLEventSetEvent(FNewItem);
end;

{ HamlibWorker.pas:415-420 }
procedure TRigWorker.RequestStop;
begin
  Terminate;
  FQueue.Enqueue(nil);   ← nil 番兵を投入 = 上の Assert に抵触
end;
```

設計上「nil を番兵として使う」ことにしたのに、キュー側は nil を禁止しています。
**Debug ビルドの利用者は `Close()` を呼んだ瞬間に必ず落ちます。**

### 修正案

番兵方式をやめ、イベントだけで起こします（キューに nil を入れない）。

```pascal
{ HamlibCommandQueue.pas — 起床専用メソッドを追加 }
procedure TCommandQueue.WakeUp;
begin
  RTLEventSetEvent(FNewItem);
end;

{ HamlibWorker.pas }
procedure TRigWorker.RequestStop;
begin
  Terminate;
  FQueue.WakeUp;    { nil を積まない }
end;
```

併せて `CancelAllQueued` / `DrainQueueOnShutdown` の `if Cmd = nil then Continue;`
（番兵スキップ）も不要になるため削除できます。

---

## P0-3: 接続失敗時に `FRig = nil` のままコマンドを実行

### 原因

```pascal
{ HamlibWorker.pas — Execute }
try
  ConnectInternal;
except
  on E: Exception do
    NotifyError(0, 'Connect failed: ' + E.Message);   ← 通知するだけ
end;

while not Terminated do
begin
  Cmd := FQueue.Dequeue(WORKER_TICK_MS);
  if Cmd <> nil then
    ProcessCommand(Cmd);      ← FRig = nil のまま実行される
  …
end;
```

`ProcessCommand` の実行前チェックは「キャンセル済みか」「CB が開いているか」の
2 つだけで、**接続状態を確認していません**。

```pascal
if ACmd.IsCancelRequested then …
else if FCircuitOpen then …
else
begin
  ACmd.Execute(FLoader, FRig);   ← FRig が nil でも呼ばれる
```

`TFakeHamlibLoader` は `ARig` を無視するのでテストでは露見しませんが、
実 Hamlib では `rig_set_freq(NULL, …)` となり、内部で `rig->state` を
参照した時点で **セグメンテーションフォルト** します。

リグの電源が入っていない、ポートが他アプリに占有されている、といった
ごく普通の状況で発生します。

### 修正案

```pascal
{ ProcessCommand の実行前チェックに追加 }
  else if (FRig = nil) or (not FConnected) then
  begin
    R.Status   := rcsRejected;
    R.ErrorMsg := 'Rig is not connected';
    Status     := rcsRejected;
    ErrCode    := 0;
    ErrMsg     := R.ErrorMsg;
  end
  else
  begin
    ACmd.Execute(FLoader, FRig);
    …
```

加えて、接続失敗時は Circuit Breaker を即座に開いて
自動再接続サイクルに乗せるのが自然です。

```pascal
try
  ConnectInternal;
except
  on E: Exception do
  begin
    NotifyError(0, 'Connect failed: ' + E.Message);
    TripCircuitBreaker;    { 10 秒後に CheckCircuitBreaker が再接続を試みる }
  end;
end;
```

---

## P1-4: 公開 API の引数検証が `Assert` のみ

### 実証（Release ビルド、アサーション無効）

```
Calling SetFrequencyAsync BEFORE Open (release build, asserts off)...
  -> exception: EAccessViolation: Access violation
```

### 原因

```pascal
{ HamlibService.pas }
function TRigService.SetFrequencyAsync(…): ICancellationToken;
begin
  Assert(AFreq > 0,  'Frequency must be positive');
  Assert(FOpen,      'Service is not open');     ← Release では消える
  …
  FWorker.PostCommand(Cmd);                       ← FWorker = nil で AV
```

`Assert` は「開発者の内部不変条件」を表明するための道具で、
**外部から渡される引数の検証に使ってはいけません**。Release ビルド（`-Sa` なし）では
コンパイラが Assert を丸ごと削除するため、防御が消えます。

さらに `HamlibErrors.pas` に `ERigServiceClosed` が定義されているにもかかわらず、
**どこからも raise されていません**（宣言のみ）。設計意図はあったが実装が漏れています。

### 修正案

```pascal
function TRigService.SetFrequencyAsync(AFreq: Double; AVfo: TRigVfo;
                                        ACallback: TRigCommandCallback): ICancellationToken;
var
  …
begin
  { 引数検証は Release でも必ず動く形にする }
  if (AFreq <= 0) or (AFreq > 100.0e9) then
    raise EArgumentException.CreateFmt(
      'Frequency out of range: %.0f Hz', [AFreq]);
  if (not FOpen) or (not Assigned(FWorker)) then
    raise ERigServiceClosed.Create(
      'Service is not open. Call Open() before issuing commands.');
  …
end;
```

同じ修正を `GetFrequencyAsync` / `SetModeAsync` / `GetModeAsync` / `SetPttAsync`、
および `Open`（`Assert(not FOpen)` → 二重 Open で例外）に適用してください。

`Assert` はそのまま残してよい箇所は、`TRigWorker.ProcessCommand` の
`Assert(Assigned(ACmd))` のような**内部呼び出し規約**の表明だけです。

---

## P2-5: `TThreadList` の `dupIgnore` による O(n) Enqueue

### 実証

```
Default Duplicates = 0 (0=dupIgnore,1=dupAccept,2=dupError)
After adding same pointer twice, count = 1
```

`TThreadList.Duplicates` の既定値が `dupIgnore` のため、`Add` のたびに
`IndexOf` による線形探索が走ります。ポーリング 150ms + 手動操作が重なって
キューが深くなると、Enqueue が O(n)、全体で O(n²) になります。

### 修正案

```pascal
constructor TCommandQueue.Create;
begin
  inherited Create;
  FList := TThreadList.Create;
  FList.Duplicates := dupAccept;   { 重複探索を無効化 — コマンドは常に一意 }
  FNewItem := RTLEventCreate;
end;
```

---

## P2-6: `Dequeue` のロストウェイクアップ

```pascal
{ 消費側 }
L := FList.LockList;
try
  if L.Count > 0 then … Exit;      ← 空だった
finally
  FList.UnlockList;                 ← ここでロック解放
end;                                ← ★ この隙に生産側が Add + SetEvent
if ATimeoutMs = 0 then Exit;
RTLEventResetEvent(FNewItem);       ← ★ シグナルを消してしまう
RTLEventWaitFor(FNewItem, ATimeoutMs);   ← 100ms フルに待つ
```

デッドロックにはなりません（`WORKER_TICK_MS = 100` 後に再チェックするため）が、
**コマンド 1 件あたり最大 100ms の無駄な遅延**が発生します。
QSY の体感レスポンスに直結します。

### 修正案

待機前ではなく、**最初のチェックの前**にリセットします。

```pascal
function TCommandQueue.Dequeue(ATimeoutMs: Cardinal): TRigCommand;
var
  L: TList;
begin
  Result := nil;
  RTLEventResetEvent(FNewItem);   { ★ 先にリセットしてから確認 }

  L := FList.LockList;
  try
    if L.Count > 0 then
    begin
      Result := TRigCommand(L[0]);
      L.Delete(0);
      Exit;
    end;
  finally
    FList.UnlockList;
  end;

  if ATimeoutMs = 0 then Exit;
  RTLEventWaitFor(FNewItem, ATimeoutMs);   { リセットしない }

  L := FList.LockList;
  try
    if L.Count > 0 then
    begin
      Result := TRigCommand(L[0]);
      L.Delete(0);
    end;
  finally
    FList.UnlockList;
  end;
end;
```

---

## P2-7: Poller のパラメータが非アトミック

```pascal
procedure TRigPollerThread.SetChangeThreshold(AHz: Double);
begin
  FThresholdHz := AHz;    { Double = 8 バイト。32bit 環境では非アトミック }
end;
```

`SetIntervalMs`（`Cardinal` = 4 バイト）は実用上問題ありませんが、
`FThresholdHz` は 32bit ビルドで破れ読みの可能性があります。

### 修正案

`TCriticalSection` で保護するか、`Integer`（Hz 単位の整数）に型を変えるのが簡単です。
本用途では Hz 未満の精度は不要なので後者を推奨します。

---

## P3-8: Linux / コンソールでの `cthreads` 要件が未記載

検証中、テストプログラムが以下で停止しました。

```
This binary has no thread support compiled in.
Runtime error 232
```

Lazarus の LCL アプリでは自動的に解決されますが、**コンソールアプリや
ユニットテストランナーでは `cthreads` を `uses` の先頭に置く必要があります**。
本コンポーネントは `TThread` を使うため必須です。マニュアルに追記してください。

```pascal
program MyTest;
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}   // ← 必ず最初に
  Classes, SysUtils, HamlibComponent;
```

---

## 良かった点

批判ばかりではないので、確認できた良い点も記録します。

**Dangling callback は実際に安全でした。** `TThread.WaitFor` が内部で
同期キューをポンプするため、`Close` → `WaitFor` の時点で保留中のコールバックが
消化されます。DanglingTest で破棄済みオブジェクトへのコールバックは 0 件でした。
ただしこれは FPC RTL の実装依存であり、設計書に書かれた
「`CancelAllPending` が保証する」という説明とは根拠が異なります。
マニュアルの説明を実態に合わせて修正することを推奨します。

**`DeliverAndFree` パターンは正しく機能しています。** 値型コピーを先に取ってから
コマンドを解放する順序が全 4 経路（Generic / Freq / Mode / Ptt）で守られており、
heaptrc でもリークは検出されませんでした（P0-1 の経路を除く）。

**ディスパッチャの自己破棄も正しい**です。`try … finally Free; end` により、
コールバックが例外を投げても解放されます。

---

## 修正優先順位

1. **P0-2**（Assert 抵触）— 1 行の修正。Debug ビルドが即死するため最優先
2. **P0-1**（循環参照）— Poller のインターフェース参照を除去。設計変更を伴う
3. **P0-3**（nil PRIG）— `ProcessCommand` に接続チェックを追加。数行
4. **P1-4**（Assert 依存）— 全公開 API を例外ベースに変更
5. **P2-5 / P2-6** — キューの 2 箇所の小修正。効果は大きい
6. **P2-7 / P3-8** — 型変更とドキュメント追記

P0 の 3 件を修正するまでは、本コンポーネントを実機運用に投入しないことを推奨します。

---

## 再検証用テストコード

本レビューで使用した実行可能テストを同梱しています。

| ファイル | 検証内容 |
|---|---|
| `test/LifecycleTest.lpr` | Open/Close/破棄の 3 パターン。P0-1・P0-2 を検出 |
| `test/DanglingTest.lpr` | 破棄済みオブジェクトへのコールバック発火 |
| `test/LeakTest.lpr` | 正常経路のリーク検査（heaptrc） |
| `test/LeakTest2.lpr` | Close 忘れ時のリーク量計測（heaptrc） |
| `test/MisuseTest.lpr` | Open 前 API 呼び出しの挙動（Release ビルド） |
| `test/fakeloader.inc` | 上記が共有する最小 Fake ローダ |

ビルド方法:

```bash
cd test
fpc -Mobjfpc -Sh -Fu../src -FE. LifecycleTest.lpr && ./LifecycleTest
fpc -Mobjfpc -Sh -Sa -B -Fu../src -FE. -oLifecycleTest_Sa LifecycleTest.lpr && ./LifecycleTest_Sa
fpc -Mobjfpc -Sh -gh -Fu../src -FE. LeakTest2.lpr && ./LeakTest2 && cat leak_report2.txt
```

---

*Code Review Rev.1.0 / 2026-05-06 — FPC 3.2.2 実機検証つき*
