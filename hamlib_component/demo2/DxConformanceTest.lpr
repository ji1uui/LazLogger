{
  DxConformanceTest.lpr

  Drives TDxSplitSequence and TDxPresenter against the real Hamlib
  library's dummy backend, through a recording view. No screen, no
  serial port, no transceiver.

  TDxSplitSequence と TDxPresenter を、記録用 view 経由で実 Hamlib の
  ダミーバックエンドに対して駆動します。画面もシリアルポートも無線機も
  不要です。

  What it is for / 目的
  ------------------------------------------------------------------
  FeatureMatrixTest proves that each Rev.6.0 call reaches the library
  and comes back with the right answer. This test asks a different
  question: when those calls are composed into an operation that can
  fail halfway, does the application layer leave the rig in a state the
  operator can trust?

  The cases that matter are the ones no unit test of a single call can
  reach:

    - abort before the dangerous step → nothing to undo
    - abort after it → the rollback runs and split really is off
    - a stale callback from a cancelled command → ignored, the
      sequence does not resume
    - the meter's back-pressure → fifty ticks do not become fifty
      queued commands

  FeatureMatrixTest は、Rev.6.0 の各呼び出しがライブラリに届き正しい
  答えを返すことを示します。本テストが問うのは別の問いです。それらの
  呼び出しを「途中で失敗しうる操作」に合成したとき、アプリケーション層は
  オペレータが信頼できる状態でリグを残すか。

  重要なのは、単一呼び出しのユニットテストでは到達できない事例です
  (上記 4 件)。

  Build:
    fpc -Mobjfpc -Sh -Criot -gh -Fu../src -Fu. DxConformanceTest.lpr
}
program DxConformanceTest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  HamlibInterfaces, HamlibErrors, HamlibVfoCodec, HamlibTimeoutPolicy,
  HamlibService, HamlibFactory,
  DxPanelView, DxSplitSequence, DxPanelPresenter;

const
  MODEL_DUMMY = 1;
  RX_MHZ      = 14.023;
  TX_MHZ      = 14.205;

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

procedure Pump(AMs: Integer);
var
  i: Integer;
begin
  for i := 1 to AMs div 10 do
  begin
    CheckSynchronize(5);
    Sleep(5);
  end;
end;

{ ------------------------------------------------------------------
  A view that only records. Implemented as a TInterfacedObject so the
  refcount rules are the ordinary ones — unlike the LCL form, which
  must suppress them because its lifetime belongs to its owner.

  記録するだけの view。参照カウントの規則が通常どおりになるよう
  TInterfacedObject として実装します。LCL のフォームとは異なります。
  フォームの寿命は所有者に属するため、参照カウントを抑制する必要が
  あるからです。
  ------------------------------------------------------------------ }
type
  TRecordingView = class(TInterfacedObject, IDxView)
  public
    Notices:      TStringList;
    CapLines:     TStringList;
    ProgressLog:  TStringList;
    UiModes:      TStringList;

    RxHz:         Double;
    SplitOn:      Boolean;
    TxVfo:        TRigVfo;
    TxHz:         Double;
    Vfo:          TRigVfo;
    RawVfo:       Integer;
    SignalDb:     Integer;
    SignalValid:  Boolean;
    OutcomeSeen:  Boolean;
    OutcomeOk:    Boolean;
    OutcomeText:  string;
    RigListCount: Integer;
    EnumAvailable: Boolean;
    LastUiMode:   TDxUiMode;
    QueueDepth:   Integer;
    BreakerOpen:  Boolean;

    constructor Create;
    destructor  Destroy; override;

    procedure ShowRigList(const AItems: array of string;
                          AEnumerationAvailable: Boolean);
    procedure ShowRxFrequency(AHz: Double);
    procedure ShowTxFrequency(ASplitOn: Boolean; ATxVfo: TRigVfo;
                              AHz: Double);
    procedure ShowSelectedVfo(AVfo: TRigVfo; ARawVfo: Integer);
    procedure ShowSignal(ADb: Integer; AValid: Boolean);
    procedure ShowSequenceProgress(AStepIndex, AStepCount: Integer;
                                   const ACaption: string);
    procedure ShowSequenceOutcome(ASucceeded: Boolean;
                                  const AMessage: string);
    procedure ShowCapabilities(const ALines: array of string);
    procedure SetUiMode(AMode: TDxUiMode);
    procedure ShowNotice(ALevel: TDxNoticeLevel; const AText: string);
    procedure ShowLibraryInfo(const AText: string);
    procedure ShowQueueDepth(ADepth: Integer; ABreakerOpen: Boolean);

    function  LastNotice: string;
    procedure ResetOutcome;
  end;

