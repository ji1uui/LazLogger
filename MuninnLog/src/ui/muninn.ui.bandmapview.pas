unit Muninn.UI.BandmapView;

{ The band map control: paints a TBandmapModel with the LCL canvas (ADR 0009).
  Layout and hit testing live in the model; this unit only draws and turns
  mouse input into model calls.

  Sizes follow the font, so the map scales with the screen DPI. Worked
  stations differ from new ones by style (italic) as well as colour, and the
  highlighted calls by a box as well as colour. }

{$mode objfpc}{$H+}

interface

uses
  Classes, Controls, Graphics, Muninn.UI.Bandmap, Muninn.UI.Theme;

type
  TBandmapTuneEvent = procedure(Sender: TObject; const AHz: Int64) of object;

  TBandmapControl = class(TCustomControl)
  private
    FModel: TBandmapModel;
    FTheme: TUiTheme;
    FRows: TBandmapRows;
    FOnTune: TBandmapTuneEvent;
    FPaintCount: Integer;
    FLastPaintUs: Int64;
    function RowHeight: Integer;
    function GutterWidth: Integer;
    procedure PaintScale(const AGutter: Integer);
    procedure PaintSpots(const AGutter, ARowHeight: Integer);
    procedure PaintOverflow(const AX, AHidden, ARowHeight: Integer);
    procedure PaintCurrentFrequency;
    procedure SetTheme(const AValue: TUiTheme);
  protected
    procedure Paint; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
  public
    { The model is not owned and must outlive the control. }
    constructor Create(AOwner: TComponent; const AModel: TBandmapModel); reintroduce;
    property Theme: TUiTheme read FTheme write SetTheme;
    { Raised by a click: the spot's frequency, or the frequency under the
      mouse. }
    property OnTune: TBandmapTuneEvent read FOnTune write FOnTune;
    { For measurements: how many times Paint ran and how long the last one
      took. }
    property PaintCount: Integer read FPaintCount;
    property LastPaintUs: Int64 read FLastPaintUs;
  end;

implementation

uses
  SysUtils, Math, Muninn.UI.Clock;

const
  TickSteps: array[0..11] of Int64 = (100, 200, 500, 1000, 2000, 5000, 10000,
    20000, 50000, 100000, 200000, 500000);

constructor TBandmapControl.Create(AOwner: TComponent; const AModel: TBandmapModel);
begin
  inherited Create(AOwner);
  if AModel = nil then
    raise EArgumentNilException.Create('TBandmapControl needs a model');
  FModel := AModel;
  FTheme := DarkTheme;
  DoubleBuffered := True;
  ControlStyle := ControlStyle + [csOpaque];
  Color := FTheme.Background;
end;

procedure TBandmapControl.SetTheme(const AValue: TUiTheme);
begin
  FTheme := AValue;
  Color := FTheme.Background;
  Invalidate;
end;

function TBandmapControl.RowHeight: Integer;
begin
  Result := Canvas.TextHeight('Wg') + Scale96ToFont(2);
end;

function TBandmapControl.GutterWidth: Integer;
begin
  Result := Canvas.TextWidth('00000.0') + Scale96ToFont(12);
end;

procedure TBandmapControl.PaintScale(const AGutter: Integer);
var
  Step, Hz: Int64;
  Index, Y, MinGap, TextH: Integer;
  TickText: string;
begin
  TextH := Canvas.TextHeight('0');
  MinGap := TextH * 3;
  { The smallest step that keeps the labels apart. }
  Step := TickSteps[High(TickSteps)];
  for Index := 0 to High(TickSteps) do
    if FModel.YOfFrequency(FModel.LowHz + TickSteps[Index], Height) >= MinGap then
    begin
      Step := TickSteps[Index];
      Break;
    end;
  Canvas.Brush.Color := FTheme.Surface;
  Canvas.FillRect(0, 0, AGutter, Height);
  Canvas.Pen.Color := FTheme.Grid;
  Canvas.Font.Color := FTheme.MutedText;
  Canvas.Font.Style := [];
  Hz := ((FModel.LowHz + Step - 1) div Step) * Step;
  while Hz <= FModel.HighHz do
  begin
    Y := FModel.YOfFrequency(Hz, Height);
    Canvas.Line(AGutter - Scale96ToFont(6), Y, AGutter, Y);
    TickText := FormatFloat('0.0', Hz / 1000);
    Canvas.TextOut(AGutter - Scale96ToFont(8) - Canvas.TextWidth(TickText),
      EnsureRange(Y - TextH div 2, 0, Height - TextH), TickText);
    Inc(Hz, Step);
  end;
  Canvas.Line(AGutter, 0, AGutter, Height);
end;

procedure TBandmapControl.PaintSpots(const AGutter, ARowHeight: Integer);
var
  Index, X, Y, MidY: Integer;
  Spot: TBandmapSpot;
  Highlighted: Boolean;
