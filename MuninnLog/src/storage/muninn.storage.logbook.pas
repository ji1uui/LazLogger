unit Muninn.Storage.Logbook;

{ The logbook port (Muninn.Core.Logbook) on SQLite: a logbook is one SQLite
  file opened with OpenLogDatabase (ADR 0003). Storage errors are reported as
  ELogbookError with a kind the UI can explain. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Muninn.Core.Logbook, Muninn.Storage.Sqlite;

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
    property Database: TSqliteDatabase read FDatabase;
  end;

  TSqliteLogbookStore = class(TInterfacedObject, ILogbookStore)
  public
    function Open(const APath: string): ILogbook;
    function CreateNew(const APath: string): ILogbook;
  end;

implementation

uses
  Muninn.Storage.Schema;

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

function TSqliteLogbookStore.Open(const APath: string): ILogbook;
begin
  { SQLite would create a missing file; opening must not. }
  if not FileExists(APath) then
    raise ELogbookError.CreateKind(lekNotFound, APath + ' does not exist');
  Result := OpenAsLogbook(APath);
end;

function TSqliteLogbookStore.CreateNew(const APath: string): ILogbook;
begin
  if FileExists(APath) or DirectoryExists(APath) then
    raise ELogbookError.CreateKind(lekAlreadyExists, APath + ' already exists');
  Result := OpenAsLogbook(APath);
end;

end.