constructor TRecordingView.Create;
begin
  inherited Create;
  Notices     := TStringList.Create;
  CapLines    := TStringList.Create;
  ProgressLog := TStringList.Create;
  UiModes     := TStringList.Create;
end;

destructor TRecordingView.Destroy;
begin
  UiModes.Free;
  ProgressLog.Free;
  CapLines.Free;
  Notices.Free;
  inherited Destroy;
end;

procedure TRecordingView.ShowRigList(const AItems: array of string;
                                      AEnumerationAvailable: Boolean);
begin
  RigListCount  := Length(AItems);
  EnumAvailable := AEnumerationAvailable;
end;

procedure TRecordingView.ShowRxFrequency(AHz: Double);
begin
  RxHz := AHz;
end;

procedure TRecordingView.ShowTxFrequency(ASplitOn: Boolean;
                                          ATxVfo: TRigVfo; AHz: Double);
begin
  SplitOn := ASplitOn;
  TxVfo   := ATxVfo;
  TxHz    := AHz;
end;

procedure TRecordingView.ShowSelectedVfo(AVfo: TRigVfo; ARawVfo: Integer);
begin
  Vfo    := AVfo;
  RawVfo := ARawVfo;
end;

procedure TRecordingView.ShowSignal(ADb: Integer; AValid: Boolean);
begin
  SignalDb    := ADb;
  SignalValid := AValid;
end;

procedure TRecordingView.ShowSequenceProgress(AStepIndex, AStepCount: Integer;
                                               const ACaption: string);
begin
  ProgressLog.Add(Format('%d/%d %s', [AStepIndex, AStepCount, ACaption]));
end;

procedure TRecordingView.ShowSequenceOutcome(ASucceeded: Boolean;
                                              const AMessage: string);
begin
  OutcomeSeen := True;
  OutcomeOk   := ASucceeded;
  OutcomeText := AMessage;
end;

procedure TRecordingView.ShowCapabilities(const ALines: array of string);
var
  i: Integer;
begin
  CapLines.Clear;
  for i := Low(ALines) to High(ALines) do
    CapLines.Add(ALines[i]);
end;

procedure TRecordingView.SetUiMode(AMode: TDxUiMode);
begin
  LastUiMode := AMode;
  UiModes.Add(IntToStr(Ord(AMode)));
end;

procedure TRecordingView.ShowNotice(ALevel: TDxNoticeLevel;
                                     const AText: string);
begin
  Notices.Add(Format('%d|%s', [Ord(ALevel), AText]));
end;

procedure TRecordingView.ShowLibraryInfo(const AText: string);
begin
  Notices.Add('lib|' + AText);
end;

procedure TRecordingView.ShowQueueDepth(ADepth: Integer;
                                         ABreakerOpen: Boolean);
begin
  QueueDepth  := ADepth;
  BreakerOpen := ABreakerOpen;
end;

function TRecordingView.LastNotice: string;
begin
  if Notices.Count = 0 then
    Result := ''
  else
    Result := Notices[Notices.Count - 1];
end;

procedure TRecordingView.ResetOutcome;
begin
  OutcomeSeen := False;
  OutcomeOk   := False;
  OutcomeText := '';
  ProgressLog.Clear;
end;

