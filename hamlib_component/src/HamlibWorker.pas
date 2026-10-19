{
  HamlibWorker.pas

  The single thread that owns the PRIG handle. ALL Hamlib API calls
  go through this thread. Implements:
    - Command serialization via TCommandQueue
    - DeliverAndFree pattern (Use-After-Free elimination)
    - Circuit Breaker (cbsFixed and cbsAdaptive strategies)
    - Auto-reconnection on persistent failures
    - DrainQueueOnShutdown (clean termination guarantee)

  PRIG ハンドルを唯一所有するスレッド。すべての Hamlib API 呼び出しは
  このスレッドを経由します。実装内容:
    - TCommandQueue によるコマンド直列化
    - DeliverAndFree パターン (Use-After-Free 排除)
    - Circuit Breaker (cbsFixed および cbsAdaptive 戦略)
    - 持続的失敗からの自動再接続
    - DrainQueueOnShutdown (クリーン終了保証)

  Layer:    L3
  Depends:  HamlibInterfaces, HamlibErrors, HamlibTimeoutPolicy,
            HamlibVfoCodec, HamlibCommandBase, HamlibCommandQueue,
            HamlibFreqCommands, HamlibModeCommands, HamlibPttCommands,
            HamlibRigCommands,
  HamlibRigCommands

  Note: Application code does NOT use this class directly. It is owned
  by TRigService.

  注: アプリケーションコードはこのクラスを直接使いません。
  TRigService が所有します。
}
unit HamlibWorker;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs,
  HamlibInterfaces, HamlibErrors, HamlibTimeoutPolicy, HamlibVfoCodec,
  HamlibCommandBase, HamlibCommandQueue, HamlibWatchdog,
  HamlibFreqCommands, HamlibModeCommands, HamlibPttCommands,
  HamlibRigCommands;

type
  { ====================================================================
    TRigWorker — single-threaded executor of rig commands
    TRigWorker - リグコマンドの単一スレッド実行者
    ==================================================================== }
  TRigWorker = class(TThread)
  private
    FLoader:        IHamlibLoader;
    FRig:           Pointer;             { PRIG handle / PRIG ハンドル }
    FModel:         Integer;
    FPort:          string;
    FConnected:     Boolean;

    FQueue:         TCommandQueue;
    FPolicy:        TRigTimeoutPolicy;
    FPolicyLock:    TCriticalSection;
    { Conf tokens the application asked for, applied right after
      rig_init and before the port is opened — the only point at which
      Hamlib will honour most of them.
      アプリケーションが要求した設定トークン。rig_init の直後、ポートを
      開く前に適用します。Hamlib が大半のトークンを尊重する唯一の時点
      だからです。 }
    FConfTokens: TStringList;

    { Tier-2 command timeout. The watchdog thread forces blocked I/O to
      fail when a single Hamlib call overruns its budget.
      コマンドタイムアウト第 2 段。1 回の Hamlib 呼び出しが予算を超過した
      とき、watchdog スレッドがブロック中の I/O を失敗させます。 }
    FWatchdog:      TRigWatchdog;

    { True once this thread has been resumed. Waiting on a TThread
      that was created suspended and never started is a deadlock, not
      a wait: it has not finished and never will.
      このスレッドが再開されたら True。サスペンド状態で生成され一度も
      開始されていない TThread を待つのは、待機ではなくデッドロック
      です。終了しておらず、今後も終了しないからです。 }
    FStarted:       Boolean;
    FAbortLock:     TCriticalSection;   { serialises abort vs. teardown
                                          中断と破棄を直列化 }

    { Circuit Breaker state. Circuit Breaker 状態。 }
    FCircuitOpen:   Boolean;
    FCircuitOpenAt: QWord;
    FConsecErrors:  Integer;
    FResultWindow:  TCommandResultWindow;

    { Event handlers, called via TThread.Queue on the UI thread.
      イベントハンドラ。TThread.Queue により UI スレッドで呼ばれます。 }
    FOnConnectionChanged: TRigConnectEvent;
    FOnError:             TRigErrorEvent;

    { ----------------------------------------------------------------
      Connection management
      接続管理
      ---------------------------------------------------------------- }
    procedure ConnectInternal;

    { Push CommandTimeoutMs/retry down into Hamlib (timeout tier 1).
      CommandTimeoutMs と retry を Hamlib に反映 (タイムアウト第 1 段)。 }
    procedure ApplyConfTokens;
    procedure ApplyHamlibTimeouts;

    { Invoked by the watchdog thread when a call overruns (tier 2).
      呼び出しが期限超過したとき watchdog スレッドから呼ばれます (第 2 段)。 }
    procedure AbortStuckCall;

    { Per-command budget, derived from the current policy.
      現在のポリシーから算出する 1 コマンドあたりの予算。 }
    function  CommandBudgetMs: Cardinal;
    procedure DisconnectInternal;
    procedure NotifyConnectionChanged(AConnected: Boolean);
    procedure NotifyError(AKind: TRigErrorKind; ANativeCode: Integer;
                          const AMsg: string);

    { ----------------------------------------------------------------
      Command processing — the heart of the Worker.
      コマンド処理 — Worker の中核。
      ---------------------------------------------------------------- }
    procedure ProcessCommand(ACmd: TRigCommand);

    { Deliver a result to the user callback and free the command.
      Critical: result and callback are copied to local stack variables
      BEFORE freeing the command, so the closure cannot reference a
      freed object.

      結果を利用者コールバックに配送し、コマンドを解放します。
      重要: 結果とコールバックはコマンド解放の前にローカルスタック変数に
      コピーされるため、クロージャが解放済みオブジェクトを参照することはありません。 }
    procedure DeliverAndFree(ACmd: TRigCommand; const AResult: TRigResult);
    procedure DeliverFreqAndFree(ACmd: TGetFreqCommand;
                                  const AResult: TRigFreqResult);
    { Reports a command that will never run through whichever typed
      callback it owns, and frees it. The single place that knows the
      command types — the implementation says why that matters.
      実行されることのないコマンドを、それが持つ型付きコールバック経由で
      報告し、解放します。コマンド型を知る唯一の場所です。理由は実装の
      コメントにあります。 }
    procedure DeliverCancelledAndFree(ACmd: TRigCommand;
                                      const AReason: string);

    procedure DeliverLevelAndFree(ACmd: TGetLevelCommand;
                                  const AResult: TRigLevelResult);
    procedure DeliverFuncAndFree(ACmd: TGetFuncCommand;
                                 const AResult: TRigFuncResult);
    procedure DeliverSplitAndFree(ACmd: TGetSplitCommand;
                                  const AResult: TRigSplitResult);
    procedure DeliverVfoAndFree(ACmd: TGetVfoCommand;
                                const AResult: TRigVfoResult);
    procedure DeliverModeAndFree(ACmd: TGetModeCommand;
                                  const AResult: TRigModeResult);
    procedure DeliverPttAndFree(ACmd: TGetPttCommand;
                                 const AResult: TRigPttResult);

    { ----------------------------------------------------------------
      Circuit Breaker
      ---------------------------------------------------------------- }
    procedure RecordCommandResult(ASuccess: Boolean);
    { AAnnounce = False suppresses the rekCircuitOpen notice, for the
      case where a more specific cause has just been reported.
      AAnnounce = False は rekCircuitOpen の通知を抑制します。より具体的
      な原因を直前に報告した場合のためです。 }
    procedure TripCircuitBreaker(AAnnounce: Boolean = True);
    procedure CheckCircuitBreaker;

    { ----------------------------------------------------------------
      Shutdown
      シャットダウン
      ---------------------------------------------------------------- }
    procedure DrainQueueOnShutdown;

    { Snapshot of FOnError for use in worker-thread notifications.
      Worker スレッド通知用の FOnError スナップショット。 }
    function GetOnErrorSnapshot: TRigErrorEvent;

  protected
    procedure Execute; override;

  public
    { Construct with a loader, rig model number, and port name.
      The thread is created suspended; call Start to begin.
      ローダ・リグモデル番号・ポート名で生成します。
      スレッドはサスペンド状態で生成されるので Start で開始してください。 }
    constructor Create(ALoader: IHamlibLoader; AModel: Integer;
                       const APort: string);
    destructor  Destroy; override;

    { Submit a command to the queue. Thread-safe; callable from any thread.
      コマンドをキューに投入します。スレッドセーフで任意のスレッドから呼べます。 }
    procedure PostCommand(ACmd: TRigCommand);

    { Cancel all queued commands by triggering their cancellation tokens
      and immediately delivering rcsCancelled. The command currently
      being executed (if any) will return rcsCancelled at its next check.

      キュー内の全コマンドを、キャンセルトークンをトリガしてから即座に
      rcsCancelled で配送することでキャンセルします。現在実行中のコマンド
      (もしあれば) は次のチェック時に rcsCancelled で戻ります。 }
    procedure CancelAllQueued;

    { Apply a new timeout policy. May be called from any thread.
      新しいタイムアウトポリシーを適用します。任意のスレッドから呼べます。 }
    { Copy the conf tokens the Service collected. Called before Start.
      Service が集めた設定トークンを複写します。Start の前に呼びます。 }
    procedure SetConfTokens(AList: TStringList);

    procedure ApplyPolicy(const APolicy: TRigTimeoutPolicy);

    { Request the worker to stop. The worker will drain its queue with
      rcsCancelled before disconnecting and exiting Execute.
      Worker に停止を要求します。Worker はキューを rcsCancelled でドレイン
      した後、切断して Execute を抜けます。 }
    { Resumes the thread and records that it was resumed, so the
      Service can tell "running" from "never started" when tearing
      down. See REV6_REPORT.md section 5.
      スレッドを再開し、再開されたことを記録します。Service が後始末の
      際に「実行中」と「一度も開始していない」を区別できるようにする
      ためです (REV6_REPORT.md 第 5 章)。 }
    procedure Start;

    { Whether Start has been called. Never call WaitFor when this is
      False.
      Start が呼ばれたか。False のとき WaitFor を呼んではいけません。 }
    property Started: Boolean read FStarted;

    procedure RequestStop;

    function QueueDepth: Integer;
    function CircuitBreakerOpen: Boolean;

    property OnConnectionChanged: TRigConnectEvent
      read FOnConnectionChanged write FOnConnectionChanged;
    property OnError: TRigErrorEvent
      read FOnError write FOnError;
  end;

