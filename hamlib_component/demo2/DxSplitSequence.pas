{
  DxSplitSequence.pas

  TDxSplitSequence — sets a rig up for split DX operation as one
  cancellable, rollback-capable sequence of asynchronous commands.

  TDxSplitSequence - リグをスプリット DX 運用の状態にします。中断可能で
  ロールバック可能な、非同期コマンドの 1 つのシーケンスとして。

  Why this unit exists / 本ユニットの存在理由
  ------------------------------------------------------------------
  RigPanel (the first sample) only ever issues *independent* commands:
  set a frequency, read a mode, key the PTT. Each one succeeds or fails
  on its own and nothing is left half-done.

  Split operation is not like that. Working a DX station means putting
  the rig into a state built from four commands:

      1. select VFO A                (listen here)
      2. set VFO A's frequency       (the DX station's transmit QRG)
      3. enable split with VFO B as the transmit VFO
      4. set the split transmit frequency (where we call)

  and then reading the result back to confirm it (5). The steps are
  ordered — step 4 is meaningless before step 3 — and any of them can
  fail. A failure after step 3 is the dangerous case: the rig is left in
  split with a transmit frequency that was never set, so the next time
  the operator keys up they transmit somewhere they did not choose. The
  sequence therefore disables split again when it fails after having
  enabled it.

  That is the whole reason this is a separate unit rather than four
  calls in a button handler: "what must be undone, and when" is a
  decision that deserves one named place.

  RigPanel (最初のサンプル) が発行するのは常に「独立した」コマンドです。
  周波数を設定する、モードを読む、PTT を押す。各々が単独で成否を決め、
  中途半端に残るものはありません。

  スプリット運用はそうではありません。DX 局と交信するには、4 つの
  コマンドから組み立てた状態にリグを置く必要があります (上記 1〜4)。
  そして結果を読み戻して確認します (5)。手順には順序があり (手順 3 の
  前に手順 4 は無意味)、どれも失敗しえます。危険なのは手順 3 の後に
  失敗した場合です。リグはスプリットのまま、送信周波数は未設定で残り、
  次にオペレータが送信したとき、自分が選んでいない周波数で電波を出す
  ことになります。そのため本シーケンスは、スプリットを有効にした後に
  失敗した場合、スプリットを無効に戻します。

  これがボタンハンドラ内の 4 回の呼び出しではなく独立ユニットである
  理由のすべてです。「何を、いつ、取り消すべきか」は、名前の付いた
  1 箇所に置くに値する判断です。

  Why a state machine and not nested callbacks
  なぜ入れ子のコールバックではなく状態機械か
  ------------------------------------------------------------------
  FPC 3.2.2 has no anonymous methods, so a nested-callback chain would
  be five named methods each of which calls the next — the order of the
  sequence would then exist only as a path through the code, which is
  exactly the shape that makes "did we remember to undo step 3?"
  unanswerable by reading. Here Advance() is the only place the order
  lives, every step handler is a guard plus a result check, and a
  single field (FSplitEnabled) records the one thing that needs undoing.

  FPC 3.2.2 に匿名メソッドはないため、入れ子のコールバック連鎖は「次を
  呼ぶ名前付きメソッド 5 つ」になります。すると順序はコード中の経路と
  してしか存在せず、「手順 3 を取り消し忘れていないか」が読んでは答え
  られない形になります。本ユニットでは順序が存在するのは Advance() だけ、
  各ステップハンドラはガードと結果判定のみ、取り消す必要がある唯一の
  事実はフィールド 1 つ (FSplitEnabled) が記録します。

  Stale callbacks / 遅れて届くコールバック
  ------------------------------------------------------------------
  A command already in the worker's queue cannot be un-issued. Abort
  cancels the token, but the component may still deliver the result —
  cancelled commands report rcsCancelled, and a command that completed
  just before the cancel reports success. Every handler therefore
  begins by checking that the sequence is still in the step that
  handler belongs to. Without that guard an aborted sequence quietly
  resumes, which is the kind of defect that only shows up when the
  operator aborts at exactly the wrong moment.

  ワーカーのキューに入ったコマンドは取り消せません。Abort はトークンを
  キャンセルしますが、コンポーネントは結果を届けることがあります。
  キャンセルされたコマンドは rcsCancelled を報告し、キャンセル直前に
  完了したコマンドは成功を報告します。したがって各ハンドラは、自分が
  属するステップにシーケンスがまだ居ることを最初に確認します。この
  ガードがないと、中断したシーケンスが黙って再開します。オペレータが
  まさに最悪の瞬間に中断したときにだけ現れる種類の欠陥です。

  Threading / スレッド
  ------------------------------------------------------------------
  Every method here runs on the UI thread. The component delivers
  callbacks via TThread.Queue, so there is no lock in this unit and
  none is needed.

  本ユニットの全メソッドは UI スレッドで動きます。コンポーネントは
  TThread.Queue でコールバックを配送するため、本ユニットにロックは
  なく、必要もありません。

  Layer:    demo2 (application)
  Depends:  HamlibInterfaces, HamlibErrors
}
unit DxSplitSequence;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  HamlibInterfaces, HamlibErrors;

