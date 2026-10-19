unit Muninn.UI.Bandmap;

{ What the band map shows, without the LCL (ADR 0009): the spots, the
  frequency range on screen, and where each spot's label goes. The LCL
  control (Muninn.UI.BandmapView) only paints this layout and forwards the
  mouse.

  Frequencies run from top (low) to bottom (high), as in N1MM Logger+ and
  zLog. Labels that would overlap are pushed down; a leader line joins a
  moved label to its frequency. }

{$mode objfpc}{$H+}

interface

uses
  Muninn.Core.Frequency;

type
  TBandmapSpot = record
    Call: string;
    Frequency: TFrequencyHz;
    { Already in the log on this band and mode. }
    Worked: Boolean;
  end;

  { One label on screen. Y values are pixels from the top of the map. }
  TBandmapRow = record
    SpotIndex: Integer;
    { Where the frequency is. }
    FrequencyY: Integer;
    { Where the label is drawn (top of its row): centred on FrequencyY,
      or lower when the label above (or the top edge) is in the way. }
    LabelY: Integer;
  end;
  TBandmapRows = array of TBandmapRow;

  { Whether ACall is in the log on AFrequency's band (and the current mode). }
  TSpotWorkedQuery = function(const ACall: string;
    const AFrequency: TFrequencyHz): Boolean of object;

  TBandmapModel = class
  private
    FSpots: array of TBandmapSpot;
    FCount: Integer;
    FLowHz: Int64;
    FHighHz: Int64;
    FCurrent: TFrequencyHz;
    FHasCurrent: Boolean;
    FHighlight: string;
    FSorted: Boolean;
    procedure Sort;
    function GetSpot(AIndex: Integer): TBandmapSpot;
  public
    constructor Create(const ALowHz, AHighHz: Int64);
    { Adds a spot, or moves the call's existing spot to the new frequency. }
    procedure AddSpot(const ASpot: TBandmapSpot);
    procedure Clear;
    { Sets every spot's Worked from the log: call it after a QSO is logged
      and when the mode changes. }
    procedure UpdateWorked(const AIsWorked: TSpotWorkedQuery);
    { Sets the visible range. Raises EArgumentException when AHighHz is not
      above ALowHz. }
    procedure SetRange(const ALowHz, AHighHz: Int64);
    { Zooms around AAtHz by AFactor (below 1 zooms in), keeping AAtHz at the
      same place on screen. The span stays between 1 kHz and 10 MHz. }
    procedure ZoomAt(const AAtHz: Int64; const AFactor: Double);
    { Scrolls by ADeltaHz (negative: towards lower frequencies). }
    procedure ScrollBy(const ADeltaHz: Int64);
    procedure SetCurrentFrequency(const AFrequency: TFrequencyHz);
    { Calls containing this text are highlighted ('' for none). }
    procedure SetHighlight(const AText: string);
    function IsHighlighted(const ASpot: TBandmapSpot): Boolean;

    function YOfFrequency(const AHz: Int64; const AHeight: Integer): Integer;
    function FrequencyAtY(const AY, AHeight: Integer): Int64;
    { The labels of the spots in range, sorted by frequency, each ARowHeight
      high and not overlapping. }
    function Layout(const AHeight, ARowHeight: Integer): TBandmapRows;
    { The spot whose label contains AY, or -1. }
    function SpotAtY(const ARows: TBandmapRows; const AY, ARowHeight: Integer): Integer;

    property Count: Integer read FCount;
    property Spots[AIndex: Integer]: TBandmapSpot read GetSpot;
    property LowHz: Int64 read FLowHz;
    property HighHz: Int64 read FHighHz;
    property CurrentFrequency: TFrequencyHz read FCurrent;
    property HasCurrentFrequency: Boolean read FHasCurrent;
    property Highlight: string read FHighlight;
  end;

implementation

uses
  SysUtils, Math;

const
  MinSpanHz = 1000;
  MaxSpanHz = 10000000;

constructor TBandmapModel.Create(const ALowHz, AHighHz: Int64);
begin
  inherited Create;
  SetRange(ALowHz, AHighHz);
  FSorted := True;
end;

function TBandmapModel.GetSpot(AIndex: Integer): TBandmapSpot;
begin
  if (AIndex < 0) or (AIndex >= FCount) then
    raise EArgumentOutOfRangeException.CreateFmt('spot %d of %d', [AIndex, FCount]);
  Sort;
  Result := FSpots[AIndex];
end;

procedure TBandmapModel.AddSpot(const ASpot: TBandmapSpot);
var
  Index: Integer;
begin
  for Index := 0 to FCount - 1 do
    if FSpots[Index].Call = ASpot.Call then
    begin
      FSpots[Index] := ASpot;
      FSorted := False;
      Exit;
    end;
  if FCount = Length(FSpots) then
    SetLength(FSpots, Max(16, FCount * 2));
  FSpots[FCount] := ASpot;
  Inc(FCount);
  FSorted := False;
end;

procedure TBandmapModel.UpdateWorked(const AIsWorked: TSpotWorkedQuery);
var
  Index: Integer;
begin
  for Index := 0 to FCount - 1 do
    FSpots[Index].Worked := AIsWorked(FSpots[Index].Call, FSpots[Index].Frequency);
end;

procedure TBandmapModel.Clear;
begin
  FSpots := nil;
  FCount := 0;
  FSorted := True;
end;

procedure TBandmapModel.Sort;

  procedure QuickSort(ALow, AHigh: Integer);
  var
    I, J: Integer;
    Pivot: Int64;
    Item: TBandmapSpot;
  begin
    while ALow < AHigh do
    begin
      Pivot := FSpots[(ALow + AHigh) div 2].Frequency.Hz;
      I := ALow;
      J := AHigh;
      repeat
        while FSpots[I].Frequency.Hz < Pivot do
          Inc(I);
        while FSpots[J].Frequency.Hz > Pivot do
          Dec(J);
        if I <= J then
        begin
          Item := FSpots[I];
          FSpots[I] := FSpots[J];
          FSpots[J] := Item;
          Inc(I);
          Dec(J);
        end;
      until I > J;
      { Recurse into the smaller part to bound the stack depth. }
      if J - ALow < AHigh - I then
      begin
        QuickSort(ALow, J);
        ALow := I;
      end
      else
      begin
        QuickSort(I, AHigh);
        AHigh := J;
      end;
    end;
  end;

begin
  if FSorted then
    Exit;
  QuickSort(0, FCount - 1);
  FSorted := True;
end;

procedure TBandmapModel.SetRange(const ALowHz, AHighHz: Int64);
begin
  if AHighHz <= ALowHz then
    raise EArgumentException.CreateFmt('empty band map range %d..%d',
      [ALowHz, AHighHz]);
  FLowHz := ALowHz;
  FHighHz := AHighHz;
end;

procedure TBandmapModel.ZoomAt(const AAtHz: Int64; const AFactor: Double);
var
  Span, NewSpan: Int64;
  Ratio: Double;
begin
  if AFactor <= 0 then
    raise EArgumentException.Create('zoom factor must be positive');
  Span := FHighHz - FLowHz;
  NewSpan := EnsureRange(Round(Span * AFactor), MinSpanHz, MaxSpanHz);
  Ratio := (AAtHz - FLowHz) / Span;
  FLowHz := AAtHz - Round(NewSpan * Ratio);
  FHighHz := FLowHz + NewSpan;
end;

procedure TBandmapModel.ScrollBy(const ADeltaHz: Int64);
begin
  Inc(FLowHz, ADeltaHz);
  Inc(FHighHz, ADeltaHz);
end;

procedure TBandmapModel.SetCurrentFrequency(const AFrequency: TFrequencyHz);
begin
  FCurrent := AFrequency;
  FHasCurrent := True;
end;

procedure TBandmapModel.SetHighlight(const AText: string);
begin
  FHighlight := UpperCase(AText);
end;

function TBandmapModel.IsHighlighted(const ASpot: TBandmapSpot): Boolean;
begin
  Result := (FHighlight <> '') and (Pos(FHighlight, ASpot.Call) > 0);
end;

function TBandmapModel.YOfFrequency(const AHz: Int64; const AHeight: Integer): Integer;
begin
  Result := Round((AHz - FLowHz) * AHeight / (FHighHz - FLowHz));
end;

function TBandmapModel.FrequencyAtY(const AY, AHeight: Integer): Int64;
begin
  if AHeight <= 0 then
    Exit(FLowHz);
  Result := FLowHz + Round(AY * (FHighHz - FLowHz) / AHeight);
end;

function TBandmapModel.Layout(const AHeight, ARowHeight: Integer): TBandmapRows;
var
  Index, Used, NextFree, Y: Integer;
begin
  Result := nil;
  if (AHeight <= 0) or (ARowHeight <= 0) then
    Exit;
  Sort;
  SetLength(Result, FCount);
  Used := 0;
  { The first label may not start above the top. }
  NextFree := 0;
  for Index := 0 to FCount - 1 do
  begin
    if (FSpots[Index].Frequency.Hz < FLowHz) or
      (FSpots[Index].Frequency.Hz > FHighHz) then
      Continue;
    Y := YOfFrequency(FSpots[Index].Frequency.Hz, AHeight);
    Result[Used].SpotIndex := Index;
    Result[Used].FrequencyY := Y;
    { Centre the label on its frequency unless the previous one is there. }
    Result[Used].LabelY := Max(Y - ARowHeight div 2, NextFree);
    NextFree := Result[Used].LabelY + ARowHeight;
    Inc(Used);
  end;
  SetLength(Result, Used);
end;

function TBandmapModel.SpotAtY(const ARows: TBandmapRows;
  const AY, ARowHeight: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ARows) do
    if (AY >= ARows[Index].LabelY) and (AY < ARows[Index].LabelY + ARowHeight) then
      Exit(ARows[Index].SpotIndex);
  Result := -1;
end;

end.