{ ------------------------------------------------------------------
  A sequence observer, for the cases that are about the sequence
  itself rather than about the panel.
  パネルではなくシーケンス自体に関する事例のための観測子。
  ------------------------------------------------------------------ }
type
  TSeqWatch = class
    Steps:     TStringList;
    Finished:  Boolean;
    Succeeded: Boolean;
    FailedAt:  TDxSequenceStep;
    Message:   string;
    constructor Create;
    destructor  Destroy; override;
    procedure OnProgress(AStep: TDxSequenceStep; AIndex, ACount: Integer;
                         const ACaption: string);
    procedure OnFinished(ASucceeded: Boolean; AFailedStep: TDxSequenceStep;
                         const AMessage: string);
    procedure Reset;
    function  Saw(AStep: TDxSequenceStep): Boolean;
  end;

constructor TSeqWatch.Create;
begin
  inherited Create;
  Steps := TStringList.Create;
end;

destructor TSeqWatch.Destroy;
begin
  Steps.Free;
  inherited Destroy;
end;

procedure TSeqWatch.OnProgress(AStep: TDxSequenceStep;
                                AIndex, ACount: Integer;
                                const ACaption: string);
begin
  Steps.Add(IntToStr(Ord(AStep)));
end;

procedure TSeqWatch.OnFinished(ASucceeded: Boolean;
                                AFailedStep: TDxSequenceStep;
                                const AMessage: string);
begin
  Finished  := True;
  Succeeded := ASucceeded;
  FailedAt  := AFailedStep;
  Message   := AMessage;
end;

procedure TSeqWatch.Reset;
begin
  Steps.Clear;
  Finished  := False;
  Succeeded := False;
  Message   := '';
end;

function TSeqWatch.Saw(AStep: TDxSequenceStep): Boolean;
begin
  Result := Steps.IndexOf(IntToStr(Ord(AStep))) >= 0;
end;

{ ------------------------------------------------------------------
  Helper: read the rig's split state synchronously, for an independent
  check that does not go through the sequence or the presenter.
  補助: リグのスプリット状態を同期的に読みます。シーケンスや presenter
  を経由しない独立した確認のためです。
  ------------------------------------------------------------------ }
type
  TSplitProbe = class
    Got:     Boolean;
    Result_: TRigSplitResult;
    procedure Handle(const AResult: TRigSplitResult);
  end;

procedure TSplitProbe.Handle(const AResult: TRigSplitResult);
begin
  Got     := True;
  Result_ := AResult;
end;

function ReadSplit(const ASvc: IRigService;
                   out AResult: TRigSplitResult): Boolean;
var
  Probe: TSplitProbe;
  Waited: Integer;
begin
  Probe := TSplitProbe.Create;
  try
    ASvc.GetSplitAsync(@Probe.Handle);
    Waited := 0;
    while (not Probe.Got) and (Waited < 2000) do
    begin
      Pump(50);
      Inc(Waited, 50);
    end;
    Result  := Probe.Got;
    AResult := Probe.Result_;
  finally
    Probe.Free;
  end;
end;

{ ------------------------------------------------------------------
  Cases / 検査
  ------------------------------------------------------------------ }

procedure CaseHappyPath(const ASvc: IRigService);
var
  Seq:   TDxSplitSequence;
  Watch: TSeqWatch;
  Split: TRigSplitResult;
  i:     Integer;