implementation

{ ====================================================================
  Internal delivery dispatcher classes
  内部配送ディスパッチャクラス
  ====================================================================
  These tiny classes encapsulate one callback invocation. The Worker
  creates them, fills in the callback and result by value, and queues
  RunOnUIThread via TThread.Queue. After running on the UI thread the
  object self-destructs.

  Why classes instead of anonymous methods? FPC 3.2.x does not support
  Delphi-style "procedure ... begin ... end" anonymous methods as
  arguments to TThread.Queue. Class-based dispatch is the most portable
  and explicit alternative.

  これらの小さなクラスは1回のコールバック呼び出しをカプセル化します。
  Worker がこれらを生成し、コールバックと結果を値でフィールドに入れ、
  TThread.Queue で RunOnUIThread をキューに積みます。UI スレッドでの
  実行後にオブジェクトは自己破棄します。

  匿名メソッドではなくクラスを使う理由は、FPC 3.2.x が TThread.Queue
  への引数として Delphi 形式の "procedure ... begin ... end" 匿名メソッドを
  サポートしないためです。クラスベースのディスパッチは最も移植性が高く
  明示的な代替手段です。 }

type
  TWWGenericDeliveryDispatch = class
  private
    FCallback: TRigInternalCallback;
    FResult:   TRigResult;
  public
    constructor Create(ACallback: TRigInternalCallback;
                       const AResult: TRigResult);
    procedure RunOnUIThread;   { Invoked by TThread.Queue.
                                  TThread.Queue から呼び出される。 }
    property Callback: TRigInternalCallback read FCallback;
  end;

  TWWFreqDeliveryDispatch = class
  private
    FCallback: TRigFreqInternalCallback;
    FResult:   TRigFreqResult;
  public
    constructor Create(ACallback: TRigFreqInternalCallback;
                       const AResult: TRigFreqResult);
    procedure RunOnUIThread;
    property Callback: TRigFreqInternalCallback read FCallback;
  end;

  { One delivery dispatcher per result type, all the same shape as
    TWWModeDeliveryDispatch: copy the callback and the value-type
    result, free the command, then run on the UI thread and
    self-destruct. The repetition is the price of FPC 3.2.x having no
    generics worth using here; the alternative — one dispatcher holding
    a variant record of every result type — would be shorter and much
    easier to get wrong.

    結果型ごとに 1 つの配送ディスパッチャ。いずれも
    TWWModeDeliveryDispatch と同じ形です。コールバックと値型の結果を
    コピーし、コマンドを解放し、UI スレッドで実行して自己破棄します。
    この反復は、FPC 3.2.x にここで使うに値するジェネリクスが無いことの
    代償です。代案 (全結果型の可変レコードを持つ 1 つのディスパッチャ) は
    短くなりますが、はるかに誤りやすくなります。 }
  TWWLevelDeliveryDispatch = class
  private
    FCallback: TRigLevelInternalCallback;
    FResult:   TRigLevelResult;
  public
    constructor Create(ACallback: TRigLevelInternalCallback;
                       const AResult: TRigLevelResult);
    procedure RunOnUIThread;
    property Callback: TRigLevelInternalCallback read FCallback;
  end;

  TWWFuncDeliveryDispatch = class
  private
    FCallback: TRigFuncInternalCallback;
    FResult:   TRigFuncResult;
  public
    constructor Create(ACallback: TRigFuncInternalCallback;
                       const AResult: TRigFuncResult);
    procedure RunOnUIThread;
    property Callback: TRigFuncInternalCallback read FCallback;
  end;

  TWWSplitDeliveryDispatch = class
  private
    FCallback: TRigSplitInternalCallback;
    FResult:   TRigSplitResult;
  public
    constructor Create(ACallback: TRigSplitInternalCallback;
                       const AResult: TRigSplitResult);
    procedure RunOnUIThread;
    property Callback: TRigSplitInternalCallback read FCallback;
  end;

  TWWVfoDeliveryDispatch = class
  private
    FCallback: TRigVfoInternalCallback;
    FResult:   TRigVfoResult;
  public
    constructor Create(ACallback: TRigVfoInternalCallback;
                       const AResult: TRigVfoResult);
    procedure RunOnUIThread;
    property Callback: TRigVfoInternalCallback read FCallback;
  end;

  TWWModeDeliveryDispatch = class
  private
    FCallback: TRigModeInternalCallback;
    FResult:   TRigModeResult;
  public
    constructor Create(ACallback: TRigModeInternalCallback;
                       const AResult: TRigModeResult);
    procedure RunOnUIThread;
    property Callback: TRigModeInternalCallback read FCallback;
  end;

  TWWPttDeliveryDispatch = class
  private
    FCallback: TRigPttInternalCallback;
    FResult:   TRigPttResult;
  public
    constructor Create(ACallback: TRigPttInternalCallback;
                       const AResult: TRigPttResult);
    procedure RunOnUIThread;
    property Callback: TRigPttInternalCallback read FCallback;
  end;

  { Connection / error notification dispatchers.
    接続変更・エラー通知用のディスパッチャ。 }
  TWWConnectionDispatch = class
  private
    FHandler:   TRigConnectEvent;
    FConnected: Boolean;
  public
    constructor Create(AHandler: TRigConnectEvent; AConnected: Boolean);
    procedure RunOnUIThread;
  end;

  TWWErrorDispatch = class
  private
    FHandler: TRigErrorEvent;
    FKind:    TRigErrorKind;
    FCode:    Integer;
    FMsg:     string;
  public
    constructor Create(AHandler: TRigErrorEvent; AKind: TRigErrorKind;
                       ACode: Integer; const AMsg: string);
    procedure RunOnUIThread;
  end;