begin
  X := AGutter + Scale96ToFont(16);
  for Index := 0 to High(FRows) do
  begin
    { Labels pushed below the bottom are not drawn; say how many. }
    if FRows[Index].LabelY + ARowHeight > Height then
    begin
      PaintOverflow(X, Length(FRows) - Index, ARowHeight);
      Break;
    end;
    Spot := FModel.Spots[FRows[Index].SpotIndex];
    Highlighted := FModel.IsHighlighted(Spot);
    Y := FRows[Index].LabelY;
    MidY := Y + ARowHeight div 2;
    Canvas.Pen.Color := FTheme.Grid;
    Canvas.Line(AGutter, FRows[Index].FrequencyY, X - Scale96ToFont(3), MidY);
    if Highlighted then
    begin
      Canvas.Brush.Color := FTheme.HighlightBack;
      Canvas.Pen.Color := FTheme.Accent;
      Canvas.Rectangle(X - Scale96ToFont(2), Y,
        X + Canvas.TextWidth(Spot.Call) + Scale96ToFont(3), Y + ARowHeight);
      Canvas.Font.Style := [fsBold];
      Canvas.Font.Color := FTheme.Text;
    end
    else if Spot.Worked then
    begin
      Canvas.Font.Style := [fsItalic];
      Canvas.Font.Color := FTheme.MutedText;
    end
    else
    begin
      Canvas.Font.Style := [];
      Canvas.Font.Color := FTheme.Text;
    end;
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(X, Y + Scale96ToFont(1), Spot.Call);
    Canvas.Brush.Style := bsSolid;
  end;
  Canvas.Font.Style := [];
end;

procedure TBandmapControl.PaintOverflow(const AX, AHidden, ARowHeight: Integer);
var
  Y: Integer;
begin
  Y := Height - ARowHeight;
  Canvas.Brush.Color := FTheme.Surface;
  Canvas.FillRect(AX - Scale96ToFont(4), Y, Width, Height);
  Canvas.Font.Style := [];
  Canvas.Font.Color := FTheme.Warning;
  Canvas.TextOut(AX, Y + Scale96ToFont(1), Format('+%d more below (zoom in)', [AHidden]));
end;

procedure TBandmapControl.PaintCurrentFrequency;
var
  Y: Integer;
begin
  if not FModel.HasCurrentFrequency then
    Exit;
  Y := FModel.YOfFrequency(FModel.CurrentFrequency.Hz, Height);
  if (Y < 0) or (Y > Height) then
    Exit;
  Canvas.Pen.Color := FTheme.Accent;
  Canvas.Pen.Width := Max(1, Scale96ToFont(2));
  Canvas.Line(0, Y, Width, Y);
  Canvas.Pen.Width := 1;
end;

procedure TBandmapControl.Paint;
var
  Started: Int64;
  Gutter, Rows: Integer;
begin
  Started := MicroTicks;
  Canvas.Font := Font;
  Canvas.Brush.Color := FTheme.Background;
  Canvas.FillRect(ClientRect);
  Gutter := GutterWidth;
  Rows := RowHeight;
  FRows := FModel.Layout(Height, Rows);
  PaintScale(Gutter);
  PaintSpots(Gutter, Rows);
  PaintCurrentFrequency;
  FLastPaintUs := MicroTicks - Started;
  Inc(FPaintCount);
end;

function TBandmapControl.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  AtHz: Int64;
begin
  Result := True;
  if ssShift in Shift then
    FModel.ScrollBy(-Sign(WheelDelta) * (FModel.HighHz - FModel.LowHz) div 10)
  else
  begin
    AtHz := FModel.FrequencyAtY(MousePos.Y, Height);
    if WheelDelta > 0 then
      FModel.ZoomAt(AtHz, 0.8)
    else
      FModel.ZoomAt(AtHz, 1.25);
  end;
  Invalidate;
end;

procedure TBandmapControl.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Index, LabelX: Integer;
  Hz: Int64;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button <> mbLeft) or not Assigned(FOnTune) then
    Exit;
  { Only a click on a label picks its spot; a label may have been pushed
    away from its frequency, so a click elsewhere tunes to where it is. }
  LabelX := GutterWidth + Scale96ToFont(16);
  Index := FModel.SpotAtY(FRows, Y, RowHeight);
  if (Index >= 0) and ((X < LabelX - Scale96ToFont(2)) or
    (X > LabelX + Canvas.TextWidth(FModel.Spots[Index].Call) + Scale96ToFont(3))) then
    Index := -1;
  if Index >= 0 then
    Hz := FModel.Spots[Index].Frequency.Hz
  else
    Hz := FModel.FrequencyAtY(Y, Height);
  FOnTune(Self, Hz);
end;

end.
