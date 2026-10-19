unit Muninn.Storage.Schema;

{ The logbook schema and its forward-only migrations (ADR 0003).
  PRAGMA user_version holds the schema version. Each migration runs in its own
  transaction together with the user_version update, so a crash leaves the
  database at the previous version. A database newer than this build is
  refused rather than opened.
  Stored codes (station.kind, operation.kind) are fixed strings, never Ord().
  Columns of qso use the ADIF field names; see docs/03_DATA_MODEL.md. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Muninn.Storage.Sqlite;

const
  CurrentSchemaVersion = 3;

type
  ESchemaError = class(Exception);

  TMigration = record
    Version: Integer;
    Sql: string;
  end;
  TMigrationArray = array of TMigration;

{ The migrations of this build, versions 1..CurrentSchemaVersion in order. }
function SchemaMigrations: TMigrationArray;
{ WAL journal, synchronous=FULL, foreign keys on. (TSqliteDatabase.Open sets
  the busy timeout.) }
procedure ConfigureConnection(const ADatabase: TSqliteDatabase);
function SchemaVersion(const ADatabase: TSqliteDatabase): Integer;
{ Applies the migrations newer than the database, in order. Returns how many
  were applied. Raises ESchemaError when the database is newer than the last
  migration or the list is not numbered 1, 2, 3, ... }
function MigrateDatabase(const ADatabase: TSqliteDatabase;
  const AMigrations: TMigrationArray): Integer;
function MigrateDatabase(const ADatabase: TSqliteDatabase): Integer;
{ Opens or creates a logbook, configures the connection and migrates it to
  CurrentSchemaVersion. The caller owns the result. }
function OpenLogDatabase(const APath: string): TSqliteDatabase;

implementation

const
  SQLITE_BUSY_CODE = 5;
  SchemaV1 =
    'CREATE TABLE station (' +
    ' id TEXT PRIMARY KEY NOT NULL,' +
    ' callsign TEXT NOT NULL,' +
    ' kind TEXT NOT NULL CHECK (kind IN (''personal'', ''club'', ''special'', ''foreign'')),' +
    ' license_number TEXT,' +
    ' valid_from_ms INTEGER,' +
    ' valid_to_ms INTEGER' +
    ') STRICT;' +

    'CREATE TABLE station_location (' +
    ' id TEXT PRIMARY KEY NOT NULL,' +
    ' name TEXT NOT NULL,' +
    ' gridsquare TEXT,' +
    ' latitude REAL,' +
    ' longitude REAL,' +
    ' dxcc INTEGER,' +
    ' cq_zone INTEGER,' +
    ' itu_zone INTEGER,' +
    ' prefecture TEXT,' +
    ' city_code TEXT,' +
    ' portable_suffix TEXT,' +
    ' is_portable INTEGER NOT NULL DEFAULT 0 CHECK (is_portable IN (0, 1))' +
    ') STRICT;' +

    'CREATE TABLE operation (' +
    ' id TEXT PRIMARY KEY NOT NULL,' +
    ' kind TEXT NOT NULL CHECK (kind IN (''general'', ''contest'', ''pota'', ''sota'', ''other'')),' +
    ' station_id TEXT REFERENCES station (id),' +
    ' location_id TEXT REFERENCES station_location (id),' +
    ' transmitted_callsign TEXT NOT NULL,' +
    ' contest_id TEXT,' +
    ' start_ms INTEGER,' +
    ' end_ms INTEGER' +
    ') STRICT;' +

    'CREATE TABLE qso (' +
    ' id TEXT PRIMARY KEY NOT NULL,' +
    ' operation_id TEXT REFERENCES operation (id),' +
    ' station_id TEXT REFERENCES station (id),' +
    ' location_id TEXT REFERENCES station_location (id),' +
    ' call TEXT NOT NULL,' +
    ' time_on_ms INTEGER NOT NULL,' +
    ' time_off_ms INTEGER,' +
    ' freq_hz INTEGER CHECK (freq_hz > 0),' +
    ' freq_rx_hz INTEGER CHECK (freq_rx_hz > 0),' +
    ' band TEXT,' +
    ' band_rx TEXT,' +
    ' mode TEXT NOT NULL,' +
    ' submode TEXT,' +
    ' rst_sent TEXT,' +
    ' rst_rcvd TEXT,' +
    ' stx INTEGER,' +
    ' stx_string TEXT,' +
    ' srx INTEGER,' +
    ' srx_string TEXT,' +
    ' contest_id TEXT,' +
    ' name TEXT,' +
    ' qth TEXT,' +
    ' gridsquare TEXT,' +
    ' pota_ref TEXT,' +
    ' sota_ref TEXT,' +
    ' station_callsign TEXT NOT NULL,' +
    ' operator TEXT,' +
    ' owner_callsign TEXT,' +
    ' my_gridsquare TEXT,' +
    ' my_dxcc INTEGER,' +
    ' my_cq_zone INTEGER,' +
    ' my_itu_zone INTEGER,' +
    ' my_state TEXT,' +
    ' my_cnty TEXT,' +
    ' my_pota_ref TEXT,' +
    ' my_sota_ref TEXT,' +
    ' my_sig TEXT,' +
    ' my_sig_info TEXT,' +
    ' my_rig TEXT,' +
    ' my_antenna TEXT,' +
    ' tx_pwr_mw INTEGER CHECK (tx_pwr_mw >= 0),' +
    ' comment TEXT,' +
    ' source TEXT,' +
    ' created_at_ms INTEGER NOT NULL,' +
    ' updated_at_ms INTEGER NOT NULL,' +
    ' revision INTEGER NOT NULL DEFAULT 1 CHECK (revision >= 1)' +
    ') STRICT;' +

    { ADIF fields without a column, kept so that import and export round-trip. }
    'CREATE TABLE qso_field (' +
    ' qso_id TEXT NOT NULL REFERENCES qso (id) ON DELETE CASCADE,' +
    ' name TEXT NOT NULL,' +
    ' value TEXT NOT NULL,' +
    ' PRIMARY KEY (qso_id, name)' +
    ') STRICT, WITHOUT ROWID;' +

    'CREATE INDEX qso_call ON qso (call);' +
    'CREATE INDEX qso_time_on ON qso (time_on_ms);' +
    'CREATE INDEX qso_call_band_mode ON qso (call, band, mode);' +
    'CREATE INDEX qso_operation ON qso (operation_id);';

  { The contacted station's location (ADIF DXCC, STATE, CNTY). STATE and CNTY
    are codes kept as text, e.g. CNTY 0101 (JCC Sapporo); see ADR 0004. }
  SchemaV2 =
    'ALTER TABLE qso ADD COLUMN dxcc INTEGER;' +
    'ALTER TABLE qso ADD COLUMN state TEXT;' +
    'ALTER TABLE qso ADD COLUMN cnty TEXT;';

  { Lossless ADIF round trips (ADR 0006): the data type indicator and the
    recorded order of fields without a column, and the definitions of
    user-defined fields (ADIF USERDEFn header fields). }
  SchemaV3 =
    'ALTER TABLE qso_field ADD COLUMN data_type TEXT NOT NULL DEFAULT '''';' +
    'ALTER TABLE qso_field ADD COLUMN position INTEGER NOT NULL DEFAULT 0;' +
    'CREATE TABLE adif_user_field (' +
    ' name TEXT PRIMARY KEY NOT NULL,' +
    ' data_type TEXT NOT NULL,' +
    ' definition TEXT NOT NULL' +
    ') STRICT;';

function SchemaMigrations: TMigrationArray;
begin
  Result := nil;
  SetLength(Result, 3);
  Result[0].Version := 1;
  Result[0].Sql := SchemaV1;
  Result[1].Version := 2;
  Result[1].Sql := SchemaV2;
  Result[2].Version := 3;
  Result[2].Sql := SchemaV3;
end;

procedure ConfigureConnection(const ADatabase: TSqliteDatabase);
var
  JournalMode: string;
begin
  JournalMode := LowerCase(ADatabase.QueryText('PRAGMA journal_mode = WAL'));
  if JournalMode <> 'wal' then
    raise ESchemaError.CreateFmt('Cannot use WAL for %s (journal mode is %s)',
      [ADatabase.Path, JournalMode]);
  ADatabase.Execute('PRAGMA synchronous = FULL');
  ADatabase.Execute('PRAGMA foreign_keys = ON');
end;

function SchemaVersion(const ADatabase: TSqliteDatabase): Integer;
begin
  Result := ADatabase.QueryInt64('PRAGMA user_version');
end;

procedure CheckNotNewer(const ADatabase: TSqliteDatabase;
  const ALatestVersion: Integer);
var
  Version: Integer;
begin
  Version := SchemaVersion(ADatabase);
  if Version > ALatestVersion then
    raise ESchemaError.CreateFmt(
      '%s has schema version %d, but this MuninnLog supports up to %d. ' +
      'Use a newer MuninnLog.', [ADatabase.Path, Version, ALatestVersion]);
end;

procedure CheckMigrationOrder(const AMigrations: TMigrationArray);
var
  Index: Integer;
begin
  for Index := 0 to High(AMigrations) do
    if AMigrations[Index].Version <> Index + 1 then
      raise ESchemaError.CreateFmt(
        'Migration %d has version %d; expected %d',
        [Index, AMigrations[Index].Version, Index + 1]);
end;

function MigrateDatabase(const ADatabase: TSqliteDatabase;
  const AMigrations: TMigrationArray): Integer;
var
  Version: Integer;
  Migration: TMigration;
begin
  CheckMigrationOrder(AMigrations);
  CheckNotNewer(ADatabase, Length(AMigrations));
  Version := SchemaVersion(ADatabase);
  Result := 0;
  for Migration in AMigrations do
  begin
    if Migration.Version <= Version then
      Continue;
    ADatabase.BeginTransaction;
    try
      { Another process may have applied it while this one waited for the lock. }
      Version := SchemaVersion(ADatabase);
      if Migration.Version <= Version then
      begin
        ADatabase.Commit;
        Continue;
      end;
      ADatabase.Execute(Migration.Sql);
      ADatabase.Execute(Format('PRAGMA user_version = %d', [Migration.Version]));
      ADatabase.Commit;
    except
      ADatabase.Rollback;
      raise;
    end;
    Inc(Result);
  end;
end;

function MigrateDatabase(const ADatabase: TSqliteDatabase): Integer;
begin
  Result := MigrateDatabase(ADatabase, SchemaMigrations);
end;

function OpenLogDatabaseOnce(const APath: string): TSqliteDatabase;
begin
  Result := TSqliteDatabase.Open(APath);
  try
    { Refuse a newer database before changing anything, even the journal mode. }
    CheckNotNewer(Result, CurrentSchemaVersion);
    ConfigureConnection(Result);
    MigrateDatabase(Result);
  except
    Result.Free;
    raise;
  end;
end;

function OpenLogDatabase(const APath: string): TSqliteDatabase;
const
  RetryDelayMs = 50;
var
  Waited: Integer;
begin
  { While a new logbook switches to WAL, SQLite can report SQLITE_BUSY at once
    instead of waiting (lock upgrade deadlock between two connections); the
    busy timeout does not apply then, so open again for up to BusyTimeoutMs. }
  Waited := 0;
  repeat
    try
      Exit(OpenLogDatabaseOnce(APath));
    except
      on E: ESqliteError do
        if ((E.ResultCode and $FF) <> SQLITE_BUSY_CODE) or (Waited >= BusyTimeoutMs) then
          raise;
    end;
    Sleep(RetryDelayMs);
    Inc(Waited, RetryDelayMs);
  until False;
end;

end.