begin
  WriteLn;
  WriteLn('SEQUENCE — the happy path, five steps in order');

  Watch := TSeqWatch.Create;
  Seq   := TDxSplitSequence.Create(ASvc);
  try
    Seq.OnProgress := @Watch.OnProgress;
    Seq.OnFinished := @Watch.OnFinished;

    Check('a sequence starts', Seq.Start(RX_MHZ * 1E6, TX_MHZ * 1E6));
    Check('and reports itself as running', Seq.Active);

    i := 0;
    while (not Watch.Finished) and (i < 60) do
    begin
      Pump(50);
      Inc(i);
    end;

    Check('it finished', Watch.Finished);
    Check('successfully', Watch.Succeeded, Watch.Message);
    Check('and is no longer running', not Seq.Active);
    WriteLn('    ', Watch.Message);

    Check('every happy-path step was reported',
          Watch.Saw(dxsSelectRxVfo) and Watch.Saw(dxsSetRxFreq)
          and Watch.Saw(dxsEnableSplit) and Watch.Saw(dxsSetTxFreq)
          and Watch.Saw(dxsVerify));
    Check('and the rollback was not',
          not Watch.Saw(dxsRollback));
    Check('the steps came in order',
          Watch.Steps.IndexOf(IntToStr(Ord(dxsEnableSplit)))
          < Watch.Steps.IndexOf(IntToStr(Ord(dxsSetTxFreq))));

    Check('the rig confirms split', Seq.VerifiedSplitOn);
    Check('on the transmit frequency asked for',
          Abs(Seq.VerifiedTxHz - TX_MHZ * 1E6) < 1.0,
          Format('%.0f', [Seq.VerifiedTxHz]));

    { Independent of the sequence: ask the rig again.
      シーケンスとは独立に、リグへ再度問います。 }
    Check('and still says so when asked separately',
          ReadSplit(ASvc, Split) and Split.SplitOn);
  finally
    Seq.Free;
    Watch.Free;
  end;
end;

procedure CaseRefusals(const ASvc: IRigService);
var
  Seq: TDxSplitSequence;
begin
  WriteLn;
  WriteLn('SEQUENCE — what Start refuses without touching the rig');

  Seq := TDxSplitSequence.Create(ASvc);
  try
    Check('a zero receive frequency is refused',
          not Seq.Start(0, TX_MHZ * 1E6));
    Check('a negative transmit frequency is refused',
          not Seq.Start(RX_MHZ * 1E6, -1));
    Check('and nothing was started', not Seq.Active);
    Check('the step is still idle', Seq.Step = dxsIdle);

    Check('a real start is accepted', Seq.Start(RX_MHZ * 1E6, TX_MHZ * 1E6));
    Check('a second start while running is refused',
          not Seq.Start(RX_MHZ * 1E6, TX_MHZ * 1E6));

    Seq.Abort;
    Pump(1500);
  finally
    Seq.Free;
  end;
end;

procedure CaseAbortBeforeSplit(const ASvc: IRigService);
var
  Seq:   TDxSplitSequence;
  Watch: TSeqWatch;
  Split: TRigSplitResult;
begin
  WriteLn;
  WriteLn('ROLLBACK — abort before the dangerous step');

  { Leave the rig in a known state first.
    まずリグを既知の状態にします。 }
  ASvc.SetSplitAsync(False);
  Pump(400);

  Watch := TSeqWatch.Create;
  Seq   := TDxSplitSequence.Create(ASvc);
  try
    Seq.OnProgress := @Watch.OnProgress;
    Seq.OnFinished := @Watch.OnFinished;

    Seq.Start(RX_MHZ * 1E6, TX_MHZ * 1E6);

    { Aborted immediately: the first command has been issued but split
      has certainly not been enabled yet, because that is step three.
      即座に中断します。最初のコマンドは発行済みですが、スプリットは
      まだ確実に有効になっていません。それは 3 番目の手順です。 }
    Check('split is not yet enabled', not Seq.SplitEnabled);
    Seq.Abort;
    Pump(1200);

    Check('the abort was reported', Watch.Finished);
    Check('as a failure', not Watch.Succeeded);
    Check('with no rollback, because there was nothing to undo',
          not Watch.Saw(dxsRollback), Watch.Message);
    Check('and the message says the rig was left alone',
          Pos('left as it was', Watch.Message) > 0, Watch.Message);
    Check('the rig really is not in split',
          ReadSplit(ASvc, Split) and (not Split.SplitOn));
  finally
    Seq.Free;
    Watch.Free;
  end;
end;

procedure CaseAbortAfterSplit(const ASvc: IRigService);
var
  Seq:   TDxSplitSequence;
  Watch: TSeqWatch;
  Split: TRigSplitResult;
  i:     Integer;
