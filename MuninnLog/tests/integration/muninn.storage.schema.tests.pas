unit Muninn.Storage.Schema.Tests;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  fpcunit, testregistry, Muninn.Storage.Sqlite, Muninn.Storage.Schema;

type
  TSchemaTests = class(TTestCase)
  private
    FPath: string;
    procedure DeleteDatabaseFiles;
    procedure InsertQso(const ADatabase: TSqliteDatabase; const AId: string);
    procedure ExpectSqlFailure(const ADatabase: TSqliteDatabase;
      const AMessage, ASql: string);
    procedure RunCrashHelper(const AMode: string);
    procedure CheckIntegrity(const ADatabase: TSqliteDatabase);
    function TableCount(const ADatabase: TSqliteDatabase): Int64;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure CurrentVersionMatchesMigrations;
    procedure CreatesEmptyDatabaseAtCurrentVersion;
    procedure ReopeningAppliesNoMigration;
    procedure RefusesDatabaseFromNewerVersion;
    procedure FailedMigrationRollsBack;
    procedure RejectsMisnumberedMigrations;
    procedure EnforcesSchemaConstraints;
    procedure StoresUtf8Text;
    procedure MigratesVersion1KeepingRows;
    procedure CrashDuringMigrationLeavesVersionZero;
    procedure CrashDuringWriteKeepsCommittedRows;
  end;

implementation

uses
  SysUtils, Process;

procedure TSchemaTests.SetUp;
begin
  FPath := IncludeTrailingPathDelimiter(GetTempDir(False)) +
    Format('muninn-test-%d-%d.sqlite', [GetProcessID, Random(MaxInt)]);
  DeleteDatabaseFiles;
end;

procedure TSchemaTests.TearDown;
begin
  DeleteDatabaseFiles;
end;

procedure TSchemaTests.DeleteDatabaseFiles;
begin
  DeleteFile(FPath);
  DeleteFile(FPath + '-wal');
  DeleteFile(FPath + '-shm');
  DeleteFile(FPath + '-journal');
end;

procedure TSchemaTests.InsertQso(const ADatabase: TSqliteDatabase;
  const AId: string);