type
  { The steps, in order. dxsRollback is not a step of the happy path:
    it is entered only from a failure that has something to undo.

    手順。順序どおりです。dxsRollback は正常系の手順ではなく、取り消す
    べきものがある失敗からのみ入ります。 }
  TDxSequenceStep = (
    dxsIdle,
    dxsSelectRxVfo,   { rig_set_vfo(VFO_A)        }
    dxsSetRxFreq,     { rig_set_freq(VFO_A, rx)   }
    dxsEnableSplit,   { rig_set_split_vfo(1, B)   }
    dxsSetTxFreq,     { rig_set_split_freq(tx)    }
    dxsVerify,        { rig_get_split_vfo + freq  }
    dxsRollback,      { rig_set_split_vfo(0)      }
    dxsDone,
    dxsFailed
  );

  TDxProgressEvent = procedure(AStep: TDxSequenceStep;
                               AIndex, ACount: Integer;
                               const ACaption: string) of object;

  { ASucceeded is False for both failure and abort; AMessage says
    which, and whether the rollback ran.
    ASucceeded は失敗でも中断でも False です。どちらであったか、そして
    ロールバックが走ったかは AMessage が述べます。 }
  TDxFinishedEvent = procedure(ASucceeded: Boolean;
                               AFailedStep: TDxSequenceStep;
                               const AMessage: string) of object;

  TDxSplitSequence = class
  private
    FService:   IRigService;
    FStep:      TDxSequenceStep;
    FRxHz:      Double;
    FTxHz:      Double;

    { True once step 3 has succeeded: the one piece of rig state this
      sequence creates that must be undone on failure.
      手順 3 が成功した時点で True。本シーケンスが作り出すリグ状態の
      うち、失敗時に取り消さなければならない唯一のものです。 }
    FSplitEnabled: Boolean;

    { The command in flight, kept so Abort can cancel it. Released by
      refcount when the next step replaces it.
      実行中のコマンド。Abort がキャンセルできるよう保持します。次の
      ステップが置き換えるとき参照カウントで解放されます。 }
    FToken:     ICancellationToken;

    FOnProgress: TDxProgressEvent;
    FOnFinished: TDxFinishedEvent;

    { What the verify step read back, so the caller can be told what
      the rig actually reports rather than what was requested.
      検証ステップが読み戻した内容。要求値ではなくリグが実際に報告した
      内容を呼び出し側に伝えるためです。 }
    FVerifiedSplit: Boolean;
    FVerifiedTxHz:  Double;

    { Set when a failure happens while split is on, because the message
      must be held until the rollback has reported. Without this the
      operator would be told "it failed" and only afterwards whether
      the rig was left able to transmit on the wrong frequency.

      スプリットが入っている状態で失敗したとき設定します。メッセージは
      ロールバックが報告するまで保持しなければならないからです。これが
      ないと、オペレータはまず「失敗した」と告げられ、リグが誤った
      周波数で送信しうる状態に残されたかどうかは後から知ることに
      なります。 }
    FPendingReason: string;
    FFailedStep:    TDxSequenceStep;

    function  GetActive: Boolean;
    procedure Advance(AStep: TDxSequenceStep);
    procedure Fail(const AReason: string);
    procedure Finish(ASucceeded: Boolean; const AMessage: string);
    procedure Report;

    { Shared tail of every step handler: returns True when the result
      says "carry on". On anything else it fails the sequence with a
      sentence naming the step, so the operator is told where it broke
      and not merely that it broke.

      全ステップハンドラの共通末尾。結果が「続行してよい」と言っている
      ときだけ True を返します。それ以外ではステップ名を含む 1 文で
      シーケンスを失敗させます。オペレータには、単に壊れたことではなく
      どこで壊れたかが伝わります。 }
    function  Accept(const AResult: TRigResult;
                     const AWhat: string): Boolean;

    procedure HandleRxVfoSet(const AResult: TRigResult);
    procedure HandleRxFreqSet(const AResult: TRigResult);
    procedure HandleSplitEnabled(const AResult: TRigResult);
    procedure HandleTxFreqSet(const AResult: TRigResult);
    procedure HandleVerified(const AResult: TRigSplitResult);
    procedure HandleRolledBack(const AResult: TRigResult);
  public
    { AService must be open. The sequence does not own it and does not
      close it.
      AService は開いていなければなりません。シーケンスはこれを所有も
      クローズもしません。 }
    constructor Create(const AService: IRigService);
    destructor  Destroy; override;

    { Begins the sequence. Returns False — without touching the rig —
      when the arguments or the current state make it pointless: a
      running sequence, a closed service, or frequencies that are not
      positive. Reporting this as a return value rather than an
      exception keeps a mis-click from unwinding the UI thread.

      シーケンスを開始します。引数や現在状態から無意味な場合は、リグに
      触れずに False を返します (実行中、サービス未接続、周波数が正で
      ない)。例外ではなく戻り値で報告することで、誤クリックが UI
      スレッドを巻き戻さないようにします。 }
    function  Start(ARxHz, ATxHz: Double): Boolean;

    { Cancels the command in flight and undoes split if it was already
      enabled. Safe to call when nothing is running.
      実行中のコマンドをキャンセルし、スプリットが既に有効なら戻します。
      何も動いていないときに呼んでも安全です。 }
    procedure Abort;

    { Human-readable name of a step, for the progress display.
      進行表示用のステップ名。 }
    class function StepCaption(AStep: TDxSequenceStep): string;

    { How many steps the happy path has, for "3 / 5".
      「3 / 5」表示のための正常系ステップ数。 }
    class function StepCount: Integer;

    { 1-based index of a step on the happy path; 0 for the others.
      正常系におけるステップの 1 起点の番号。それ以外は 0。 }
    class function StepIndex(AStep: TDxSequenceStep): Integer;

    property Step:   TDxSequenceStep read FStep;

    { True while the rig is being waited on, rollback included.
      リグを待っている間 True。ロールバックも含みます。 }
    property Active: Boolean read GetActive;

    { Whether split is on because this sequence turned it on.
      Read-only: the field is the sequence's record of what it must
      undo, and an application that could write it could make the
      rollback lie.

      本シーケンスがスプリットを入れた結果、現在入っているかどうか。
      読み取り専用です。このフィールドはシーケンスが「取り消すべきもの」
      として持つ記録であり、書き込めるならロールバックに嘘をつかせる
      ことができてしまいます。 }
    property SplitEnabled: Boolean read FSplitEnabled;

    property VerifiedSplitOn: Boolean read FVerifiedSplit;
    property VerifiedTxHz:    Double  read FVerifiedTxHz;

    property OnProgress: TDxProgressEvent read FOnProgress
                                          write FOnProgress;
    property OnFinished: TDxFinishedEvent read FOnFinished
                                          write FOnFinished;
  end;

