{
  HamlibWatchdog.pas

  Tier-2 command timeout. A tiny supervisor thread that notices when the
  Worker has been stuck inside one Hamlib call for too long and forces
  the underlying I/O to unblock.

  コマンドタイムアウトの第 2 段。Worker が 1 つの Hamlib 呼び出しの中で
  長く固まっていることを検出し、下位の I/O を強制的に解除する小さな
  監視スレッドです。

  Layer:    L3 support
  Depends:  HamlibInterfaces, SyncObjs

  --------------------------------------------------------------------
  Why two tiers
  なぜ二段構えなのか
  --------------------------------------------------------------------
  Tier 1 is Hamlib's own "timeout"/"retry" configuration, applied in
  TRigWorker.ConnectInternal. It covers the normal case: the rig is
  attached but silent, so the serial read expires and Hamlib returns
  -RIG_ETIMEOUT by itself. That is the cheap, correct path and it needs
  no extra thread.

  第 1 段は Hamlib 自身の "timeout"/"retry" 設定で、
  TRigWorker.ConnectInternal で適用します。通常のケース、つまりリグは
  繋がっているが無応答という状況を担当します。シリアル読み取りが期限切れに
  なり Hamlib が自分で -RIG_ETIMEOUT を返します。これが安価で正しい経路で、
  追加スレッドは不要です。

  Tier 1 cannot cover the case where the read never expires at all: a USB
  serial adapter unplugged mid-transfer, a driver that blocks in the
  kernel, or a backend that loops internally. Hamlib's timeout is applied
  per read() and a wedged device may never return from one. Then the
  Worker thread is gone for good, the queue stops draining, and the
  application looks hung with no error ever delivered.

  第 1 段では、読み取りがそもそも期限切れにならないケースを救えません。
  転送中に USB シリアル変換器が抜かれた、ドライバがカーネル内でブロック
  している、バックエンドが内部でループしている、といった場合です。Hamlib の
  timeout は read() ごとに効くため、固まったデバイスからは戻ってこないことが
  あります。こうなると Worker スレッドは戻らず、キューは流れず、エラーも
  届かないままアプリケーションは停止して見えます。

  Tier 2 handles that. The Worker stamps the start of every Hamlib call;
  this thread watches the stamp and, once the deadline passes, invokes an
  abort action supplied by the Worker. The abort closes the rig handle,
  which makes the blocked read fail and lets the Worker unwind.

  第 2 段がこれを扱います。Worker は各 Hamlib 呼び出しの開始時刻を記録し、
  本スレッドがそれを監視して、期限を過ぎたら Worker から渡された中断処理を
  起動します。中断処理はリグハンドルを閉じ、ブロック中の読み取りを失敗させて
  Worker を巻き戻します。

  --------------------------------------------------------------------
  Honest limitation
  正直な限界
  --------------------------------------------------------------------
  Calling rig_close from a second thread while the Worker is inside a
  Hamlib call is not something Hamlib documents as safe. It is a last
  resort: the alternative is an application that never recovers. The
  abort fires only after the deadline has already been missed, which
  means the session is being torn down anyway — the Worker always
  reconnects from scratch afterwards and never reuses the handle.

  Worker が Hamlib 呼び出しの中にいる間に別スレッドから rig_close を呼ぶ
  ことは、Hamlib が安全と明記している操作ではありません。これは最後の手段
  です。代替案は「二度と回復しないアプリケーション」だからです。中断は期限を
  過ぎて初めて発火し、その時点でセッションは破棄される前提です。Worker は
  必ずゼロから再接続し、そのハンドルを再利用することはありません。
}
unit HamlibWatchdog;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs;

type
  { Supplied by the Worker. Called on the watchdog thread when a command
    has overrun its deadline. Must force the blocked I/O to fail.

    Worker が供給します。コマンドが期限を超過したとき watchdog スレッド
    から呼ばれます。ブロック中の I/O を失敗させる必要があります。 }
  TWatchdogAbortProc = procedure of object;

  TRigWatchdog = class(TThread)
  private
    FLock:        TCriticalSection;
    FStopEvent:   PRTLEvent;
    FOnAbort:     TWatchdogAbortProc;

    { Armed state, all guarded by FLock.
      armed 状態。すべて FLock で保護。 }
    { True once the thread has actually been resumed. A TThread created
      suspended and never started never enters Execute, so WaitFor on
      it blocks forever — this flag is what lets the destructor tell
      the two cases apart. See REV6_REPORT.md section 5.

      スレッドが実際に再開されたら True。サスペンド状態で生成され一度も
      開始されていない TThread は Execute に入らないため、WaitFor は
      永久にブロックします。本フラグはデストラクタが 2 つの場合を区別
      するためのものです (REV6_REPORT.md 第 5 章)。 }
    FStarted:     Boolean;
    FArmed:       Boolean;
    FDeadline:    QWord;    { GetTickCount64 value / GetTickCount64 の値 }
    FFired:       Boolean;  { abort already invoked for this arming
                              / 今回の arming で中断済みか }
    FTimeoutCount: Integer;

    function GetTimeoutCount: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AOnAbort: TWatchdogAbortProc);
    destructor  Destroy; override;

    procedure Start;
    procedure Stop;

    { Whether Start has been called. The Worker needs this because it
      may be destroyed before it ever ran, and waiting on a thread
      that was never resumed is a deadlock, not a wait.
      Start が呼ばれたか。Worker は一度も実行されないまま破棄されること
      があり、再開されていないスレッドを待つのは待機ではなくデッド
      ロックであるため、この情報が必要です。 }
    property Started: Boolean read FStarted;

    { Begin watching a call that must finish within ABudgetMs.
      Called by the Worker immediately before entering Hamlib.
      ABudgetMs 以内に終わるべき呼び出しの監視を開始します。
      Worker が Hamlib に入る直前に呼びます。 }
    procedure Arm(ABudgetMs: Cardinal);

    { Stop watching. Returns True if the watchdog had already fired, i.e.
      the call that just finished overran and its result must be reported
      as rcsTimeout rather than trusted.

      監視を終了します。すでに中断が発火していた場合 True を返します。
      つまり直前の呼び出しは期限超過であり、その結果は信用せず
      rcsTimeout として報告しなければなりません。 }
    function  Disarm: Boolean;

    { Number of times the watchdog has fired since construction.
      生成以降に中断が発火した回数。 }
    property TimeoutCount: Integer read GetTimeoutCount;
  end;

