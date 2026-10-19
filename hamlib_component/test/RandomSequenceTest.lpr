{
  RandomSequenceTest.lpr

  Generates pseudo-random sequences of API calls, runs them against the
  real Hamlib library, and checks invariants that must hold whatever
  order the calls arrive in.

  擬似乱数で API 呼び出し列を生成し、実 Hamlib ライブラリに対して実行し、
  呼び出しの順序によらず成り立たねばならない不変条件を検査します。

  Why / 理由
  ------------------------------------------------------------------
  Every hand-written test in this project exercises an order somebody
  thought of. The defects that survive such a suite are the ones in
  orders nobody thought of — a cancel arriving between two steps, a
  Close while a read is in flight, a polling toggle during a burst.
  A generator does not have to think of them.

  本プロジェクトの手書きテストはすべて、誰かが思いついた順序を動かします。
  そのテスト群を生き延びる欠陥は、誰も思いつかなかった順序にあるものです。
  2 つのステップの間に届くキャンセル、読み取り実行中の Close、バースト中の
  ポーリング切り替え。生成器はそれらを思いつく必要がありません。

  The invariants / 不変条件
  ------------------------------------------------------------------
    I1  No undocumented exception ever escapes an API call.
        文書化されていない例外が API 呼び出しから漏れない。

    I2  Every command that was accepted delivers exactly one callback.
        Not zero (a lost result leaves the application waiting
        forever) and not two (a double free waiting to happen).
        受理されたコマンドはコールバックをちょうど 1 回配送する。
        0 回ではなく (結果の消失はアプリを永久に待たせる)、2 回でもない
        (いずれ二重解放になる)。

    I3  The queue drains. After the last command and a quiet period,
        QueueDepth is 0.
        キューは掃ける。最後のコマンドと静止期間の後、QueueDepth は 0。

    I4  QueueDepth is never negative.
        QueueDepth は決して負にならない。

    I5  CurrentState.Connected always agrees with IsOpen.
        CurrentState.Connected は常に IsOpen と一致する。

    I6  The snapshot timestamp never goes backwards.
        スナップショットのタイムスタンプは決して巻き戻らない。

    I7  Nothing leaks (checked by heaptrc at exit).
        何も漏れない (終了時に heaptrc が検査)。

  A failing run prints its seed. Re-running with that seed reproduces
  the exact sequence, because every random choice comes from RandSeed
  and nothing else.

  失敗した実行はシードを出力します。そのシードで再実行すると、まったく
  同じ順序が再現されます。すべての乱択が RandSeed だけに由来するからです。

  Usage:
    ./RandomSequenceTest [seed] [iterations]
}
program RandomSequenceTest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  HamlibInterfaces, HamlibErrors, HamlibTimeoutPolicy,
  HamlibService, HamlibFactory;

const
  MODEL_DUMMY = 1;

var
  Passed:    Integer = 0;
  Failed:    Integer = 0;
  Seed:      LongInt;
  Iterations: Integer;

  { I2's two counters. Issued is incremented only when the call
    returned without raising, because a call that raised never became
    a command.
    I2 の 2 つのカウンタ。Issued は呼び出しが例外を出さずに戻ったとき
    だけ増やします。例外を出した呼び出しはコマンドになっていないから
    です。 }
  Issued:    Integer = 0;
  Delivered: Integer = 0;

  LastStamp: QWord = 0;

  { How many deliveries reported rcsCancelled. 配送のうち rcsCancelled
    を報告した件数。 }
  CancelledSeen: Integer = 0;

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

procedure Fail(const AText: string);
begin
  Inc(Failed);
  WriteLn('    [FAIL] ', AText);
end;

procedure Pump(AMs: Integer);
var
  i: Integer;
begin
  for i := 1 to AMs div 5 do
  begin
    CheckSynchronize(2);
    Sleep(3);
  end;
end;

