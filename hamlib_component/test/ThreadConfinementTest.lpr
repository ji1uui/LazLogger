{
  ThreadConfinementTest.lpr

  Architectural fitness function for the component's central invariant:

      Every call that touches the opaque PRIG handle happens on exactly
      one thread — the Worker thread — no matter which thread asked for
      it.

  コンポーネント中核の不変条件に対するアーキテクチャ・フィットネス関数:

      不透明ハンドル PRIG に触れる呼び出しは、どのスレッドから依頼された
      かに関わらず、必ず唯一のスレッド (Worker スレッド) 上で起きる。

  Why this test exists / このテストが存在する理由
  ------------------------------------------------------------------
  Hamlib's RIG structure is not documented as thread-safe. The whole
  queue/Worker design exists solely to confine access to it. That
  confinement is an invariant of the architecture, not of any one unit,
  so no unit test can protect it: a future contributor could "optimise"
  a getter by reading the handle directly from the caller's thread and
  every existing test would still pass. A fitness function observes the
  property itself.

  Hamlib の RIG 構造体はスレッドセーフと文書化されていません。キュー +
  Worker 設計は、ひとえにその構造体へのアクセスを閉じ込めるために存在
  します。この閉じ込めは個々のユニットではなくアーキテクチャの不変条件
  であり、通常のユニットテストでは守れません。将来、誰かが getter を
  「最適化」して呼び出し元スレッドから直接ハンドルを読んでも、既存の
  テストはすべて通ってしまいます。フィットネス関数は性質そのものを観測
  します。

  How it works / 仕組み
  ------------------------------------------------------------------
  A probe loader records GetCurrentThreadId on every one of the 13
  IHamlibLoader methods that receive a PRIG handle. Commands are then
  issued from the main thread, from a second application thread, and by
  the polling thread, all at the same time. Afterwards the recorded
  thread IDs are collapsed to a set; the invariant holds only if that
  set has exactly one member, and that member is neither of the calling
  threads.

  プローブローダが、PRIG ハンドルを受け取る 13 の IHamlibLoader メソッド
  すべてで GetCurrentThreadId を記録します。その上でメインスレッド、
  第 2 のアプリケーションスレッド、ポーリングスレッドから同時にコマンドを
  発行します。最後に記録済みスレッド ID を集合に畳み込み、要素がちょうど
  1 つで、かつそれがどの発行側スレッドでもないときにのみ不変条件が成立
  します。

  The one sanctioned exception / 唯一の例外
  ------------------------------------------------------------------
  TRigWatchdog deliberately calls rig_close from the watchdog thread to
  break a wedged I/O call. That is the single documented violation, and
  SCENARIO B asserts it is the *only* one: the watchdog thread must
  touch rig_close and nothing else. Were the exception to spread to
  other calls, this test fails.

  TRigWatchdog は、固まった I/O を解除するために watchdog スレッドから
  意図的に rig_close を呼びます。これが唯一の文書化された違反であり、
  SCENARIO B はそれが「唯一」であることを検査します。watchdog スレッド
  が触れてよいのは rig_close のみです。例外が他の呼び出しに広がれば、
  このテストは失敗します。

  Build:
    fpc -Mobjfpc -Sh -Fu../src -FE. ThreadConfinementTest.lpr
}
program ThreadConfinementTest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils, SyncObjs,
  HamlibInterfaces, HamlibService, HamlibTimeoutPolicy;

{ ====================================================================
  Call log — shared by the probe loaders and the assertions.
  コールログ — プローブローダと検査の共有領域。
  ==================================================================== }
type
  TCallRecord = record
    Name: string;
    Tid:  TThreadID;
  end;

var
  LogLock:   TCriticalSection;
  CallLog:   array of TCallRecord;
  MainTid:   TThreadID;
  IssuerTid: TThreadID = 0;
  Checks:    Integer = 0;
  Failures:  Integer = 0;

{ Record one PRIG-touching call together with the thread it ran on.
  Called from several threads at once, hence the lock.
  PRIG に触れる呼び出しを、実行スレッドと共に 1 件記録します。
  複数スレッドから同時に呼ばれるためロックします。 }
procedure NoteCall(const AName: string);
var
  N: Integer;