{ True while the sequence is in one of the steps that are waiting on
  the rig. Written as a function rather than a property so the test and
  the presenter agree on what "running" means.
  リグを待っているステップのいずれかに居る間 True。テストと presenter
  が「実行中」の意味で一致するよう、プロパティではなく関数にしています。 }
function DxSequenceRunning(AStep: TDxSequenceStep): Boolean;

implementation

const
  { The happy path. dxsRollback, dxsDone and dxsFailed are deliberately
    absent: a rollback is not progress.
    正常系。dxsRollback、dxsDone、dxsFailed は意図的に含みません。
    ロールバックは進行ではありません。 }
  HAPPY_PATH: array[1..5] of TDxSequenceStep = (
    dxsSelectRxVfo, dxsSetRxFreq, dxsEnableSplit, dxsSetTxFreq, dxsVerify
  );

function DxSequenceRunning(AStep: TDxSequenceStep): Boolean;
begin
  Result := AStep in [dxsSelectRxVfo, dxsSetRxFreq, dxsEnableSplit,
                      dxsSetTxFreq, dxsVerify, dxsRollback];
end;

{ ------------------------------------------------------------------
  Construction / 構築
  ------------------------------------------------------------------ }

constructor TDxSplitSequence.Create(const AService: IRigService);
begin
  inherited Create;
  Assert(Assigned(AService), 'AService must not be nil');
  FService       := AService;
  FStep          := dxsIdle;
  FSplitEnabled  := False;
  FVerifiedSplit := False;
  FVerifiedTxHz  := 0;
