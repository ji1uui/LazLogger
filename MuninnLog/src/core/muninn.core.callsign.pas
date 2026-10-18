unit Muninn.Core.Callsign;

{ Callsign value object. Input is a UTF-8 string; full-width ASCII typed through a
  Japanese IME (e.g. 'ＪＡ１ＡＢＣ') is folded to ASCII before validation. }

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

type
  TCallsignError = (ceNone, ceEmpty, ceTooShort, ceTooLong, ceInvalidCharacter,
    ceMissingDigit, ceMissingLetter, ceInvalidSeparator);

  TCallsign = record
  private
    FValue: string;
  public
    class function TryCreate(const ARaw: string; out ACallsign: TCallsign;
      out AError: TCallsignError): Boolean; static; overload;
    class function TryCreate(const ARaw: string;
      out ACallsign: TCallsign): Boolean; static; overload;
    function IsEmpty: Boolean;
    function Equals(const AOther: TCallsign): Boolean;
    function ToString: string;
  end;

const
  MinimumCallsignLength = 3;
  MaximumCallsignLength = 20;

{ Folds full-width ASCII and the ideographic space to ASCII, trims, and upper-cases
  ASCII letters. Other characters are kept so validation can reject them. }
function NormalizeCallsignInput(const ARaw: string): string;

implementation

uses
  SysUtils;

function NormalizeCallsignInput(const ARaw: string): string;
var
  Index, Count: Integer;
  Second, Third: Byte;
begin
  Result := '';
  Index := 1;
  Count := Length(ARaw);
  while Index <= Count do
  begin
    if (Ord(ARaw[Index]) = $EF) and (Index + 2 <= Count) then
    begin
      Second := Ord(ARaw[Index + 1]);
      Third := Ord(ARaw[Index + 2]);
      { U+FF01..U+FF3F is EF BC 81..BF; U+FF40..U+FF5E is EF BD 80..9E. }
      if (Second = $BC) and (Third >= $81) and (Third <= $BF) then
      begin
        Result := Result + Chr($21 + Third - $81);
        Inc(Index, 3);
        Continue;
      end;
      if (Second = $BD) and (Third >= $80) and (Third <= $9E) then
      begin
        Result := Result + Chr($60 + Third - $80);
        Inc(Index, 3);
        Continue;
      end;
    end;
    { U+3000 IDEOGRAPHIC SPACE is E3 80 80. }
    if (Ord(ARaw[Index]) = $E3) and (Index + 2 <= Count) and
      (Ord(ARaw[Index + 1]) = $80) and (Ord(ARaw[Index + 2]) = $80) then
    begin
      Result := Result + ' ';
      Inc(Index, 3);
      Continue;
    end;
    Result := Result + ARaw[Index];
    Inc(Index);
  end;
  { SysUtils.UpperCase only changes a..z, so no widestring manager is needed. }
  Result := UpperCase(Trim(Result));
end;

class function TCallsign.TryCreate(const ARaw: string;
  out ACallsign: TCallsign; out AError: TCallsignError): Boolean;
var
  Normalized: string;
  Index: Integer;
  HasLetter, HasDigit: Boolean;
begin
  ACallsign.FValue := '';
  Normalized := NormalizeCallsignInput(ARaw);

  if Normalized = '' then
    AError := ceEmpty
  else if Length(Normalized) < MinimumCallsignLength then
    AError := ceTooShort
  else if Length(Normalized) > MaximumCallsignLength then
    AError := ceTooLong
  else
  begin
    AError := ceNone;
    HasLetter := False;
    HasDigit := False;
    for Index := 1 to Length(Normalized) do
      case Normalized[Index] of
        'A'..'Z': HasLetter := True;
        '0'..'9': HasDigit := True;
        '/': ;
      else
        begin
          AError := ceInvalidCharacter;
          Break;
        end;
      end;
    if AError = ceNone then
      if (Normalized[1] = '/') or (Normalized[Length(Normalized)] = '/') or
        (Pos('//', Normalized) > 0) then
        AError := ceInvalidSeparator
      else if not HasDigit then
        AError := ceMissingDigit
      else if not HasLetter then
        AError := ceMissingLetter;
  end;

  Result := AError = ceNone;
  if Result then
    ACallsign.FValue := Normalized;
end;

class function TCallsign.TryCreate(const ARaw: string;
  out ACallsign: TCallsign): Boolean;
var
  Error: TCallsignError;
begin
  Result := TryCreate(ARaw, ACallsign, Error);
end;

function TCallsign.IsEmpty: Boolean;
begin
  Result := FValue = '';
end;

function TCallsign.Equals(const AOther: TCallsign): Boolean;
begin
  Result := FValue = AOther.FValue;
end;

function TCallsign.ToString: string;
begin
  Result := FValue;
end;

end.
