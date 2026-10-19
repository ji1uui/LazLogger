{
  ThreadStartupTest.lpr

  Every way the component's threads can be torn down before they ever
  ran. Each case has a wall-clock budget, because the failure mode
  being guarded against is not a wrong answer — it is no answer at all.

  コンポーネントのスレッドが、一度も実行されないまま破棄されうる経路の
  すべて。各事例には実時間の上限を設けます。本検査が守る失敗モードは
  誤った答えではなく、答えが返らないことだからです。

  What this is about / 何についての検査か
  ------------------------------------------------------------------
  A TThread constructed with Create(True) sits inside the RTL's start
  gate until Start resumes it. It is not running, so Terminate does not
  reach it, and WaitFor on it never returns: the thread has not
  finished and never will.

  Up to Rev.6.0 the Worker's destructor called Stop and WaitFor on its
  watchdog unconditionally, and the Service called WaitFor on its
  Worker unconditionally. Either one, reached before the thread in
  question had been resumed, hung the calling thread forever — no
  error, no timeout, no way out. In an application that is the window
  freezing and never coming back.

  Create(True) で構築された TThread は、Start が再開するまで RTL の開始
  ゲート内に留まります。実行されていないため Terminate は届かず、
  WaitFor は決して戻りません。スレッドは終了しておらず、今後も終了
  しないからです。

  Rev.6.0 まで、Worker のデストラクタは watchdog に対して Stop と
  WaitFor を無条件に呼び、Service は Worker に対して WaitFor を無条件に
  呼んでいました。問題のスレッドが再開される前にそこへ到達すると、
  呼び出し側スレッドは永久に停止しました。エラーもタイムアウトも脱出
  手段もなく。アプリケーションにおいては、ウィンドウが固まったまま
  二度と戻らないということです。

  How it was found / 発見の経緯
  ------------------------------------------------------------------
  Not by a unit test. A long soak run of repeated connect/disconnect
  cycles stopped making progress; the process was sleeping on a futex
  with two threads, and a stack dump put the main thread in the
  Worker's destructor at WaitFor and the other thread in the RTL's
  start gate. The race needs the teardown to arrive before the
  operating system has scheduled the new thread's first instruction,
  which is why thousands of short tests never hit it and one long one
  under CPU contention did.

  ユニットテストではありません。接続・切断を繰り返す長時間のソーク実行
  が進まなくなりました。プロセスはスレッド 2 本で futex 待ちで眠って
  おり、スタックダンプはメインスレッドを Worker のデストラクタの
  WaitFor に、もう一方を RTL の開始ゲートに示しました。この競合は、
  OS が新しいスレッドの最初の命令をスケジュールする前に後始末が到達
  することを必要とします。短いテストを何千回行っても当たらず、CPU が
  競合した長い実行 1 回が当てたのは、そのためです。

  Build:
    fpc -Mobjfpc -Sh -Sa -Criot -gh -Fu../src -FE. ThreadStartupTest.lpr
}
program ThreadStartupTest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  HamlibInterfaces, HamlibErrors, HamlibTimeoutPolicy,
  HamlibWatchdog, HamlibWorker, HamlibLoader, HamlibService,
  HamlibFactory;

const
  MODEL_DUMMY = 1;

  { Every case must finish well inside this. The number is not a
    performance target — it is the line between "returned" and
    "deadlocked", and anything near it is already a defect.
    各事例はこの時間内に十分余裕をもって終わらなければなりません。これは
    性能目標ではなく「戻った」と「デッドロックした」の境界であり、これに
    近いだけで既に欠陥です。 }
  CASE_BUDGET_MS = 10000;

var
  Passed: Integer = 0;
  Failed: Integer = 0;

procedure Check(const ALabel: string; ACondition: Boolean;
                const ADetail: string = '');
begin
  if ACondition then
  begin
    Inc(Passed);
    WriteLn('    [ok]   ', ALabel);
  end
  else
  begin
    Inc(Failed);
    if ADetail <> '' then
      WriteLn('    [FAIL] ', ALabel, '  <-- ', ADetail)
    else
      WriteLn('    [FAIL] ', ALabel);
  end;
end;