end;

destructor TDxSplitSequence.Destroy;
begin
  { Cancelling here is not optional. The token keeps the component
    alive for as long as the command is queued, and a callback that
    fires after this object is gone would call a method on freed
    memory. The component's own guard (it drops callbacks for a closed
    service) is not the same guarantee: the service may still be open
    while only this sequence is being destroyed.

    ここでのキャンセルは任意ではありません。トークンはコマンドが
    キューにある間コンポーネントを生かし、本オブジェクト消滅後に発火
    したコールバックは解放済みメモリのメソッドを呼びます。コンポーネント
    側のガード (クローズ済みサービスのコールバックは捨てる) は同じ保証
    ではありません。サービスは開いたままで、本シーケンスだけが破棄され
    ることがあるからです。 }
  if Assigned(FToken) then
    FToken.Cancel;
  FToken   := nil;
  FService := nil;
  inherited Destroy;
end;

{ ------------------------------------------------------------------
  Public entry points / 公開入口
  ------------------------------------------------------------------ }

function TDxSplitSequence.Start(ARxHz, ATxHz: Double): Boolean;
begin
  Result := False;

  if DxSequenceRunning(FStep) then
    Exit;
  if not FService.IsOpen then
    Exit;
  if (ARxHz <= 0) or (ATxHz <= 0) then
    Exit;

  FRxHz          := ARxHz;
  FTxHz          := ATxHz;
  FSplitEnabled  := False;
  FPendingReason := '';
  FFailedStep    := dxsIdle;
  FVerifiedSplit := False;
  FVerifiedTxHz  := 0;

  Advance(dxsSelectRxVfo);
  Result := True;
end;

procedure TDxSplitSequence.Abort;
var
  WasEnabled: Boolean;
