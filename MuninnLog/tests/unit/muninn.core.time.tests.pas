unit Muninn.Core.Time.Tests;

{ Expected Unix millisecond values were computed independently with Python's
  datetime module (UTC). }

{$mode objfpc}{$H+}

interface

uses
  fpcunit, testregistry, Muninn.Core.Time;

type
  TTimeTests = class(TTestCase)
  private
    function Make(const AYear, AMonth, ADay, AHour, AMinute, ASecond,
      AMillisecond: Integer): TUtcComponents;
    procedure CheckInstant(const AComponents: TUtcComponents;
      const AExpectedUnixMs: Int64);
  published
    procedure ConvertsKnownInstants;
    procedure RoundTripsComponents;
    procedure HandlesInstantsBefore1970;
    procedure ValidatesCalendar;
    procedure FormatsAdifAndIso;
  end;

implementation

uses
  SysUtils;

function TTimeTests.Make(const AYear, AMonth, ADay, AHour, AMinute, ASecond,
  AMillisecond: Integer): TUtcComponents;
begin
  Result.Year := AYear;
  Result.Month := AMonth;
  Result.Day := ADay;
  Result.Hour := AHour;
  Result.Minute := AMinute;
  Result.Second := ASecond;
  Result.Millisecond := AMillisecond;
end;

procedure TTimeTests.CheckInstant(const AComponents: TUtcComponents;
  const AExpectedUnixMs: Int64);
var
  Instant: TUtcInstant;
  Back: TUtcComponents;
begin
  AssertTrue('valid', TUtcInstant.TryFromComponents(AComponents, Instant));
  AssertEquals('unix ms', AExpectedUnixMs, Instant.UnixMs);
  Back := TUtcInstant.FromUnixMs(AExpectedUnixMs).Components;
  AssertEquals('year', AComponents.Year, Back.Year);
  AssertEquals('month', AComponents.Month, Back.Month);
  AssertEquals('day', AComponents.Day, Back.Day);
  AssertEquals('hour', AComponents.Hour, Back.Hour);
  AssertEquals('minute', AComponents.Minute, Back.Minute);
  AssertEquals('second', AComponents.Second, Back.Second);
  AssertEquals('millisecond', AComponents.Millisecond, Back.Millisecond);
end;

procedure TTimeTests.ConvertsKnownInstants;
begin
  CheckInstant(Make(1970, 1, 1, 0, 0, 0, 0), 0);
  CheckInstant(Make(2026, 10, 18, 5, 52, 30, 250), 1792302750250);
  CheckInstant(Make(2024, 2, 29, 23, 59, 59, 0), 1709251199000);
  CheckInstant(Make(2000, 3, 1, 0, 0, 0, 0), 951868800000);
  CheckInstant(Make(9999, 12, 31, 23, 59, 59, 999), 253402300799999);
end;

procedure TTimeTests.RoundTripsComponents;
var
  Day: Integer;
  Instant: TUtcInstant;
  Components: TUtcComponents;
begin
  { Every day of a leap year, including the century rule for 2000. }
  for Day := 0 to 365 do
  begin
    Instant := TUtcInstant.FromUnixMs(Int64(946684800000) + Int64(Day) * 86400000);
    Components := Instant.Components;
    AssertTrue('day ' + IntToStr(Day),
      TUtcInstant.TryFromComponents(Components, Instant));
    AssertEquals('day ' + IntToStr(Day),
      Int64(946684800000) + Int64(Day) * 86400000, Instant.UnixMs);
  end;
end;

procedure TTimeTests.HandlesInstantsBefore1970;
begin
  CheckInstant(Make(1969, 12, 31, 23, 59, 59, 999), -1);
  CheckInstant(Make(1900, 1, 1, 0, 0, 0, 0), -2208988800000);
end;

procedure TTimeTests.ValidatesCalendar;
var
  Instant: TUtcInstant;
begin
  AssertFalse('2023-02-29', TUtcInstant.TryFromComponents(Make(2023, 2, 29, 0, 0, 0, 0), Instant));
  AssertFalse('1900-02-29', TUtcInstant.TryFromComponents(Make(1900, 2, 29, 0, 0, 0, 0), Instant));
  AssertTrue('2000-02-29', TUtcInstant.TryFromComponents(Make(2000, 2, 29, 0, 0, 0, 0), Instant));
  AssertFalse('month 13', TUtcInstant.TryFromComponents(Make(2026, 13, 1, 0, 0, 0, 0), Instant));
  AssertFalse('day 0', TUtcInstant.TryFromComponents(Make(2026, 1, 0, 0, 0, 0, 0), Instant));
  AssertFalse('hour 24', TUtcInstant.TryFromComponents(Make(2026, 1, 1, 24, 0, 0, 0), Instant));
  AssertFalse('second 60', TUtcInstant.TryFromComponents(Make(2026, 1, 1, 0, 0, 60, 0), Instant));
  AssertFalse('year 1899', TUtcInstant.TryFromComponents(Make(1899, 12, 31, 0, 0, 0, 0), Instant));
end;

procedure TTimeTests.FormatsAdifAndIso;
var
  Instant: TUtcInstant;
begin
  Instant := TUtcInstant.FromUnixMs(1792302750250);
  AssertEquals('20261018', Instant.ToAdifDate);
  AssertEquals('055230', Instant.ToAdifTime);
  AssertEquals('2026-10-18T05:52:30Z', Instant.ToIso8601);
end;

initialization
  RegisterTest(TTimeTests);
end.
