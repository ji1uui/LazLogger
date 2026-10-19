unit Muninn.App.Prototype;

{ Demo data and response-time measurements for the UI prototype (T10,
  ADR 0009). The measurements drive the real window: they type into the
  callsign field and wait until the band map has been painted again. }

{$mode objfpc}{$H+}

interface

uses
  Classes, Muninn.UI.MainForm;

{ Fills the band map with ASpots spots between 7.000 and 7.040 MHz, gives
  the partial check AKnownCalls calls, and tunes to 7.010 MHz. Always the
  same data. }
procedure LoadDemoData(const AForm: TMainForm; const ASpots, AKnownCalls: Integer);

{ Runs every measurement, writes the report to AOutput (and stdout), and
  returns False when a paint was not seen in time. AStartedUs is when the
  program started (MicroTicks). }
function RunMeasurements(const AForm: TMainForm; const AOutput: string;
  const AStartedUs: Int64): Boolean;

implementation

uses
  SysUtils, Math, Forms, InterfaceBase, LCLPlatformDef, Muninn.Core.Frequency,
  Muninn.UI.Bandmap, Muninn.UI.Clock;

const
  Prefixes: array[0..29] of string = ('JA', 'JH', 'JR', 'JE', 'JF', 'JG', 'JI',
    'JJ', 'JK', 'JL', 'JM', 'JN', 'JO', 'JP', 'JQ', '7K', '7L', '7M', '7N', '8J',
    'K', 'W', 'N', 'DL', 'G', 'F', 'VK', 'BV', 'HL', 'UA');
  PaintTimeoutUs = 2000000;

type
  TSamples = array of Int64;

var
  Report: TStringList;
  PaintTimedOut: Boolean;

function RandomCall: string;
var
  Index: Integer;
begin
  Result := Prefixes[Random(Length(Prefixes))] + IntToStr(Random(10));
  for Index := 1 to 2 + Random(2) do
    Result := Result + Chr(Ord('A') + Random(26));
end;

procedure FillSpots(const AForm: TMainForm; const ACount: Integer);
var
  Index: Integer;
  Spot: TBandmapSpot;
begin
  AForm.BandmapModel.Clear;
  for Index := 1 to ACount do
  begin
    Spot := Default(TBandmapSpot);
    Spot.Call := RandomCall;
    if not TFrequencyHz.TryFromHz(7000000 + Random(40000), Spot.Frequency) then
      raise EInvalidOperation.Create('demo frequency out of range');
    Spot.Worked := Random(4) = 0;
    AForm.BandmapModel.AddSpot(Spot);
  end;
end;

procedure FillKnownCalls(const AForm: TMainForm; const ACount: Integer);
var
  Calls: TStringList;
  Index: Integer;
begin
  Calls := TStringList.Create;
  try
    Calls.Capacity := ACount;
    for Index := 1 to ACount do
      Calls.Add(RandomCall);
    AForm.Presenter.SetKnownCalls(Calls);
  finally
    Calls.Free;
  end;
end;

procedure LoadDemoData(const AForm: TMainForm; const ASpots, AKnownCalls: Integer);
var
  Index: Integer;
begin
  RandSeed := 20261019;
  FillSpots(AForm, ASpots);
  FillKnownCalls(AForm, AKnownCalls);
  AForm.Tune(7010000);
  { A few QSOs, so the log and the duplicate check have something to show. }
  for Index := 0 to 2 do
  begin
    AForm.CallEdit.Text := AForm.BandmapModel.Spots[Index * 5].Call;
    AForm.Presenter.LogRequested('599', '599');
  end;
end;

{ Measurement helpers }

procedure Emit(const ALine: string);
begin
  Report.Add(ALine);
  { A Windows GUI program has no console to write to. }
  if IsConsole then
    WriteLn(ALine);
end;

function Percentile(const ASorted: TSamples; const AFraction: Double): Int64;
begin
  Result := ASorted[Min(High(ASorted), Floor(AFraction * Length(ASorted)))];
end;

procedure SortSamples(var ASamples: TSamples);
var
  I, J: Integer;
  Value: Int64;
begin
  for I := 1 to High(ASamples) do
  begin
    Value := ASamples[I];
    J := I - 1;
    while (J >= 0) and (ASamples[J] > Value) do
    begin
      ASamples[J + 1] := ASamples[J];
      Dec(J);
    end;
    ASamples[J + 1] := Value;
  end;
end;

function Ms(const AUs: Int64): string;
begin
  Result := FormatFloat('0.00', AUs / 1000);
end;

procedure EmitSamples(const AName: string; ASamples: TSamples);
begin
  if Length(ASamples) = 0 then
  begin
    Emit(Format('%-34s %6d %9s %9s %9s', [AName, 0, '-', '-', '-']));
    Exit;
  end;
  SortSamples(ASamples);
  Emit(Format('%-34s %6d %9s %9s %9s', [AName, Length(ASamples),
    Ms(Percentile(ASamples, 0.5)), Ms(Percentile(ASamples, 0.95)),
    Ms(ASamples[High(ASamples)])]));
end;

procedure Add(var ASamples: TSamples; const AValue: Int64);
begin
  SetLength(ASamples, Length(ASamples) + 1);
  ASamples[High(ASamples)] := AValue;
end;

{ Processes messages until the band map has painted more than APaintCount
  times. Returns the time waited, or -1 after the timeout. }
