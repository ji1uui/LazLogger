unit Muninn.UI.Theme;

{ Colours of the custom-drawn controls, in a dark and a light variant
  (ADR 0009). Native controls keep the system's colours. }

{$mode objfpc}{$H+}

interface

uses
  Graphics;

type
  TUiTheme = record
    Name: string;
    Background: TColor;
    Surface: TColor;
    Text: TColor;
    MutedText: TColor;
    Grid: TColor;
    Accent: TColor;
    HighlightBack: TColor;
    Warning: TColor;
  end;

function DarkTheme: TUiTheme;
function LightTheme: TUiTheme;

implementation

function DarkTheme: TUiTheme;
begin
  Result.Name := 'dark';
  Result.Background := RGBToColor($1E, $21, $27);
  Result.Surface := RGBToColor($26, $2A, $31);
  Result.Text := RGBToColor($E6, $E8, $EB);
  Result.MutedText := RGBToColor($8A, $91, $9C);
  Result.Grid := RGBToColor($44, $4B, $55);
  Result.Accent := RGBToColor($4D, $A3, $FF);
  Result.HighlightBack := RGBToColor($1F, $3A, $5C);
  Result.Warning := RGBToColor($FF, $B0, $40);
end;

function LightTheme: TUiTheme;
begin
  Result.Name := 'light';
  Result.Background := RGBToColor($FF, $FF, $FF);
  Result.Surface := RGBToColor($F2, $F4, $F7);
  Result.Text := RGBToColor($1A, $1D, $22);
  Result.MutedText := RGBToColor($6B, $72, $7D);
  Result.Grid := RGBToColor($C8, $CD, $D4);
  Result.Accent := RGBToColor($00, $5F, $CC);
  Result.HighlightBack := RGBToColor($DC, $EB, $FF);
  Result.Warning := RGBToColor($B3, $5C, $00);
end;

end.