constructor TWWGenericDeliveryDispatch.Create(ACallback: TRigInternalCallback;
                                             const AResult: TRigResult);
begin
  inherited Create;
  FCallback := ACallback;
  FResult   := AResult;
end;

procedure TWWGenericDeliveryDispatch.RunOnUIThread;
begin
  try
    if Assigned(FCallback) then
      FCallback(FResult);
  finally
    Free;   { Self-destruct after delivery. 配送後の自己破棄。 }
  end;
end;

constructor TWWFreqDeliveryDispatch.Create(ACallback: TRigFreqInternalCallback;
                                          const AResult: TRigFreqResult);
begin
  inherited Create;
  FCallback := ACallback;
  FResult   := AResult;
end;

procedure TWWFreqDeliveryDispatch.RunOnUIThread;
begin
  try
    if Assigned(FCallback) then
      FCallback(FResult);
  finally
    Free;
  end;
end;

constructor TWWModeDeliveryDispatch.Create(ACallback: TRigModeInternalCallback;
                                          const AResult: TRigModeResult);
begin
  inherited Create;
  FCallback := ACallback;
  FResult   := AResult;
end;

procedure TWWModeDeliveryDispatch.RunOnUIThread;
begin
  try
    if Assigned(FCallback) then
      FCallback(FResult);
  finally
    Free;
  end;
end;

constructor TWWLevelDeliveryDispatch.Create(ACallback: TRigLevelInternalCallback;
                                            const AResult: TRigLevelResult);
begin
  inherited Create;
  FCallback := ACallback;
  FResult   := AResult;
end;

procedure TWWLevelDeliveryDispatch.RunOnUIThread;
begin
  try
    if Assigned(FCallback) then FCallback(FResult);
  finally
    Free;
  end;
end;

constructor TWWFuncDeliveryDispatch.Create(ACallback: TRigFuncInternalCallback;
                                           const AResult: TRigFuncResult);
begin
  inherited Create;
  FCallback := ACallback;
  FResult   := AResult;
end;

procedure TWWFuncDeliveryDispatch.RunOnUIThread;
begin
  try
    if Assigned(FCallback) then FCallback(FResult);
  finally
    Free;
  end;
end;

constructor TWWSplitDeliveryDispatch.Create(ACallback: TRigSplitInternalCallback;
                                            const AResult: TRigSplitResult);
begin
  inherited Create;
  FCallback := ACallback;
  FResult   := AResult;
end;

procedure TWWSplitDeliveryDispatch.RunOnUIThread;
begin
  try
    if Assigned(FCallback) then FCallback(FResult);
  finally
    Free;
  end;
end;

constructor TWWVfoDeliveryDispatch.Create(ACallback: TRigVfoInternalCallback;
                                          const AResult: TRigVfoResult);
begin
  inherited Create;
  FCallback := ACallback;
  FResult   := AResult;
end;

procedure TWWVfoDeliveryDispatch.RunOnUIThread;
begin
  try
    if Assigned(FCallback) then FCallback(FResult);
  finally
    Free;
  end;
end;

constructor TWWPttDeliveryDispatch.Create(ACallback: TRigPttInternalCallback;
                                         const AResult: TRigPttResult);
begin
  inherited Create;
  FCallback := ACallback;
  FResult   := AResult;
end;

procedure TWWPttDeliveryDispatch.RunOnUIThread;
begin
  try
    if Assigned(FCallback) then
      FCallback(FResult);
  finally
    Free;
  end;
end;

constructor TWWConnectionDispatch.Create(AHandler: TRigConnectEvent;
                                        AConnected: Boolean);
begin
  inherited Create;
  FHandler   := AHandler;
  FConnected := AConnected;
end;

procedure TWWConnectionDispatch.RunOnUIThread;
begin
  try
    if Assigned(FHandler) then
      FHandler(nil, FConnected);
  finally
    Free;
  end;
end;

constructor TWWErrorDispatch.Create(AHandler: TRigErrorEvent;
                                   AKind: TRigErrorKind;
                                   ACode: Integer; const AMsg: string);
begin
  inherited Create;
  FHandler := AHandler;
  FKind    := AKind;
  FCode    := ACode;
  FMsg     := AMsg;
end;

procedure TWWErrorDispatch.RunOnUIThread;
begin
  try
    if Assigned(FHandler) then
      FHandler(nil, FKind, FCode, FMsg);
  finally
    Free;
  end;
end;

const
  { How often (ms) Execute wakes up to check Circuit Breaker recovery.
    Execute が Circuit Breaker 回復チェックのため起きる間隔 (ms)。 }
  WORKER_TICK_MS = 100;

  { Hamlib RIG_ETIMEOUT (positive enum value; functions return -this).
    Hamlib の RIG_ETIMEOUT (正の enum 値。関数はこの符号反転を返す)。 }
  RIG_ETIMEOUT_CODE = 5;

{ ============= TRigWorker ============= }

constructor TRigWorker.Create(ALoader: IHamlibLoader; AModel: Integer;
                               const APort: string);
begin
  Assert(Assigned(ALoader), 'Loader required');
  Assert(ALoader.IsLoaded,  'Loader must be loaded');
  Assert(AModel > 0,        'Invalid model number');

  inherited Create(True);   { Suspended / サスペンド状態 }

  FreeOnTerminate := False;
  FLoader      := ALoader;
  FModel       := AModel;
  FPort        := APort;
  FQueue       := TCommandQueue.Create;
  FPolicyLock  := TCriticalSection.Create;
  FPolicy      := RigPolicy_Default;
  FResultWindow := TCommandResultWindow.Create(10);
  FAbortLock   := TCriticalSection.Create;
  FWatchdog    := TRigWatchdog.Create(@AbortStuckCall);
end;