function WaitForPaint(const AForm: TMainForm; const APaintCount: Integer;
  const AStartedUs: Int64): Int64;
begin
  repeat
    Application.ProcessMessages;
    if AForm.Bandmap.PaintCount > APaintCount then
      Exit(MicroTicks - AStartedUs);
  until MicroTicks - AStartedUs > PaintTimeoutUs;
  PaintTimedOut := True;
  Result := -1;
end;

procedure MeasureTyping(const AForm: TMainForm);
const
  Rounds = 20;
var
  Handler, ToPaint: TSamples;
  Round, Index, Count: Integer;
  Call: string;
  Started, Waited: Int64;
begin
  Handler := nil;
  ToPaint := nil;
  for Round := 1 to Rounds do
  begin
    AForm.ClearEntry;
    { Settle: the field may have been empty already, so force a paint. }
    AForm.Bandmap.Invalidate;
    WaitForPaint(AForm, AForm.Bandmap.PaintCount, MicroTicks);
    Call := RandomCall;
    for Index := 1 to Length(Call) do
    begin
      Count := AForm.Bandmap.PaintCount;
      Started := MicroTicks;
      AForm.CallEdit.SelStart := Length(AForm.CallEdit.Text);
      AForm.CallEdit.SelText := Call[Index];
      Add(Handler, MicroTicks - Started);
      Waited := WaitForPaint(AForm, Count, Started);
      if Waited >= 0 then
        Add(ToPaint, Waited);
    end;
  end;
  EmitSamples('keystroke: handler', Handler);
  EmitSamples('keystroke: to band map painted', ToPaint);
end;

procedure MeasureBandmap(const AForm: TMainForm; const ASpots: Integer);
const
  Rounds = 30;
var
  Paint, ToPaint: TSamples;
  Round, Count: Integer;
  Started, Waited: Int64;
begin
  FillSpots(AForm, ASpots);
  Paint := nil;
  ToPaint := nil;
  for Round := 1 to Rounds do
  begin
    Count := AForm.Bandmap.PaintCount;
    Started := MicroTicks;
    AForm.Bandmap.Invalidate;
    Waited := WaitForPaint(AForm, Count, Started);
    if Waited >= 0 then
    begin
      Add(ToPaint, Waited);
      Add(Paint, AForm.Bandmap.LastPaintUs);
    end;
  end;
  EmitSamples(Format('band map %d spots: paint', [ASpots]), Paint);
  EmitSamples(Format('band map %d spots: to painted', [ASpots]), ToPaint);
end;

procedure MeasurePartialCheck(const AForm: TMainForm; const AKnown: Integer);
const
  Texts: array[0..5] of string = ('JA', 'JA1', 'JA1A', '1AB', '7K', 'DL1');
var
  Samples: TSamples;
  Round, Index: Integer;
  Started: Int64;
begin
  FillKnownCalls(AForm, AKnown);
  Samples := nil;
  for Round := 1 to 5 do
    for Index := 0 to High(Texts) do
    begin
      Started := MicroTicks;
      AForm.CallEdit.Text := Texts[Index];
      Add(Samples, MicroTicks - Started);
      Application.ProcessMessages;
    end;
  EmitSamples(Format('partial check %d calls: handler', [AKnown]), Samples);
end;

procedure MeasureLogging(const AForm: TMainForm);
const
  Rounds = 50;
var
  Samples: TSamples;
  Round: Integer;
  Started: Int64;
begin
  Samples := nil;
  for Round := 1 to Rounds do
  begin
    AForm.CallEdit.Text := RandomCall;
    Application.ProcessMessages;
    Started := MicroTicks;
    if AForm.Presenter.LogRequested('599', '599') then
      Add(Samples, MicroTicks - Started);
    Application.ProcessMessages;
  end;
  EmitSamples('log QSO (Enter): handler', Samples);
end;

function RunMeasurements(const AForm: TMainForm; const AOutput: string;
  const AStartedUs: Int64): Boolean;
var
  Startup: Int64;
begin
  Report := TStringList.Create;
  try
    PaintTimedOut := False;
    Startup := WaitForPaint(AForm, 0, AStartedUs);
    Emit(Format('MuninnLog UI prototype measurements (%s-%s, %s, %d dpi, FPC %s)',
      [{$I %FPCTARGETCPU%}, {$I %FPCTARGETOS%},
       LCLPlatformDisplayNames[WidgetSet.LCLPlatform], Screen.PixelsPerInch,
       {$I %FPCVERSION%}]));
    Emit(Format('%-34s %6s %9s %9s %9s', ['metric (ms)', 'n', 'median', 'p95', 'max']));
    if Startup >= 0 then
      Emit(Format('%-34s %6d %9s %9s %9s', ['startup: to first paint', 1,
        Ms(Startup), Ms(Startup), Ms(Startup)]))
    else
      Emit('startup: no paint within the timeout');
    MeasureTyping(AForm);
    MeasureBandmap(AForm, 100);
    MeasureBandmap(AForm, 1000);
    MeasureBandmap(AForm, 5000);
    MeasurePartialCheck(AForm, 10000);
    MeasurePartialCheck(AForm, 100000);
    MeasureLogging(AForm);
    if PaintTimedOut then
      Emit('WARNING: some paints were not seen within 2 s');
    if AOutput <> '' then
      Report.SaveToFile(AOutput);
    Result := not PaintTimedOut;
  finally
    FreeAndNil(Report);
  end;
end;

end.