{ ------------------------------------------------------------------
  The counter sink. Every generated command gets one of these, so I2
  can be checked.
  カウンタ用シンク。生成された全コマンドにこれを渡すことで I2 を検査
  できます。
  ------------------------------------------------------------------ }
{ Accounting is kept per command SHAPE, not just in total.

  A total alone cannot see a defect that loses every callback of one
  kind while the others cover for it in the sum. That is not
  hypothetical: the four Get commands added in Rev.6.0 once fell
  through to a generic branch in the cancellation path whose callback
  field is nil for a typed command, so GetLevelAsync, GetFuncAsync,
  GetSplitAsync and GetVfoAsync reported nothing at all when cancelled
  and an application waiting on one waited forever. Per-shape counts
  name the shape that went missing.

  会計はコマンドの「種類」ごとに取り、合計だけにはしません。

  合計だけでは、ある種類のコールバックを全部失いながら他の種類がその
  分を埋めてしまう欠陥が見えません。これは仮定の話ではありません。
  Rev.6.0 で追加された Get コマンド 4 種は、かつてキャンセル経路の汎用
  分岐に落ちていました。型付きコマンドではその分岐のコールバック
  フィールドは nil のため、GetLevelAsync、GetFuncAsync、GetSplitAsync、
  GetVfoAsync はキャンセル時に何も報告せず、待っていたアプリケーション
  は永久に待ちました。種類ごとの計数は、消えた種類を名指しします。 }
type
  TCmdShape = (csSetFreq, csGetFreq, csSetMode, csGetMode,
               csGetLevel, csSetLevelF, csSetLevelI,
               csGetFunc, csSetFunc,
               csSetSplit, csGetSplit, csSetSplitFreq,
               csSetVfo, csGetVfo);

const
  SHAPE_NAME: array[TCmdShape] of string = (
    'SetFrequencyAsync', 'GetFrequencyAsync', 'SetModeAsync', 'GetModeAsync',
    'GetLevelAsync', 'SetLevelFloatAsync', 'SetLevelIntAsync',
    'GetFuncAsync', 'SetFuncAsync',
    'SetSplitAsync', 'GetSplitAsync', 'SetSplitFreqAsync',
    'SetVfoAsync', 'GetVfoAsync');

var
  ShapeIssued:    array[TCmdShape] of Integer;
  ShapeDelivered: array[TCmdShape] of Integer;

procedure ResetShapeCounts;
var
  Sh: TCmdShape;
begin
  for Sh := Low(TCmdShape) to High(TCmdShape) do
  begin
    ShapeIssued[Sh]    := 0;
    ShapeDelivered[Sh] := 0;
  end;
end;

type
  TCounter = class
    procedure OnCommand(const R: TRigResult);
    procedure OnFreq(const R: TRigFreqResult);
    procedure OnMode(const R: TRigModeResult);
    procedure OnLevel(const R: TRigLevelResult);
    procedure OnFunc(const R: TRigFuncResult);
    procedure OnSplit(const R: TRigSplitResult);
    procedure OnVfo(const R: TRigVfoResult);

    { One per set-shape, because they all return the same TRigResult
      and a single handler could not tell them apart.
      設定系は 1 種類につき 1 つ。いずれも同じ TRigResult を返すため、
      ハンドラが 1 つでは区別できないからです。 }
    procedure OnSetFreq(const R: TRigResult);
    procedure OnSetMode(const R: TRigResult);
    procedure OnSetLevelF(const R: TRigResult);
    procedure OnSetLevelI(const R: TRigResult);
    procedure OnSetFunc(const R: TRigResult);
    procedure OnSetSplit(const R: TRigResult);
    procedure OnSetSplitFreq(const R: TRigResult);
    procedure OnSetVfo(const R: TRigResult);
  end;

{ Also records how many results came back as rcsCancelled, so the
  cancellation phase can prove it actually cancelled something. A phase
  in which every command happened to finish before the cancel landed
  would pass while testing nothing.
  rcsCancelled で戻った件数も記録します。キャンセルのフェーズが実際に
  何かをキャンセルしたことを証明できるようにするためです。すべての
  コマンドがキャンセル到達前に偶然完了したフェーズは、何も検査せずに
  合格してしまいます。 }
procedure Count(ASh: TCmdShape; AStatus: TRigCommandStatus);
begin
  Inc(Delivered);
  Inc(ShapeDelivered[ASh]);
  if AStatus = rcsCancelled then
    Inc(CancelledSeen);
end;

procedure TCounter.OnCommand(const R: TRigResult);  begin Inc(Delivered); end;
procedure TCounter.OnFreq(const R: TRigFreqResult); begin Count(csGetFreq, R.Status); end;
procedure TCounter.OnMode(const R: TRigModeResult); begin Count(csGetMode, R.Status); end;
procedure TCounter.OnLevel(const R: TRigLevelResult); begin Count(csGetLevel, R.Status); end;
procedure TCounter.OnFunc(const R: TRigFuncResult); begin Count(csGetFunc, R.Status); end;
procedure TCounter.OnSplit(const R: TRigSplitResult); begin Count(csGetSplit, R.Status); end;
procedure TCounter.OnVfo(const R: TRigVfoResult);   begin Count(csGetVfo, R.Status); end;

