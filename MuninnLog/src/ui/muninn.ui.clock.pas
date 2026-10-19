unit Muninn.UI.Clock;

{ A microsecond counter for measuring the UI's response times (ADR 0009).
  Only differences between two readings mean anything. }

{$mode objfpc}{$H+}

interface

function MicroTicks: Int64;

implementation

{$IFDEF WINDOWS}
uses
  Windows;

var
  Frequency: Int64 = 0;

function MicroTicks: Int64;
var
  Counter: Int64;
begin
  if Frequency = 0 then
    QueryPerformanceFrequency(Frequency);
  QueryPerformanceCounter(Counter);
  Result := Counter div Frequency * 1000000 +
    (Counter mod Frequency) * 1000000 div Frequency;
end;
{$ELSE}
uses
  BaseUnix, Unix;

{ The wall clock: good enough for measurements of milliseconds, but a clock
  change during one would spoil it. }
function MicroTicks: Int64;
var
  Time: TTimeVal;
begin
  fpgettimeofday(@Time, nil);
  Result := Int64(Time.tv_sec) * 1000000 + Time.tv_usec;
end;
{$ENDIF}

end.
