{
  HamlibPoller.pas

  LCL-free polling thread that periodically asks the Service to issue one
  frequency query. Hidden inside TRigService — application code never
  references this class directly.

  LCL 非依存のポーリングスレッド。Service に対して「1 回だけ周波数を問い合わせよ」
  と周期的に依頼します。TRigService 内部に隠蔽されており、アプリケーション
  コードはこのクラスを直接参照しません。

  Layer:    L5
  Depends:  HamlibInterfaces, SyncObjs

  --------------------------------------------------------------------
  Rev.4.1 CHANGE — no interface reference to the Service
  Rev.4.1 変更 — Service へのインターフェース参照を持たない
  --------------------------------------------------------------------
  Up to Rev.4.0 this thread held `FService: IRigService`. Because
  TRigService descends from TInterfacedObject, that reference incremented
  its reference count, creating a cycle:

      TRigService --(plain pointer FPoller)--> TRigPollerThread
      TRigPollerThread --(IRigService, refcount +1)--> TRigService

  The cycle meant TRigService.Destroy never ran unless Close() was called
  first — exactly the opposite of the "self-defending destructor" intent.

  Rev.4.0 までは `FService: IRigService` を保持していました。TRigService は
  TInterfacedObject 派生のため、この参照が参照カウントを増やし循環参照を作って
  いました。結果として Close() を呼ばない限り TRigService.Destroy が実行されず、
  「自己防衛デストラクタ」の意図と正反対の挙動になっていました。

  Rev.4.1 uses method pointers instead. A method pointer stores only
  (code address, instance address) and does NOT touch the reference count.
  The Service guarantees the poller is stopped and freed before the Service
  itself is destroyed, so the raw instance pointer can never dangle.

  Rev.4.1 ではメソッドポインタを使います。メソッドポインタは (コードアドレス,
  インスタンスアドレス) だけを保持し、参照カウントに触れません。Service は
  自身の破棄前に必ず poller を停止・解放するため、素のインスタンスポインタが
  ダングリングすることはありません。

  Note: waiting uses RTLEventWaitFor (NOT TTimer or any LCL primitive), so
  this unit works in console programs and unit test runners.

  注: 待機には RTLEventWaitFor を使用します (TTimer や LCL プリミティブ
  ではない)。コンソールプログラムやテストランナーでも動作します。
}
unit HamlibPoller;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs,
  HamlibInterfaces;