destructor TRigWorker.Destroy;
var
  Drained: TList;
  i:       Integer;
begin
  { If RequestStop / WaitFor was not called, free any remaining queue.
    RequestStop / WaitFor が呼ばれていない場合、残ったキューを解放します。 }
  Drained := TList.Create;
  try
    FQueue.DrainAll(Drained);
    for i := 0 to Drained.Count - 1 do
      TRigCommand(Drained[i]).Free;
  finally
    Drained.Free;
  end;

  { The watchdog must be stopped before FRig/FLoader go away, otherwise
    an in-flight abort could touch a freed handle.
    FRig / FLoader が消える前に watchdog を止めます。さもないと実行中の
    中断処理が解放済みハンドルに触れ得ます。 }
  if Assigned(FWatchdog) then
  begin
    FWatchdog.Stop;

    { Only wait for a thread that was actually resumed. The watchdog
      is started inside Execute, so a Worker destroyed before its own
      thread ran has a watchdog still sitting in the RTL's start gate,
      and WaitFor on that never returns. The watchdog's destructor
      resumes and joins it correctly in that case.
      実際に再開されたスレッドだけを待ちます。watchdog は Execute の
      中で開始されるため、自身のスレッドが走る前に破棄された Worker の
      watchdog は RTL の開始ゲートに留まっており、それに対する WaitFor
      は決して戻りません。その場合は watchdog のデストラクタが正しく
      再開して join します。 }
    if FWatchdog.Started then
      FWatchdog.WaitFor;
    FreeAndNil(FWatchdog);
  end;

  FQueue.Free;
  FResultWindow.Free;
  FPolicyLock.Free;
  FAbortLock.Free;
  FreeAndNil(FConfTokens);
  FLoader := nil;
  inherited;
end;

procedure TRigWorker.Start;
begin
  FStarted := True;
  inherited Start;
end;

procedure TRigWorker.RequestStop;
begin
  Terminate;
  FQueue.WakeUp;   { Signal only — never put nil into the queue.
                     シグナルのみ。キューに nil を入れない。 }
end;

function TRigWorker.QueueDepth: Integer;
begin
  Result := FQueue.Count;
end;

function TRigWorker.CircuitBreakerOpen: Boolean;
begin
  Result := FCircuitOpen;
end;

procedure TRigWorker.PostCommand(ACmd: TRigCommand);
begin
  Assert(Assigned(ACmd), 'Cannot post nil command');
  FQueue.Enqueue(ACmd);
end;

{ ------------------------------------------------------------------
  The one place that knows how to report a command that will never run.

  Up to Rev.6.0 this type switch existed twice — in CancelAllQueued and
  in DrainQueueOnShutdown — and both knew only the three Get commands
  that existed when they were written. The four added in Rev.6.0
  (level, function, split, VFO) fell through to the generic branch,
  whose Callback field is nil for a typed command. So a cancelled
  GetLevelAsync never invoked the application's callback and never
  freed the dispatch object the Service had allocated for it: the
  application waited forever, and leaked.

  Duplication was the mechanism. A type switch that must be updated in
  two places when a command type is added will be updated in one.

  実行されることのないコマンドを報告する方法を知る、唯一の場所。

  Rev.6.0 まで、この型スイッチは CancelAllQueued と
  DrainQueueOnShutdown の 2 箇所に存在し、どちらも書かれた時点で存在
  した Get コマンド 3 種しか知りませんでした。Rev.6.0 で追加された 4 種
  (レベル、機能、スプリット、VFO) は汎用分岐に落ちますが、型付き
  コマンドではその Callback フィールドは nil です。そのため、キャンセル
  された GetLevelAsync はアプリケーションのコールバックを呼ばず、
  Service が確保した配送オブジェクトも解放しませんでした。アプリケー
  ションは永久に待ち、かつ漏れました。

  原因は重複です。コマンド型を追加するたび 2 箇所を更新しなければ
  ならない型スイッチは、1 箇所だけ更新されます。

  A virtual DeliverCancelled on TRigCommand would remove the switch
  altogether and is the better end state; collapsing two switches into
  one removes the mechanism that caused this defect, at a fraction of
  the risk, and the option is recorded here so it is not forgotten.

  TRigCommand に仮想メソッド DeliverCancelled を置けばスイッチ自体が
  消え、終着点としてはその方が優れています。2 つのスイッチを 1 つに
  畳むことは、はるかに小さな危険で本欠陥の仕組みを取り除きます。
  忘れないよう選択肢をここに記します。
  ------------------------------------------------------------------ }
procedure TRigWorker.DeliverCancelledAndFree(ACmd: TRigCommand;
                                              const AReason: string);
var
  R:  TRigResult;
  FR: TRigFreqResult;
  MR: TRigModeResult;
  PR: TRigPttResult;
  LR: TRigLevelResult;
  UR: TRigFuncResult;
  SR: TRigSplitResult;
  VR: TRigVfoResult;
  Api: Integer;
begin
  if not Assigned(ACmd) then
    Exit;

  { Signal the token, in case the application still holds a reference.
    アプリケーションがトークン参照を保持している場合に備えシグナル。 }
  if Assigned(ACmd.Token) then
    ACmd.Token.Cancel;

  Api := 4;
  if Assigned(FLoader) then
    Api := FLoader.ApiMajor;

  { Each command knows how to describe its own result, including which
    level, function or VFO it was about. Using Build*Result rather than
    filling the record here keeps that knowledge in one place, and a
    cancelled result then carries the same identity a successful one
    would.
    各コマンドは自身の結果の記述方法を知っており、どのレベル・機能・
    VFO に関するものかも含みます。ここでレコードを埋めるのではなく
    Build*Result を使うことで、その知識は 1 箇所に留まり、キャンセル
    された結果も成功時と同じ識別情報を運びます。 }
  if ACmd is TGetFreqCommand then
  begin
    TGetFreqCommand(ACmd).BuildFreqResult(FR, rcsCancelled, rekNone, 0,
                                          AReason);
    DeliverFreqAndFree(TGetFreqCommand(ACmd), FR);
  end
  else if ACmd is TGetModeCommand then
  begin
    TGetModeCommand(ACmd).BuildModeResult(MR, rcsCancelled, rekNone, 0,
                                          AReason);
    DeliverModeAndFree(TGetModeCommand(ACmd), MR);
  end
  else if ACmd is TGetPttCommand then
  begin
    TGetPttCommand(ACmd).BuildPttResult(PR, rcsCancelled);
    DeliverPttAndFree(TGetPttCommand(ACmd), PR);
  end
  else if ACmd is TGetLevelCommand then
  begin
    TGetLevelCommand(ACmd).BuildLevelResult(LR, rcsCancelled, rekNone, 0,
                                            AReason);
    DeliverLevelAndFree(TGetLevelCommand(ACmd), LR);
  end
  else if ACmd is TGetFuncCommand then
  begin
    TGetFuncCommand(ACmd).BuildFuncResult(UR, rcsCancelled, rekNone, 0,
                                          AReason);
    DeliverFuncAndFree(TGetFuncCommand(ACmd), UR);
  end
  else if ACmd is TGetSplitCommand then
  begin
    TGetSplitCommand(ACmd).BuildSplitResult(SR, rcsCancelled, rekNone, 0,
                                            AReason, Api);
    DeliverSplitAndFree(TGetSplitCommand(ACmd), SR);
  end
  else if ACmd is TGetVfoCommand then
  begin
    TGetVfoCommand(ACmd).BuildVfoResult(VR, rcsCancelled, rekNone, 0,
                                        AReason, Api);
    DeliverVfoAndFree(TGetVfoCommand(ACmd), VR);
  end
  else
  begin
    R.Status     := rcsCancelled;
    R.Error      := rekNone;
    R.NativeCode := 0;
    R.ErrorMsg   := AReason;
    DeliverAndFree(ACmd, R);
  end;