procedure TCounter.OnSetFreq(const R: TRigResult);      begin Count(csSetFreq, R.Status); end;
procedure TCounter.OnSetMode(const R: TRigResult);      begin Count(csSetMode, R.Status); end;
procedure TCounter.OnSetLevelF(const R: TRigResult);    begin Count(csSetLevelF, R.Status); end;
procedure TCounter.OnSetLevelI(const R: TRigResult);    begin Count(csSetLevelI, R.Status); end;
procedure TCounter.OnSetFunc(const R: TRigResult);      begin Count(csSetFunc, R.Status); end;
procedure TCounter.OnSetSplit(const R: TRigResult);     begin Count(csSetSplit, R.Status); end;
procedure TCounter.OnSetSplitFreq(const R: TRigResult); begin Count(csSetSplitFreq, R.Status); end;
procedure TCounter.OnSetVfo(const R: TRigResult);       begin Count(csSetVfo, R.Status); end;

var
  Svc: IRigService;
  Cnt: TCounter;

{ Picks a VFO that is legal as a transmit VFO. rvfoCurr is excluded
  because the component refuses it there, by design.
  送信 VFO として適法な VFO を選びます。rvfoCurr はコンポーネントが
  設計上そこで拒否するため除外します。 }
function RandomTxVfo: TRigVfo;
begin
  case Random(4) of
    0: Result := rvfoA;
    1: Result := rvfoB;
    2: Result := rvfoMain;
  else
    Result := rvfoSub;
  end;
end;

function RandomSettableLevel: TRigLevel;
begin
  case Random(4) of
    0: Result := rlvRfPower;
    1: Result := rlvAf;
    2: Result := rlvMicGain;
  else
    Result := rlvRf;
  end;
end;

{ Issues one randomly chosen command. Returns True when a command was
  actually accepted, so the caller can keep Issued honest.
  乱択した 1 コマンドを発行します。実際に受理された場合のみ True を返し、
  呼び出し側が Issued を正しく保てるようにします。 }
{ Issues exactly one command of the named shape, with the sink that
  counts that shape.
  指定された種類のコマンドをちょうど 1 つ、その種類を数えるシンク付きで
  発行します。 }
procedure IssueShape(ASh: TCmdShape);
begin
  case ASh of
    csSetFreq:      Svc.SetFrequencyAsync(7000000 + Random(7000000),
                                          rvfoCurr, @Cnt.OnSetFreq);
    csGetFreq:      Svc.GetFrequencyAsync(rvfoCurr, @Cnt.OnFreq);
    csSetMode:      Svc.SetModeAsync(rmUSB, 1800 + Random(1200), rvfoCurr,
                                     @Cnt.OnSetMode);
    csGetMode:      Svc.GetModeAsync(rvfoCurr, @Cnt.OnMode);
    csGetLevel:     Svc.GetLevelAsync(rlvStrength, @Cnt.OnLevel);
    csSetLevelF:    Svc.SetLevelFloatAsync(RandomSettableLevel,
                                           Random / 1.0, @Cnt.OnSetLevelF);
    csSetLevelI:    Svc.SetLevelIntAsync(rlvKeySpeed, 5 + Random(50),
                                         @Cnt.OnSetLevelI);
    csGetFunc:      Svc.GetFuncAsync(rfnNoiseBlanker, @Cnt.OnFunc);
    csSetFunc:      Svc.SetFuncAsync(rfnNoiseBlanker, Random(2) = 0,
                                     @Cnt.OnSetFunc);
    csSetSplit:     Svc.SetSplitAsync(True, RandomTxVfo, @Cnt.OnSetSplit);
    csGetSplit:     Svc.GetSplitAsync(@Cnt.OnSplit);
    csSetSplitFreq: Svc.SetSplitFreqAsync(14000000 + Random(300000),
                                          @Cnt.OnSetSplitFreq);
    csSetVfo:       Svc.SetVfoAsync(RandomTxVfo, @Cnt.OnSetVfo);
    csGetVfo:       Svc.GetVfoAsync(@Cnt.OnVfo);
  end;
end;

function IssueRandomCommand: Boolean;
var
  Shape: TCmdShape;
