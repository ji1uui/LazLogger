unit Muninn.UI.Bandmap.Tests;

{$mode objfpc}{$H+}

interface

uses
  fpcunit, testregistry, Muninn.Core.Frequency, Muninn.UI.Bandmap;

type
  TBandmapModelTests = class(TTestCase)
  private
    FModel: TBandmapModel;
    procedure Add(const ACall: string; const AHz: Int64);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure MapsFrequencyToY;
    procedure SortsSpotsByFrequency;
    procedure MovesARespottedCall;
    procedure PushesOverlappingLabelsDown;
    procedure KeepsTheFirstLabelBelowTheTop;
    procedure SortsManySpots;
    procedure LeavesOutSpotsOutOfRange;
    procedure FindsTheSpotUnderTheMouse;
    procedure ZoomKeepsThePointUnderTheMouse;
    procedure ZoomStaysWithinLimits;
    procedure RefusesAnEmptyRange;
    procedure HighlightsMatchingCalls;
    procedure MarksWorkedCalls;
  end;

implementation

uses
  SysUtils;

procedure TBandmapModelTests.SetUp;
begin
  FModel := TBandmapModel.Create(7000000, 7040000);
end;

procedure TBandmapModelTests.TearDown;
begin
  FModel.Free;
end;

procedure TBandmapModelTests.Add(const ACall: string; const AHz: Int64);
var
  Spot: TBandmapSpot;
begin
  Spot := Default(TBandmapSpot);
  Spot.Call := ACall;
  AssertTrue(TFrequencyHz.TryFromHz(AHz, Spot.Frequency));
  FModel.AddSpot(Spot);
end;

procedure TBandmapModelTests.MapsFrequencyToY;
begin
  AssertEquals(0, FModel.YOfFrequency(7000000, 400));
  AssertEquals(200, FModel.YOfFrequency(7020000, 400));
  AssertEquals(400, FModel.YOfFrequency(7040000, 400));
  AssertEquals(7010000, FModel.FrequencyAtY(100, 400));
end;

procedure TBandmapModelTests.SortsSpotsByFrequency;
begin
  Add('JA1BBB', 7030000);
  Add('JA1AAA', 7010000);
  Add('JA1CCC', 7020000);
  AssertEquals('JA1AAA', FModel.Spots[0].Call);
  AssertEquals('JA1CCC', FModel.Spots[1].Call);
  AssertEquals('JA1BBB', FModel.Spots[2].Call);
end;

procedure TBandmapModelTests.MovesARespottedCall;
begin
  Add('JA1AAA', 7010000);
  Add('JA1AAA', 7025000);
  AssertEquals(1, FModel.Count);
  AssertEquals(7025000, FModel.Spots[0].Frequency.Hz);
end;

procedure TBandmapModelTests.PushesOverlappingLabelsDown;
var
  Rows: TBandmapRows;
begin
  { 400 px for 40 kHz: 100 Hz per pixel. }
  Add('JA1AAA', 7010000);
  Add('JA1BBB', 7010100);
  Add('JA1CCC', 7030000);
  Rows := FModel.Layout(400, 16);
  AssertEquals(3, Length(Rows));
  AssertEquals(100, Rows[0].FrequencyY);
  AssertEquals('centred', 92, Rows[0].LabelY);
  AssertEquals(101, Rows[1].FrequencyY);
  AssertEquals('pushed below the first label', 108, Rows[1].LabelY);
  AssertEquals('room of its own', 292, Rows[2].LabelY);
end;

procedure TBandmapModelTests.KeepsTheFirstLabelBelowTheTop;
var
  Rows: TBandmapRows;
begin
  Add('JA1AAA', 7000100);
  Rows := FModel.Layout(400, 16);
  AssertEquals(1, Rows[0].FrequencyY);
  AssertEquals(0, Rows[0].LabelY);
end;

procedure TBandmapModelTests.SortsManySpots;
var
  Index: Integer;
begin
  RandSeed := 1;
  for Index := 1 to 3000 do
    Add(Format('JA%dA%d', [Index mod 10, Index]), 7000000 + Random(40000));
  AssertEquals(3000, FModel.Count);
  for Index := 1 to FModel.Count - 1 do
    AssertTrue('in order at ' + IntToStr(Index),
      FModel.Spots[Index - 1].Frequency.Hz <= FModel.Spots[Index].Frequency.Hz);
end;

procedure TBandmapModelTests.LeavesOutSpotsOutOfRange;
var
  Rows: TBandmapRows;
begin
  Add('JA1AAA', 6999000);
  Add('JA1BBB', 7020000);
  Add('JA1CCC', 7041000);
  Rows := FModel.Layout(400, 16);
  AssertEquals(1, Length(Rows));
  AssertEquals('JA1BBB', FModel.Spots[Rows[0].SpotIndex].Call);
end;

procedure TBandmapModelTests.FindsTheSpotUnderTheMouse;
var
  Rows: TBandmapRows;
begin
  Add('JA1AAA', 7010000);
  Add('JA1BBB', 7030000);
  Rows := FModel.Layout(400, 16);
  AssertEquals('JA1AAA', FModel.Spots[FModel.SpotAtY(Rows, 95, 16)].Call);
  AssertEquals('JA1BBB', FModel.Spots[FModel.SpotAtY(Rows, 300, 16)].Call);
  AssertEquals(-1, FModel.SpotAtY(Rows, 200, 16));
end;

procedure TBandmapModelTests.ZoomKeepsThePointUnderTheMouse;
begin
  FModel.ZoomAt(7010000, 0.5);
  AssertEquals(7005000, FModel.LowHz);
  AssertEquals(7025000, FModel.HighHz);
  AssertEquals(100, FModel.YOfFrequency(7010000, 400));
end;

procedure TBandmapModelTests.ZoomStaysWithinLimits;
begin
  FModel.ZoomAt(7020000, 0.0001);
  AssertEquals('1 kHz at least', 1000, FModel.HighHz - FModel.LowHz);
  FModel.ZoomAt(7020000, 100000);
  AssertEquals('10 MHz at most', 10000000, FModel.HighHz - FModel.LowHz);
end;

procedure TBandmapModelTests.RefusesAnEmptyRange;
begin
  try
    FModel.SetRange(7000000, 7000000);
    Fail('empty range accepted');
  except
    on EArgumentException do ;
  end;
end;

procedure TBandmapModelTests.HighlightsMatchingCalls;
begin
  Add('JA1ABC', 7010000);
  FModel.SetHighlight('1ab');
  AssertTrue(FModel.IsHighlighted(FModel.Spots[0]));
  FModel.SetHighlight('');
  AssertFalse(FModel.IsHighlighted(FModel.Spots[0]));
end;

procedure TBandmapModelTests.MarksWorkedCalls;
begin
  Add('JA1ABC', 7010000);
  Add('JA1ABD', 7020000);
  FModel.MarkWorked('JA1ABD');
  AssertFalse(FModel.Spots[0].Worked);
  AssertTrue(FModel.Spots[1].Worked);
end;

initialization
  RegisterTest(TBandmapModelTests);

end.