end;

procedure TRigWorker.CancelAllQueued;
var
  Drained: TList;
  i:       Integer;
begin
  Drained := TList.Create;
  try
    FQueue.DrainAll(Drained);
    for i := 0 to Drained.Count - 1 do
      DeliverCancelledAndFree(TRigCommand(Drained[i]), '');
  finally
    Drained.Free;
  end;
end;

procedure TRigWorker.ApplyPolicy(const APolicy: TRigTimeoutPolicy);
var
  RebuildWindow: Boolean;
begin
  FPolicyLock.Acquire;
  try
    RebuildWindow := APolicy.CbAdaptiveWindowSize <> FPolicy.CbAdaptiveWindowSize;
    FPolicy := APolicy;
    if RebuildWindow and (APolicy.CbAdaptiveWindowSize >= 3) then
    begin
      FResultWindow.Free;
      FResultWindow := TCommandResultWindow.Create(APolicy.CbAdaptiveWindowSize);
    end;
  finally
    FPolicyLock.Release;
  end;
end;

procedure TRigWorker.Execute;
var
  Cmd: TRigCommand;
begin
  FWatchdog.Start;   { tier-2 supervisor / 第 2 段の監視を開始 }

  try
    ConnectInternal;
  except
    { The order of these three notifications is deliberate, because they
      arrive on the UI thread in the order they are queued and an
      application typically shows the last one.

      1. the attempt is over and we are not connected, so the UI can
         leave its "Connecting..." state — without this the window has
         no way to find out that the attempt failed, since
         OnConnectionChanged otherwise only fires on a successful
         connect or on losing an established link;
      2. then WHY it failed, which is what the operator needs to read;
      3. the breaker is tripped quietly, because announcing "too many
         failures, pausing" right after a specific cause would replace
         the useful message with a vague one.

      以下 3 つの通知の順序は意図的です。UI スレッドにはキューした順で
      届き、アプリケーションは通常最後のものを表示するためです。

      1. 試行が終わり未接続であること。UI が「接続中...」状態を抜けられ
         ます。これが無いとウィンドウは試行の失敗を知る手段がありません。
         OnConnectionChanged は本来、接続成功時と確立済みリンクの喪失時
         にしか発火しないからです。
      2. 次に失敗の理由。オペレータが読む必要があるのはこれです。
      3. ブレーカは静かに開きます。具体的な原因の直後に「失敗が続いた
         ため休止」と告知すると、有用なメッセージが曖昧なものに置き換わ
         ってしまいます。 }
    on E: ERigError do
    begin
      { Keep the Hamlib classification. Reporting every connect failure
        as rekConnectFailed told the application only that something
        went wrong during Open, so "the port is in use" and "the cable
        is unplugged" were indistinguishable — the application could
        not give the operator the one piece of advice that would help.

        Hamlib の分類を保持します。接続失敗をすべて rekConnectFailed と
        して報告すると、アプリケーションには「Open 中に何か起きた」しか
        伝わらず、「ポートが使用中」と「ケーブルが抜けている」が区別
        できません。役に立つ唯一の助言をオペレータに出せなくなります。 }
      NotifyConnectionChanged(False);
      NotifyError(E.Kind, E.Code, 'Connect failed: ' + E.Message);
      TripCircuitBreaker(False);
    end;
    on E: Exception do
    begin
      { Not a Hamlib return code — rig_init returned nil, or something
        inside this component failed. There is no classification to
        preserve, so the generic kind is the honest one.
        Hamlib の戻り値ではありません。rig_init が nil を返した、または
        本コンポーネント内部の失敗です。保持すべき分類が無いため、
        汎用の種別が正直な答えです。 }
      NotifyConnectionChanged(False);
      NotifyError(rekConnectFailed, 0, 'Connect failed: ' + E.Message);
      TripCircuitBreaker(False);
    end;
  end;

  while not Terminated do
  begin
    Cmd := FQueue.Dequeue(WORKER_TICK_MS);
    if Cmd <> nil then
      ProcessCommand(Cmd);
    CheckCircuitBreaker;
  end;

  { Shutdown: stop the supervisor first so it cannot abort a handle we
    are about to close ourselves, then drain and disconnect.
    シャットダウン: まず監視を止め、これから自分で閉じるハンドルを
    中断処理が触らないようにしてから、ドレインと切断を行います。 }
  FWatchdog.Stop;
  FWatchdog.WaitFor;

  DrainQueueOnShutdown;
  DisconnectInternal;
end;

function TRigWorker.CommandBudgetMs: Cardinal;
begin
  FPolicyLock.Acquire;
  try
    Result := FPolicy.CommandTimeoutMs;
  finally
    FPolicyLock.Release;
  end;
  if Result < 200 then Result := 200;
end;

procedure TRigWorker.SetConfTokens(AList: TStringList);
begin
  if not Assigned(FConfTokens) then
    FConfTokens := TStringList.Create;
  FConfTokens.Clear;
  if Assigned(AList) then
    FConfTokens.Assign(AList);
end;

procedure TRigWorker.ApplyConfTokens;
var
  i:    Integer;
  Name: string;
begin
  if (FRig = nil) or (not Assigned(FConfTokens)) then Exit;

  for i := 0 to FConfTokens.Count - 1 do
  begin
    Name := FConfTokens.Names[i];
    if Name = '' then Continue;

    { A token the running Hamlib does not know returns an error, and
      that is worth saying out loud rather than swallowing: a
      misspelled ptt_type is the difference between a rig that keys and
      one that does not, and it would otherwise fail in silence.

      実行中の Hamlib が知らないトークンはエラーを返します。これは飲み
      込まずに伝える価値があります。ptt_type の綴り誤りは「送信できる
      リグ」と「できないリグ」の差であり、黙っていれば静かに失敗します。 }
    if FLoader.SetConf(FRig, Name, FConfTokens.ValueFromIndex[i]) < 0 then
      NotifyError(rekConfiguration, 0,
        Format('Hamlib rejected the configuration "%s=%s"',
               [Name, FConfTokens.ValueFromIndex[i]]));
  end;
end;

procedure TRigWorker.ApplyHamlibTimeouts;
var
  Budget:  Cardinal;
  Retries: Integer;
  PerRead: Cardinal;
begin
  if FRig = nil then Exit;

  Budget := CommandBudgetMs;

  { Worst-case blocking inside one Hamlib call is about
    per-read timeout * (retry + 1). Pick one retry so a single dropped
    byte still recovers, and give each read half the budget.

    1 回の Hamlib 呼び出しでの最悪ブロック時間はおおよそ
    「読み取りタイムアウト × (retry + 1)」です。1 バイト落ちても回復できる
    よう retry は 1 とし、各読み取りに予算の半分を与えます。 }
  Retries := 1;
  PerRead := Budget div (Cardinal(Retries) + 1);
  if PerRead < 100 then PerRead := 100;

  FLoader.SetConf(FRig, 'timeout', IntToStr(PerRead));
  FLoader.SetConf(FRig, 'retry',   IntToStr(Retries));