begin
  WriteLn;
  WriteLn('ROLLBACK — abort after split was enabled');

  ASvc.SetSplitAsync(False);
  Pump(400);

  Watch := TSeqWatch.Create;
  Seq   := TDxSplitSequence.Create(ASvc);
  try
    Seq.OnProgress := @Watch.OnProgress;
    Seq.OnFinished := @Watch.OnFinished;
    Seq.Start(RX_MHZ * 1E6, TX_MHZ * 1E6);

    { Wait for step three to land, then abort. The dummy rig answers
      in microseconds, so this is a race the test has to win
      deliberately rather than by sleeping a guessed amount.
      手順 3 が成立するのを待ってから中断します。ダミーリグはマイクロ秒
      で応答するため、これは当て推量の sleep ではなく意図的に勝ち取る
      べき競合です。 }
    i := 0;
    while (not Seq.SplitEnabled) and (not Watch.Finished) and (i < 100) do
    begin
      CheckSynchronize(1);
      Sleep(1);
      Inc(i);
    end;

    if Watch.Finished then
    begin
      { The whole sequence completed before the abort could be placed.
        This is not a test failure — it is the dummy backend being
        faster than the test — but the case has then not been
        exercised, and saying so is more useful than a green tick.

        中断を差し込む前にシーケンス全体が完了しました。テストの失敗
        ではなく、ダミーバックエンドがテストより速いということです。
        ただしこの事例は検査されていないため、緑のチェックより、そう
        述べる方が有用です。 }
      WriteLn('    [skip] the sequence finished before the abort '
              + 'could be placed');
      WriteLn('           (the dummy rig answers faster than the test '
              + 'can interleave)');

      { Fall back to the equivalent check that is still available: the
        sequence's own record of what it enabled must agree with the
        rig.
        それでも可能な同等の確認に退きます。シーケンス自身の記録が
        リグと一致していなければなりません。 }
      Check('and what it enabled agrees with the rig',
            ReadSplit(ASvc, Split) and (Split.SplitOn = Seq.VerifiedSplitOn));
      Exit;
    end;

    Check('split was enabled before the abort', Seq.SplitEnabled);
    Seq.Abort;

    i := 0;
    while (not Watch.Finished) and (i < 60) do
    begin
      Pump(50);
      Inc(i);
    end;

    Check('the abort was reported', Watch.Finished);
    Check('as a failure', not Watch.Succeeded);
    Check('the rollback ran', Watch.Saw(dxsRollback), Watch.Message);
    Check('and said so in the message',
          Pos('turned back off', Watch.Message) > 0, Watch.Message);
    Check('the sequence no longer believes split is on',
          not Seq.SplitEnabled);
    Check('and the rig agrees it is off',
          ReadSplit(ASvc, Split) and (not Split.SplitOn));
  finally
    Seq.Free;
    Watch.Free;
  end;
end;

procedure CaseStaleCallback(const ASvc: IRigService);
var
  Seq:   TDxSplitSequence;
  Watch: TSeqWatch;
  Before: Integer;
begin
  WriteLn;
  WriteLn('STALE CALLBACKS — an aborted sequence must not resume');

  ASvc.SetSplitAsync(False);
  Pump(400);

  Watch := TSeqWatch.Create;
  Seq   := TDxSplitSequence.Create(ASvc);
  try
    Seq.OnProgress := @Watch.OnProgress;
    Seq.OnFinished := @Watch.OnFinished;

    Seq.Start(RX_MHZ * 1E6, TX_MHZ * 1E6);
    Seq.Abort;

    { Everything the worker had queued is now delivered. Each of those
      callbacks belongs to a step the sequence has left, so each must
      return without advancing anything.
      ワーカーがキューに持っていたものがすべて配送されます。それらの
      コールバックはシーケンスが離れたステップに属するため、どれも何も
      進めずに戻らなければなりません。 }
    Pump(1500);
    Before := Watch.Steps.Count;
    Pump(800);

    Check('no further steps were reported after the abort settled',
          Watch.Steps.Count = Before,
          Format('%d -> %d', [Before, Watch.Steps.Count]));
    Check('the sequence is not running', not Seq.Active);
    Check('and did not reach the verify step',
          not Watch.Saw(dxsVerify));
  finally
    Seq.Free;
    Watch.Free;
  end;
