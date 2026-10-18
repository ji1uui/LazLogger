unit Muninn.Core.Time;

{ UTC instant held as milliseconds since 1970-01-01T00:00:00Z. Calendar
  conversion uses integer arithmetic only (proleptic Gregorian calendar), so it
  does not depend on the local time zone or on TDateTime rounding. }

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

const
  MinimumYear = 1900;
  MaximumYear = 9999;

type
  TUtcComponents = record
    Year, Month, Day: Integer;
    Hour, Minute, Second, Millisecond: Integer;
  end;

  TUtcInstant = record
  private
    FUnixMs: Int64;
  public
    class function FromUnixMs(const AUnixMs: Int64): TUtcInstant; static;
    { False for an invalid calendar date or time, or a year outside
      MinimumYear..MaximumYear. }
    class function TryFromComponents(const AComponents: TUtcComponents;
      out AInstant: TUtcInstant): Boolean; static;
    function UnixMs: Int64;
    function Components: TUtcComponents;
    { ADIF QSO_DATE: YYYYMMDD }
    function ToAdifDate: string;
    { ADIF TIME_ON / TIME_OFF: HHMMSS }
    function ToAdifTime: string;
    { YYYY-MM-DDTHH:MM:SSZ }
    function ToIso8601: string;
    function Equals(const AOther: TUtcInstant): Boolean;
  end;

function IsLeapYear(const AYear: Integer): Boolean;
function DaysInMonth(const AYear, AMonth: Integer): Integer;

implementation

uses
  SysUtils;

const
  MsPerSecond = 1000;
  MsPerDay = Int64(86400000);

function IsLeapYear(const AYear: Integer): Boolean;
begin
  Result := ((AYear mod 4 = 0) and (AYear mod 100 <> 0)) or (AYear mod 400 = 0);
end;

function DaysInMonth(const AYear, AMonth: Integer): Integer;
const
  Days: array[1..12] of Integer = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
begin
  Result := Days[AMonth];
  if (AMonth = 2) and IsLeapYear(AYear) then
    Result := 29;
end;

{ Days since 1970-01-01 for a civil date; algorithm by Howard Hinnant.
  Valid for years >= 0, which covers MinimumYear..MaximumYear. }
function DaysFromCivil(AYear: Int64; const AMonth, ADay: Integer): Int64;
var
  Era, YearOfEra, DayOfYear, DayOfEra: Int64;
  ShiftedMonth: Integer;
begin
  if AMonth <= 2 then
    Dec(AYear);
  Era := AYear div 400;
  YearOfEra := AYear - Era * 400;
  if AMonth > 2 then
    ShiftedMonth := AMonth - 3
  else
    ShiftedMonth := AMonth + 9;
  DayOfYear := (153 * ShiftedMonth + 2) div 5 + ADay - 1;
  DayOfEra := YearOfEra * 365 + YearOfEra div 4 - YearOfEra div 100 + DayOfYear;
  Result := Era * 146097 + DayOfEra - 719468;
end;

procedure CivilFromDays(ADays: Int64; out AYear, AMonth, ADay: Integer);
var
  Era, DayOfEra, YearOfEra, DayOfYear, ShiftedMonth: Int64;
begin
  Inc(ADays, 719468);
  Era := ADays div 146097;
  DayOfEra := ADays - Era * 146097;
  YearOfEra := (DayOfEra - DayOfEra div 1460 + DayOfEra div 36524 -
    DayOfEra div 146096) div 365;
  DayOfYear := DayOfEra - (365 * YearOfEra + YearOfEra div 4 - YearOfEra div 100);
  ShiftedMonth := (5 * DayOfYear + 2) div 153;
  ADay := DayOfYear - (153 * ShiftedMonth + 2) div 5 + 1;
  if ShiftedMonth < 10 then
    AMonth := ShiftedMonth + 3
  else
    AMonth := ShiftedMonth - 9;
  AYear := YearOfEra + Era * 400;
  if AMonth <= 2 then
    Inc(AYear);
end;

class function TUtcInstant.FromUnixMs(const AUnixMs: Int64): TUtcInstant;
begin
  Result.FUnixMs := AUnixMs;
end;

class function TUtcInstant.TryFromComponents(const AComponents: TUtcComponents;
  out AInstant: TUtcInstant): Boolean;
begin
  AInstant.FUnixMs := 0;
  with AComponents do
  begin
    Result := (Year >= MinimumYear) and (Year <= MaximumYear) and
      (Month >= 1) and (Month <= 12) and
      (Day >= 1) and (Day <= DaysInMonth(Year, Month)) and
      (Hour >= 0) and (Hour <= 23) and (Minute >= 0) and (Minute <= 59) and
      (Second >= 0) and (Second <= 59) and
      (Millisecond >= 0) and (Millisecond <= 999);
    if Result then
      AInstant.FUnixMs := DaysFromCivil(Year, Month, Day) * MsPerDay +
        ((Int64(Hour) * 60 + Minute) * 60 + Second) * MsPerSecond + Millisecond;
  end;
end;

function TUtcInstant.UnixMs: Int64;
begin
  Result := FUnixMs;
end;

function TUtcInstant.Components: TUtcComponents;
var
  Days, MsOfDay: Int64;
begin
  { Floor division so instants before 1970 land on the correct day. }
  Days := FUnixMs div MsPerDay;
  MsOfDay := FUnixMs mod MsPerDay;
  if MsOfDay < 0 then
  begin
    Dec(Days);
    Inc(MsOfDay, MsPerDay);
  end;
  CivilFromDays(Days, Result.Year, Result.Month, Result.Day);
  Result.Millisecond := MsOfDay mod MsPerSecond;
  MsOfDay := MsOfDay div MsPerSecond;
  Result.Second := MsOfDay mod 60;
  MsOfDay := MsOfDay div 60;
  Result.Minute := MsOfDay mod 60;
  Result.Hour := MsOfDay div 60;
end;

function TUtcInstant.ToAdifDate: string;
begin
  with Components do
    Result := Format('%.4d%.2d%.2d', [Year, Month, Day]);
end;

function TUtcInstant.ToAdifTime: string;
begin
  with Components do
    Result := Format('%.2d%.2d%.2d', [Hour, Minute, Second]);
end;

function TUtcInstant.ToIso8601: string;
begin
  with Components do
    Result := Format('%.4d-%.2d-%.2dT%.2d:%.2d:%.2dZ',
      [Year, Month, Day, Hour, Minute, Second]);
end;

function TUtcInstant.Equals(const AOther: TUtcInstant): Boolean;
begin
  Result := FUnixMs = AOther.FUnixMs;
end;

end.