{ Runs ABody and reports how long it took. A deadlock cannot be caught
  from inside the process that is deadlocked, so this cannot time out —
  it measures, and the runner's own timeout is what catches a hang.
  The measurement is still worth having: a case that takes seconds
  instead of milliseconds is the same defect, narrowly avoided.

  ABody を実行し所要時間を報告します。デッドロックは、デッドロックして
  いるプロセスの内側からは捕捉できないため、ここでタイムアウトはでき
  ません。計測を行い、停止を捕まえるのは実行側のタイムアウトです。計測
  には価値があります。ミリ秒でなく秒かかる事例は、同じ欠陥を辛うじて
  免れただけだからです。 }
function TimeIt(const ALabel: string; ABody: TProcedure): QWord;
var
  T0: QWord;
begin
  Write('    ... ', ALabel);
  Flush(Output);
  T0 := GetTickCount64;
  ABody();
  Result := GetTickCount64 - T0;
  WriteLn('  (', Result, ' ms)');
end;

var
  SharedLoader: IHamlibLoader;

{ ------------------------------------------------------------------
  Case 1: a watchdog that is freed without ever being started.
  事例 1: 一度も開始されないまま解放される watchdog。
  ------------------------------------------------------------------ }
{ TWatchdogAbortProc is a method pointer, so the callback needs an
  object even though it does nothing here.
  TWatchdogAbortProc はメソッドポインタのため、ここでは何もしなくても
  コールバックにはオブジェクトが必要です。 }
type
  TAbortSink = class
    Fired: Integer;
    procedure Abort;
  end;

procedure TAbortSink.Abort;
begin
  Inc(Fired);
end;

var
  Sink: TAbortSink;

procedure Case_WatchdogNeverStarted;
var
  W: TRigWatchdog;
begin
  W := TRigWatchdog.Create(@Sink.Abort);
  W.Free;
end;

{ ------------------------------------------------------------------
  Case 2: a watchdog started and stopped normally.
  事例 2: 正常に開始・停止される watchdog。
  ------------------------------------------------------------------ }
procedure Case_WatchdogStarted;
var
  W: TRigWatchdog;
begin
  W := TRigWatchdog.Create(@Sink.Abort);
  W.Start;
  Sleep(120);
  W.Stop;
  W.WaitFor;
  W.Free;
end;

{ ------------------------------------------------------------------
  Case 3: a Worker freed without ever being started. This is the
  deterministic form of the race: the Worker's destructor reaches its
  watchdog, which is started inside the Worker's own Execute and so
  has never run.

  事例 3: 一度も開始されないまま解放される Worker。これは競合の決定的な
  形です。Worker のデストラクタが watchdog に到達しますが、watchdog は
  Worker 自身の Execute の中で開始されるため、一度も実行されていません。
  ------------------------------------------------------------------ }
procedure Case_WorkerNeverStarted;
var
  W: TRigWorker;
begin
  W := TRigWorker.Create(SharedLoader, MODEL_DUMMY, '');
  Check('a Worker reports itself as not started before Start',
        not W.Started);
  W.Free;
end;

{ ------------------------------------------------------------------
  Case 4: a Worker started, stopped and freed normally.
  事例 4: 正常に開始・停止・解放される Worker。
  ------------------------------------------------------------------ }
procedure Case_WorkerStarted;
var
  W: TRigWorker;
begin
  W := TRigWorker.Create(SharedLoader, MODEL_DUMMY, '');
  W.Start;
  Sleep(150);
  W.RequestStop;
  W.WaitFor;
  W.Free;
end;

{ ------------------------------------------------------------------
  Case 5: a Service created and freed without ever being opened —
  the shape of an application that starts, fails its version gate or
  changes its mind, and shuts down.

  事例 5: 一度も Open されずに生成・解放される Service。起動し、バージョン
  ゲートで止まるか気が変わって終了するアプリケーションの形です。
  ------------------------------------------------------------------ }
procedure Case_ServiceNeverOpened;
var
  F: IRigServiceFactory;
begin
  F := TRigServiceFactory.Create;

  { Created and released in one statement. The point is the release,
    not the reference: a Service that was never opened still owns a
    Worker, and the Worker still owns a watchdog that has never run.
    1 つの文で生成し解放します。要点は参照ではなく解放です。一度も
    Open されていない Service も Worker を所有し、その Worker は一度も
    実行されていない watchdog を所有しているからです。 }
  F.CreateService;

  F := nil;
end;

{ ------------------------------------------------------------------
  Case 6: the race itself. Open and Close as fast as the machine
  allows, many times. Each iteration gives the operating system a
  chance to schedule the teardown before the new thread's first
  instruction — which is the window the defect lived in.

  事例 6: 競合そのもの。機械が許す限り速く Open と Close を多数回繰り
  返します。各反復は、新しいスレッドの最初の命令より前に後始末を
  スケジュールする機会を OS に与えます。欠陥が棲んでいた窓です。
  ------------------------------------------------------------------ }
