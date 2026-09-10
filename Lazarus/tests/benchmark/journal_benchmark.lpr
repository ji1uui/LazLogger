program ZLogJournalBenchmark;

{$mode objfpc}{$H+}

uses
  SysUtils, ZLog.Domain.Types, ZLog.Domain.Qso, ZLog.Application.Ports,
  ZLog.Application.LogQso, ZLog.Infrastructure.Journal,
  ZLog.Infrastructure.Deterministic;

const
  DefaultIterations = 200;

procedure Sort(var AValues: array of QWord; const ALeft, ARight: Integer);
var
  LeftIndex, RightIndex: Integer;
  Pivot, Temporary: QWord;
begin
  LeftIndex := ALeft;
  RightIndex := ARight;
  Pivot := AValues[(ALeft + ARight) div 2];
  repeat
    while AValues[LeftIndex] < Pivot do Inc(LeftIndex);
    while AValues[RightIndex] > Pivot do Dec(RightIndex);
    if LeftIndex <= RightIndex then
    begin
      Temporary := AValues[LeftIndex];
      AValues[LeftIndex] := AValues[RightIndex];
      AValues[RightIndex] := Temporary;
      Inc(LeftIndex);
      Dec(RightIndex);
    end;
  until LeftIndex > RightIndex;
  if ALeft < RightIndex then Sort(AValues, ALeft, RightIndex);
  if LeftIndex < ARight then Sort(AValues, LeftIndex, ARight);
end;

function IterationCount: Integer;
begin
  Result := DefaultIterations;
  if ParamCount > 0 then
    Result := StrToInt(ParamStr(1));
  if Result <= 0 then
    raise EArgumentOutOfRangeException.Create('Iteration count must be positive');
end;

var
  Count, Index, P95Index: Integer;
  FileName: string;
  Repository: IQsoRepository;
  UseCase: ILogQsoUseCase;
  Draft: TQsoDraft;
  LogResult: TLogQsoResult;
  Durations: array of QWord;
  StartedAt, TotalStartedAt, TotalMs: QWord;
begin
  Count := IterationCount;
  FileName := IncludeTrailingPathDelimiter(GetTempDir(False)) +
    'zlog-journal-benchmark.bin';
  DeleteFile(FileName);
  SetLength(Durations, Count);
  Repository := TJournalQsoRepository.Create(FileName);
  UseCase := TLogQsoUseCase.Create(Repository, TFixedClock.Create(1900000000000),
    TSequentialIdGenerator.Create('benchmark-'));
  Draft.Callsign := 'JA1ZLO';
  Draft.FrequencyHz := 7000000;
  Draft.Mode := emCW;
  Draft.SentExchange := '599 001';
  Draft.ReceivedExchange := '599 002';

  TotalStartedAt := GetTickCount64;
  for Index := 0 to Count - 1 do
  begin
    StartedAt := GetTickCount64;
    LogResult := UseCase.Execute(Draft);
    Durations[Index] := GetTickCount64 - StartedAt;
    if not LogResult.Success then
      raise Exception.CreateFmt('QSO %d was rejected', [Index]);
  end;
  TotalMs := GetTickCount64 - TotalStartedAt;
  Sort(Durations, 0, High(Durations));
  P95Index := ((Count * 95) + 99) div 100 - 1;
  WriteLn('{"iterations":', Count, ',"total_ms":', TotalMs,
    ',"p95_ms":', Durations[P95Index], ',"max_ms":', Durations[High(Durations)],
    ',"records":', Repository.Count, '}');
  Repository := nil;
  UseCase := nil;
  DeleteFile(FileName);
end.