begin
  ADatabase.Execute(Format(
    'INSERT INTO qso (id, call, time_on_ms, mode, station_callsign, ' +
    'created_at_ms, updated_at_ms) VALUES (''%s'', ''JA1ZZZ'', 0, ''CW'', ' +
    '''JA1AAA'', 0, 0)', [AId]));
end;

procedure TSchemaTests.ExpectSqlFailure(const ADatabase: TSqliteDatabase;
  const AMessage, ASql: string);
begin
  try
    ADatabase.Execute(ASql);
  except
    on ESqliteError do
      Exit;
  end;
  Fail(AMessage);
end;

procedure TSchemaTests.RunCrashHelper(const AMode: string);
var
  Helper: TProcess;
begin
  Helper := TProcess.Create(nil);
  try
    Helper.Executable := ExtractFilePath(ParamStr(0)) + 'muninn-crash-helper' +
      ExtractFileExt(ParamStr(0));
    Helper.Parameters.Add(AMode);
    Helper.Parameters.Add(FPath);
    Helper.Options := [poWaitOnExit];
    Helper.Execute;
    { 2 means bad arguments; a clean exit means the helper did not crash. }
    AssertTrue('helper must be killed, not exit normally',
      (Helper.ExitStatus <> 0) and (Helper.ExitStatus <> 2));
  finally
    Helper.Free;
  end;
end;

procedure TSchemaTests.CheckIntegrity(const ADatabase: TSqliteDatabase);
begin
  AssertEquals('integrity_check', 'ok',
    ADatabase.QueryText('PRAGMA integrity_check'));
  AssertEquals('foreign_key_check', 0,
    ADatabase.QueryInt64('SELECT count(*) FROM pragma_foreign_key_check'));
end;

function TSchemaTests.TableCount(const ADatabase: TSqliteDatabase): Int64;
begin
  Result := ADatabase.QueryInt64(
    'SELECT count(*) FROM sqlite_schema WHERE type = ''table''');
end;

procedure TSchemaTests.CurrentVersionMatchesMigrations;
begin
  AssertEquals(CurrentSchemaVersion, Length(SchemaMigrations));
end;

procedure TSchemaTests.CreatesEmptyDatabaseAtCurrentVersion;
var
  Database: TSqliteDatabase;
begin
  Database := OpenLogDatabase(FPath);
  try
    AssertEquals('version', CurrentSchemaVersion, SchemaVersion(Database));
    AssertEquals('journal mode', 'wal',
      Database.QueryText('PRAGMA journal_mode'));
    AssertEquals('synchronous FULL', 2,
      Database.QueryInt64('PRAGMA synchronous'));
    AssertEquals('foreign keys', 1, Database.QueryInt64('PRAGMA foreign_keys'));
    AssertEquals('tables', 5, TableCount(Database));
    AssertEquals('no QSO', 0, Database.QueryInt64('SELECT count(*) FROM qso'));
    CheckIntegrity(Database);
  finally
    Database.Free;
  end;
end;

procedure TSchemaTests.ReopeningAppliesNoMigration;
var
  Database: TSqliteDatabase;
begin
  OpenLogDatabase(FPath).Free;
  Database := TSqliteDatabase.Open(FPath);
  try
    ConfigureConnection(Database);
    AssertEquals('applied', 0, MigrateDatabase(Database));
    AssertEquals(CurrentSchemaVersion, SchemaVersion(Database));
  finally
    Database.Free;
  end;
end;

procedure TSchemaTests.RefusesDatabaseFromNewerVersion;
var
  Database: TSqliteDatabase;
begin
  Database := TSqliteDatabase.Open(FPath);
  try
    Database.Execute(Format('PRAGMA user_version = %d',
      [CurrentSchemaVersion + 1]));
  finally
    Database.Free;
  end;
  try
    OpenLogDatabase(FPath).Free;
    Fail('a newer database must be refused');
  except
    on ESchemaError do;
  end;
  Database := TSqliteDatabase.Open(FPath);
  try
    AssertEquals('left unchanged', CurrentSchemaVersion + 1,
      SchemaVersion(Database));
    AssertEquals('no tables created', 0, TableCount(Database));
    AssertEquals('journal mode untouched', 'delete',
      Database.QueryText('PRAGMA journal_mode'));
  finally
    Database.Free;
  end;
end;

procedure TSchemaTests.FailedMigrationRollsBack;
var
  Database: TSqliteDatabase;
  Migrations: TMigrationArray;
begin
  Migrations := nil;
  SetLength(Migrations, 2);
  Migrations[0].Version := 1;
  Migrations[0].Sql := 'CREATE TABLE first (x INTEGER) STRICT;';
  Migrations[1].Version := 2;
  Migrations[1].Sql := 'CREATE TABLE second (x INTEGER) STRICT;' +
    'INSERT INTO missing_table VALUES (1);';
  Database := TSqliteDatabase.Open(FPath);
  try
    ConfigureConnection(Database);
    try
      MigrateDatabase(Database, Migrations);
      Fail('the broken migration must raise');
    except
      on ESqliteError do;
    end;
    AssertFalse('transaction closed', Database.InTransaction);
    AssertEquals('stays at the last good version', 1, SchemaVersion(Database));
    AssertEquals('second table rolled back', 0, Database.QueryInt64(
      'SELECT count(*) FROM sqlite_schema WHERE name = ''second'''));
    AssertEquals('first table kept', 1, Database.QueryInt64(
      'SELECT count(*) FROM sqlite_schema WHERE name = ''first'''));
  finally
    Database.Free;
  end;
end;

procedure TSchemaTests.RejectsMisnumberedMigrations;
var
  Database: TSqliteDatabase;
  Migrations: TMigrationArray;
begin
  Migrations := nil;
  SetLength(Migrations, 1);
  Migrations[0].Version := 2;
  Migrations[0].Sql := 'CREATE TABLE skipped (x INTEGER) STRICT;';
  Database := TSqliteDatabase.Open(FPath);
  try
    try
      MigrateDatabase(Database, Migrations);
      Fail('a gap in the versions must be refused');
    except
      on ESchemaError do;
    end;
    AssertEquals(0, SchemaVersion(Database));
    AssertEquals(0, TableCount(Database));
  finally
    Database.Free;
  end;
end;

procedure TSchemaTests.EnforcesSchemaConstraints;
var
  Database: TSqliteDatabase;
begin
  Database := OpenLogDatabase(FPath);
  try
    InsertQso(Database, 'valid');
    ExpectSqlFailure(Database, 'duplicate id', Format(
      'INSERT INTO qso (id, call, time_on_ms, mode, station_callsign, ' +
      'created_at_ms, updated_at_ms) VALUES (''valid'', ''JA1ZZZ'', 0, ' +
      '''CW'', ''JA1AAA'', 0, 0)', []));
    ExpectSqlFailure(Database, 'zero frequency',
      'UPDATE qso SET freq_hz = 0 WHERE id = ''valid''');
    ExpectSqlFailure(Database, 'STRICT rejects text in an INTEGER column',
      'UPDATE qso SET time_on_ms = ''yesterday'' WHERE id = ''valid''');
    ExpectSqlFailure(Database, 'unknown operation',
      'UPDATE qso SET operation_id = ''missing'' WHERE id = ''valid''');
    ExpectSqlFailure(Database, 'unknown station kind',
      'INSERT INTO station (id, callsign, kind) VALUES (''s'', ''JA1AAA'', ''x'')');
    ExpectSqlFailure(Database, 'missing call',
      'INSERT INTO qso (id, time_on_ms, mode, station_callsign, ' +
      'created_at_ms, updated_at_ms) VALUES (''x'', 0, ''CW'', ''JA1AAA'', 0, 0)');
    Database.Execute('INSERT INTO qso_field (qso_id, name, value) ' +
      'VALUES (''valid'', ''APP_TEST_FIELD'', ''1'')');
    Database.Execute('DELETE FROM qso WHERE id = ''valid''');
    AssertEquals('extra fields deleted with the QSO', 0,
      Database.QueryInt64('SELECT count(*) FROM qso_field'));
  finally
    Database.Free;
  end;
end;

procedure TSchemaTests.StoresUtf8Text;
const
  Name = '山田 太郎';
var
  Database: TSqliteDatabase;
  Statement: TSqliteStatement;
begin
  Database := OpenLogDatabase(FPath);
  try
    InsertQso(Database, 'utf8');
    Statement := TSqliteStatement.Create(Database,
      'UPDATE qso SET name = ?1, comment = ?2 WHERE id = ?3');
    try
      Statement.BindText(1, Name);
      Statement.BindNull(2);
      Statement.BindText(3, 'utf8');
      AssertFalse('UPDATE returns no row', Statement.Step);
    finally
      Statement.Free;
    end;
    Statement := TSqliteStatement.Create(Database,
      'SELECT name, comment, length(name) FROM qso WHERE id = ''utf8''');
    try
      AssertTrue(Statement.Step);
      AssertEquals('name', Name, Statement.ColumnText(0));
      AssertTrue('comment is NULL', Statement.ColumnIsNull(1));
      AssertEquals('stored as 5 characters', 5, Statement.ColumnInt64(2));
    finally
      Statement.Free;
    end;
  finally
    Database.Free;
  end;
end;

procedure TSchemaTests.MigratesVersion1KeepingRows;
var
  Database: TSqliteDatabase;
  Migrations: TMigrationArray;
begin
  Migrations := Copy(SchemaMigrations, 0, 1);
  Database := TSqliteDatabase.Open(FPath);
  try
    ConfigureConnection(Database);
    AssertEquals(1, MigrateDatabase(Database, Migrations));
    InsertQso(Database, 'from-v1');
  finally
    Database.Free;
  end;
  Database := OpenLogDatabase(FPath);
  try
    AssertEquals(CurrentSchemaVersion, SchemaVersion(Database));
    AssertEquals('row kept', 1, Database.QueryInt64('SELECT count(*) FROM qso'));
    AssertEquals('new columns are NULL', 1, Database.QueryInt64(
      'SELECT count(*) FROM qso WHERE dxcc IS NULL AND state IS NULL AND cnty IS NULL'));
    Database.Execute('UPDATE qso SET dxcc = 339, state = ''01'', cnty = ''0101''');
    AssertEquals('leading zero kept', '0101', Database.QueryText('SELECT cnty FROM qso'));
    ExpectSqlFailure(Database, 'STRICT: dxcc is an INTEGER',
      'UPDATE qso SET dxcc = ''Japan''');
    CheckIntegrity(Database);
  finally
    Database.Free;
  end;
end;

procedure TSchemaTests.CrashDuringMigrationLeavesVersionZero;
var
  Database: TSqliteDatabase;
begin
  RunCrashHelper('migrate');
  Database := TSqliteDatabase.Open(FPath);
  try
    AssertEquals('version not advanced', 0, SchemaVersion(Database));
    AssertEquals('no partial tables', 0, TableCount(Database));
    CheckIntegrity(Database);
  finally
    Database.Free;
  end;
  Database := OpenLogDatabase(FPath);
  try
    AssertEquals('migrates after the crash', CurrentSchemaVersion,
      SchemaVersion(Database));
    CheckIntegrity(Database);
  finally
    Database.Free;
  end;
end;

procedure TSchemaTests.CrashDuringWriteKeepsCommittedRows;
var
  Database: TSqliteDatabase;
begin
  RunCrashHelper('write');
  Database := OpenLogDatabase(FPath);
  try
    AssertEquals(CurrentSchemaVersion, SchemaVersion(Database));
    AssertEquals('committed row kept', 1, Database.QueryInt64(
      'SELECT count(*) FROM qso WHERE id = ''committed'''));
    AssertEquals('uncommitted row gone', 0, Database.QueryInt64(
      'SELECT count(*) FROM qso WHERE id = ''uncommitted'''));
    CheckIntegrity(Database);
  finally
    Database.Free;
  end;
end;

initialization
  Randomize;
  RegisterTest(TSchemaTests);
end.
