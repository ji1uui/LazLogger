unit Muninn.Core.Mode;

{ Operating mode as the ADIF MODE / SUBMODE pair (ADIF 3.1.8), e.g. SSB/USB or
  MFSK/FT4. Any syntactically valid pair is accepted so imported logs keep modes
  this table does not list; the category is only known for listed modes.
  The full ADIF enumeration is in Muninn.Core.AdifModes. }

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

type
  TModeCategory = (mcUnknown, mcCw, mcPhone, mcDigital);

  TMode = record
  private
    FMode: string;
    FSubmode: string;
  public
    { Mode is required; submode may be empty. Both are trimmed and upper-cased.
      Mode: A-Z, 0-9, '_' and '-'. Submode also allows '/' and single inner
      spaces, as in the ADIF submodes 'VARA HF' and 'OLIVIA 4/125'. }
    class function TryCreate(const AMode, ASubmode: string;
      out AResult: TMode): Boolean; static;
    { Parses what an operator types or a logger shows: a mode ('CW', 'FT8') or a
      well-known submode that implies its mode ('USB' -> SSB/USB, 'FT4' -> MFSK/FT4). }
    class function TryParseDisplay(const AText: string;
      out AResult: TMode): Boolean; static;
    function Mode: string;
    function Submode: string;
    { The submode when present, otherwise the mode. }
    function DisplayName: string;
    function IsKnown: Boolean;
    function Category: TModeCategory;
    function Equals(const AOther: TMode): Boolean;
  end;

implementation

uses
  SysUtils;

type
  TKnownMode = record
    Mode: string;
    Category: TModeCategory;
  end;

  TImpliedMode = record
    Submode: string;
    Mode: string;
  end;

const
  KnownModes: array[0..11] of TKnownMode = (
    (Mode: 'AM'; Category: mcPhone),
    (Mode: 'CW'; Category: mcCw),
    (Mode: 'DIGITALVOICE'; Category: mcPhone),
    (Mode: 'FM'; Category: mcPhone),
    (Mode: 'FT8'; Category: mcDigital),
    (Mode: 'HELL'; Category: mcDigital),
    (Mode: 'JT65'; Category: mcDigital),
    (Mode: 'MFSK'; Category: mcDigital),
    (Mode: 'OLIVIA'; Category: mcDigital),
    (Mode: 'PSK'; Category: mcDigital),
    (Mode: 'RTTY'; Category: mcDigital),
    (Mode: 'SSB'; Category: mcPhone));

  { Submodes operators commonly name on their own, with the ADIF mode they belong to. }
  ImpliedModes: array[0..7] of TImpliedMode = (
    (Submode: 'USB'; Mode: 'SSB'),
    (Submode: 'LSB'; Mode: 'SSB'),
    (Submode: 'FT4'; Mode: 'MFSK'),
    (Submode: 'FST4'; Mode: 'MFSK'),
    (Submode: 'JS8'; Mode: 'MFSK'),
    (Submode: 'Q65'; Mode: 'MFSK'),
    (Submode: 'PSK31'; Mode: 'PSK'),
    (Submode: 'PSK63'; Mode: 'PSK'));

function IsValidToken(const AValue: string): Boolean;
var
  Index: Integer;
begin
  Result := AValue <> '';
  for Index := 1 to Length(AValue) do
    if not (AValue[Index] in ['A'..'Z', '0'..'9', '_', '-']) then
      Exit(False);
end;

function IsValidSubmode(const AValue: string): Boolean;
var
  Index: Integer;
begin
  Result := AValue <> '';
  for Index := 1 to Length(AValue) do
    case AValue[Index] of
      'A'..'Z', '0'..'9', '_', '-', '/': ;
      ' ':
        { Trimmed already, so a space is never first or last. }
        if AValue[Index + 1] = ' ' then
          Exit(False);
    else
      Exit(False);
    end;
end;

function FindKnownMode(const AMode: string; out ACategory: TModeCategory): Boolean;
var
  Index: Integer;
begin
  for Index := Low(KnownModes) to High(KnownModes) do
    if KnownModes[Index].Mode = AMode then
    begin
      ACategory := KnownModes[Index].Category;
      Exit(True);
    end;
  ACategory := mcUnknown;
  Result := False;
end;

class function TMode.TryCreate(const AMode, ASubmode: string;
  out AResult: TMode): Boolean;
var
  ModeText, SubmodeText: string;
begin
  AResult.FMode := '';
  AResult.FSubmode := '';
  ModeText := UpperCase(Trim(AMode));
  SubmodeText := UpperCase(Trim(ASubmode));
  Result := IsValidToken(ModeText) and
    ((SubmodeText = '') or IsValidSubmode(SubmodeText));
  if Result then
  begin
    AResult.FMode := ModeText;
    AResult.FSubmode := SubmodeText;
  end;
end;

class function TMode.TryParseDisplay(const AText: string;
  out AResult: TMode): Boolean;
var
  Text: string;
  Index: Integer;
  KnownCategory: TModeCategory;
begin
  Text := UpperCase(Trim(AText));
  if FindKnownMode(Text, KnownCategory) then
    Exit(TryCreate(Text, '', AResult));
  for Index := Low(ImpliedModes) to High(ImpliedModes) do
    if ImpliedModes[Index].Submode = Text then
      Exit(TryCreate(ImpliedModes[Index].Mode, Text, AResult));
  AResult.FMode := '';
  AResult.FSubmode := '';
  Result := False;
end;

function TMode.Mode: string;
begin
  Result := FMode;
end;

function TMode.Submode: string;
begin
  Result := FSubmode;
end;

function TMode.DisplayName: string;
begin
  if FSubmode <> '' then
    Result := FSubmode
  else
    Result := FMode;
end;

function TMode.IsKnown: Boolean;
var
  KnownCategory: TModeCategory;
begin
  Result := FindKnownMode(FMode, KnownCategory);
end;

function TMode.Category: TModeCategory;
begin
  FindKnownMode(FMode, Result);
end;

function TMode.Equals(const AOther: TMode): Boolean;
begin
  Result := (FMode = AOther.FMode) and (FSubmode = AOther.FSubmode);
end;

end.