begin
  if not DxSequenceRunning(FStep) then
    Exit;

  { Already rolling back: let it finish. Cancelling the rollback is the
    one cancel that would leave the rig in the state we are trying to
    get it out of.
    既にロールバック中なら、終わらせます。ロールバックのキャンセルは、
    まさに脱出しようとしている状態にリグを置き去りにする唯一の
    キャンセルです。 }
  if FStep = dxsRollback then
    Exit;

  if Assigned(FToken) then
    FToken.Cancel;

  WasEnabled := FSplitEnabled;

  { The step is moved out of the waiting set before the rollback is
    issued, so the cancelled command's own callback — which may arrive
    after this line — finds a step it does not belong to and returns.
    ロールバック発行前にステップを待機集合から外します。これにより、
    この行の後に届きうるキャンセル済みコマンドのコールバックは、自分の
    属さないステップを見て戻ります。 }
  FStep := dxsIdle;

  if WasEnabled then
  begin
    Advance(dxsRollback);
    FToken := FService.SetSplitAsync(False, rvfoCurr, @HandleRolledBack);
  end
  else
  begin
    FFailedStep := dxsIdle;
    FStep       := dxsFailed;
    Finish(False, 'aborted by the operator before split was enabled '
                  + '— the rig was left as it was');
  end;
end;

{ ------------------------------------------------------------------
  The order of the sequence — the only place it exists
  シーケンスの順序。それが存在する唯一の場所
  ------------------------------------------------------------------ }

procedure TDxSplitSequence.Advance(AStep: TDxSequenceStep);
begin
  FStep := AStep;
  Report;

  case AStep of
    dxsSelectRxVfo:
      FToken := FService.SetVfoAsync(rvfoA, @HandleRxVfoSet);

    dxsSetRxFreq:
      FToken := FService.SetFrequencyAsync(FRxHz, rvfoA, @HandleRxFreqSet);

    dxsEnableSplit:
      FToken := FService.SetSplitAsync(True, rvfoB, @HandleSplitEnabled);

    dxsSetTxFreq:
      { rig_set_split_freq takes no VFO: it addresses "the transmit
        VFO", which step 3 has just declared to be VFO B. This is why
        the order matters and why step 4 cannot be issued in parallel
        with step 3.

        rig_set_split_freq は VFO を取りません。対象は「送信 VFO」で
        あり、それを手順 3 が今 VFO B と宣言したところです。これが順序が
        重要な理由であり、手順 4 を手順 3 と並行して発行できない理由
        です。 }
      FToken := FService.SetSplitFreqAsync(FTxHz, @HandleTxFreqSet);

    dxsVerify:
      FToken := FService.GetSplitAsync(@HandleVerified);

    dxsRollback:
      { Issued by the caller (Abort or Fail), because the message that
        goes with it differs.
        発行は呼び出し側 (Abort または Fail) が行います。付随する
        メッセージが異なるためです。 }
      ;
  else
    ;
  end;
end;

{ ------------------------------------------------------------------
  Failure handling / 失敗処理
  ------------------------------------------------------------------ }

function TDxSplitSequence.Accept(const AResult: TRigResult;
                                  const AWhat: string): Boolean;
begin
  Result := AResult.Status = rcsSuccess;
  if Result then
    Exit;

  case AResult.Status of
    rcsCancelled:
      { Abort has already decided what happens next and has already
        moved the step; saying anything here would overwrite its
        message with a less specific one.
        Abort が既に次を決めてステップを移しています。ここで何か言うと、
        そのメッセージをより曖昧なものに
        上書きしてしまいます。 }
      ;
    rcsTimeout:
      Fail(AWhat + ' timed out — the rig did not answer in time');
    rcsRejected:
      Fail(AWhat + ' was rejected by the rig: ' + AResult.ErrorMsg);
  else
    Fail(Format('%s failed (%s): %s',
                [AWhat, RigErrorKindToString(AResult.Error),
                 AResult.ErrorMsg]));
  end;
end;

procedure TDxSplitSequence.Fail(const AReason: string);
var
  FailedAt: TDxSequenceStep;