begin
  Result := False;
  try
    Shape := TCmdShape(Random(Ord(High(TCmdShape)) + 1));
    IssueShape(Shape);
    Inc(ShapeIssued[Shape]);
    Result := True;
  except
    { An argument exception here would mean the generator built an
      illegal call, which is the generator's bug, not the component's —
      so it is reported rather than swallowed.
      ここでの引数例外は、生成器が不正な呼び出しを作ったことを意味し、
      それは生成器の不具合でコンポーネントのものではありません。
      したがって握りつぶさず報告します。 }
    on E: EArgumentException do
      Fail('the generator built an illegal call: ' + E.Message);
    on E: ERigServiceClosed do
      ;  { expected in the chaos phase / 混沌フェーズでは想定内 }
    on E: Exception do
      Fail('I1 violated: ' + E.ClassName + ': ' + E.Message);
  end;
end;

{ Waits until the queue is empty AND no further callback has arrived,
  rather than sleeping a guessed amount.

  The first version of this test slept four seconds and then asserted
  that everything had been delivered. 862 commands were still queued,
  so it reported 863 'lost' callbacks that were merely late — and
  worse, those callbacks then arrived during the next phase and were
  counted there, which made that phase report callbacks it had never
  issued. A drain condition expressed as a duration measures the
  machine; expressed as a state, it measures the component.

  キューが空になり、かつそれ以上コールバックが届かなくなるまで待ちます。
  当て推量の sleep ではありません。

  本テストの最初の版は 4 秒 sleep してからすべて配送済みと主張していま
  した。実際には 862 コマンドがまだキューにあり、単に遅れていただけの
  コールバック 863 件を「消失」と報告しました。さらに悪いことに、それら
  は次のフェーズ中に届いてそちらで計上され、そのフェーズに「発行して
  いないコールバックを受け取った」と報告させました。掃き出し条件を時間で
  表すと測るのはマシンであり、状態で表すと測るのはコンポーネントです。 }
procedure Drain;
var
  Quiet, Before: Integer;
begin
  Quiet := 0;
  while Quiet < 40 do
  begin
    Before := Delivered;
    Pump(100);
    if (Svc.QueueDepth = 0) and (Delivered = Before) then
      Inc(Quiet)
    else
      Quiet := 0;
  end;
end;

{ Checks the invariants that must hold at every moment.
  常時成り立たねばならない不変条件を検査します。 }
procedure CheckContinuousInvariants;
var
  St: TRigState;
  D:  Integer;
begin
  D := Svc.QueueDepth;
  if D < 0 then
    Fail(Format('I4 violated: QueueDepth = %d', [D]));

  St := Svc.CurrentState;
  if St.Connected <> Svc.IsOpen then
    Fail(Format('I5 violated: Connected=%s IsOpen=%s',
                [BoolToStr(St.Connected, True),
                 BoolToStr(Svc.IsOpen, True)]));

  { Timestamp = 0 is documented as "no data has been collected yet",
    and Close resets the snapshot to exactly that. So zero is a
    re-baseline, not a backwards step; only a decrease between two
    non-zero readings would mean the clock had gone back.

    The first version of this check treated the reset as a violation
    and then, because it kept the old high-water mark, reported every
    subsequent reading as a violation too — 233 failures from one
    mis-stated invariant. An invariant that has not been stated
    precisely does not test the component, it tests the wording.

    Timestamp = 0 は「まだデータ未収集」と文書化されており、Close は
    スナップショットをまさにその状態に戻します。したがって 0 は基準の
    取り直しであって後退ではありません。後退を意味するのは、非零の
    2 つの読み値の間での減少だけです。

    本検査の最初の版はリセットを違反と見なし、さらに古い最高値を保持し
    続けたため、以降のすべての読み値も違反として報告しました。1 つの
    不正確な不変条件から 233 件の失敗です。精密に述べられていない不変
    条件が検査するのはコンポーネントではなく、その文言です。 }
  if St.Timestamp = 0 then
    LastStamp := 0
  else if St.Timestamp < LastStamp then
    Fail(Format('I6 violated: timestamp went backwards, %d -> %d',
                [LastStamp, St.Timestamp]))
  else
    LastStamp := St.Timestamp;
end;

{ ------------------------------------------------------------------
  Phase 1 — commands only. Here I2 is exact: nothing cancels, nothing
  closes, so every accepted command must deliver exactly one callback.
  フェーズ 1 — コマンドのみ。ここでは I2 が厳密です。キャンセルも
  クローズもないため、受理された全コマンドはコールバックをちょうど
  1 回配送しなければなりません。
  ------------------------------------------------------------------ }
{ Prints the per-shape ledger and fails any shape that does not
  balance, naming it.
  種類ごとの収支を表示し、合わない種類を名指しして失敗させます。 }
