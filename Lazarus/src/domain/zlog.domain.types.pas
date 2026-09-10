unit ZLog.Domain.Types;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils;

type
  TEmissionMode = (emUnknown, emCW, emRTTY, emSSB);

  TCallsign = record
  private
    FValue: string;
  public
    class function TryCreate(const ARawValue: string; out ACallsign: TCallsign): Boolean; static;
    function IsEmpty: Boolean;
    function ToString: string;
  end;

  TFrequencyHz = record
  private
    FValue: Int64;
  public
    class function TryCreate(const AValue: Int64; out AFrequency: TFrequencyHz): Boolean; static;
    function ToInt64: Int64;
  end;

implementation

function IsCallsignCharacter(const AValue: Char): Boolean;
begin
  Result := (AValue in ['A'..'Z']) or (AValue in ['0'..'9']) or
    (AValue = '/');
end;

class function TCallsign.TryCreate(const ARawValue: string;
  out ACallsign: TCallsign): Boolean;
var
  Index: Integer;
  Normalized: string;
  HasLetter: Boolean;
  HasDigit: Boolean;
begin
  ACallsign.FValue := '';
  Normalized := UpperCase(Trim(ARawValue));
  Result := (Length(Normalized) >= 3) and (Length(Normalized) <= 16);
  HasLetter := False;
  HasDigit := False;

  if Result then
    for Index := 1 to Length(Normalized) do
    begin
      if not IsCallsignCharacter(Normalized[Index]) then
        Exit(False);
      HasLetter := HasLetter or (Normalized[Index] in ['A'..'Z']);
      HasDigit := HasDigit or (Normalized[Index] in ['0'..'9']);
    end;

  Result := Result and HasLetter and HasDigit and
    (Normalized[1] <> '/') and (Normalized[Length(Normalized)] <> '/') and
    (Pos('//', Normalized) = 0);
  if Result then
    ACallsign.FValue := Normalized;
end;

function TCallsign.IsEmpty: Boolean;
begin
  Result := FValue = '';
end;

function TCallsign.ToString: string;
begin
  Result := FValue;
end;

class function TFrequencyHz.TryCreate(const AValue: Int64;
  out AFrequency: TFrequencyHz): Boolean;
const
  MinimumAmateurFrequencyHz = 100000;
  MaximumAmateurFrequencyHz = 300000000000;
begin
  Result := (AValue >= MinimumAmateurFrequencyHz) and
    (AValue <= MaximumAmateurFrequencyHz);
  if Result then
    AFrequency.FValue := AValue
  else
    AFrequency.FValue := 0;
end;

function TFrequencyHz.ToInt64: Int64;
begin
  Result := FValue;
end;

end.
