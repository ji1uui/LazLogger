{
  StressTest.lpr

  Sustained churn, with the heap measured as it goes. Where
  RandomSequenceTest asks "does any order break an invariant", this
  asks "does anything grow".

  持続的な酷使と、その最中の heap 測定。RandomSequenceTest が「ある順序が
  不変条件を破るか」を問うのに対し、本テストは「何かが増え続けるか」を
  問います。

  Why a separate test / 別テストにする理由
  ------------------------------------------------------------------
  A leak of one object per cycle is invisible in any test that runs a
  few cycles, and heaptrc's end-of-run total cannot distinguish "leaked
  200 objects" from "still holds 200 objects it will free at exit".
  Sampling the heap at intervals and comparing the samples can: a leak
  shows as a line with a slope, a cache shows as a line that flattens.

  1 サイクルにつき 1 オブジェクトの漏れは、数サイクルしか回さないテスト
  からは見えません。また heaptrc の終了時合計は「200 個漏らした」と
  「終了時に解放する 200 個をまだ保持している」を区別できません。一定間隔
  で heap を標本化して比較すればできます。漏れは傾きのある直線として、
  キャッシュは寝ていく直線として現れます。

  Build:
    fpc -Mobjfpc -Sh -Sa -Criot -gh -Fu../src -FE. StressTest.lpr
}
program StressTest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  HamlibInterfaces, HamlibErrors, HamlibTimeoutPolicy,
  HamlibService, HamlibFactory;

const
  MODEL_DUMMY = 1;

var
  Passed: Integer = 0;
  Failed: Integer = 0;
  Delivered: Int64 = 0;

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
  for i := 1 to AMs div 5 do
  begin
    CheckSynchronize(2);
    Sleep(3);
  end;
end;

type
  TSink = class
    procedure OnCommand(const R: TRigResult);
    procedure OnFreq(const R: TRigFreqResult);
  end;

procedure TSink.OnCommand(const R: TRigResult);  begin Inc(Delivered); end;
procedure TSink.OnFreq(const R: TRigFreqResult); begin Inc(Delivered); end;

var
  Sink: TSink;

{ Bytes currently allocated. The difference between two samples is what
  matters; the absolute figure includes whatever the RTL holds.
  現在の確保バイト数。意味を持つのは 2 標本の差であり、絶対値には RTL が
  保持する分も含まれます。 }
function HeapUsed: PtrUInt;
begin
  Result := GetFPCHeapStatus.CurrHeapUsed;
end;

{ ------------------------------------------------------------------
  1. Service churn — create, open, work, close, destroy, repeatedly.
     This is the shape of an application that reconnects on every
     failure, which is what an application with a flaky USB cable
     does all day.
     サービスの反復 — 生成、接続、作業、切断、破棄の繰り返し。失敗の
     たびに再接続するアプリケーションの形であり、USB ケーブルが不安定な
     環境のアプリが一日中していることです。
  ------------------------------------------------------------------ }
procedure CaseServiceChurn(ACycles: Integer);
var
  Factory: IRigServiceFactory;
  Svc:     IRigService;
  i, j:    Integer;
  Base, Now_, Growth: PtrUInt;
begin
  WriteLn;
  WriteLn('CHURN — ', ACycles, ' create/open/work/close/destroy cycles');

  Factory := TRigServiceFactory.Create;
  Base    := 0;

  for i := 1 to ACycles do
  begin
    Svc := Factory.CreateService;
    Svc.ApplyTimeoutPolicy(RigPolicy_FastUsb);
    Svc.Open(MODEL_DUMMY, '');
    Svc.EnablePolling(50);
    for j := 1 to 10 do
    begin
      Svc.GetFrequencyAsync(rvfoCurr, @Sink.OnFreq);
      Svc.SetFrequencyAsync(14000000 + j * 1000, rvfoCurr, @Sink.OnCommand);
    end;
    Pump(40);
    Svc.Close;
    Svc := nil;
    Pump(40);

    { The first few cycles warm caches, so the baseline is taken after
      them rather than at zero — otherwise start-up cost would be read
      as a leak.
      最初の数サイクルはキャッシュを温めるため、基準は 0 ではなくその後
      で取ります。さもないと起動時の確保を漏れと読んでしまいます。 }
    if i = 10 then
      Base := HeapUsed;
  end;

  Pump(500);
  Now_ := HeapUsed;
  if Now_ > Base then
    Growth := Now_ - Base
  else
    Growth := 0;

  WriteLn(Format('    heap after cycle 10: %d bytes, at the end: %d '
                 + '(growth %d over %d cycles)',
                 [Base, Now_, Growth, ACycles - 10]));
  Check('the heap did not grow with the number of service lifecycles',
        Growth < 64 * 1024,
        Format('%d bytes of growth across %d cycles', [Growth, ACycles - 10]));
end;

{ ------------------------------------------------------------------
  2. Cancel storm — commands posted and immediately abandoned.
     キャンセル嵐 — 投稿して即座に放棄されるコマンド。
  ------------------------------------------------------------------ }
procedure CaseCancelStorm(ARounds, APerRound: Integer);
var
  Factory: IRigServiceFactory;
  Svc:     IRigService;
  i, j:    Integer;
  Base, Now_, Growth: PtrUInt;
  Issued:  Int64;
