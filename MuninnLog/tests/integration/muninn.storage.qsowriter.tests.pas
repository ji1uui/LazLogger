unit Muninn.Storage.QsoWriter.Tests;

{ The QSO writer on SQLite (T13, ADR 0011): order, failures and retries, the
  queue limit, a crash with QSOs queued, and the entry line's speed with a
  100 000-QSO logbook. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Muninn.Core.Qso, Muninn.Core.Logbook,
  Muninn.Core.QsoWriter, Muninn.UI.QsoEntry;

type
  TWriterProbe = class
  public
    SavedTickets: array of Int64;
    SavedIds: TStringList;
    FailedTickets: array of Int64;
    LastError: string;
    constructor Create;
    destructor Destroy; override;
    procedure Saved(const ATicket: Int64; const AQsoId: string);
    procedure Failed(const ATicket: Int64; const AMessage: string);
  end;

  { Takes what the entry presenter shows; only timing matters here. }
  TSilentEntryView = class(TInterfacedObject, IQsoEntryView)
  public
    procedure ShowCallsignState(const ANormalized, AProblem: string);
    procedure ShowPartialMatches(const AMatches: TCallList; const ATotal: Integer);
    procedure ShowDuplicate(const AIsDuplicate: Boolean);
    procedure ShowLogged(const AQso: TLoggedQso);
    procedure ClearEntry;
    procedure ShowSaveState(const ATicket: Int64; const AState: TQsoSaveState;
      const AMessage: string);
    procedure ShowSaveStatus(const APending: Integer; const ALastSavedUtcMs: Int64;
      const ALastError: string);
  end;

  TQsoWriterTests = class(TTestCase)
  private
    FDirectory: string;
    FPath: string;
    FProbe: TWriterProbe;
    function NewQso(const ACall: string): TQsoRecord;
    procedure WaitUntil(const ASaved, AFailed: Integer);
    function Clock: Int64;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure SavesInOrder;
    procedure ReportsAFailureOnceAndRetries;
    procedure RefusesWhenTheQueueIsFull;
    procedure LoadsWorkedWithBandFromFrequency;
    procedure KeepsSavedQsosAfterAKill;
    procedure EntryStaysFastWithALargeLog;
  end;

implementation

uses
  Process, Muninn.Core.Mode, Muninn.Core.Time, Muninn.Core.Frequency,
  Muninn.Storage.Sqlite, Muninn.Storage.Logbook, Muninn.Storage.QsoWriter,
  Muninn.Storage.Schema;

const
  WaitLimitMs = 10000;

{ TWriterProbe }

constructor TWriterProbe.Create;
begin
  inherited Create;
  SavedIds := TStringList.Create;
end;

destructor TWriterProbe.Destroy;
begin
  SavedIds.Free;
  inherited Destroy;
end;

procedure TWriterProbe.Saved(const ATicket: Int64; const AQsoId: string);
begin
  SetLength(SavedTickets, Length(SavedTickets) + 1);
  SavedTickets[High(SavedTickets)] := ATicket;
  SavedIds.Add(AQsoId);
end;

procedure TWriterProbe.Failed(const ATicket: Int64; const AMessage: string);
begin
  SetLength(FailedTickets, Length(FailedTickets) + 1);
  FailedTickets[High(FailedTickets)] := ATicket;
  LastError := AMessage;
end;

{ TSilentEntryView }

procedure TSilentEntryView.ShowCallsignState(const ANormalized, AProblem: string);
begin
end;

procedure TSilentEntryView.ShowPartialMatches(const AMatches: TCallList;
  const ATotal: Integer);
begin
end;

procedure TSilentEntryView.ShowDuplicate(const AIsDuplicate: Boolean);
begin
end;

procedure TSilentEntryView.ShowLogged(const AQso: TLoggedQso);
begin
end;

procedure TSilentEntryView.ClearEntry;
begin
end;

procedure TSilentEntryView.ShowSaveState(const ATicket: Int64;
  const AState: TQsoSaveState; const AMessage: string);
begin
end;

procedure TSilentEntryView.ShowSaveStatus(const APending: Integer;
  const ALastSavedUtcMs: Int64; const ALastError: string);
begin
end;

{ TQsoWriterTests }

procedure TQsoWriterTests.SetUp;
begin
  FDirectory := IncludeTrailingPathDelimiter(GetTempDir(False)) +
    Format('muninn-writer-%d-%d', [GetProcessID, Random(MaxInt)]);
  ForceDirectories(FDirectory);
  FPath := IncludeTrailingPathDelimiter(FDirectory) + 'log.muninnlog';
  TSqliteLogbookStore.Create.CreateNew(FPath);
  FProbe := TWriterProbe.Create;
end;

procedure TQsoWriterTests.TearDown;
var
  Search: TSearchRec;
begin
  { Results still queued for a freed writer are dropped; let them go. }
  CheckSynchronize(20);
  FProbe.Free;
  if FindFirst(IncludeTrailingPathDelimiter(FDirectory) + AllFilesMask, faAnyFile,
    Search) = 0 then
    try
      repeat
        DeleteFile(IncludeTrailingPathDelimiter(FDirectory) + Search.Name);
      until FindNext(Search) <> 0;
    finally
      FindClose(Search);
    end;
  RemoveDir(FDirectory);
end;

function TQsoWriterTests.Clock: Int64;
begin
  Result := 1700000000000;
end;

function TQsoWriterTests.NewQso(const ACall: string): TQsoRecord;
var
  Mode: TMode;
begin
  AssertTrue(TMode.TryCreate('CW', '', Mode));
  Result := TQsoRecord.Create;
  Result.Call := ACall;
  Result.TimeOn := TUtcInstant.FromUnixMs(1700000000000);
  Result.FrequencyHz := 7010000;
  Result.Band := '40m';
  Result.Mode := Mode;
end;

procedure TQsoWriterTests.WaitUntil(const ASaved, AFailed: Integer);
var
  Deadline: QWord;
begin
  Deadline := GetTickCount64 + WaitLimitMs;
  while ((Length(FProbe.SavedTickets) < ASaved) or
    (Length(FProbe.FailedTickets) < AFailed)) and (GetTickCount64 < Deadline) do
    CheckSynchronize(5);
  AssertTrue(Format('saved %d of %d, failed %d of %d in time',
    [Length(FProbe.SavedTickets), ASaved, Length(FProbe.FailedTickets), AFailed]),
    (Length(FProbe.SavedTickets) >= ASaved) and
    (Length(FProbe.FailedTickets) >= AFailed));
end;

procedure TQsoWriterTests.SavesInOrder;
var
  Logbook: ILogbook;
  Writer: IQsoWriter;
  Tickets: array[1..20] of Int64;
  Index: Integer;
  Database: TSqliteDatabase;
  Statement: TSqliteStatement;
begin
  Logbook := TSqliteLogbookStore.Create.Open(FPath);
  Writer := Logbook.CreateWriter;
  Writer.SetOnSaved(@FProbe.Saved);
  for Index := 1 to 20 do
    Tickets[Index] := Writer.Submit(NewQso(Format('JA1S%.2d', [Index])));
  WaitUntil(20, 0);
  for Index := 1 to 20 do
    AssertEquals('result order', Tickets[Index], FProbe.SavedTickets[Index - 1]);
  AssertEquals(0, Writer.PendingCount);
  Writer := nil;
  Database := OpenLogDatabase(FPath);
  try
    Statement := TSqliteStatement.Create(Database,
      'SELECT call, source FROM qso ORDER BY rowid');
    try
      for Index := 1 to 20 do
      begin
        AssertTrue(Statement.Step);
        AssertEquals(Format('JA1S%.2d', [Index]), Statement.ColumnText(0));
        AssertEquals('entry', Statement.ColumnText(1));
      end;
      AssertFalse(Statement.Step);
    finally
      Statement.Free;
    end;
  finally
    Database.Free;
  end;
end;

procedure TQsoWriterTests.ReportsAFailureOnceAndRetries;
var
  Writer: IQsoWriter;
  Other: TSqliteDatabase;
  Deadline: QWord;
begin
  Other := OpenLogDatabase(FPath);
  try
    Other.Execute('CREATE TRIGGER refuse BEFORE INSERT ON qso ' +
      'BEGIN SELECT RAISE(ABORT, ''refused for the test''); END');
    Writer := TSqliteQsoWriter.Create(OpenLogDatabase(FPath), 'entry', 30);
    Writer.SetOnSaved(@FProbe.Saved);
    Writer.SetOnFailed(@FProbe.Failed);
    Writer.Submit(NewQso('JA1F01'));
    Writer.Submit(NewQso('JA1F02'));
    WaitUntil(0, 1);
    { Several retries later, still one report for the same error. }
    Deadline := GetTickCount64 + 300;
    while GetTickCount64 < Deadline do
      CheckSynchronize(10);
    AssertEquals('reported once', 1, Length(FProbe.FailedTickets));
    AssertTrue('the message', Pos('refused for the test', FProbe.LastError) > 0);
    AssertEquals('nothing saved out of order', 0, Length(FProbe.SavedTickets));
    AssertEquals(2, Writer.PendingCount);
    Other.Execute('DROP TRIGGER refuse');
  finally
    Other.Free;
  end;
  WaitUntil(2, 1);
  AssertTrue('in order', FProbe.SavedTickets[0] < FProbe.SavedTickets[1]);
  Writer := nil;
end;

procedure TQsoWriterTests.RefusesWhenTheQueueIsFull;
var
  Writer: IQsoWriter;
  Other: TSqliteDatabase;
  Index: Integer;
begin
  Other := OpenLogDatabase(FPath);
  try
    Other.Execute('CREATE TRIGGER refuse BEFORE INSERT ON qso ' +
      'BEGIN SELECT RAISE(ABORT, ''full''); END');
    Writer := TSqliteQsoWriter.Create(OpenLogDatabase(FPath), 'entry', 5000);
    for Index := 1 to TSqliteQsoWriter.MaxPending do
      Writer.Submit(NewQso('JA1Q'));
    try
      Writer.Submit(NewQso('JA1QX'));
      Fail('accepted beyond the limit');
    except
      on EQsoQueueFull do ;
    end;
    AssertEquals(TSqliteQsoWriter.MaxPending, Writer.PendingCount);
    Other.Execute('DROP TRIGGER refuse');
  finally
    Other.Free;
  end;
  AssertTrue('drains once the cause is gone', Writer.Flush(WaitLimitMs));
  Writer := nil;
end;

procedure TQsoWriterTests.LoadsWorkedWithBandFromFrequency;
var
  Logbook: ILogbook;
  Database: TSqliteDatabase;
  Worked: TWorkedEntries;
begin
  Database := OpenLogDatabase(FPath);
  try
    Database.Execute('INSERT INTO qso (id, call, time_on_ms, freq_hz, band, mode, ' +
      'station_callsign, created_at_ms, updated_at_ms) VALUES ' +
      '(''a'', ''ja1abc'', 0, 14074000, NULL, ''ft8'', '''', 0, 0), ' +
      '(''b'', ''JA1ABD'', 0, NULL, ''40M'', ''CW'', '''', 0, 0), ' +
      '(''c'', ''JA1ABE'', 0, NULL, NULL, ''CW'', '''', 0, 0)');
  finally
    Database.Free;
  end;
  Logbook := TSqliteLogbookStore.Create.Open(FPath);
  Worked := Logbook.LoadWorked;
  AssertEquals(3, Length(Worked));
  AssertEquals('JA1ABC', Worked[0].Call);
  AssertEquals('band from the frequency', '20m', Worked[0].Band);
  AssertEquals('FT8', Worked[0].Mode);
  AssertEquals('40m', Worked[1].Band);
  AssertEquals('no band known', '', Worked[2].Band);
end;

procedure TQsoWriterTests.KeepsSavedQsosAfterAKill;
var
  IdsPath, Helper, Output: string;
  Ids: TStringList;
  Database: TSqliteDatabase;
  Index: Integer;
begin
  IdsPath := IncludeTrailingPathDelimiter(FDirectory) + 'saved.txt';
  Helper := ExtractFilePath(ParamStr(0)) + 'muninn-crash-helper' +
    ExtractFileExt(ParamStr(0));
  RunCommand(Helper, ['writer', FPath, IdsPath], Output, [poNoConsole]);
  Ids := TStringList.Create;
  try
    Ids.LoadFromFile(IdsPath);
    AssertTrue('the helper saw QSOs saved', Ids.Count >= 50);
    Database := OpenLogDatabase(FPath);
    try
      AssertEquals('ok', Database.QueryText('PRAGMA integrity_check'));
      for Index := 0 to Ids.Count - 1 do
        AssertEquals('saved QSO ' + Ids[Index] + ' is there', 1,
          Database.QueryInt64('SELECT count(*) FROM qso WHERE id = ''' +
          Ids[Index] + ''''));
    finally
      Database.Free;
    end;
  finally
    Ids.Free;
  end;
end;

procedure TQsoWriterTests.EntryStaysFastWithALargeLog;
const
  LogSize = 100000;
  Texts: array[0..7] of string = ('J', 'JA', 'JA1', 'JA1A', 'JA1AB', '7K', '1AB', 'DL1');
var
  Database: TSqliteDatabase;
  Logbook: ILogbook;
  Worked: TWorkedEntries;
  ViewRef: IQsoEntryView;
  Presenter: TQsoEntryPresenter;
  Frequency: TFrequencyHz;
  Samples: array of QWord;
  Started, LoadMs: QWord;
  Round, Index, J: Integer;
  Value: QWord;
begin
  Database := OpenLogDatabase(FPath);
  try
    { 100 000 distinct calls on 40 m CW, written in one statement. }
    Database.Execute('WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 ' +
      'FROM n WHERE i < ' + IntToStr(LogSize) + ') ' +
      'INSERT INTO qso (id, call, time_on_ms, freq_hz, band, mode, ' +
      'station_callsign, created_at_ms, updated_at_ms) ' +
      'SELECT ''q'' || i, ''JA'' || (i % 10) || ''X'' || i, i, 7010000, ''40m'', ' +
      '''CW'', '''', 0, 0 FROM n');
  finally
    Database.Free;
  end;
  Logbook := TSqliteLogbookStore.Create.Open(FPath);
  Started := GetTickCount64;
  Worked := Logbook.LoadWorked;
  ViewRef := TSilentEntryView.Create;
  Presenter := TQsoEntryPresenter.Create(ViewRef, @Clock);
  try
    Presenter.AttachLog(nil, Worked);
    LoadMs := GetTickCount64 - Started;
    AssertEquals(LogSize, Length(Worked));
    AssertTrue(TFrequencyHz.TryFromHz(7010000, Frequency));
    Presenter.SetFrequency(Frequency);
    Samples := nil;
    for Round := 1 to 10 do
      for Index := 0 to High(Texts) do
      begin
        Started := GetTickCount64;
        Presenter.CallsignChanged(Texts[Index]);
        SetLength(Samples, Length(Samples) + 1);
        Samples[High(Samples)] := GetTickCount64 - Started;
      end;
    for Index := 1 to High(Samples) do
    begin
      Value := Samples[Index];
      J := Index - 1;
      while (J >= 0) and (Samples[J] > Value) do
      begin
        Samples[J + 1] := Samples[J];
        Dec(J);
      end;
      Samples[J + 1] := Value;
    end;
    { Shown in the test log; the budget is one frame. }
    WriteLn(Format('  100 000-QSO log: load %d ms, keystroke p95 %d ms, max %d ms',
      [LoadMs, Samples[Length(Samples) * 95 div 100], Samples[High(Samples)]]));
    AssertTrue('keystroke p95 within 16 ms',
      Samples[Length(Samples) * 95 div 100] <= 16);
    Presenter.CallsignChanged('JA1X1');
    AssertTrue('the log is used for duplicates', Presenter.IsDuplicate('JA1X1'));
  finally
    Presenter.Free;
  end;
end;

initialization
  RegisterTest(TQsoWriterTests);

end.