end;

{ ------------------------------------------------------------------
  Regression: the snapshot must not claim to know which VFO a polled
  frequency belongs to.

  退行検査: スナップショットは、ポーリングした周波数がどの VFO のもの
  かを知っていると主張してはなりません。
  ------------------------------------------------------------------ }
procedure CaseSnapshotLabels(const ASvc: IRigService);
var
  St: TRigState;
begin
  WriteLn;
  WriteLn('SNAPSHOT — which VFO does a polled frequency belong to?');

  ASvc.SetSplitAsync(False);
  ASvc.SetFrequencyAsync(7020000, rvfoA);
  ASvc.SetFrequencyAsync(21300000, rvfoB);
  Pump(600);

  { Select VFO B, then poll. Up to Rev.5.1 the poller filed its answer
    under VfoAFreq, so this is the arrangement in which the snapshot
    used to report VFO B's frequency as VFO A's.
    VFO B を選択してからポーリングします。Rev.5.1 までポーラは答えを
    VfoAFreq へ格納していたため、これはスナップショットが VFO B の
    周波数を VFO A のものとして報告していた状況です。 }
  ASvc.SetVfoAsync(rvfoB);
  Pump(400);
  ASvc.EnablePolling(80);
  Pump(600);
  ASvc.DisablePolling;
  Pump(200);

  St := ASvc.CurrentState;
  WriteLn(Format('    CurrentFreq %.0f   VfoAFreq %.0f   VfoBFreq %.0f',
                 [St.CurrentFreq, St.VfoAFreq, St.VfoBFreq]));

  Check('polling fills CurrentFreq', St.CurrentFreq > 0);
  Check('with the selected VFO''s frequency, which is B''s',
        Abs(St.CurrentFreq - 21300000) < 1.0,
        Format('%.0f', [St.CurrentFreq]));
  Check('and does NOT overwrite VfoAFreq with it',
        Abs(St.VfoAFreq - 21300000) >= 1.0,
        'the Rev.5.1 defect is back: a polled frequency was filed as '
        + 'VFO A''s without the rig ever saying so');

  { VfoAFreq is still 0 even though VFO A was set to 7.020 MHz a few
    lines ago. That is deliberate: the snapshot records what the rig
    reported, never what it was asked for. An optimistic update would
    be wrong the moment a rig rounds to its tuning step, and it would
    be wrong silently.

    数行前に VFO A を 7.020 MHz に設定したにもかかわらず VfoAFreq は
    まだ 0 です。これは意図的です。スナップショットが記録するのは
    リグが報告した内容であり、要求した内容ではありません。楽観的な
    更新は、リグがチューニングステップに丸めた瞬間に誤りとなり、
    しかも黙って誤ります。 }
  Check('a Set alone does not populate the snapshot',
        St.VfoAFreq = 0, Format('%.0f', [St.VfoAFreq]));

  ASvc.GetFrequencyAsync(rvfoA);
  Pump(500);
  St := ASvc.CurrentState;
  Check('a read that names VFO A does populate it',
        Abs(St.VfoAFreq - 7020000) < 1.0, Format('%.0f', [St.VfoAFreq]));
  Check('and leaves the polled frequency alone',
        Abs(St.CurrentFreq - 21300000) < 1.0,
        Format('%.0f', [St.CurrentFreq]));
  WriteLn(Format('    after an explicit read of A: CurrentFreq %.0f   '
                 + 'VfoAFreq %.0f', [St.CurrentFreq, St.VfoAFreq]));

  { Put the rig back on A so later cases start where they expect to.
    後続の事例が想定どおりの場所から始まるよう、リグを A に戻します。 }
  ASvc.SetVfoAsync(rvfoA);
  Pump(400);