begin
  WriteLn;
  WriteLn('CANCEL STORM — ', ARounds, ' rounds of ', APerRound,
          ' commands, each round cancelled');

  Factory   := TRigServiceFactory.Create;
  Svc       := Factory.CreateService;
  Svc.ApplyTimeoutPolicy(RigPolicy_FastUsb);
  Svc.Open(MODEL_DUMMY, '');
  Delivered := 0;
  Issued    := 0;
  Base      := 0;

  for i := 1 to ARounds do
  begin
    for j := 1 to APerRound do
    begin
      Svc.GetFrequencyAsync(rvfoCurr, @Sink.OnFreq);
      Inc(Issued);
    end;
    Svc.CancelAllPending;
    Pump(30);
    if i = 5 then
      Base := HeapUsed;
  end;

  { Everything must still report, cancelled or not. A cancelled command
    that reports nothing leaves its caller waiting forever.
    キャンセルの有無にかかわらず、すべてが報告しなければなりません。
    何も報告しないキャンセル済みコマンドは、呼び出し側を永久に待たせます。 }
  Pump(3000);
  Now_ := HeapUsed;
  if Now_ > Base then Growth := Now_ - Base else Growth := 0;

  WriteLn(Format('    issued %d, delivered %d, heap growth %d bytes',
                 [Issued, Delivered, Growth]));
  Check('every command reported, cancelled or not', Delivered = Issued,
        Format('%d issued, %d delivered', [Issued, Delivered]));
  Check('the queue drained', Svc.QueueDepth = 0,
        Format('%d left', [Svc.QueueDepth]));
  Check('cancelling did not grow the heap', Growth < 64 * 1024,
        Format('%d bytes', [Growth]));

  Svc.Close;
  Svc := nil;
end;

{ ------------------------------------------------------------------
  3. Deep queue — more commands than the worker can execute promptly,
     to find out what the component does when it is behind.
     深いキュー — ワーカーが直ちに実行できる以上のコマンドを積み、
     遅れているときの振る舞いを調べます。
  ------------------------------------------------------------------ }
procedure CaseDeepQueue(ACount: Integer);
var
  Factory: IRigServiceFactory;
  Svc:     IRigService;
  i:       Integer;
  Peak:    Integer;
  Issued:  Int64;
  Quiet, Before: Integer;
begin
  WriteLn;
  WriteLn('DEEP QUEUE — ', ACount, ' commands posted without pumping');

  Factory   := TRigServiceFactory.Create;
  Svc       := Factory.CreateService;
  Svc.ApplyTimeoutPolicy(RigPolicy_FastUsb);
  Svc.Open(MODEL_DUMMY, '');
  Delivered := 0;
  Issued    := 0;
  Peak      := 0;

  for i := 1 to ACount do
  begin
    Svc.GetFrequencyAsync(rvfoCurr, @Sink.OnFreq);
    Inc(Issued);
    if Svc.QueueDepth > Peak then
      Peak := Svc.QueueDepth;
  end;

  WriteLn(Format('    peak queue depth %d', [Peak]));
  Check('the queue depth was reported honestly while filling',
        Peak > 0, 'the queue never reported a backlog');

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

  WriteLn(Format('    issued %d, delivered %d', [Issued, Delivered]));
  Check('a deep queue drains completely', Delivered = Issued,
        Format('%d issued, %d delivered', [Issued, Delivered]));
  Check('and the breaker did not trip on a backlog',
        not Svc.CircuitBreakerOpen,
        'a slow queue was mistaken for a failing rig');

  Svc.Close;
  Svc := nil;
end;

{ ------------------------------------------------------------------
  4. Polling toggles under load — the path that hid a use-after-free.
     負荷下でのポーリング切り替え — use-after-free が潜んでいた経路。
  ------------------------------------------------------------------ }
procedure CasePollingToggle(ARounds: Integer);
var
  Factory: IRigServiceFactory;
  Svc:     IRigService;
  i, j:    Integer;
  Base, Now_, Growth: PtrUInt;
begin
  WriteLn;
  WriteLn('POLLING TOGGLE — ', ARounds,
          ' rounds of enable/commands/disable with results in flight');

  Factory := TRigServiceFactory.Create;
  Svc     := Factory.CreateService;
  Svc.ApplyTimeoutPolicy(RigPolicy_FastUsb);
  Svc.Open(MODEL_DUMMY, '');
  Base := 0;

  for i := 1 to ARounds do
  begin
    Svc.EnablePolling(50);
    for j := 1 to 8 do
      Svc.GetFrequencyAsync(rvfoCurr, @Sink.OnFreq);
    CheckSynchronize(1);          { deliver some, leave the rest queued }
    Svc.DisablePolling;           { frees the poller thread mid-flight }
    Pump(20);
    if i = 10 then
      Base := HeapUsed;
  end;

  Pump(1500);
  Now_ := HeapUsed;
  if Now_ > Base then Growth := Now_ - Base else Growth := 0;

  WriteLn(Format('    heap growth across %d toggles: %d bytes',
                 [ARounds - 10, Growth]));
  Check('toggling polling with results in flight is survivable', True);
  Check('and does not grow the heap', Growth < 64 * 1024,
        Format('%d bytes', [Growth]));

  Svc.Close;
  Svc := nil;
end;

{ ------------------------------------------------------------------
  Main
  ------------------------------------------------------------------ }
begin
  WriteLn('StressTest — sustained churn, with the heap watched');
  WriteLn('==================================================');

  Sink := TSink.Create;
  try
    CaseServiceChurn(120);
    CaseCancelStorm(60, 40);
    CaseDeepQueue(4000);
    CasePollingToggle(120);
  finally
    Sink.Free;
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
    WriteLn(Format('RESULT: %d FAILED', [Failed]));
    ExitCode := 1;
  end;
end.