end;

procedure TRigWorker.AbortStuckCall;
var
  RigCopy: Pointer;
begin
  { Runs on the watchdog thread. Closing the handle makes the blocked
    read in the Worker fail so the Worker can unwind. FConnected is
    cleared first so ProcessCommand rejects anything that arrives in the
    meantime instead of touching a closing handle.

    watchdog スレッドで実行されます。ハンドルを閉じることで Worker 側の
    ブロック中の読み取りを失敗させ、Worker を巻き戻せるようにします。
    先に FConnected を落とし、その間に届くコマンドが閉じかけのハンドルに
    触れず拒否されるようにします。 }
  FAbortLock.Acquire;
  try
    RigCopy := FRig;
    if RigCopy = nil then Exit;
    FConnected := False;
    try
      FLoader.CallRigClose(RigCopy);
    except
      { Best effort — the point is to unblock, not to close cleanly.
        ベストエフォート。目的は綺麗に閉じることではなくブロック解除です。 }
    end;
  finally
    FAbortLock.Release;
  end;

  NotifyError(rekTimeout, -RIG_ETIMEOUT_CODE,
    'Command timed out; connection aborted and will be re-established');
end;

procedure TRigWorker.ConnectInternal;
var
  RetCode: Integer;
begin
  if FConnected then Exit;

  FRig := FLoader.CallRigInit(FModel);
  if FRig = nil then
    raise Exception.Create('rig_init failed for model ' + IntToStr(FModel));

  if FPort <> '' then
    FLoader.SetSerialPort(FRig, FPort);

  { The application's conf tokens are applied here, BEFORE
    ApplyHamlibTimeouts. That order is deliberate: the component's own
    timeout and retry settings are what make CommandTimeoutMs mean
    anything, so they win over an application that names those same two
    tokens. Everything else — ptt_type, rts_state, data_bits — the
    component has no opinion about and passes through untouched.

    アプリケーションの設定トークンはここで、ApplyHamlibTimeouts より
    「前」に適用します。この順序は意図的です。CommandTimeoutMs を意味
    あるものにしているのはコンポーネント自身の timeout / retry 設定なので、
    同じ 2 つを指定したアプリケーションより優先します。それ以外
    (ptt_type、rts_state、data_bits 等) にコンポーネントは見解を持たず、
    そのまま通します。 }
  ApplyConfTokens;

  { ---- Timeout tier 1: bound Hamlib's own serial I/O ----
    Hamlib's "timeout" conf is the read timeout in ms and "retry" is how
    many times it repeats a failed exchange. Worst-case blocking inside
    one Hamlib call is roughly timeout * (retry + 1), so the per-read
    budget is derived from CommandTimeoutMs rather than set to it.

    Without this, Hamlib uses the backend default (often 1000 ms with
    retries) and our CommandTimeoutMs would describe nothing.

    ---- タイムアウト第 1 段: Hamlib 自身のシリアル I/O を縛る ----
    Hamlib の "timeout" conf は読み取りタイムアウト [ms]、"retry" は失敗した
    やり取りの再試行回数です。1 回の Hamlib 呼び出しでの最悪ブロック時間は
    おおよそ timeout × (retry + 1) になるため、1 回あたりの予算は
    CommandTimeoutMs そのものではなくそこから逆算します。

    これを設定しないと Hamlib はバックエンド既定値 (多くは 1000ms + 再試行)
    を使い、CommandTimeoutMs は何も意味しなくなります。 }
  ApplyHamlibTimeouts;

  RetCode := FLoader.CallRigOpen(FRig);
  if RetCode < 0 then
  begin
    FLoader.CallRigCleanup(FRig);
    FRig := nil;
    raise ERigError.CreateFromHamlib(RetCode, FLoader);
  end;

  FConnected := True;
  NotifyConnectionChanged(True);
end;

procedure TRigWorker.DisconnectInternal;
begin
  { Serialise with AbortStuckCall so the watchdog and this path never
    close the same handle concurrently.
    AbortStuckCall と直列化し、watchdog と本経路が同じハンドルを同時に
    閉じないようにします。 }
  FAbortLock.Acquire;
  try
  if FRig = nil then Exit;
  try
    if FConnected then
      FLoader.CallRigClose(FRig);
    FLoader.CallRigCleanup(FRig);
  except
    { Best effort during shutdown.
      シャットダウン中はベストエフォート。 }
  end;
  FRig       := nil;
  if FConnected then
  begin
    FConnected := False;
    NotifyConnectionChanged(False);
  end;
  finally
    FAbortLock.Release;
  end;
end;

procedure TRigWorker.ProcessCommand(ACmd: TRigCommand);
var
  R:           TRigResult;
  FreqResult:  TRigFreqResult;
  ModeResult:  TRigModeResult;
  PttResult:   TRigPttResult;
  LevelResult: TRigLevelResult;
  FuncResult:  TRigFuncResult;
  SplitResult: TRigSplitResult;
  VfoResult:   TRigVfoResult;
  Status:      TRigCommandStatus;
  ErrCode:     Integer;
  ErrMsg:      string;
  TimedOut:    Boolean;