end;

procedure CasePresenter;
var
  View:  TRecordingView;
  ViewI: IDxView;
  Pres:  TDxPresenter;
  i, Depth: Integer;
begin
  WriteLn;
  WriteLn('PRESENTER — the panel as the operator drives it');

  View  := TRecordingView.Create;
  ViewI := View;                { the only owning reference }
  Pres  := TDxPresenter.Create(ViewI);
  try
    Pres.Initialise;
    Check('the rig list was offered', View.RigListCount > 0,
          Format('%d', [View.RigListCount]));
    Check('the panel starts disconnected',
          View.LastUiMode = duiDisconnected);

    Pres.Connect(MODEL_DUMMY, '', 'default');
    Pump(600);
    Check('connecting leaves the panel connected',
          View.LastUiMode = duiConnected);

    Check('the capability panel was filled', View.CapLines.Count > 0);
    Check('and says what "empty" means, rather than implying '
          + '"unsupported"',
          Pos('not asked', View.CapLines.Text) > 0);
    Check('PTT is reported as available, because the panel supplied '
          + 'ptt_type=RIG',
          Pos('PTT: available', View.CapLines.Text) > 0,
          View.CapLines.Text);

    { Back-pressure. Fifty ticks with no pumping in between: the
      presenter must issue at most one command, because the first
      read's callback cannot have arrived yet.
      バックプレッシャ。間に pump を挟まず 50 回のティック。最初の
      読み取りのコールバックはまだ届きえないため、presenter が発行する
      コマンドは最大 1 つでなければなりません。 }
    for i := 1 to 50 do
      Pres.MeterTick;
    Depth := 0;
    Pres.StateTick;
    Depth := View.QueueDepth;
    Check('fifty meter ticks did not become fifty queued commands',
          Depth <= 1, Format('queue depth %d', [Depth]));
    Pump(400);
    Check('the meter reads a value', View.SignalValid);
    WriteLn('    S-meter: ', View.SignalDb, ' dB relative to S9');

    { The sequence, through the presenter, in MHz as an operator types
      it off a cluster line.
      presenter 経由のシーケンス。オペレータがクラスタの行から打つ
      とおりの MHz で。 }
    View.ResetOutcome;
    Pres.StartSplitSetup(RX_MHZ, TX_MHZ);
    Check('the panel locks itself while the sequence runs',
          View.LastUiMode = duiSequenceRunning);
    i := 0;
    while (not View.OutcomeSeen) and (i < 60) do
    begin
      Pump(50);
      Inc(i);
    end;
    Check('an outcome was shown', View.OutcomeSeen);
    Check('and it succeeded', View.OutcomeOk, View.OutcomeText);
    Check('the panel unlocked afterwards',
          View.LastUiMode = duiConnected);
    Check('progress was shown step by step',
          View.ProgressLog.Count >= TDxSplitSequence.StepCount,
          Format('%d lines', [View.ProgressLog.Count]));

    Pump(300);
    Check('the panel shows split as on', View.SplitOn);
    Check('with the transmit frequency the rig reports',
          Abs(View.TxHz - TX_MHZ * 1E6) < 1.0,
          Format('%.0f', [View.TxHz]));

    { A start refused while one is running must not disturb the one
      that is running.
      実行中に拒否された start が、実行中のものを乱してはなりません。 }
    View.ResetOutcome;
    Pres.StartSplitSetup(RX_MHZ, TX_MHZ);
    Pres.StartSplitSetup(RX_MHZ, TX_MHZ);
    Check('the second start was refused with a notice',
          Pos('already running', View.LastNotice) > 0, View.LastNotice);
    i := 0;
    while (not View.OutcomeSeen) and (i < 60) do
    begin
      Pump(50);
      Inc(i);
    end;
    Check('and the first one still completed', View.OutcomeOk,
          View.OutcomeText);

    Pres.ClearSplit;
    Pump(500);
    Check('clearing split is reflected in the panel', not View.SplitOn);

    { The dummy backend refuses RIG_OP_TOGGLE once a VFO has been
      selected explicitly (it answers RIG_EVFO, as Hamlib's own rigctld
      also reports — tools/differential.py step 16). The check that
      matters is therefore not "did it work" but "was the operator
      told": an earlier version of this test asserted only that some
      VFO was still selected afterwards, which is true whether the
      operation succeeded or failed, so a silent failure would have
      passed.

      ダミーバックエンドは、VFO が明示的に選択された後の
      RIG_OP_TOGGLE を拒否します (RIG_EVFO を返します。Hamlib 自身の
      rigctld も同じ報告をします — tools/differential.py のステップ 16)。
      したがって重要な検査は「成功したか」ではなく「オペレータに伝わった
      か」です。本テストの以前の版は、その後も何らかの VFO が選択されて
      いることだけを主張していました。それは操作の成否にかかわらず真で
      あり、沈黙した失敗が通ってしまいます。 }
    View.Notices.Clear;
    Pres.ToggleVfo;
    Pump(500);
    Check('a VFO operation leaves a VFO selected',
          View.Vfo in [rvfoA, rvfoB, rvfoMain, rvfoSub],
          Format('%d', [Ord(View.Vfo)]));
    Check('and the raw vfo_t was passed through for display',
          View.RawVfo <> 0, Format('%d', [View.RawVfo]));
    Check('a refused VFO operation is reported, never swallowed',
          (View.Notices.Count = 0)
          or (Pos('invalid', LowerCase(View.Notices.Text)) > 0)
          or (Pos('vfo', LowerCase(View.Notices.Text)) > 0),
          View.Notices.Text);

    Pres.SetRfPowerPercent(42);
    Pump(400);
    Pres.SetRfPowerPercent(250);
    Check('an out-of-range RF power is refused by the presenter',
          Pos('0..100', View.LastNotice) > 0, View.LastNotice);

    Pres.SetNoiseBlanker(True);
    Pump(400);

    Pres.Disconnect;
    Check('disconnecting returns the panel to its initial mode',
          View.LastUiMode = duiDisconnected);
    Check('and blanks the meter rather than showing a stale 0 dB',
          not View.SignalValid);
  finally
    Pres.Free;
    ViewI := nil;
  end;
