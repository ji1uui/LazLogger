unit Muninn.Storage.Sqlite;

{ A thin wrapper over the SQLite C API, loaded at run time through FPC's
  sqlite3dyn (ADR 0003). Text is exchanged with SQLite as UTF-8.
  Errors raise ESqliteError; the caller owns every object it creates.
  Not thread-safe: use one TSqliteDatabase per thread. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, sqlite3dyn;

const
  { STRICT tables need SQLite 3.37.0. }
  MinimumSqliteVersionNumber = 3037000;
  { Set this environment variable to load a specific SQLite library file. }
  SqliteLibraryEnvironmentVariable = 'MUNINN_SQLITE_LIBRARY';
  { How long a statement waits for another connection's lock. }
  BusyTimeoutMs = 5000;

type
  ESqliteError = class(Exception)
  private
    FResultCode: Integer;
  public
    constructor CreateCode(const AResultCode: Integer; const AMessage: string);
    { The extended SQLite result code; 0 when the error is not from SQLite. }
    property ResultCode: Integer read FResultCode;
  end;

  TSqliteDatabase = class;

  TSqliteStatement = class
  private
    FDatabase: TSqliteDatabase;
    FHandle: psqlite3_stmt;
    procedure CheckBind(const AResultCode: Integer);
  public
    { Parameter and column indexes follow SQLite: parameters from 1, columns from 0. }
    constructor Create(const ADatabase: TSqliteDatabase; const ASql: string);
    destructor Destroy; override;
    procedure BindInt64(const AIndex: Integer; const AValue: Int64);
    procedure BindText(const AIndex: Integer; const AValue: string);
    procedure BindNull(const AIndex: Integer);
    { True when a row is ready; False when the statement has finished. }
    function Step: Boolean;
    procedure Reset;
    function ColumnIsNull(const AIndex: Integer): Boolean;
    function ColumnInt64(const AIndex: Integer): Int64;
    function ColumnText(const AIndex: Integer): string;
  end;

  TSqliteDatabase = class
  private
    FHandle: psqlite3;
    FPath: string;
  public
    { Opens the database file, creating it when it does not exist, with a
      busy timeout of BusyTimeoutMs. }
    constructor Open(const APath: string);
    destructor Destroy; override;
    { Runs one or more statements that return no rows. }
    procedure Execute(const ASql: string);
    { The first column of the first row; raises when there is no row. }
    function QueryInt64(const ASql: string): Int64;
    function QueryText(const ASql: string): string;
    { BEGIN IMMEDIATE: takes the write lock at the start. }
    procedure BeginTransaction;
    procedure Commit;
    procedure Rollback;
    function InTransaction: Boolean;
    property Path: string read FPath;
    property Handle: psqlite3 read FHandle;
  end;

{ Loads the SQLite library once per process. Tries the library named by
  MUNINN_SQLITE_LIBRARY when it is set, otherwise the usual names for the OS.
  Raises ESqliteError when no library loads or it is older than 3.37.0. }
procedure LoadSqliteLibrary;
function SqliteLibraryVersion: string;
function LoadedSqliteLibraryName: string;

implementation

var
  LibraryLoaded: Boolean = False;

function LibraryCandidates: TStringArray;
var
  Overridden: string;
begin
  Overridden := GetEnvironmentVariable(SqliteLibraryEnvironmentVariable);
  if Overridden <> '' then
    Exit([Overridden]);
{$IF defined(WINDOWS)}
  Result := ['sqlite3.dll'];
{$ELSEIF defined(DARWIN)}
  Result := ['libsqlite3.dylib', '/usr/lib/libsqlite3.dylib'];
{$ELSE}
  { libsqlite3.so comes only with the -dev package; the runtime package has .so.0. }
  Result := ['libsqlite3.so.0', 'libsqlite3.so'];
{$ENDIF}
end;

procedure LoadSqliteLibrary;
var
  Candidate: string;
  Tried: string;
begin
  if LibraryLoaded then
    Exit;
  Tried := '';
  for Candidate in LibraryCandidates do
  begin
    if TryInitializeSqlite(UnicodeString(Candidate)) > 0 then
    begin
      { A library that is not SQLite loads but leaves the entry points nil. }
      if (Pointer(sqlite3_libversion_number) = nil) or (Pointer(sqlite3_open_v2) = nil) or
        (Pointer(sqlite3_prepare_v2) = nil) or (Pointer(sqlite3_busy_timeout) = nil) then
      begin
        ReleaseSqlite;
        raise ESqliteError.CreateCode(0, Format(
          '%s is not an SQLite library. Set %s to the SQLite library.',
          [Candidate, SqliteLibraryEnvironmentVariable]));
      end;
      if sqlite3_libversion_number() < MinimumSqliteVersionNumber then
      begin
        Tried := string(sqlite3_libversion());
        ReleaseSqlite;
        raise ESqliteError.CreateCode(0, Format(
          'SQLite %s is too old; MuninnLog needs 3.37.0 or later', [Tried]));
      end;
      LibraryLoaded := True;
      Exit;
    end;
    if Tried <> '' then
      Tried := Tried + ', ';
    Tried := Tried + Candidate;
  end;
  raise ESqliteError.CreateCode(0, Format(
    'Cannot load the SQLite library (tried: %s). Set %s to its path.',
    [Tried, SqliteLibraryEnvironmentVariable]));
end;

function SqliteLibraryVersion: string;
begin
  LoadSqliteLibrary;
  Result := string(sqlite3_libversion());
end;

function LoadedSqliteLibraryName: string;
begin
  LoadSqliteLibrary;
  Result := string(SQLiteLoadedLibrary);
end;

function Utf8Text(const AText: string): UTF8String;
begin
  Result := UTF8String(AText);
end;

function TextFromUtf8(const AText: PAnsiChar; const ALength: Integer): string;
var
  Raw: UTF8String;
begin
  SetString(Raw, AText, ALength);
  Result := string(Raw);
end;

procedure RaiseDatabaseError(const AHandle: psqlite3; const AResultCode: Integer;
  const AContext: string);
var
  Message: string;
begin
  if AHandle <> nil then
    Message := string(UTF8String(sqlite3_errmsg(AHandle)))
  else
    Message := string(sqlite3_errstr(AResultCode));
  raise ESqliteError.CreateCode(AResultCode,
    Format('%s: %s (SQLite code %d)', [AContext, Message, AResultCode]));
end;

{ ESqliteError }

constructor ESqliteError.CreateCode(const AResultCode: Integer;
  const AMessage: string);
begin
  inherited Create(AMessage);
  FResultCode := AResultCode;
end;

{ TSqliteStatement }

constructor TSqliteStatement.Create(const ADatabase: TSqliteDatabase;
  const ASql: string);
var
  Sql: UTF8String;
  ResultCode: Integer;
begin
  inherited Create;
  FDatabase := ADatabase;
  Sql := Utf8Text(ASql);
  ResultCode := sqlite3_prepare_v2(FDatabase.Handle, PAnsiChar(Sql), Length(Sql),
    @FHandle, nil);
  if ResultCode <> SQLITE_OK then
    RaiseDatabaseError(FDatabase.Handle, ResultCode, 'Prepare failed');
  if FHandle = nil then
    raise ESqliteError.CreateCode(0, 'Prepare failed: the SQL has no statement');
end;

destructor TSqliteStatement.Destroy;
begin
  if FHandle <> nil then
    sqlite3_finalize(FHandle);
  inherited Destroy;
end;

procedure TSqliteStatement.CheckBind(const AResultCode: Integer);
begin
  if AResultCode <> SQLITE_OK then
    RaiseDatabaseError(FDatabase.Handle, AResultCode, 'Bind failed');
end;

procedure TSqliteStatement.BindInt64(const AIndex: Integer; const AValue: Int64);
begin
  CheckBind(sqlite3_bind_int64(FHandle, AIndex, AValue));
end;

procedure TSqliteStatement.BindText(const AIndex: Integer; const AValue: string);
var
  Value: UTF8String;
begin
  Value := Utf8Text(AValue);
  { SQLITE_TRANSIENT: SQLite copies the text, so Value may go out of scope. }
  CheckBind(sqlite3_bind_text(FHandle, AIndex, PAnsiChar(Value), Length(Value),
    sqlite3_destructor_type(SQLITE_TRANSIENT)));
end;

procedure TSqliteStatement.BindNull(const AIndex: Integer);
begin
  CheckBind(sqlite3_bind_null(FHandle, AIndex));
end;

function TSqliteStatement.Step: Boolean;
var
  ResultCode: Integer;
begin
  ResultCode := sqlite3_step(FHandle);
  case ResultCode of
    SQLITE_ROW: Result := True;
    SQLITE_DONE: Result := False;
  else
    RaiseDatabaseError(FDatabase.Handle, ResultCode, 'Step failed');
    Result := False;
  end;
end;

procedure TSqliteStatement.Reset;
begin
  sqlite3_reset(FHandle);
  sqlite3_clear_bindings(FHandle);
end;

function TSqliteStatement.ColumnIsNull(const AIndex: Integer): Boolean;
begin
  Result := sqlite3_column_type(FHandle, AIndex) = SQLITE_NULL;
end;

function TSqliteStatement.ColumnInt64(const AIndex: Integer): Int64;
begin
  Result := sqlite3_column_int64(FHandle, AIndex);
end;

function TSqliteStatement.ColumnText(const AIndex: Integer): string;
var
  Text: PAnsiChar;
begin
  { Call column_text before column_bytes, as the SQLite documentation advises. }
  Text := sqlite3_column_text(FHandle, AIndex);
  Result := TextFromUtf8(Text, sqlite3_column_bytes(FHandle, AIndex));
end;

{ TSqliteDatabase }

constructor TSqliteDatabase.Open(const APath: string);
var
  FileName: UTF8String;
  ResultCode: Integer;
begin
  inherited Create;
  LoadSqliteLibrary;
  FPath := APath;
  FileName := Utf8Text(APath);
  ResultCode := sqlite3_open_v2(PAnsiChar(FileName), @FHandle,
    SQLITE_OPEN_READWRITE or SQLITE_OPEN_CREATE, nil);
  if ResultCode <> SQLITE_OK then
    RaiseDatabaseError(FHandle, ResultCode, 'Cannot open ' + APath);
  sqlite3_extended_result_codes(FHandle, 1);
  { Set before the first statement: reading the schema version or switching the
    journal mode must also wait for another connection instead of failing. }
  sqlite3_busy_timeout(FHandle, BusyTimeoutMs);
end;

destructor TSqliteDatabase.Destroy;
begin
  { Also reached when Open raises; sqlite3_close_v2 accepts the handle it left. }
  if FHandle <> nil then
    sqlite3_close_v2(FHandle);
  inherited Destroy;
end;

procedure TSqliteDatabase.Execute(const ASql: string);
var
  Sql: UTF8String;
  ErrorText: PAnsiChar;
  Message: string;
  ResultCode: Integer;
begin
  Sql := Utf8Text(ASql);
  ErrorText := nil;
  ResultCode := sqlite3_exec(FHandle, PAnsiChar(Sql), nil, nil, @ErrorText);
  if ResultCode <> SQLITE_OK then
  begin
    if ErrorText <> nil then
    begin
      Message := string(UTF8String(ErrorText));
      sqlite3_free(ErrorText);
    end
    else
      Message := string(sqlite3_errstr(ResultCode));
    raise ESqliteError.CreateCode(ResultCode,
      Format('Execute failed: %s (SQLite code %d)', [Message, ResultCode]));
  end;
end;

function TSqliteDatabase.QueryInt64(const ASql: string): Int64;
var
  Statement: TSqliteStatement;
begin
  Statement := TSqliteStatement.Create(Self, ASql);
  try
    if not Statement.Step then
      raise ESqliteError.CreateCode(0, 'Query returned no row: ' + ASql);
    Result := Statement.ColumnInt64(0);
  finally
    Statement.Free;
  end;
end;

function TSqliteDatabase.QueryText(const ASql: string): string;
var
  Statement: TSqliteStatement;
begin
  Statement := TSqliteStatement.Create(Self, ASql);
  try
    if not Statement.Step then
      raise ESqliteError.CreateCode(0, 'Query returned no row: ' + ASql);
    Result := Statement.ColumnText(0);
  finally
    Statement.Free;
  end;
end;

procedure TSqliteDatabase.BeginTransaction;
begin
  Execute('BEGIN IMMEDIATE');
end;

procedure TSqliteDatabase.Commit;
begin
  Execute('COMMIT');
end;

procedure TSqliteDatabase.Rollback;
begin
  { After some errors SQLite has already rolled back; do not fail then. }
  if InTransaction then
    Execute('ROLLBACK');
end;

function TSqliteDatabase.InTransaction: Boolean;
begin
  Result := sqlite3_get_autocommit(FHandle) = 0;
end;

end.