procedure ReportShapes(const AWhat: string);
var
  Sh: TCmdShape;
  Bad: Integer;
begin
  Bad := 0;
  for Sh := Low(TCmdShape) to High(TCmdShape) do
    if ShapeIssued[Sh] <> ShapeDelivered[Sh] then
    begin
      Inc(Bad);
      Fail(Format('%s: %s issued %d but delivered %d',
                  [AWhat, SHAPE_NAME[Sh], ShapeIssued[Sh],
                   ShapeDelivered[Sh]]));
    end;
  if Bad = 0 then
  begin
    Inc(Passed);
    WriteLn('    [ok]   ', AWhat,
            ': all 14 command shapes balanced individually');
  end;
end;

procedure PhaseCommandsOnly;
var
  i: Integer;
begin
  ResetShapeCounts;
  WriteLn;
  WriteLn('PHASE 1 — ', Iterations, ' random commands, nothing else');

  Issued    := 0;
  Delivered := 0;
  LastStamp := 0;

  for i := 1 to Iterations do
  begin
    if IssueRandomCommand then
      Inc(Issued);
    if (i mod 7) = 0 then
      CheckContinuousInvariants;
    if (i mod 20) = 0 then
      Pump(20);
  end;

  Drain;

  WriteLn(Format('    issued %d, delivered %d', [Issued, Delivered]));
  ReportShapes('I2 per shape');
  Check('I2: every accepted command delivered exactly one callback',
        Delivered = Issued,
        Format('%d issued, %d delivered — %d %s', [Issued, Delivered,
               Abs(Issued - Delivered),
               BoolToStr(Delivered < Issued, 'lost', 'duplicated')]));
  Check('I3: the queue drained', Svc.QueueDepth = 0,
        Format('%d still queued', [Svc.QueueDepth]));
  Check('the circuit breaker stayed closed under a clean burst',
        not Svc.CircuitBreakerOpen);
end;

{ ------------------------------------------------------------------
  Phase 1b — cancellation accounting, per shape.

  A cancelled command must still report. The component's contract is
  that cancellation changes the Status to rcsCancelled, not that the
  result disappears: an application waiting on a call it cancelled is
  still waiting for an answer, and silence leaves it waiting forever.

  This is checked shape by shape because the failure it guards against
  is shape-specific — a cancellation path that knows only the command
  shapes that existed when it was written will lose exactly the newer
  ones, and a total would hide that behind the shapes that still work.

  フェーズ 1b — 種類ごとのキャンセル会計。

  キャンセルされたコマンドも報告しなければなりません。コンポーネントの
  契約は「Status が rcsCancelled に変わる」ことであって「結果が消える」
  ことではありません。自分がキャンセルした呼び出しを待っている
  アプリケーションは、依然として答えを待っており、沈黙はそれを永久に
  待たせます。

  種類ごとに検査するのは、防ごうとしている失敗が種類に固有だからです。
  書かれた時点のコマンド種類しか知らないキャンセル経路は、まさに新しい
  種類だけを失います。合計では、まだ動く種類の陰に隠れてしまいます。
  ------------------------------------------------------------------ }
procedure PhaseCancelAccounting(APerShape: Integer);
var
  Sh: TCmdShape;
  i:  Integer;
begin
  WriteLn;
  WriteLn('PHASE 1b — ', APerShape,
          ' of each command shape, all cancelled before they can run');

  ResetShapeCounts;
  Issued        := 0;
  Delivered     := 0;
  CancelledSeen := 0;

  for Sh := Low(TCmdShape) to High(TCmdShape) do
    for i := 1 to APerShape do
    begin
      IssueShape(Sh);
      Inc(ShapeIssued[Sh]);
      Inc(Issued);
    end;

  { Cancelled immediately, with nothing pumped in between, so as many
    as possible are still queued rather than already executed.
    間に何も pump せず即座にキャンセルします。できるだけ多くが実行済み
    ではなくキュー上に残っている状態にするためです。 }
  Svc.CancelAllPending;
  Drain;

  WriteLn(Format('    issued %d, delivered %d', [Issued, Delivered]));
  ReportShapes('cancelled commands still report, per shape');
  Check('every cancelled command reported', Delivered = Issued,
        Format('%d issued, %d delivered', [Issued, Delivered]));

  WriteLn(Format('    %d of the %d results came back as rcsCancelled',
                 [CancelledSeen, Delivered]));
  Check('and the cancel actually caught commands in the queue',
        CancelledSeen > 0,
        'every command finished before the cancel landed — this phase '
        + 'proved nothing, raise the count per shape');