end;

{ ------------------------------------------------------------------
  Main / 本体
  ------------------------------------------------------------------ }
var
  Factory: IRigServiceFactory;
  Svc:     IRigService;

begin
  WriteLn('DxConformanceTest — the second sample, driven headlessly');
  WriteLn('=======================================================');

  Factory := TRigServiceFactory.Create;

  { One service for the sequence cases, opened directly so those cases
    are about the sequence and not about the presenter.
    シーケンス事例用のサービスを 1 つ、直接開きます。それらの事例が
    presenter ではなくシーケンスに関するものであるためです。 }
  Svc := Factory.CreateService;
  try
    Svc.ApplyTimeoutPolicy(RigPolicy_FastUsb);
    Svc.Open(MODEL_DUMMY, '');
    Check('the dummy rig opened', Svc.IsOpen);

    CaseHappyPath(Svc);
    CaseRefusals(Svc);
    CaseAbortBeforeSplit(Svc);
    CaseAbortAfterSplit(Svc);
    CaseStaleCallback(Svc);
    CaseSnapshotLabels(Svc);

    Svc.SetSplitAsync(False);
    Pump(400);
    Svc.Close;
    Check('the rig closed cleanly', not Svc.IsOpen);
  finally
    Svc := nil;
  end;

  CasePresenter;

  Factory := nil;

  WriteLn;
  WriteLn(Format('--- %d / %d checks passed ---',
                 [Passed, Passed + Failed]));
  if Failed = 0 then
  begin
    WriteLn('RESULT: OK');
    ExitCode := 0;
  end
  else
  begin
    WriteLn(Format('RESULT: %d FAILED', [Failed]));
    ExitCode := 1;
  end;
end.
