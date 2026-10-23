program MuninnCrashHelper;

{ Used by Muninn.Storage.Schema.Tests: kills its own process in the middle of a
  write transaction, so the tests can check what SQLite recovers.
  Usage: muninn-crash-helper (migrate | write) <database path>
         muninn-crash-helper writer <logbook path> <saved ids file>
    migrate  creates the v1 schema in a transaction, then dies before COMMIT
    write    migrates, commits the QSO 'committed', starts a transaction,
             inserts the QSO 'uncommitted', then dies before COMMIT
    writer   submits 200 QSOs to the QSO writer (ADR 0011), writes the id of
             each QSO reported saved to the ids file, and dies once 50 are
             reported, with the rest still queued
  Exit codes: 2 on bad arguments; otherwise the process is killed. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads, cwstring,{$ENDIF}
  Muninn.Core.Utf8Default,
  {$IFDEF UNIX}BaseUnix,{$ENDIF}
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, Muninn.Core.Qso, Muninn.Core.Mode, Muninn.Core.Time,
  Muninn.Core.Logbook, Muninn.Core.QsoWriter, Muninn.Storage.Sqlite,
  Muninn.Storage.Schema, Muninn.Storage.Logbook;

type
  TSavedRecorder = class
  public
    Ids: TFileStream;
    Count: Integer;
    procedure Saved(const ATicket: Int64; const AQsoId: string);
  end;

procedure TSavedRecorder.Saved(const ATicket: Int64; const AQsoId: string);
var
  Line: string;
begin
  { Written before the next result is taken: the OS keeps it after a kill. }
  Line := AQsoId + LineEnding;
  Ids.WriteBuffer(Line[1], Length(Line));
  Inc(Count);
end;

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

procedure CrashWithQueuedQsos(const APath, AIdsPath: string);
const
  Submitted = 200;
  StopAfter = 50;
var
  Logbook: ILogbook;
  Writer: IQsoWriter;
  Recorder: TSavedRecorder;
  Qso: TQsoRecord;
  Mode: TMode;
  Index: Integer;
begin
  Logbook := TSqliteLogbookStore.Create.Open(APath);
  Writer := Logbook.CreateWriter;
  Recorder := TSavedRecorder.Create;
  { Shared, so the test can read it while Windows is still tearing the killed
    process down. }
  Recorder.Ids := TFileStream.Create(AIdsPath, fmCreate or fmShareDenyNone);
  Writer.SetOnSaved(@Recorder.Saved);
  if not TMode.TryCreate('CW', '', Mode) then
    Halt(3);
  for Index := 1 to Submitted do
  begin
    Qso := TQsoRecord.Create;
    Qso.Call := Format('JA1C%.3d', [Index]);
    Qso.TimeOn := TUtcInstant.FromUnixMs(1700000000000 + Index * 1000);
    Qso.FrequencyHz := 7010000;
    Qso.Band := '40m';
    Qso.Mode := Mode;
    Writer.Submit(Qso);
  end;
  while Recorder.Count < StopAfter do
    CheckSynchronize(5);
  KillSelf;
end;

begin
  if (ParamCount = 3) and (ParamStr(1) = 'writer') then
  begin
    CrashWithQueuedQsos(ParamStr(2), ParamStr(3));
    Exit;
  end;
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
