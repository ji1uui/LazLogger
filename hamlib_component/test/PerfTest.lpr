{
  PerfTest.lpr

  Measures the two queue optimisations:
    P2-5  TThreadList dupIgnore -> dupAccept  (Enqueue was O(n))
    P2-6  Dequeue lost-wakeup   -> reset before peek (latency)

  2 つのキュー最適化を測定します:
    P2-5  TThreadList dupIgnore → dupAccept (Enqueue が O(n) だった)
    P2-6  Dequeue のロストウェイクアップ → 覗き見前にリセット (遅延)

  Build: fpc -Mobjfpc -Sh -O2 -Fu../src -FE. PerfTest.lpr
}
program PerfTest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils, DateUtils,
  HamlibInterfaces, HamlibCancellation, HamlibCommandBase,
  HamlibCommandQueue, HamlibFreqCommands;

{ --------------------------------------------------------------
  Part 1 — enqueue throughput with a deep queue
  パート 1 — 深いキューでの Enqueue スループット
  -------------------------------------------------------------- }
procedure MeasureEnqueue(ACount: Integer);
var
  Q:     TCommandQueue;
  i:     Integer;
  T0:    TDateTime;
  Ms:    Int64;
  Cmd:   TRigCommand;
  Drain: TList;
begin
  Q     := TCommandQueue.Create;
  Drain := TList.Create;
  try
    T0 := Now;
    for i := 1 to ACount do
      Q.Enqueue(TSetFreqCommand.Create(rvfoA, 14074000.0 + i,
                                       TRigCancellationToken.Create, nil));
    Ms := MilliSecondsBetween(Now, T0);
    WriteLn(Format('  enqueue %5d commands : %4d ms', [ACount, Ms]));

    { tidy up / 後始末 }
    Q.DrainAll(Drain);
    for i := 0 to Drain.Count - 1 do
    begin
      Cmd := TRigCommand(Drain[i]);
      Cmd.Free;
    end;
  finally
    Drain.Free;
    Q.Free;
  end;
end;

{ --------------------------------------------------------------
  Part 2 — wake-up latency for an item enqueued just before the wait
  パート 2 — 待機直前に投入された項目の起床遅延
  -------------------------------------------------------------- }
type
  TProducer = class(TThread)
  private
    FQueue: TCommandQueue;
    FDelay: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AQueue: TCommandQueue; ADelayMs: Integer);
  end;

constructor TProducer.Create(AQueue: TCommandQueue; ADelayMs: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FQueue := AQueue;
  FDelay := ADelayMs;
end;

procedure TProducer.Execute;
begin
  Sleep(FDelay);
  FQueue.Enqueue(TSetFreqCommand.Create(rvfoA, 7074000.0,
                                        TRigCancellationToken.Create, nil));
end;

procedure MeasureWakeLatency(ARounds: Integer);
var
  Q:       TCommandQueue;
  P:       TProducer;
  Cmd:     TRigCommand;
  r:       Integer;
  T0:      TDateTime;
  Ms, Tot: Int64;
  Worst:   Int64;
begin
  Tot   := 0;
  Worst := 0;
  for r := 1 to ARounds do
  begin
    Q := TCommandQueue.Create;
    P := TProducer.Create(Q, 0);    { fire immediately: aim at the
                                        unlock..reset race window }
    try
      P.Start;
      T0  := Now;
      Cmd := Q.Dequeue(100);        { same timeout the Worker uses }
      Ms  := MilliSecondsBetween(Now, T0);
      Inc(Tot, Ms);
      if Ms > Worst then Worst := Ms;
      if Assigned(Cmd) then Cmd.Free;
      P.WaitFor;
    finally
      P.Free;
      Q.Free;
    end;
  end;
  WriteLn(Format('  dequeue wake latency  : avg %3d ms, worst %3d ms (over %d rounds)',
    [Tot div ARounds, Worst, ARounds]));
  WriteLn('    (producer fires immediately; worst ~100 ms means a signal was');
  WriteLn('     lost in the unlock..reset window and the full timeout elapsed)');
end;

begin
  WriteLn('=== Command queue performance ===');
  WriteLn;
  MeasureEnqueue(2000);
  MeasureEnqueue(8000);
  WriteLn;
  MeasureWakeLatency(300);
  WriteLn;
  WriteLn('=== Done ===');
end.