begin
  FailedAt := FStep;

  if FSplitEnabled then
  begin
    { The dangerous case. Undo split before telling anyone the sequence
      failed, so the operator is never looking at a failure message
      while the rig is still in split with an unset transmit frequency.

      危険な場合。失敗を伝える前にスプリットを解除します。送信周波数が
      未設定のままスプリット状態のリグを前にして、オペレータが失敗
      メッセージを読んでいる、という状況を作らないためです。 }
    FStep := dxsRollback;
    Report;
    FToken         := FService.SetSplitAsync(False, rvfoCurr,
                                             @HandleRolledBack);
    FPendingReason := AReason;
    FFailedStep    := FailedAt;
    Exit;
  end;

  FFailedStep := FailedAt;
  FStep       := dxsFailed;
  Finish(False, AReason);
end;

procedure TDxSplitSequence.Finish(ASucceeded: Boolean;
                                   const AMessage: string);
begin
  FToken := nil;
  if ASucceeded then
  begin
    FFailedStep := dxsIdle;
    FStep       := dxsDone;
  end
  else if FStep <> dxsFailed then
    FStep := dxsFailed;
  Report;
  if Assigned(FOnFinished) then
    FOnFinished(ASucceeded, FFailedStep, AMessage);
end;

function TDxSplitSequence.GetActive: Boolean;
begin
  Result := DxSequenceRunning(FStep);
end;

procedure TDxSplitSequence.Report;
begin
  if Assigned(FOnProgress) then
    FOnProgress(FStep, StepIndex(FStep), StepCount, StepCaption(FStep));
end;

{ ------------------------------------------------------------------
  Step handlers. Each is: am I still this step? then did it work?
  ステップハンドラ。各々「まだ自分のステップか」「成功したか」のみ。
  ------------------------------------------------------------------ }

procedure TDxSplitSequence.HandleRxVfoSet(const AResult: TRigResult);
begin
  if FStep <> dxsSelectRxVfo then Exit;

  { A rig that cannot select a VFO is not disqualified from split: many
    simple backends report RIG_ENAVAIL for rig_set_vfo and still handle
    rig_set_split_vfo correctly. Treating this step as advisory rather
    than mandatory is a decision about Hamlib's real behaviour, not a
    way of ignoring errors — every other step is mandatory.

    VFO を選択できないリグがスプリットの資格を失うわけではありません。
    単純なバックエンドの多くは rig_set_vfo に RIG_ENAVAIL を返しながら
    rig_set_split_vfo は正しく処理します。本ステップを必須ではなく
    助言的に扱うのは Hamlib の実挙動に関する判断であり、エラーを無視
    する手段ではありません。他のステップはすべて必須です。 }
  if (AResult.Status <> rcsSuccess)
     and (AResult.Error in [rekNotAvailable, rekNotImplemented,
                            rekVfoNotTargetable]) then
  begin
    Advance(dxsSetRxFreq);
    Exit;
  end;

  if Accept(AResult, 'selecting VFO A') then
    Advance(dxsSetRxFreq);
end;

procedure TDxSplitSequence.HandleRxFreqSet(const AResult: TRigResult);
begin
  if FStep <> dxsSetRxFreq then Exit;
  if Accept(AResult, 'setting the receive frequency') then
    Advance(dxsEnableSplit);
end;

procedure TDxSplitSequence.HandleSplitEnabled(const AResult: TRigResult);
begin
  if FStep <> dxsEnableSplit then Exit;
  if Accept(AResult, 'enabling split') then
  begin
    { Recorded before the next step is issued: if step 4 fails, the
      rollback must already know that split is on.
      次のステップ発行前に記録します。手順 4 が失敗したとき、ロール
      バックはスプリットが入っていることを既に知っていなければなり
      ません。 }
    FSplitEnabled := True;
    Advance(dxsSetTxFreq);
  end;
end;

procedure TDxSplitSequence.HandleTxFreqSet(const AResult: TRigResult);
begin
  if FStep <> dxsSetTxFreq then Exit;
  if Accept(AResult, 'setting the transmit frequency') then
    Advance(dxsVerify);
end;