implementation

const
  { How often the watchdog re-checks the deadline. Fine enough that the
    overshoot stays small next to any realistic CommandTimeoutMs.
    watchdog が期限を再確認する間隔。現実的な CommandTimeoutMs に対して
    行き過ぎが小さく収まる程度の粒度。 }
  WATCHDOG_TICK_MS = 50;

constructor TRigWatchdog.Create(AOnAbort: TWatchdogAbortProc);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLock      := TCriticalSection.Create;
  FStopEvent := RTLEventCreate;
  FOnAbort   := AOnAbort;
  FArmed     := False;
  FFired     := False;
end;

destructor TRigWatchdog.Destroy;
begin
  { Guarantee the thread is terminated before anything it touches is
    freed, whether or not it was ever started.

    A TThread constructed with Create(True) sits inside the RTL's
    start gate until Start resumes it. It is not running, so Terminate
    does not reach it and WaitFor on it never returns — the thread has
    not finished and never will. Up to Rev.6.0 the Worker's destructor
    called Stop and WaitFor unconditionally, so a Worker destroyed
    before its thread was resumed hung the calling thread forever,
    with no error and no way out. An application that connected and
    disconnected quickly, or whose Open raised after the Worker was
    constructed, froze.

    Starting a terminated thread is the fix rather than a trick:
    Execute's loop condition is `while not Terminated`, so the thread
    resumes, finds the flag set, returns immediately, and WaitFor then
    has something real to wait for.

    スレッドが触れるものを解放する前に、起動済みか否かに関わらずスレッド
    の終了を保証します。

    Create(True) で構築された TThread は、Start が再開するまで RTL の
    開始ゲート内に留まります。実行されていないため Terminate は届かず、
    WaitFor は決して戻りません。スレッドは終了しておらず、今後も終了
    しないからです。Rev.6.0 まで Worker のデストラクタは Stop と WaitFor
    を無条件に呼んでいたため、スレッドが再開される前に破棄された
    Worker は、呼び出し側スレッドを永久に停止させました。エラーもなく、
    脱出手段もなく。接続直後に切断するアプリケーション、あるいは Worker
    構築後に Open が例外を投げたアプリケーションは、そこで固まりました。

    終了済みのスレッドを開始するのは小細工ではなく修正です。Execute の
    ループ条件は `while not Terminated` であり、スレッドは再開し、フラグ
    が立っているのを見て直ちに戻ります。WaitFor はそこで初めて、実際に
    待つべきものを持ちます。 }
  Terminate;
  if not FStarted then
  begin
    FStarted := True;
    inherited Start;
  end;
  RTLEventSetEvent(FStopEvent);
  WaitFor;

  RTLEventDestroy(FStopEvent);
  FLock.Free;
  inherited;
end;

procedure TRigWatchdog.Start;
begin
  RTLEventResetEvent(FStopEvent);
  FStarted := True;
  inherited Start;
end;

procedure TRigWatchdog.Stop;
begin
  Terminate;
  RTLEventSetEvent(FStopEvent);
end;

procedure TRigWatchdog.Arm(ABudgetMs: Cardinal);
begin
  FLock.Acquire;
  try
    FArmed    := True;
    FFired    := False;
    FDeadline := GetTickCount64 + ABudgetMs;
  finally
    FLock.Release;
  end;
end;

function TRigWatchdog.Disarm: Boolean;
begin
  FLock.Acquire;
  try
    Result := FFired;
    FArmed := False;
    FFired := False;
  finally
    FLock.Release;
  end;
end;

function TRigWatchdog.GetTimeoutCount: Integer;
begin
  FLock.Acquire;
  try
    Result := FTimeoutCount;
  finally
    FLock.Release;
  end;
end;

procedure TRigWatchdog.Execute;
var
  MustAbort: Boolean;
begin
  while not Terminated do
  begin
    MustAbort := False;

    FLock.Acquire;
    try
      if FArmed and (not FFired) and (GetTickCount64 >= FDeadline) then
      begin
        FFired := True;
        Inc(FTimeoutCount);
        MustAbort := True;
      end;
    finally
      FLock.Release;
    end;

    { The abort runs outside the lock: it reaches into Hamlib and may
      block briefly, and holding FLock there would stall Arm/Disarm on
      the Worker thread.

      中断処理はロックの外で実行します。Hamlib に踏み込み短時間ブロック
      し得るため、FLock を保持したままでは Worker スレッドの Arm/Disarm を
      止めてしまいます。 }
    if MustAbort and Assigned(FOnAbort) then
    try
      FOnAbort;
    except
      { An abort that itself fails leaves the deadline passed and the
        Worker still stuck; nothing further this thread can do.
        中断処理自体が失敗した場合、期限超過のまま Worker は固まった
        ままです。本スレッドにできることはこれ以上ありません。 }
    end;

    RTLEventResetEvent(FStopEvent);
    RTLEventWaitFor(FStopEvent, WATCHDOG_TICK_MS);
  end;
end;

end.