end;

{ ------------------------------------------------------------------
  Phase 2 — chaos. Cancels, polling toggles and Close/Open are mixed
  in. I2 becomes an inequality: a cancelled command still reports, but
  a command issued to a Service that closes underneath it may not, and
  that is the documented behaviour rather than a lost result.

  フェーズ 2 — 混沌。キャンセル、ポーリング切り替え、Close/Open を
  混ぜます。I2 は不等式になります。キャンセルされたコマンドも報告は
  しますが、足元で Close された Service に発行したコマンドは報告しない
  ことがあり、それは結果の消失ではなく文書化された動作です。
  ------------------------------------------------------------------ }
procedure PhaseChaos;
var
  i:      Integer;
  Reopen: Integer;
begin
  WriteLn;
  WriteLn('PHASE 2 — ', Iterations, ' operations with cancels, polling '
          + 'toggles and Close/Open mixed in');

  Issued    := 0;
  Delivered := 0;
  LastStamp := 0;
  Reopen    := 0;

  for i := 1 to Iterations do
  begin
    case Random(100) of
      0..74:
        if Svc.IsOpen and IssueRandomCommand then
          Inc(Issued);
      75..84:
        Svc.CancelAllPending;
      85..90:
        if Random(2) = 0 then
          Svc.EnablePolling(50 + Random(200))
        else
          Svc.DisablePolling;
      91..94:
        if Svc.IsOpen then
        begin
          Svc.Close;
          Inc(Reopen);
        end;
    else
      if not Svc.IsOpen then
      try
        Svc.Open(MODEL_DUMMY, '');
      except
        on E: Exception do
          Fail('reopening failed: ' + E.ClassName + ': ' + E.Message);
      end;
    end;

    if (i mod 5) = 0 then
      CheckContinuousInvariants;
    if (i mod 15) = 0 then
      Pump(15);
  end;

  Svc.DisablePolling;
  if not Svc.IsOpen then
    Svc.Open(MODEL_DUMMY, '');
  Drain;

  WriteLn(Format('    issued %d, delivered %d, closed mid-run %d times',
                 [Issued, Delivered, Reopen]));
  Check('I2 (weak): no callback was delivered that was never issued',
        Delivered <= Issued,
        Format('%d delivered > %d issued — a duplicate callback',
               [Delivered, Issued]));
  Check('I3: the queue drained after the chaos', Svc.QueueDepth = 0,
        Format('%d still queued', [Svc.QueueDepth]));
  Check('I5: the service is consistent at the end',
        Svc.CurrentState.Connected = Svc.IsOpen);
end;

{ ------------------------------------------------------------------
  Main
  ------------------------------------------------------------------ }
var
  Factory: IRigServiceFactory;

begin
  if ParamCount >= 1 then
    Seed := StrToIntDef(ParamStr(1), 0)
  else
    Seed := 20261018;
  if ParamCount >= 2 then
    Iterations := StrToIntDef(ParamStr(2), 1500)
  else
    Iterations := 1500;

  RandSeed := Seed;

  WriteLn('RandomSequenceTest — invariants under generated call orders');
  WriteLn('==========================================================');
  WriteLn('    seed ', Seed, ', ', Iterations,
          ' iterations per phase (re-run with the same seed to '
          + 'reproduce exactly)');

  Factory := TRigServiceFactory.Create;
  Svc     := Factory.CreateService;
  Cnt     := TCounter.Create;
  try
    Svc.ApplyTimeoutPolicy(RigPolicy_FastUsb);
    Svc.Open(MODEL_DUMMY, '');
    Check('the dummy rig opened', Svc.IsOpen);

    PhaseCommandsOnly;
    PhaseCancelAccounting(12);
    PhaseChaos;

    if Svc.IsOpen then
      Svc.Close;
    Check('the rig closed cleanly at the end', not Svc.IsOpen);
  finally
    Cnt.Free;
    Svc     := nil;
    Factory := nil;
  end;

  WriteLn;
  WriteLn(Format('--- %d / %d checks passed ---', [Passed, Passed + Failed]));
  if Failed = 0 then
  begin
    WriteLn('RESULT: OK');
    ExitCode := 0;
  end
  else
  begin
    WriteLn(Format('RESULT: %d FAILED  (reproduce with: '
                   + 'RandomSequenceTest %d %d)',
                   [Failed, Seed, Iterations]));
    ExitCode := 1;
  end;
end.