procedure Case_RapidOpenClose;
var
  F: IRigServiceFactory;
  S: IRigService;
  i: Integer;
begin
  F := TRigServiceFactory.Create;
  for i := 1 to 60 do
  begin
    S := F.CreateService;
    S.ApplyTimeoutPolicy(RigPolicy_FastUsb);
    if Odd(i) then
      S.AddConfToken('ptt_type', 'RIG');
    S.Open(MODEL_DUMMY, '');

    { No pump, no sleep, no command: Close is issued while the worker
      thread may not have executed a single instruction.
      pump も sleep もコマンドもなし。ワーカースレッドが 1 命令も実行
      していないかもしれない状態で Close を発行します。 }
    S.Close;
    S := nil;
  end;
  F := nil;
end;

{ ------------------------------------------------------------------
  Case 7: the same race, without Close — the self-defending
  destructor path.
  事例 7: 同じ競合を Close なしで。自己防衛デストラクタの経路です。
  ------------------------------------------------------------------ }
procedure Case_RapidOpenNoClose;
var
  F: IRigServiceFactory;
  S: IRigService;
  i: Integer;
begin
  F := TRigServiceFactory.Create;
  for i := 1 to 40 do
  begin
    S := F.CreateService;
    S.Open(MODEL_DUMMY, '');
    S := nil;            { no Close — the destructor must cope }
  end;
  F := nil;
end;

var
  Ms: QWord;

begin
  WriteLn('ThreadStartupTest — threads torn down before they ever ran');
  WriteLn('==========================================================');
  WriteLn;

  Sink := TAbortSink.Create;
  SharedLoader := THamlibLoader.Create;
  if not SharedLoader.Load('') then
  begin
    WriteLn('SKIP: no Hamlib library could be loaded.');
    SharedLoader := nil;
    Sink.Free;
    ExitCode := 0;
    Halt;
  end;

  WriteLn('WATCHDOG');
  Ms := TimeIt('freed without ever being started', @Case_WatchdogNeverStarted);
  Check('a never-started watchdog can be freed', Ms < CASE_BUDGET_MS,
        Format('%d ms', [Ms]));
  Ms := TimeIt('started, stopped, freed', @Case_WatchdogStarted);
  Check('a started watchdog still stops and joins', Ms < CASE_BUDGET_MS,
        Format('%d ms', [Ms]));

  WriteLn;
  WriteLn('WORKER');
  Ms := TimeIt('freed without ever being started', @Case_WorkerNeverStarted);
  Check('a never-started Worker can be freed', Ms < CASE_BUDGET_MS,
        Format('%d ms', [Ms]));
  Ms := TimeIt('started, stopped, freed', @Case_WorkerStarted);
  Check('a started Worker still stops and joins', Ms < CASE_BUDGET_MS,
        Format('%d ms', [Ms]));

  WriteLn;
  WriteLn('SERVICE');
  Ms := TimeIt('created and freed, never opened', @Case_ServiceNeverOpened);
  Check('a Service that was never opened can be freed',
        Ms < CASE_BUDGET_MS, Format('%d ms', [Ms]));

  WriteLn;
  WriteLn('THE RACE');
  Ms := TimeIt('60 x Open/Close with no pause', @Case_RapidOpenClose);
  Check('60 immediate open/close cycles complete',
        Ms < 60 * CASE_BUDGET_MS, Format('%d ms', [Ms]));
  WriteLn(Format('    (%d ms for 60 cycles, %.1f ms each)',
                 [Ms, Ms / 60]));

  Ms := TimeIt('40 x Open then drop, no Close', @Case_RapidOpenNoClose);
  Check('40 open-and-drop cycles complete',
        Ms < 40 * CASE_BUDGET_MS, Format('%d ms', [Ms]));

  SharedLoader := nil;
  Sink.Free;

  WriteLn;
  WriteLn(Format('--- %d / %d checks passed ---', [Passed, Passed + Failed]));
  if Failed = 0 then
  begin
    WriteLn('RESULT: OK — no teardown path waits on a thread that never ran');
    ExitCode := 0;
  end
  else
  begin
    WriteLn(Format('RESULT: %d FAILED', [Failed]));
    ExitCode := 1;
  end;
end.
