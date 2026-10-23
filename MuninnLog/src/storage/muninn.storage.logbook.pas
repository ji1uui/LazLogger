unit Muninn.Storage.Logbook;

{ The logbook port (Muninn.Core.Logbook) on SQLite: a logbook is one SQLite
  file opened with OpenLogDatabase (ADR 0003). Storage errors are reported as
  ELogbookError with a kind the UI can explain. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Muninn.Core.Logbook, Muninn.Core.QsoWriter, Muninn.Storage.Sqlite;

type
  TSqliteLogbook = class(TInterfacedObject, ILogbook)
  private
    FDatabase: TSqliteDatabase;
  public
    { Takes ownership of ADatabase. }
    constructor Create(const ADatabase: TSqliteDatabase);
    destructor Destroy; override;
    function Path: string;
    function QsoCount: Int64;
    function LoadWorked: TWorkedEntries;
    function CreateWriter: IQsoWriter;
    property Database: TSqliteDatabase read FDatabase;
  end;

  TSqliteLogbookStore = class(TInterfacedObject, ILogbookStore)
  public
    function Open(const APath: string): ILogbook;
    function CreateNew(const APath: string): ILogbook;
  end;

const
  { qso.source of QSOs typed in the entry line. }
  EntrySource = 'entry';

implementation

uses
  Muninn.Core.Frequency, Muninn.Core.Band, Muninn.Storage.Schema,
  Muninn.Storage.QsoWriter;

const
  SQLITE_BUSY = 5;
  SQLITE_LOCKED = 6;
  SQLITE_CORRUPT = 11;
  SQLITE_NOTADB = 26;

{ TSqliteLogbook }

constructor TSqliteLogbook.Create(const ADatabase: TSqliteDatabase);
begin
  inherited Create;
  FDatabase := ADatabase;
end;

destructor TSqliteLogbook.Destroy;
begin
  FDatabase.Free;
  inherited Destroy;
end;

function TSqliteLogbook.Path: string;
begin
  Result := FDatabase.Path;
end;

function TSqliteLogbook.QsoCount: Int64;
begin
  Result := FDatabase.QueryInt64('SELECT count(*) FROM qso');
end;

function TSqliteLogbook.LoadWorked: TWorkedEntries;
var
  Statement: TSqliteStatement;
  Count: Integer;
  Frequency: TFrequencyHz;
  Band: TBand;
begin
  Result := nil;
  SetLength(Result, QsoCount);
  Count := 0;
  Statement := TSqliteStatement.Create(FDatabase,
    'SELECT call, band, freq_hz, mode FROM qso');
  try
    while Statement.Step do
    begin
      if Count = Length(Result) then
        SetLength(Result, Count * 2 + 16);
      Result[Count].Call := UpperCase(Statement.ColumnText(0));
      Result[Count].Band := LowerCase(Statement.ColumnText(1));
      { A QSO with a frequency but no band (allowed by ADIF) gets the band of
        its frequency. }
      if (Result[Count].Band = '') and not Statement.ColumnIsNull(2) and
        TFrequencyHz.TryFromHz(Statement.ColumnInt64(2), Frequency) and
        TryBandOfFrequency(Frequency, Band) then
        Result[Count].Band := BandAdifName(Band);
      Result[Count].Mode := UpperCase(Statement.ColumnText(3));
      Inc(Count);
    end;
  finally
    Statement.Free;
  end;
  SetLength(Result, Count);
end;

function TSqliteLogbook.CreateWriter: IQsoWriter;
begin
  { Its own connection: the writer's thread is its only user. }
  Result := TSqliteQsoWriter.Create(OpenLogDatabase(FDatabase.Path), EntrySource);
end;

{ TSqliteLogbookStore }

function OpenAsLogbook(const APath: string): ILogbook;
begin
  try
    Result := TSqliteLogbook.Create(OpenLogDatabase(APath));
  except
    on E: ESchemaNewerError do
      raise ELogbookError.CreateKind(lekNewerVersion, E.Message);
    on E: ESqliteError do
      case E.ResultCode and $FF of
        SQLITE_BUSY, SQLITE_LOCKED:
          raise ELogbookError.CreateKind(lekBusy, E.Message);
        SQLITE_NOTADB, SQLITE_CORRUPT:
          raise ELogbookError.CreateKind(lekNotALogbook, E.Message);
      else
        raise ELogbookError.CreateKind(lekFailed, E.Message);
      end;
    on E: ESchemaError do
      raise ELogbookError.CreateKind(lekFailed, E.Message);
  end;
end;

{ True when APath already holds a MuninnLog logbook: a schema version of at
  least 1 and a qso table. Only reads, so another SQLite database or a file
  of another kind is not changed (no WAL switch, no migration). }
function IsLogbookFile(const APath: string): Boolean;
var
  Database: TSqliteDatabase;
begin
  Database := TSqliteDatabase.Open(APath);
  try
    Result := (SchemaVersion(Database) >= 1) and (Database.QueryInt64(
      'SELECT count(*) FROM sqlite_master WHERE type = ''table'' AND name = ''qso''') = 1);
  finally
    Database.Free;
  end;
end;

function TSqliteLogbookStore.Open(const APath: string): ILogbook;
var
  IsLogbook: Boolean;
begin
  { SQLite would create a missing file; opening must not. }
  if not FileExists(APath) then
    raise ELogbookError.CreateKind(lekNotFound, APath + ' does not exist');
  try
    IsLogbook := IsLogbookFile(APath);
  except
    on E: ESqliteError do
      case E.ResultCode and $FF of
        SQLITE_BUSY, SQLITE_LOCKED:
          raise ELogbookError.CreateKind(lekBusy, E.Message);
        SQLITE_NOTADB, SQLITE_CORRUPT:
          raise ELogbookError.CreateKind(lekNotALogbook, E.Message);
      else
        raise ELogbookError.CreateKind(lekFailed, E.Message);
      end;
  end;
  { An empty file, another application's database, or a logbook whose
    creation was cut off before its first migration. }
  if not IsLogbook then
    raise ELogbookError.CreateKind(lekNotALogbook,
      APath + ' is not a MuninnLog logbook');
  Result := OpenAsLogbook(APath);
end;

function TSqliteLogbookStore.CreateNew(const APath: string): ILogbook;
begin
  if FileExists(APath) or DirectoryExists(APath) then
    raise ELogbookError.CreateKind(lekAlreadyExists, APath + ' already exists');
  Result := OpenAsLogbook(APath);
end;

end.