procedure TDxSplitSequence.HandleVerified(const AResult: TRigSplitResult);
begin
  if FStep <> dxsVerify then Exit;

  if AResult.Status = rcsCancelled then
    Exit;

  if AResult.Status <> rcsSuccess then
  begin
    { The rig is configured but will not say so. That is a weaker
      failure than the others — the setup commands all succeeded — so
      it is reported as a failure with the reason named, and the
      rollback still runs, because an unverifiable split is exactly the
      state this sequence exists to avoid leaving behind.

      リグは設定済みですが、それを答えません。他より弱い失敗です
      (設定コマンドはすべて成功した)。そのため理由を明記した失敗として
      報告し、ロールバックも実行します。検証できないスプリットこそ、
      本シーケンスが残さないために存在する状態だからです。 }
    Fail('the rig would not confirm the split setting: '
         + AResult.ErrorMsg);
    Exit;
  end;

  FVerifiedSplit := AResult.SplitOn;
  FVerifiedTxHz  := AResult.TxFreq;

  if not AResult.SplitOn then
  begin
    FSplitEnabled := False;   { nothing to undo — it is already off }
    FStep         := dxsFailed;
    Finish(False, 'the rig accepted the split command and then reported '
                  + 'split as off — the model does not support it');
    Exit;
  end;

  { A transmit frequency that came back different is not a failure by
    itself: rigs round to their tuning step. It is reported so the
    operator can see the rig's own number, which is the one that will
    be transmitted on.

    読み戻した送信周波数が異なること自体は失敗ではありません。リグは
    自身のチューニングステップに丸めます。リグ自身の数値を報告するのは、
    実際に送信されるのがその数値だからです。 }
  FStep := dxsDone;
  if Abs(AResult.TxFreq - FTxHz) >= 1.0 then
    Finish(True, Format('split is on; the rig rounded the transmit '
                        + 'frequency to %.6f MHz (asked for %.6f)',
                        [AResult.TxFreq / 1E6, FTxHz / 1E6]))
  else
    Finish(True, Format('split is on, transmitting on %.6f MHz',
                        [AResult.TxFreq / 1E6]));
end;

procedure TDxSplitSequence.HandleRolledBack(const AResult: TRigResult);
var
  Tail: string;
begin
  if FStep <> dxsRollback then Exit;

  FSplitEnabled := False;

  if AResult.Status = rcsSuccess then
    Tail := ' — split was turned back off'
  else
    Tail := ' — AND SPLIT COULD NOT BE TURNED BACK OFF (' +
            AResult.ErrorMsg + '): check the rig before transmitting';

  FStep := dxsFailed;
  if FPendingReason <> '' then
    Finish(False, FPendingReason + Tail)
  else
    Finish(False, 'aborted by the operator' + Tail);
  FPendingReason := '';
end;

{ ------------------------------------------------------------------
  Presentation helpers / 表示補助
  ------------------------------------------------------------------ }

class function TDxSplitSequence.StepCaption(AStep: TDxSequenceStep): string;
begin
  case AStep of
    dxsIdle:        Result := 'idle';
    dxsSelectRxVfo: Result := 'selecting VFO A';
    dxsSetRxFreq:   Result := 'setting the receive frequency';
    dxsEnableSplit: Result := 'enabling split (TX on VFO B)';
    dxsSetTxFreq:   Result := 'setting the transmit frequency';
    dxsVerify:      Result := 'reading the split state back';
    dxsRollback:    Result := 'undoing split after a failure';
    dxsDone:        Result := 'ready for split operation';
    dxsFailed:      Result := 'not set up';
  else
    Result := Format('unlabelled step %d', [Ord(AStep)]);
  end;
end;

class function TDxSplitSequence.StepCount: Integer;
begin
  Result := High(HAPPY_PATH) - Low(HAPPY_PATH) + 1;
end;

class function TDxSplitSequence.StepIndex(AStep: TDxSequenceStep): Integer;
var
  i: Integer;
begin
  for i := Low(HAPPY_PATH) to High(HAPPY_PATH) do
    if HAPPY_PATH[i] = AStep then
    begin
      Result := i;
      Exit;
    end;
  Result := 0;
end;

end.
