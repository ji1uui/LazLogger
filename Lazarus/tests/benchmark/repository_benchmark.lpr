program ZLogRepositoryBenchmark;

{$mode objfpc}{$H+}

uses
  SysUtils, ZLog.Domain.Types, ZLog.Domain.Qso, ZLog.Application.Ports,
  ZLog.Infrastructure.Memory;

const
  RecordCount = 100000;
  LookupCount = 10000;
  RecentQueryCount = 1000;
  RecentPageSize = 50;

var
  Repository: IQsoRepository;
  Callsign: TCallsign;
  Frequency: TFrequencyHz;
  Qso: TQso;
  Index: Integer;
  StartedAt, InsertMs, LookupMs, RecentMs: QWord;
  Id: string;
  Recent: TQsoSnapshotArray;
begin
  if not TCallsign.TryCreate('JA1ZLO', Callsign) then
    Halt(1);
  if not TFrequencyHz.TryCreate(7000000, Frequency) then
    Halt(1);
  Repository := TInMemoryQsoRepository.Create;

  StartedAt := GetTickCount64;
  for Index := 1 to RecordCount do
  begin
    Id := 'qso-' + Format('%.8d', [Index]);
    Qso := TQso.Create(Id, Callsign, Frequency, emCW, '599 001', '599 002', Index);
    try
      Repository.Add(Qso);
    finally
      Qso.Free;
    end;
  end;
  InsertMs := GetTickCount64 - StartedAt;

  StartedAt := GetTickCount64;
  for Index := 1 to LookupCount do
  begin
    Id := 'qso-' + Format('%.8d', [((Index * 7919) mod RecordCount) + 1]);
    Qso := Repository.FindById(Id);
    if not Assigned(Qso) then
      raise Exception.CreateFmt('Missing benchmark QSO: %s', [Id]);
    Qso.Free;
  end;
  LookupMs := GetTickCount64 - StartedAt;

  StartedAt := GetTickCount64;
  for Index := 1 to RecentQueryCount do
  begin
    Recent := Repository.GetRecent(RecentPageSize);
    if (Length(Recent) <> RecentPageSize) or
      (Recent[0].Id <> 'qso-00100000') then
      raise Exception.Create('Invalid recent QSO page');
  end;
  RecentMs := GetTickCount64 - StartedAt;

  WriteLn('{"records":', Repository.Count, ',"insert_ms":', InsertMs,
    ',"lookups":', LookupCount, ',"lookup_ms":', LookupMs,
    ',"recent_queries":', RecentQueryCount, ',"recent_page_size":',
    RecentPageSize, ',"recent_ms":', RecentMs, '}');
end.