begin
  Assert(Assigned(ACmd), 'ACmd must not be nil');

  R.Error      := rekNone;
  R.NativeCode := 0;
  R.ErrorMsg   := '';

  { Pre-execution checks. 実行前チェック。 }
  if ACmd.IsCancelRequested then
  begin
    R.Status := rcsCancelled;
    Status   := rcsCancelled;
    ErrCode  := 0;
    ErrMsg   := '';
  end
  else if (FRig = nil) or (not FConnected) then
  begin
    { Checked BEFORE the circuit breaker, deliberately. A failed
      initial connection trips the breaker, so with the breaker first
      every command afterwards was rejected as "paused after repeated
      failures" — true of the breaker, but useless to an operator whose
      rig was never connected in the first place. "Not connected" is the
      actionable answer, and it is also the more specific one.

      意図的に Circuit Breaker より先に検査します。初回接続の失敗は
      ブレーカを開くため、ブレーカを先に見ると以降の全コマンドが
      「失敗が続いたため休止」として拒否されていました。ブレーカの
      事実としては正しいものの、そもそも一度も接続できていない
      オペレータには役に立ちません。「未接続」が行動につながる答えで
      あり、より具体的でもあります。

      Connection never succeeded, or was torn down. Passing a nil PRIG
      to Hamlib dereferences rig->state inside the C library and
      segfaults the whole process, so refuse the command instead.
      This happens routinely: rig powered off, port held by another
      application, cable unplugged.

      接続が成立しなかった、または切断された状態です。nil の PRIG を
      Hamlib に渡すと C ライブラリ内部で rig->state を参照してプロセス
      全体がセグフォルトするため、コマンドを拒否します。これはリグの電源
      オフ、他アプリによるポート占有、ケーブル抜けなど日常的に起きます。 }
    R.Status   := rcsRejected;
    R.Error    := rekNotConnected;
    R.ErrorMsg := 'Rig is not connected';
    Status     := rcsRejected;
    ErrCode    := 0;
    ErrMsg     := R.ErrorMsg;
  end
  else if FCircuitOpen then
  begin
    R.Status   := rcsRejected;
    R.Error    := rekCircuitOpen;
    R.ErrorMsg := 'Circuit breaker is open';
    Status     := rcsRejected;
    ErrCode    := 0;
    ErrMsg     := R.ErrorMsg;
  end
  else
  begin
    { Execute the command under the tier-2 watchdog. Arm before entering
      Hamlib, disarm after; if Disarm reports the watchdog fired, the
      call overran and its outcome is reported as rcsTimeout whatever
      Hamlib eventually returned.

      第 2 段 watchdog の監視下で実行します。Hamlib に入る前に Arm し、
      出たら Disarm します。Disarm が発火を報告した場合、その呼び出しは
      期限超過なので、Hamlib の最終的な戻り値に関わらず rcsTimeout として
      報告します。 }
    FWatchdog.Arm(CommandBudgetMs);
    try
      ACmd.Execute(FLoader, FRig);
      TimedOut := FWatchdog.Disarm;
      if TimedOut then
      begin
        R.Status     := rcsTimeout;
        R.Error      := rekTimeout;
        R.NativeCode := -RIG_ETIMEOUT_CODE;
        R.ErrorMsg   := 'Command exceeded its time budget';
        Status       := rcsTimeout;
        ErrCode      := -RIG_ETIMEOUT_CODE;
        ErrMsg     := R.ErrorMsg;
        RecordCommandResult(False);
      end
      else
      begin
        R.Status := rcsSuccess;
        Status   := rcsSuccess;
        ErrCode  := 0;
        ErrMsg   := '';
        RecordCommandResult(True);
      end;
    except
      on E: ERigError do
      begin
        TimedOut := FWatchdog.Disarm;
        { Report rcsTimeout when either tier detected it: our watchdog
          fired, or Hamlib itself returned -RIG_ETIMEOUT from tier 1.
          どちらの段で検出しても rcsTimeout を報告します。watchdog が
          発火した場合と、第 1 段で Hamlib 自身が -RIG_ETIMEOUT を
          返した場合の両方です。 }
        if TimedOut or (E.Code = -RIG_ETIMEOUT_CODE) then
          R.Status := rcsTimeout
        else
          R.Status := rcsError;
        R.Error      := E.Kind;
        R.NativeCode := E.Code;
        R.ErrorMsg   := E.Message;
        Status       := R.Status;
        ErrCode      := E.Code;
        ErrMsg       := E.Message;
        RecordCommandResult(False);
      end;
      on E: Exception do
      begin
        TimedOut := FWatchdog.Disarm;
        if TimedOut then
        begin
          R.Status := rcsTimeout;
          R.Error  := rekTimeout;
        end
        else
        begin
          R.Status := rcsError;
          R.Error  := rekComponentFault;
        end;
        R.ErrorMsg := E.Message;
        Status     := R.Status;
        ErrCode    := 0;
        ErrMsg     := E.Message;
        RecordCommandResult(False);
      end;
    end;
  end;

  { Deliver based on the command's specific type.
    コマンドの具体的型に応じて配送。 }
  if ACmd is TGetFreqCommand then
  begin
    TGetFreqCommand(ACmd).BuildFreqResult(FreqResult, Status, R.Error,
                                          ErrCode, ErrMsg);
    DeliverFreqAndFree(TGetFreqCommand(ACmd), FreqResult);
  end
  else if ACmd is TGetModeCommand then
  begin
    TGetModeCommand(ACmd).BuildModeResult(ModeResult, Status, R.Error,
                                          ErrCode, ErrMsg);
    DeliverModeAndFree(TGetModeCommand(ACmd), ModeResult);
  end
  else if ACmd is TGetPttCommand then
  begin
    TGetPttCommand(ACmd).BuildPttResult(PttResult, Status);
    DeliverPttAndFree(TGetPttCommand(ACmd), PttResult);
  end
  else if ACmd is TGetLevelCommand then
  begin
    TGetLevelCommand(ACmd).BuildLevelResult(LevelResult, Status, R.Error,
                                            ErrCode, ErrMsg);
    DeliverLevelAndFree(TGetLevelCommand(ACmd), LevelResult);
  end
  else if ACmd is TGetFuncCommand then
  begin
    TGetFuncCommand(ACmd).BuildFuncResult(FuncResult, Status, R.Error,
                                          ErrCode, ErrMsg);
    DeliverFuncAndFree(TGetFuncCommand(ACmd), FuncResult);
  end
  else if ACmd is TGetSplitCommand then
  begin
    TGetSplitCommand(ACmd).BuildSplitResult(SplitResult, Status, R.Error,
                                            ErrCode, ErrMsg, FLoader.ApiMajor);
    DeliverSplitAndFree(TGetSplitCommand(ACmd), SplitResult);
  end
  else if ACmd is TGetVfoCommand then
  begin
    TGetVfoCommand(ACmd).BuildVfoResult(VfoResult, Status, R.Error,
                                        ErrCode, ErrMsg, FLoader.ApiMajor);
    DeliverVfoAndFree(TGetVfoCommand(ACmd), VfoResult);
  end
  else
    DeliverAndFree(ACmd, R);
end;

procedure TRigWorker.DeliverAndFree(ACmd: TRigCommand; const AResult: TRigResult);
var
  Disp: TWWGenericDeliveryDispatch;
begin
  Assert(Assigned(ACmd), 'Cannot deliver from nil command');

  { Critical: build dispatch object with copies of the result and the
    callback BEFORE freeing the command. The dispatch object owns the
    callback invocation and self-destructs after running on the UI thread.

    重要: コマンド解放の前に、結果とコールバックをコピーした配送オブジェクトを
    構築。配送オブジェクトはコールバック呼び出しを所有し、UI スレッドで実行後
    自身を破棄します。 }
  Disp := TWWGenericDeliveryDispatch.Create(ACmd.Callback, AResult);

  FreeAndNil(ACmd);   { After this, ACmd MUST NOT be touched.
                       これ以降 ACmd に絶対に触れてはならない。 }

  if Assigned(Disp.Callback) then
    TThread.Queue(nil, @Disp.RunOnUIThread)
  else
    Disp.Free;
end;

procedure TRigWorker.DeliverFreqAndFree(ACmd: TGetFreqCommand;
                                         const AResult: TRigFreqResult);
var
  Disp: TWWFreqDeliveryDispatch;
begin
  Disp := TWWFreqDeliveryDispatch.Create(ACmd.FreqCallback, AResult);
  FreeAndNil(ACmd);

  if Assigned(Disp.Callback) then
    TThread.Queue(nil, @Disp.RunOnUIThread)
  else
    Disp.Free;
end;

procedure TRigWorker.DeliverModeAndFree(ACmd: TGetModeCommand;
                                         const AResult: TRigModeResult);
var
  Disp: TWWModeDeliveryDispatch;
begin
  Disp := TWWModeDeliveryDispatch.Create(ACmd.ModeCallback, AResult);
  FreeAndNil(ACmd);

  if Assigned(Disp.Callback) then
    TThread.Queue(nil, @Disp.RunOnUIThread)
  else
    Disp.Free;
end;