type
  { Internal callback used by the Service to deliver one poll result.
    Service が 1 回分のポーリング結果を配送するための内部コールバック。 }
  TRigPollerFreqCallback = procedure(const AResult: TRigFreqResult) of object;

  { Supplied by the Service. Issues exactly one frequency query and routes
    the result to ACallback. Implemented as a method pointer so that no
    reference count is taken on the Service.

    Service が供給します。周波数問い合わせを 1 回だけ発行し、結果を
    ACallback に流します。メソッドポインタとして実装することで Service の
    参照カウントを取りません。 }
  TRigPollTickProc = procedure(ACallback: TRigPollerFreqCallback) of object;

  { Supplied by the Service. Returns True when a poll may be issued now
    (connected, not overloaded). Checked immediately before each tick.

    Service が供給します。今ポーリングを発行してよいとき True を返します
    (接続済みかつ輻輳していない)。各ティックの直前に確認されます。 }
  TRigPollCanRunFunc = function: Boolean of object;

  { ====================================================================
    TRigPollFreqSink — where a poll result is actually handled
    TRigPollFreqSink - ポーリング結果を実際に処理する場所
    ====================================================================
    This used to be a method on TRigPollerThread, and that was a
    use-after-free waiting to happen.

    A poll result travels: poller thread -> Worker -> TThread.Queue ->
    UI thread. The queued delivery held `@Poller.HandleFreqResult`, a
    raw method pointer bound to the poller instance. DisablePolling
    frees that instance. Close calls DisablePolling and then
    FWorker.WaitFor — and FPC's TThread.WaitFor runs CheckSynchronize
    while it waits, so the queued delivery fired microseconds after its
    target had been freed, inside Close itself.

    Found by RandomSequenceTest and reduced to a short reproducer
    (open, poll, leave results queued, Close) that crashed within three
    rounds with an access violation.

    The fix is to put the handler somewhere the delivery can hold onto.
    This object is reference-counted and the dispatch takes a reference,
    so it outlives the poller thread and the Close. Deactivate makes a
    late result a no-op rather than an action taken on behalf of a rig
    nobody is watching any more.

    これはかつて TRigPollerThread のメソッドであり、それは起きるのを待って
    いる use-after-free でした。

    ポーリング結果は ポーラスレッド → Worker → TThread.Queue → UI スレッド
    と流れます。キューに積まれた配送が保持していたのは
    `@Poller.HandleFreqResult`、すなわちポーラ実体に束縛された生のメソッド
    ポインタです。DisablePolling はその実体を解放します。Close は
    DisablePolling を呼び、続いて FWorker.WaitFor を呼びます。そして FPC の
    TThread.WaitFor は待機中に CheckSynchronize を回すため、積まれていた
    配送は対象が解放された数マイクロ秒後、Close の内部で発火していました。

    RandomSequenceTest が発見し、短い再現コード (open、ポーリング、結果を
    キューに残す、Close) に縮約したところ、3 周以内にアクセス違反で落ちま
    した。

    修正は、ハンドラを「配送が掴んでいられる場所」に置くことです。本
    オブジェクトは参照カウント管理され、配送が参照を取るため、ポーラ
    スレッドより、そして Close より長生きします。Deactivate は、遅れて
    届いた結果を、もはや誰も見ていないリグのための動作ではなく無処理に
    します。 }
  TRigPollFreqSink = class(TInterfacedObject, IRigDeliveryKeepAlive)
  private
    { Touched only on the UI thread. UI スレッドでのみ触れます。 }
    FLastFreq:      Double;
    FLastFreqValid: Boolean;
    FThresholdHz:   Double;
    FActive:        Boolean;
    FOnFreqChanged: TRigFreqChangedEvent;
  public
    constructor Create;

    { The poll callback. Runs on the UI thread.
      ポーリングのコールバック。UI スレッドで動きます。 }
    procedure HandleFreqResult(const AResult: TRigFreqResult);

    procedure SetThresholdHz(AHz: Double);
    procedure SetOnFrequencyChanged(AHandler: TRigFreqChangedEvent);

    { Polling is starting / has stopped. A deactivated sink still
      accepts deliveries — it has to, they are already queued — and
      ignores them.
      ポーリングの開始 / 停止。非活性のシンクも配送は受け取ります
      (既にキューにあるため受け取らざるをえません) が、無視します。 }
    procedure Activate;
    procedure Deactivate;
  end;

  { ====================================================================
    TRigPollerThread — periodic frequency polling
    TRigPollerThread - 周波数の周期ポーリング
    ==================================================================== }
  TRigPollerThread = class(TThread)
  private
    { Callbacks into the Service. Method pointers — no refcount taken.
      Service へのコールバック。メソッドポインタのため参照カウントなし。 }
    FOnPollTick:     TRigPollTickProc;
    FCanRun:         TRigPollCanRunFunc;

    { Parameters mutable from other threads; guarded by FParamLock.
      他スレッドから変更されるパラメータ。FParamLock で保護します。 }
    FParamLock:      TCriticalSection;
    FIntervalMs:     Cardinal;

    FStopEvent:      PRTLEvent;

    { The callback each tick is posted with. It belongs to the sink,
      not to this thread, so that freeing this thread cannot strand a
      delivery that is already on its way back.
      各ティックの投稿に使うコールバック。本スレッドではなくシンクに属し
      ます。本スレッドを解放しても、戻る途中の配送が宙吊りにならないよう
      にするためです。 }
    FInternalFreqCb: TRigPollerFreqCallback;

    function  GetIntervalMs: Cardinal;
  protected
    procedure Execute; override;
  public
    { AOnPollTick and ACanRun are method pointers belonging to the Service.
      The Service must stop and free this thread before destroying itself.

      AOnPollTick と ACanRun は Service に属するメソッドポインタです。
      Service は自身の破棄前に本スレッドを停止・解放しなければなりません。 }
    constructor Create(AOnPollTick: TRigPollTickProc;
                       ACanRun: TRigPollCanRunFunc;
                       AFreqCallback: TRigPollerFreqCallback;
                       AIntervalMs: Cardinal = 200);
    destructor  Destroy; override;

    { Begin polling. ポーリングを開始します。 }
    procedure Start;

    { Signal the thread to stop. Returns immediately; call WaitFor to block
      until the thread has actually exited.
      停止を指示します。即座に戻るため、実際の終了を待つには WaitFor を呼びます。 }
    procedure Stop;

    { Thread-safe parameter updates. スレッドセーフなパラメータ更新。 }
    procedure SetIntervalMs(AMs: Cardinal);
  end;

implementation

const
  MIN_INTERVAL_MS = 50;

{ ------------------------------------------------------------------
  TRigPollFreqSink
  ------------------------------------------------------------------ }

constructor TRigPollFreqSink.Create;
begin
  inherited Create;
  FLastFreq      := 0;
  FLastFreqValid := False;
  FThresholdHz   := 1.0;
  FActive        := False;
end;

procedure TRigPollFreqSink.SetThresholdHz(AHz: Double);
begin
  if AHz > 0 then
    FThresholdHz := AHz;
end;

procedure TRigPollFreqSink.SetOnFrequencyChanged(AHandler: TRigFreqChangedEvent);
begin
  FOnFreqChanged := AHandler;