begin
  LogLock.Acquire;
  try
    N := Length(CallLog);
    SetLength(CallLog, N + 1);
    CallLog[N].Name := AName;
    CallLog[N].Tid  := GetCurrentThreadId;
  finally
    LogLock.Release;
  end;
end;

procedure ResetLog;
begin
  LogLock.Acquire;
  try
    SetLength(CallLog, 0);
  finally
    LogLock.Release;
  end;
end;

{ Number of log entries for a given call name.
  指定した呼び出し名のログ件数。 }
function CallCount(const AName: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  LogLock.Acquire;
  try
    for i := 0 to High(CallLog) do
      if CallLog[i].Name = AName then Inc(Result);
  finally
    LogLock.Release;
  end;
end;

{ How many distinct threads appear in the log, ignoring entries whose
  name is AExcludeName (pass '' to consider everything). ASample
  returns one of those threads, for identity checks.

  ログに現れる相異なるスレッド数。名前が AExcludeName のエントリは無視
  します ('' を渡すと全件対象)。ASample には同一性検査用にそのうちの
  1 つを返します。 }
function DistinctThreadCount(const AExcludeName: string;
                             out ASample: TThreadID): Integer;
var
  i, j: Integer;
  Seen: array of TThreadID;
  Known: Boolean;
begin
  Result  := 0;
  ASample := 0;
  SetLength(Seen, 0);
  LogLock.Acquire;
  try
    for i := 0 to High(CallLog) do
    begin
      if (AExcludeName <> '') and (CallLog[i].Name = AExcludeName) then
        Continue;
      Known := False;
      for j := 0 to High(Seen) do
        if Seen[j] = CallLog[i].Tid then
        begin
          Known := True;
          Break;
        end;
      if not Known then
      begin
        SetLength(Seen, Length(Seen) + 1);
        Seen[High(Seen)] := CallLog[i].Tid;
      end;
    end;
  finally
    LogLock.Release;
  end;
  Result := Length(Seen);
  if Result > 0 then ASample := Seen[0];
end;

{ True if AName was ever logged from a thread other than AThread.
  AName が AThread 以外のスレッドから記録されたことがあれば True。 }
function CalledFromOtherThan(const AName: string; AThread: TThreadID): Boolean;
var
  i: Integer;
begin
  Result := False;
  LogLock.Acquire;
  try
    for i := 0 to High(CallLog) do
      if (CallLog[i].Name = AName) and (CallLog[i].Tid <> AThread) then
      begin
        Result := True;
        Break;
      end;
  finally
    LogLock.Release;
  end;
end;

{ Names of all calls logged from AThread, as a comma-separated list.
  Used to prove the watchdog thread touched nothing but rig_close.
  AThread から記録された全呼び出し名のカンマ区切り一覧。
  watchdog スレッドが rig_close 以外に触れていないことの証明に使います。 }
function NamesFromThread(AThread: TThreadID): string;
var
  i: Integer;
begin
  Result := '';
  LogLock.Acquire;
  try
    for i := 0 to High(CallLog) do
      if CallLog[i].Tid = AThread then
        if Pos(CallLog[i].Name, Result) = 0 then
        begin
          if Result <> '' then Result := Result + ',';
          Result := Result + CallLog[i].Name;
        end;
  finally
    LogLock.Release;
  end;
end;

{ ------------------------------------------------------------------
  Assertion helper. Prints and tallies; never aborts, so one failure
  does not hide the others.
  検査ヘルパー。表示と集計のみで中断しないため、1 件の失敗が他を
  隠しません。
  ------------------------------------------------------------------ }
procedure Check(const ALabel: string; ACondition: Boolean;
                const ADetail: string = '');
begin
  Inc(Checks);
  if ACondition then
    WriteLn('    [ok]   ', ALabel)
  else
  begin
    Inc(Failures);
    if ADetail <> '' then
      WriteLn('    [FAIL] ', ALabel, '  --> ', ADetail)
    else
      WriteLn('    [FAIL] ', ALabel);
  end;
end;

{ ====================================================================
  SCENARIO A probe loader — records every PRIG-touching call.
  SCENARIO A 用プローブローダ — PRIG に触れる呼び出しをすべて記録。
  ====================================================================
  The names used in NoteCall are the C function names, so a failure
  message reads like the Hamlib API it is protecting.
  NoteCall に渡す名前は C 関数名です。失敗メッセージが、保護対象の
  Hamlib API そのままの語彙で読めるようにしています。 }
type
  TProbeLoader = class(TInterfacedObject, IHamlibLoader)
  public
    function  Load(const APath: string = ''): Boolean;
    procedure Unload;
    function  GetIsLoaded: Boolean;
    function  GetApiMajor: Integer;
    function  GetApiMinor: Integer;
    function  GetLibPath:  string;
    function  HasSymbol(const AName: string): Boolean;
    { The handle-bearing calls are virtual so SCENARIO B can replace
      three of them without re-declaring the whole interface. A plain
      re-declaration in a descendant would leave the interface table
      resolution to the compiler's name lookup rules; virtual/override
      states the intent explicitly.

      ハンドルを伴う呼び出しは virtual です。SCENARIO B がインターフェース
      全体を再宣言せずに 3 つだけ差し替えられるようにするためです。子孫で
      単に再宣言するとインターフェーステーブルの解決がコンパイラの名前検索
      規則に委ねられます。virtual/override は意図を明示します。 }
    function  CallRigInit(AModel: Integer): Pointer; virtual;
    function  CallRigOpen(ARig: Pointer): Integer; virtual;
    function  CallRigClose(ARig: Pointer): Integer; virtual;
    function  CallRigCleanup(ARig: Pointer): Integer; virtual;
    function  CallRigSetFreq(ARig: Pointer; AVfo: Integer; AFreq: Double): Integer; virtual;
    function  CallRigGetFreq(ARig: Pointer; AVfo: Integer; out AFreq: Double): Integer; virtual;
    function  CallRigSetMode(ARig: Pointer; AVfo: Integer; AMode: Int64; AWidth: Int64): Integer;
    function  CallRigGetMode(ARig: Pointer; AVfo: Integer; out AMode: Int64; out AWidth: Int64): Integer;
    function  CallRigSetPtt(ARig: Pointer; AVfo: Integer; APtt: Integer): Integer;
    function  CallRigGetPtt(ARig: Pointer; AVfo: Integer; out APtt: Integer): Integer;
    function  CallRigError(ACode: Integer): string;
    function  SetConf(ARig: Pointer; const AName, AValue: string): Integer;
    function  SetSerialPort(ARig: Pointer; const APort: string): Integer;
    function  SetSerialBaud(ARig: Pointer; ABaud: Integer): Integer;
  end;

{ --- version / symbol queries: no handle involved, so not logged ---
  --- バージョン・シンボル照会: ハンドルを伴わないため記録しない --- }
function  TProbeLoader.Load(const APath: string): Boolean; begin Result := True; end;
procedure TProbeLoader.Unload; begin end;
function  TProbeLoader.GetIsLoaded: Boolean; begin Result := True; end;
function  TProbeLoader.GetApiMajor: Integer; begin Result := 4; end;
function  TProbeLoader.GetApiMinor: Integer; begin Result := 7; end;
function  TProbeLoader.GetLibPath: string; begin Result := '<probe>'; end;
function  TProbeLoader.HasSymbol(const AName: string): Boolean; begin Result := True; end;
function  TProbeLoader.CallRigError(ACode: Integer): string;
begin Result := Format('probe error %d', [ACode]); end;

{ --- handle-bearing calls: every one is logged ---
  --- ハンドルを伴う呼び出し: すべて記録する --- }
function TProbeLoader.CallRigInit(AModel: Integer): Pointer;
begin
  { rig_init creates the handle, so it belongs to the same confinement.
    rig_init はハンドルを生成するため、同じ閉じ込めの対象です。 }
  NoteCall('rig_init');
  Result := Pointer(1);
end;

function TProbeLoader.CallRigOpen(ARig: Pointer): Integer;
begin NoteCall('rig_open'); Result := 0; end;

function TProbeLoader.CallRigClose(ARig: Pointer): Integer;
begin NoteCall('rig_close'); Result := 0; end;

function TProbeLoader.CallRigCleanup(ARig: Pointer): Integer;
begin NoteCall('rig_cleanup'); Result := 0; end;

function TProbeLoader.CallRigSetFreq(ARig: Pointer; AVfo: Integer;
                                     AFreq: Double): Integer;
begin NoteCall('rig_set_freq'); Result := 0; end;

function TProbeLoader.CallRigGetFreq(ARig: Pointer; AVfo: Integer;
                                     out AFreq: Double): Integer;
begin
  NoteCall('rig_get_freq');
  { A short sleep widens the window in which a careless direct read from
    another thread would overlap this one.
    短い Sleep により、他スレッドからの不注意な直読みが本呼び出しと
    重なる窓を広げます。 }
  Sleep(2);
  AFreq  := 14074000.0;
  Result := 0;
end;

function TProbeLoader.CallRigSetMode(ARig: Pointer; AVfo: Integer;
                                     AMode: Int64; AWidth: Int64): Integer;
begin NoteCall('rig_set_mode'); Result := 0; end;

function TProbeLoader.CallRigGetMode(ARig: Pointer; AVfo: Integer;
                                     out AMode: Int64;
                                     out AWidth: Int64): Integer;
begin
  NoteCall('rig_get_mode');
  AMode  := Int64(1) shl 2;
  AWidth := 2700;
  Result := 0;
end;

function TProbeLoader.CallRigSetPtt(ARig: Pointer; AVfo: Integer;
                                    APtt: Integer): Integer;
begin NoteCall('rig_set_ptt'); Result := 0; end;

function TProbeLoader.CallRigGetPtt(ARig: Pointer; AVfo: Integer;
                                    out APtt: Integer): Integer;
begin NoteCall('rig_get_ptt'); APtt := 0; Result := 0; end;

function TProbeLoader.SetConf(ARig: Pointer;
                              const AName, AValue: string): Integer;
begin NoteCall('rig_set_conf'); Result := 0; end;

function TProbeLoader.SetSerialPort(ARig: Pointer; const APort: string): Integer;
begin Result := SetConf(ARig, 'rig_pathname', APort); end;

function TProbeLoader.SetSerialBaud(ARig: Pointer; ABaud: Integer): Integer;
begin Result := SetConf(ARig, 'serial_speed', IntToStr(ABaud)); end;

{ ====================================================================
  SCENARIO B probe loader — same recording, plus a wedged rig_get_freq
  so the watchdog has to intervene.
  SCENARIO B 用プローブローダ — 同じ記録に加え、rig_get_freq が固まり
  watchdog の介入を強制します。
  ==================================================================== }
type
  TStuckProbeLoader = class(TProbeLoader)
  private
    FAborted: Boolean;
  public
    function CallRigOpen(ARig: Pointer): Integer; override;
    function CallRigClose(ARig: Pointer): Integer; override;
    function CallRigGetFreq(ARig: Pointer; AVfo: Integer;
                            out AFreq: Double): Integer; override;
  end;

const
  BLOCK_MS = 8000;   { far beyond the budget / 予算を大きく超える }

function TStuckProbeLoader.CallRigOpen(ARig: Pointer): Integer;
begin
  NoteCall('rig_open');
  FAborted := False;
  Result   := 0;
end;

function TStuckProbeLoader.CallRigClose(ARig: Pointer): Integer;
begin
  NoteCall('rig_close');
  { Closing the handle is what unblocks the pending read, exactly as a
    real driver would start returning EBADF.
    ハンドルを閉じることが待機中の読み取りを解除します。実ドライバが
    EBADF を返し始めるのと同じ挙動です。 }
  FAborted := True;
  Result   := 0;
end;

function TStuckProbeLoader.CallRigGetFreq(ARig: Pointer; AVfo: Integer;
                                          out AFreq: Double): Integer;
var
  Waited: Integer;
begin
  NoteCall('rig_get_freq');
  AFreq  := 0;
  Waited := 0;
  while (Waited < BLOCK_MS) and (not FAborted) do
  begin
    Sleep(20);
    Inc(Waited, 20);
  end;
  if FAborted then
    Result := -6              { -RIG_EIO, a closed descriptor / 閉じた fd }
  else
  begin
    AFreq  := 14074000.0;
    Result := 0;
  end;
end;

{ ====================================================================
  A second application thread that issues commands concurrently with
  the main thread. Its only job is to prove the caller's thread has no
  influence on which thread touches the handle.

  メインスレッドと並行してコマンドを発行する第 2 のアプリケーション
  スレッド。呼び出し元スレッドがハンドル接触スレッドに影響しないことを
  示すためだけに存在します。
  ==================================================================== }
type
  TIssuerThread = class(TThread)
  private
    FSvc: IRigService;
  protected
    procedure Execute; override;
  public
    constructor Create(const ASvc: IRigService);
  end;

constructor TIssuerThread.Create(const ASvc: IRigService);
begin
  FSvc := ASvc;        { holds a reference for the thread's lifetime
                         / スレッド存続中の参照を保持 }
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TIssuerThread.Execute;
var
  i: Integer;
begin
  IssuerTid := GetCurrentThreadId;
  for i := 1 to 15 do
  begin
    { Callbacks are left nil on purpose: this thread must not be the
      one that receives results either.
      コールバックは意図的に nil です。このスレッドが結果受信側にも
      ならないようにします。 }
    FSvc.SetFrequencyAsync(7074000 + i * 500, rvfoB);
    FSvc.GetFrequencyAsync(rvfoB);
    FSvc.SetModeAsync(rmLSB, 2400, rvfoB);
    FSvc.GetModeAsync(rvfoB);
    FSvc.SetPttAsync(rpttOff);
    Sleep(4);
  end;
  FSvc := nil;
end;

{ ====================================================================
  Scenario A — normal operation under three concurrent issuers.
  SCENARIO A — 3 系統の同時発行下での通常動作。
  ==================================================================== }
procedure RunNormalOperation;
var
  Svc:        IRigService;
  Issuer:     TIssuerThread;
  i:          Integer;
  Distinct:   Integer;
  WorkerTid:  TThreadID;
  PolledFreq: Integer;
begin
  WriteLn('SCENARIO A - normal operation, three concurrent issuers');
  WriteLn('             (main thread, a second app thread, the poller)');
  ResetLog;

  Svc := TRigService.Create(TProbeLoader.Create);
  try
    Svc.Open(1, 'none');
    Sleep(120);                      { let the Worker connect / 接続完了待ち }

    Svc.EnablePolling(60);
    Issuer := TIssuerThread.Create(Svc);
    try
      for i := 1 to 15 do
      begin
        Svc.SetFrequencyAsync(14074000 + i * 500, rvfoA);
        Svc.GetFrequencyAsync(rvfoA);
        Svc.SetModeAsync(rmUSB, 2700, rvfoA);
        Svc.GetModeAsync(rvfoA);
        Svc.SetPttAsync(rpttOff);
        CheckSynchronize(5);
        Sleep(4);
      end;
      Issuer.WaitFor;
    finally
      Issuer.Free;
    end;

    { Drain the queue so the counts below reflect completed work.
      下記の件数が完了済み作業を反映するよう、キューを吐き出させます。 }
    for i := 1 to 80 do
    begin
      CheckSynchronize(10);
      Sleep(5);
      if Svc.QueueDepth = 0 then Break;
    end;

    { Then let the poller run alone for a while, so its contribution to
      the get_freq count is unambiguous and the handle keeps being
      touched while the main thread does nothing but pump.

      続いて poller を単独で走らせます。get_freq 件数への寄与を明確にし、
      メインスレッドがポンプしかしていない間もハンドルが触られ続ける
      状態を作ります。 }
    for i := 1 to 60 do
    begin
      CheckSynchronize(5);
      Sleep(10);
    end;

    Svc.DisablePolling;
    Svc.CancelAllPending;
    Svc.Close;
  finally
    Svc := nil;
    CheckSynchronize(300);
  end;

  Distinct   := DistinctThreadCount('', WorkerTid);
  PolledFreq := CallCount('rig_get_freq');

  WriteLn('    calls recorded : ', Length(CallLog));
  WriteLn('    rig_init / open / close / cleanup : ',
          CallCount('rig_init'), ' / ', CallCount('rig_open'), ' / ',
          CallCount('rig_close'), ' / ', CallCount('rig_cleanup'));
  WriteLn('    set_freq / get_freq : ',
          CallCount('rig_set_freq'), ' / ', PolledFreq);
  WriteLn('    set_mode / get_mode / set_ptt : ',
          CallCount('rig_set_mode'), ' / ', CallCount('rig_get_mode'),
          ' / ', CallCount('rig_set_ptt'));
  WriteLn('    distinct threads touching the handle : ', Distinct);
  WriteLn;

  Check('the handle was actually exercised',
        Length(CallLog) > 100,
        Format('only %d calls recorded', [Length(CallLog)]));
  Check('lifecycle calls all happened',
        (CallCount('rig_init') = 1) and (CallCount('rig_open') = 1)
        and (CallCount('rig_close') = 1) and (CallCount('rig_cleanup') = 1));
  Check('tier-1 conf was pushed through the same path',
        CallCount('rig_set_conf') >= 2);
  Check('every command kind reached the handle',
        (CallCount('rig_set_freq') > 0) and (CallCount('rig_get_freq') > 0)
        and (CallCount('rig_set_mode') > 0) and (CallCount('rig_get_mode') > 0)
        and (CallCount('rig_set_ptt') > 0));
  Check('the second application thread really ran',
        IssuerTid <> 0);
  Check('the poller contributed queries of its own',
        PolledFreq > 35,
        Format('%d get_freq calls; 30 were issued explicitly, so the poller '
               + 'should push this well past 35', [PolledFreq]));

  { The invariant itself. / 不変条件そのもの。 }
  Check('INVARIANT: exactly one thread ever touched the handle',
        Distinct = 1,
        Format('%d distinct threads', [Distinct]));
  Check('that thread is not the main thread',
        WorkerTid <> MainTid);
  Check('that thread is not the second application thread',
        WorkerTid <> IssuerTid);
  WriteLn;
end;

{ ====================================================================
  Scenario B — the one sanctioned exception, and nothing beyond it.
  SCENARIO B — 唯一許された例外と、それ以上がないこと。
  ==================================================================== }
procedure RunWatchdogException;
var
  Svc:       IRigService;
  Policy:    TRigTimeoutPolicy;
  i:         Integer;
  Distinct:  Integer;
  WorkerTid: TThreadID;
  WdogTid:   TThreadID;
  j:         Integer;
begin
  WriteLn('SCENARIO B - watchdog abort: rig_close from a second thread');
  WriteLn('             must be the ONLY cross-thread handle access');
  ResetLog;

  Policy := RigPolicy_Default;
  Policy.CommandTimeoutMs := 1000;

  Svc := TRigService.Create(TStuckProbeLoader.Create);
  try
    Svc.ApplyTimeoutPolicy(Policy);
    Svc.Open(1, 'none');
    Sleep(120);

    Svc.GetFrequencyAsync(rvfoA);          { this one wedges / これが固まる }
    for i := 1 to 400 do
    begin
      CheckSynchronize(10);
      Sleep(5);
      if (CallCount('rig_get_freq') > 0) and
         (CallCount('rig_close') > 0) then Break;
    end;

    Svc.CancelAllPending;
    Svc.Close;
  finally
    Svc := nil;
    CheckSynchronize(300);
  end;

  { The Worker is whichever thread ran rig_get_freq — it is the thread
    that was blocked, by construction.
    Worker は rig_get_freq を実行したスレッドです。構造上、ブロックされて
    いたスレッドがそれに当たります。 }
  WorkerTid := 0;
  LogLock.Acquire;
  try
    for j := 0 to High(CallLog) do
      if CallLog[j].Name = 'rig_get_freq' then
      begin
        WorkerTid := CallLog[j].Tid;
        Break;
      end;
  finally
    LogLock.Release;
  end;

  { Find the watchdog thread: the rig_close that did not come from the
    Worker.
    watchdog スレッドの特定: Worker 由来でない rig_close。 }
  WdogTid := 0;
  LogLock.Acquire;
  try
    for j := 0 to High(CallLog) do
      if (CallLog[j].Name = 'rig_close') and (CallLog[j].Tid <> WorkerTid) then
      begin
        WdogTid := CallLog[j].Tid;
        Break;
      end;
  finally
    LogLock.Release;
  end;

  Distinct := DistinctThreadCount('rig_close', WorkerTid);

  WriteLn('    calls recorded : ', Length(CallLog));
  WriteLn('    rig_close calls : ', CallCount('rig_close'));
  WriteLn('    watchdog aborted the stuck call : ', WdogTid <> 0);
  if WdogTid <> 0 then
    WriteLn('    calls seen from the watchdog thread : ', NamesFromThread(WdogTid));
  WriteLn('    distinct threads excluding rig_close : ', Distinct);
  WriteLn;

  Check('the stuck call was aborted by another thread',
        WdogTid <> 0,
        'no rig_close arrived from outside the Worker');
  Check('INVARIANT: excluding the abort, still exactly one thread',
        Distinct = 1,
        Format('%d distinct threads', [Distinct]));
  Check('the abort thread touched rig_close and nothing else',
        (WdogTid = 0) or (NamesFromThread(WdogTid) = 'rig_close'),
        NamesFromThread(WdogTid));
  Check('the Worker is still not the main thread',
        (WorkerTid <> 0) and (WorkerTid <> MainTid));
  WriteLn;
end;

{ ====================================================================
  Scenario C — detector self-test.
  SCENARIO C — 検出器の自己検査。
  ====================================================================
  A fitness function that cannot fail is worthless: if a refactor ever
  removed the probe, scenarios A and B would still print "ok". So this
  scenario deliberately commits the violation it is meant to catch —
  the main thread reads the handle directly, the way a careless "fast
  path" optimisation would — and asserts the detector notices.

  失敗し得ないフィットネス関数は無価値です。将来の改修でプローブが外れて
  も、SCENARIO A と B は "ok" を印字し続けてしまいます。そこで本シナリオ
  は、検出対象の違反を意図的に犯します。不注意な「高速パス」最適化がやり
  そうな、メインスレッドからのハンドル直読みです。検出器がそれを捉えるこ
  とを検査します。
  ==================================================================== }
procedure RunDetectorSelfTest;
var
  Svc:      IRigService;
  Probe:    IHamlibLoader;
  i:        Integer;
  Distinct: Integer;
  Sample:   TThreadID;
  Freq:     Double;
begin
  WriteLn('SCENARIO C - detector self-test: an injected direct call from');
  WriteLn('             the main thread must be caught');
  ResetLog;

  Probe := TProbeLoader.Create;
  Svc   := TRigService.Create(Probe);
  try
    Svc.Open(1, 'none');
    Sleep(120);

    Svc.GetFrequencyAsync(rvfoA);
    for i := 1 to 40 do
    begin
      CheckSynchronize(5);
      Sleep(5);
      if Svc.QueueDepth = 0 then Break;
    end;

    { The violation. This is what the architecture forbids.
      これが違反です。アーキテクチャが禁じている行為そのものです。 }
    Probe.CallRigGetFreq(Pointer(1), 0, Freq);

    Svc.CancelAllPending;
    Svc.Close;
  finally
    Svc   := nil;
    Probe := nil;
    CheckSynchronize(300);
  end;

  Distinct := DistinctThreadCount('', Sample);
  WriteLn('    distinct threads after the injected violation : ', Distinct);
  WriteLn('    main thread appears in the log : ',
          CalledFromOtherThan('rig_get_freq', Sample));
  WriteLn;

  Check('the detector reports two threads when the rule is broken',
        Distinct = 2,
        Format('%d distinct threads - the probe is no longer observing '
               + 'what it claims to observe', [Distinct]));
  WriteLn;
end;

{ ==================================================================== }
begin
  MainTid := GetCurrentThreadId;
  LogLock := TCriticalSection.Create;
  try
    WriteLn('=== Thread-confinement fitness function ===');
    WriteLn('    invariant: all PRIG access happens on one thread');
    WriteLn;

    RunNormalOperation;
    RunWatchdogException;
    RunDetectorSelfTest;

    WriteLn('--- ', Checks - Failures, ' / ', Checks, ' checks passed ---');
    if Failures = 0 then
      WriteLn('RESULT: OK (thread confinement holds)')
    else
    begin
      WriteLn('RESULT: *** ', Failures, ' FAILURE(S) - the confinement ',
              'invariant is broken ***');
      ExitCode := 1;
    end;
  finally
    SetLength(CallLog, 0);
    LogLock.Free;
  end;
end.