procedure TRigWorker.DeliverLevelAndFree(ACmd: TGetLevelCommand;
                                          const AResult: TRigLevelResult);
var
  Disp: TWWLevelDeliveryDispatch;
begin
  Disp := TWWLevelDeliveryDispatch.Create(ACmd.LevelCallback, AResult);
  FreeAndNil(ACmd);
  if Assigned(Disp.Callback) then
    TThread.Queue(nil, @Disp.RunOnUIThread)
  else
    Disp.Free;
end;

procedure TRigWorker.DeliverFuncAndFree(ACmd: TGetFuncCommand;
                                         const AResult: TRigFuncResult);
var
  Disp: TWWFuncDeliveryDispatch;
begin
  Disp := TWWFuncDeliveryDispatch.Create(ACmd.FuncCallback, AResult);
  FreeAndNil(ACmd);
  if Assigned(Disp.Callback) then
    TThread.Queue(nil, @Disp.RunOnUIThread)
  else
    Disp.Free;
end;

procedure TRigWorker.DeliverSplitAndFree(ACmd: TGetSplitCommand;
                                          const AResult: TRigSplitResult);
var
  Disp: TWWSplitDeliveryDispatch;
begin
  Disp := TWWSplitDeliveryDispatch.Create(ACmd.SplitCallback, AResult);
  FreeAndNil(ACmd);
  if Assigned(Disp.Callback) then
    TThread.Queue(nil, @Disp.RunOnUIThread)
  else
    Disp.Free;
end;

procedure TRigWorker.DeliverVfoAndFree(ACmd: TGetVfoCommand;
                                        const AResult: TRigVfoResult);
var
  Disp: TWWVfoDeliveryDispatch;
begin
  Disp := TWWVfoDeliveryDispatch.Create(ACmd.VfoCallback, AResult);
  FreeAndNil(ACmd);
  if Assigned(Disp.Callback) then
    TThread.Queue(nil, @Disp.RunOnUIThread)
  else
    Disp.Free;
end;

procedure TRigWorker.DeliverPttAndFree(ACmd: TGetPttCommand;
                                        const AResult: TRigPttResult);
var
  Disp: TWWPttDeliveryDispatch;
begin
  Disp := TWWPttDeliveryDispatch.Create(ACmd.PttCallback, AResult);
  FreeAndNil(ACmd);

  if Assigned(Disp.Callback) then
    TThread.Queue(nil, @Disp.RunOnUIThread)
  else
    Disp.Free;
end;

procedure TRigWorker.RecordCommandResult(ASuccess: Boolean);
var
  Strategy:  TCircuitBreakerStrategy;
  Threshold: Integer;
  Rate:      Double;
begin
  FPolicyLock.Acquire;
  try
    Strategy  := FPolicy.CbStrategy;
    Threshold := FPolicy.CbFixedThreshold;
    Rate      := FPolicy.CbAdaptiveFailureRate;
  finally
    FPolicyLock.Release;
  end;

  case Strategy of
    cbsFixed:
      begin
        if ASuccess then
          FConsecErrors := 0
        else
        begin
          Inc(FConsecErrors);
          if FConsecErrors >= Threshold then
            TripCircuitBreaker;
        end;
      end;

    cbsAdaptive:
      begin
        FResultWindow.RecordResult(ASuccess);
        if FResultWindow.IsFilled
           and (FResultWindow.FailureRate >= Rate) then
          TripCircuitBreaker;
      end;
  end;
end;

procedure TRigWorker.TripCircuitBreaker(AAnnounce: Boolean);
begin
  if FCircuitOpen then Exit;
  FCircuitOpen   := True;
  FCircuitOpenAt := GetTickCount64;
  if AAnnounce then
    NotifyError(rekCircuitOpen, 0, 'Circuit breaker tripped');
end;

procedure TRigWorker.CheckCircuitBreaker;
var
  RecoveryMs: Cardinal;
begin
  if not FCircuitOpen then Exit;

  FPolicyLock.Acquire;
  try
    RecoveryMs := FPolicy.CbRecoveryMs;
  finally
    FPolicyLock.Release;
  end;

  if (GetTickCount64 - FCircuitOpenAt) < RecoveryMs then Exit;

  { Try to recover by reconnecting.
    再接続で回復を試みます。 }
  DisconnectInternal;
  Sleep(500);
  try
    ConnectInternal;
    FCircuitOpen   := False;
    FConsecErrors  := 0;
    FResultWindow.Reset;
    { Informational, not a failure: the error channel is the only
      notification path the component has, so recovery arrives with
      rekNone. An application can show it or ignore it by kind.
      失敗ではなく通知です。コンポーネントの通知経路はエラーチャネル
      しかないため、回復は rekNone で届きます。アプリは種別で表示/無視
      を選べます。 }
    NotifyError(rekNone, 0, 'Circuit breaker recovered');
  except
    { Recovery failed; wait another period.
      回復失敗; もう一周期待つ。 }
    FCircuitOpenAt := GetTickCount64;
  end;
end;

procedure TRigWorker.DrainQueueOnShutdown;
var
  Drained: TList;
  i:       Integer;
begin
  Drained := TList.Create;
  try
    FQueue.DrainAll(Drained);
    for i := 0 to Drained.Count - 1 do
      DeliverCancelledAndFree(TRigCommand(Drained[i]),
                              'Worker shutting down');
  finally
    Drained.Free;
  end;
end;

function TRigWorker.GetOnErrorSnapshot: TRigErrorEvent;
begin
  Result := FOnError;
end;

{ Both notifiers hand a self-freeing dispatch object to TThread.Queue.
  The object owns the handler snapshot and the payload by value, so the
  UI thread can run it safely even after the Worker has exited.

  どちらの通知も自己解放する配送オブジェクトを TThread.Queue に渡します。
  オブジェクトはハンドラのスナップショットとペイロードを値で所有するため、
  Worker 終了後でも UI スレッドが安全に実行できます。 }

{ The local variable is required: @TClass.Create(...).Method binds the
  address against a temporary and yields a method pointer with a bogus
  Self. Keep the two-step form.

  ローカル変数は必須です。@TClass.Create(...).Method は一時オブジェクトに
  対してアドレスを解決し、不正な Self を持つメソッドポインタになります。
  2 段階の形を維持すること。 }

{ Note 5027 is a false positive: @Sink.Method is not counted as a read.
  Note 5027 は誤検知です。@Sink.Method は読み出しとみなされません。 }
{$PUSH}
{$WARN 5027 OFF}

procedure TRigWorker.NotifyConnectionChanged(AConnected: Boolean);
var
  Sink: TWWConnectionDispatch;
begin
  if not Assigned(FOnConnectionChanged) then Exit;
  Sink := TWWConnectionDispatch.Create(FOnConnectionChanged, AConnected);
  TThread.Queue(nil, @Sink.RunOnUIThread);
end;

procedure TRigWorker.NotifyError(AKind: TRigErrorKind; ANativeCode: Integer;
                                 const AMsg: string);
var
  Sink: TWWErrorDispatch;
begin
  if not Assigned(FOnError) then Exit;
  Sink := TWWErrorDispatch.Create(FOnError, AKind, ANativeCode, AMsg);
  TThread.Queue(nil, @Sink.RunOnUIThread);
end;

{$POP}

end.