end;

procedure TRigPollFreqSink.Activate;
begin
  { The last reading is forgotten, not kept. Polling that resumes after
    a gap must report the first frequency it sees, because the operator
    may have moved the rig while nobody was looking — comparing against
    a pre-gap value would suppress exactly the change worth announcing.
    直前の読み値は保持せず忘れます。中断を挟んで再開したポーリングは、
    最初に見た周波数を報告しなければなりません。誰も見ていない間に
    オペレータがリグを動かした可能性があり、中断前の値と比較すると、
    まさに知らせる価値のある変化を握りつぶすことになります。 }
  FLastFreqValid := False;
  FActive        := True;
end;

procedure TRigPollFreqSink.Deactivate;
begin
  FActive := False;
end;

procedure TRigPollFreqSink.HandleFreqResult(const AResult: TRigFreqResult);
begin
  { Runs on the UI thread (dispatched from the Worker via TThread.Queue).
    UI スレッドで実行されます (Worker から TThread.Queue 経由で配送)。 }
  if not FActive then Exit;
  if AResult.Status <> rcsSuccess then Exit;

  if (not FLastFreqValid)
     or (Abs(AResult.Freq - FLastFreq) > FThresholdHz) then
  begin
    FLastFreq      := AResult.Freq;
    FLastFreqValid := True;
    if Assigned(FOnFreqChanged) then
      FOnFreqChanged(nil, AResult.Freq);
  end;
end;

{ ------------------------------------------------------------------
  TRigPollerThread
  ------------------------------------------------------------------ }

constructor TRigPollerThread.Create(AOnPollTick: TRigPollTickProc;
                                     ACanRun: TRigPollCanRunFunc;
                                     AFreqCallback: TRigPollerFreqCallback;
                                     AIntervalMs: Cardinal);
begin
  Assert(Assigned(AOnPollTick), 'Poll tick procedure must be assigned');

  inherited Create(True);   { Suspended / サスペンド状態 }
  FreeOnTerminate := False;

  FOnPollTick     := AOnPollTick;
  FCanRun         := ACanRun;
  FParamLock      := TCriticalSection.Create;

  if AIntervalMs < MIN_INTERVAL_MS then
    AIntervalMs := MIN_INTERVAL_MS;
  FIntervalMs     := AIntervalMs;

  FStopEvent      := RTLEventCreate;
  FInternalFreqCb := AFreqCallback;
end;

destructor TRigPollerThread.Destroy;
begin
  RTLEventDestroy(FStopEvent);
  FParamLock.Free;
  inherited;
end;

procedure TRigPollerThread.Start;
begin
  RTLEventResetEvent(FStopEvent);
  inherited Start;
end;

procedure TRigPollerThread.Stop;
begin
  Terminate;
  RTLEventSetEvent(FStopEvent);   { Break out of a pending Wait.
                                    待機中の Wait を中断する。 }
end;

procedure TRigPollerThread.SetIntervalMs(AMs: Cardinal);
begin
  if AMs < MIN_INTERVAL_MS then
    AMs := MIN_INTERVAL_MS;
  FParamLock.Acquire;
  try
    FIntervalMs := AMs;
  finally
    FParamLock.Release;
  end;
end;

function TRigPollerThread.GetIntervalMs: Cardinal;
begin
  FParamLock.Acquire;
  try
    Result := FIntervalMs;
  finally
    FParamLock.Release;
  end;
end;




procedure TRigPollerThread.Execute;
begin
  while not Terminated do
  begin
    { Ask the Service whether a poll is appropriate right now, then let it
      issue the query. No interface reference is held at any point.

      今ポーリングしてよいかを Service に確認し、問い合わせを発行させます。
      どの時点でもインターフェース参照は保持しません。

      The try/except is load-bearing: CanRun and the actual enqueue are not
      one atomic step, so a Close() on another thread can slip between them
      and make the Service raise ERigServiceClosed. Letting that escape
      Execute would silently kill polling for the rest of the session.

      try/except は必須です。CanRun と実際の投入は不可分ではないため、
      別スレッドの Close() が間に割り込み Service が ERigServiceClosed を
      発生させ得ます。これが Execute の外へ出ると、以降セッション全体で
      ポーリングが静かに停止してしまいます。 }
    try
      if (not Assigned(FCanRun)) or FCanRun() then
        FOnPollTick(FInternalFreqCb);
    except
      { The next CanRun will report the Service as closed and the loop
        will simply idle until Stop arrives.
        次の CanRun が Service を閉鎖中と報告し、Stop が来るまでループは
        アイドルします。 }
    end;

    RTLEventResetEvent(FStopEvent);
    RTLEventWaitFor(FStopEvent, GetIntervalMs);
  end;
end;


end.
