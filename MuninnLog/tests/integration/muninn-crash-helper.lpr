program MuninnCrashHelper;

{ Used by Muninn.Storage.Schema.Tests: kills its own process in the middle of a
  write transaction, so the tests can check what SQLite recovers.
  Usage: muninn-crash-helper (migrate | write) <database path>
    migrate  creates the v1 schema in a transaction, then dies before COMMIT
    write    migrates, commits the QSO 'committed', starts a transaction,
             inserts the QSO 'uncommitted', then dies before COMMIT
  Exit codes: 2 on bad arguments; otherwise the process is killed. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads, cwstring, BaseUnix,{$ENDIF}
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  SysUtils, Muninn.Storage.Sqlite, Muninn.Storage.Schema;

procedure KillSelf;
begin
  { No COMMIT, no close, no unit finalization: like a power cut for the process. }
{$IFDEF UNIX}
  FpKill(FpGetpid, SIGKILL);
{$ENDIF}
{$IFDEF WINDOWS}
  TerminateProcess(GetCurrentProcess, 9);
{$ENDIF}
  Halt(9);
end;

procedure InsertQso(const ADatabase: TSqliteDatabase; const AId: string);
begin
  ADatabase.Execute(Format(
    'INSERT INTO qso (id, call, time_on_ms, mode, station_callsign, ' +
    'created_at_ms, updated_at_ms) VALUES (''%s'', ''JA1ZZZ'', 0, ''CW'', ' +
    '''JA1AAA'', 0, 0)', [AId]));
end;

procedure CrashDuringMigration(const APath: string);
var
  Database: TSqliteDatabase;
begin
  Database := TSqliteDatabase.Open(APath);
  ConfigureConnection(Database);
  { The same steps as MigrateDatabase, stopped before COMMIT. }
  Database.BeginTransaction;
  Database.Execute(SchemaMigrations[0].Sql);
  Database.Execute('PRAGMA user_version = 1');
  KillSelf;
end;

procedure CrashDuringWrite(const APath: string);
var
  Database: TSqliteDatabase;
begin
  Database := OpenLogDatabase(APath);
  InsertQso(Database, 'committed');
  Database.BeginTransaction;
  InsertQso(Database, 'uncommitted');
  KillSelf;
end;

begin
  if ParamCount <> 2 then
  begin
    WriteLn(StdErr, 'Usage: muninn-crash-helper (migrate | write) <database path>');
    Halt(2);
  end;
  if ParamStr(1) = 'migrate' then
    CrashDuringMigration(ParamStr(2))
  else if ParamStr(1) = 'write' then
    CrashDuringWrite(ParamStr(2))
  else
  begin
    WriteLn(StdErr, 'Unknown mode: ', ParamStr(1));
    Halt(2);
  end;
end.
