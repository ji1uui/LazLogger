unit Muninn.Cli.Tests;

{ Runs build/muninn-cli as a separate process: ADIF -> SQLite -> ADIF golden
  tests and the exit codes of ADR 0006. scripts/test.sh builds muninn-cli
  first. Expected exports are tests/golden/adif/<case>.cli-expected.adi;
  MUNINN_UPDATE_GOLDEN=1 rewrites them. }

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Process, fpcunit, testregistry;

type
  TCliTests = class(TTestCase)
  private
    FDirectory: string;
    function RunCli(const AArguments: array of string; out AOutput: string;
      const AEnvironment: string = ''): Integer;
    function StartCli(const AArguments: array of string): TProcess;
    function Path(const AName: string): string;
    procedure CheckRoundTrip(const ACase: string; const AExpectedImportExit: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ShowsVersionAndHelp;
    procedure RoundTripsWsjtxLog;
    procedure RoundTripsJapaneseLog;
    procedure RejectsInvalidArguments;
    procedure ReportsMissingFiles;
    procedure RejectsUnsupportedFormats;
    procedure RefusesToOverwriteTheLogbook;
    procedure RejectsFormatOnImport;
    procedure ReportsALibraryThatIsNotSqlite;
    procedure ImportsConcurrentlyIntoANewLogbook;
    procedure KeepsEmptyStationCallsign;
    procedure RefusesNewerLogbook;
    procedure KeepsUserDefinedFieldsValid;
  end;

implementation

uses
  {$IFDEF UNIX}BaseUnix,{$ENDIF}
  Classes, SysUtils, Muninn.Core.Adif, Muninn.Storage.Sqlite,
  Muninn.Storage.AdifTransfer;

const
  ExitSuccess = 0;
  ExitFileError = 1;
  ExitUnsupportedFormat = 2;
  ExitInvalidArguments = 4;
  ExitDataErrors = 5;
  ExitLogbookError = 6;

function GoldenDirectory: string;
begin
  Result := GetEnvironmentVariable('MUNINN_GOLDEN_DIR');
  if Result = '' then
    Result := 'tests/golden/adif';
  Result := IncludeTrailingPathDelimiter(Result);
end;

function CliPath: string;
begin
  Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..' + PathDelim +
    'muninn-cli' + ExtractFileExt(ParamStr(0)));
end;

{ The export without the lines that change on every run. }
function StableText(const AText: string): string;
var
  Lines: TStringList;
  Index: Integer;
begin
  Lines := TStringList.Create;
  try
    { Exports and golden files use LF on every OS. }
    Lines.LineBreak := #10;
    Lines.Text := AText;
    for Index := Lines.Count - 1 downto 0 do
      if (Pos('<CREATED_TIMESTAMP:', Lines[Index]) = 1) or
        (Pos('<PROGRAMVERSION:', Lines[Index]) = 1) then
        Lines.Delete(Index);
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

{ Each record as sorted NAME=VALUE lines, to compare field sets regardless of order. }
function FieldSets(const AText: string): string;
var
  Document: TAdifDocument;
  Issues: TAdifIssues;
  Fields: TStringList;
  RecordIndex, FieldIndex: Integer;
begin
  Result := '';
  Document := TAdifDocument.Create;
  Issues := TAdifIssues.Create;
  Fields := TStringList.Create;
  try
    ReadAdi(AText, Document, Issues);
    for RecordIndex := 0 to Document.RecordCount - 1 do
    begin
      Fields.Clear;
      for FieldIndex := 0 to Document[RecordIndex].Count - 1 do
        Fields.Add(Document[RecordIndex][FieldIndex].Name + '=' +
          Document[RecordIndex][FieldIndex].Value);
      Fields.Sort;
      Result := Result + Fields.Text + '--' + LineEnding;
    end;
  finally
    Fields.Free;
    Issues.Free;
    Document.Free;
  end;
end;

procedure TCliTests.SetUp;
begin
  FDirectory := IncludeTrailingPathDelimiter(GetTempDir(False)) +
    Format('muninn-cli-%d-%d', [GetProcessID, Random(MaxInt)]);
  ForceDirectories(FDirectory);
end;

procedure TCliTests.TearDown;
var
  Found: TSearchRec;
begin
  if FindFirst(IncludeTrailingPathDelimiter(FDirectory) + '*', faAnyFile, Found) = 0 then
  begin
    repeat
      if (Found.Attr and faDirectory) = 0 then
        DeleteFile(IncludeTrailingPathDelimiter(FDirectory) + Found.Name);
    until FindNext(Found) <> 0;
    FindClose(Found);
  end;
  RemoveDir(FDirectory);
end;

function TCliTests.Path(const AName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(FDirectory) + AName;
end;

{ Runs muninn-cli and returns its exit code; AOutput gets stdout and stderr. }
{ Waits until AProcess has exited. WaitOnExit alone can return early when the
  wait is interrupted (another child exiting), leaving ExitCode at 0. }
procedure WaitForExit(const AProcess: TProcess);
begin
  while AProcess.Running do
    Sleep(10);
end;

{ AEnvironment, when set, is one NAME=VALUE added to the inherited environment. }
function TCliTests.RunCli(const AArguments: array of string;
  out AOutput: string; const AEnvironment: string): Integer;
var
  Cli: TProcess;
  Argument: string;
  Buffer: array[0..4095] of Byte;
  Count: Integer;
  Chunk, Prefix: string;
begin
  AssertTrue('muninn-cli is built: ' + CliPath, FileExists(CliPath));
  AOutput := '';
  FillChar(Buffer, SizeOf(Buffer), 0);
  Cli := TProcess.Create(nil);
  try
    Cli.Executable := CliPath;
    for Argument in AArguments do
      Cli.Parameters.Add(Argument);
    if AEnvironment <> '' then
    begin
      { Replace an inherited variable of the same name: with two entries,
        Windows uses the first one. }
      Prefix := UpperCase(Copy(AEnvironment, 1, Pos('=', AEnvironment)));
      for Count := 1 to GetEnvironmentVariableCount do
        if Pos(Prefix, UpperCase(GetEnvironmentString(Count))) <> 1 then
          Cli.Environment.Add(GetEnvironmentString(Count));
      Cli.Environment.Add(AEnvironment);
    end;
    Cli.Options := [poUsePipes, poStderrToOutPut];
    Cli.Execute;
    { Drain the pipe while the process runs so it never blocks on a full pipe. }
    repeat
      Count := Cli.Output.Read(Buffer, SizeOf(Buffer));
      if Count > 0 then
      begin
        SetString(Chunk, PAnsiChar(@Buffer[0]), Count);
        AOutput := AOutput + Chunk;
      end;
    until (Count <= 0) and not Cli.Running;
    WaitForExit(Cli);
    Result := Cli.ExitCode;
  finally
    Cli.Free;
  end;
end;

{ Starts muninn-cli without waiting; the caller waits and frees it. Output is
  small, so the pipe never fills. }
function TCliTests.StartCli(const AArguments: array of string): TProcess;
var
  Argument: string;
begin
  Result := TProcess.Create(nil);
  Result.Executable := CliPath;
  for Argument in AArguments do
    Result.Parameters.Add(Argument);
  Result.Options := [poUsePipes, poStderrToOutPut];
  Result.Execute;
end;

procedure TCliTests.CheckRoundTrip(const ACase: string;
  const AExpectedImportExit: Integer);
var
  Output, Exported, Again, Expected: string;
begin
  AssertEquals('import ' + ACase, AExpectedImportExit,
    RunCli(['import', '--db', Path('a.sqlite'), GoldenDirectory + ACase + '.adi'], Output));
  AssertEquals('export ' + ACase, ExitSuccess,
    RunCli(['export', '--db', Path('a.sqlite'), '--output', Path('a.adi')], Output));
  Exported := ReadFileBytes(Path('a.adi'));
  if GetEnvironmentVariable('MUNINN_UPDATE_GOLDEN') = '1' then
    WriteFileBytes(GoldenDirectory + ACase + '.cli-expected.adi', StableText(Exported));
  Expected := ReadFileBytes(GoldenDirectory + ACase + '.cli-expected.adi');
  AssertEquals('export of ' + ACase, Expected, StableText(Exported));
  { The logbook keeps the same fields and values as the in-memory conversion
    (tests/golden/adif/<case>.expected.adi); only the order may differ. }
  AssertEquals('same fields as the core export of ' + ACase,
    FieldSets(StableText(ReadFileBytes(GoldenDirectory + ACase + '.expected.adi'))),
    FieldSets(StableText(Exported)));
  { Exported files import into a new logbook without loss. }
  AssertEquals('re-import ' + ACase, ExitSuccess,
    RunCli(['import', '--db', Path('b.sqlite'), Path('a.adi')], Output));
  AssertEquals(ExitSuccess,
    RunCli(['export', '--db', Path('b.sqlite'), '--output', Path('b.adi')], Output));
  Again := ReadFileBytes(Path('b.adi'));
  AssertEquals('re-export of ' + ACase + ' is unchanged', StableText(Exported),
    StableText(Again));
end;

procedure TCliTests.ShowsVersionAndHelp;
var
  Output: string;
begin
  AssertEquals(ExitSuccess, RunCli(['--version'], Output));
  AssertEquals('MuninnLog 0.0.0', Trim(Output));
  AssertEquals(ExitSuccess, RunCli(['--help'], Output));
  AssertTrue(Pos('muninn-cli import', Output) > 0);
end;

procedure TCliTests.RoundTripsWsjtxLog;
begin
  CheckRoundTrip('wsjtx', ExitSuccess);
end;

procedure TCliTests.RoundTripsJapaneseLog;
var
  Database: TSqliteDatabase;
begin
  { One record of japan.adi is dated 1929 and cannot be imported. }
  CheckRoundTrip('japan', ExitDataErrors);
  Database := TSqliteDatabase.Open(Path('a.sqlite'));
  try
    AssertEquals('valid records are stored', 3,
      Database.QueryInt64('SELECT count(*) FROM qso'));
  finally
    Database.Free;
  end;
end;

procedure TCliTests.RejectsInvalidArguments;
var
  Output: string;
begin
  AssertEquals(ExitInvalidArguments, RunCli(['--unknown-option'], Output));
  AssertEquals(ExitInvalidArguments, RunCli(['frobnicate', '--db', Path('a.sqlite')], Output));
  AssertEquals('--db is required', ExitInvalidArguments,
    RunCli(['import', GoldenDirectory + 'wsjtx.adi'], Output));
  AssertEquals('missing value', ExitInvalidArguments, RunCli(['export', '--db'], Output));
  AssertEquals('no input file', ExitInvalidArguments,
    RunCli(['import', '--db', Path('a.sqlite')], Output));
  AssertFalse('nothing created', FileExists(Path('a.sqlite')));
end;

procedure TCliTests.ReportsMissingFiles;
var
  Output: string;
begin
  AssertEquals(ExitFileError,
    RunCli(['import', '--db', Path('a.sqlite'), Path('missing.adi')], Output));
  AssertFalse('no logbook created', FileExists(Path('a.sqlite')));
  AssertEquals(ExitFileError, RunCli(['export', '--db', Path('missing.sqlite')], Output));
  AssertFalse('no logbook created', FileExists(Path('missing.sqlite')));
end;

procedure TCliTests.RejectsUnsupportedFormats;
var
  Output: string;
begin
  AssertEquals(ExitSuccess,
    RunCli(['import', '--db', Path('a.sqlite'), GoldenDirectory + 'wsjtx.adi'], Output));
  AssertEquals(ExitUnsupportedFormat,
    RunCli(['export', '--db', Path('a.sqlite'), '--format', 'cabrillo'], Output));
end;

procedure TCliTests.RefusesToOverwriteTheLogbook;
var
  Output: string;
  Database: TSqliteDatabase;
begin
  AssertEquals(ExitSuccess,
    RunCli(['import', '--db', Path('a.sqlite'), GoldenDirectory + 'wsjtx.adi'], Output));
  AssertEquals(ExitInvalidArguments, RunCli(['export', '--db', Path('a.sqlite'),
    '--output', Path('.') + PathDelim + 'a.sqlite'], Output));
  AssertEquals(ExitInvalidArguments, RunCli(['export', '--db', Path('a.sqlite'),
    '--output', Path('a.sqlite-wal')], Output));
{$IFDEF UNIX}
  AssertEquals('symbolic link', 0, FpSymlink(PChar(Path('a.sqlite')), PChar(Path('link.adi'))));
  AssertEquals(ExitInvalidArguments, RunCli(['export', '--db', Path('a.sqlite'),
    '--output', Path('link.adi')], Output));
{$ENDIF}
  Database := TSqliteDatabase.Open(Path('a.sqlite'));
  try
    AssertEquals('logbook intact', 2, Database.QueryInt64('SELECT count(*) FROM qso'));
  finally
    Database.Free;
  end;
end;

procedure TCliTests.RejectsFormatOnImport;
var
  Output: string;
begin
  AssertEquals(ExitInvalidArguments, RunCli(['import', '--db', Path('a.sqlite'),
    '--format', 'csv', GoldenDirectory + 'wsjtx.adi'], Output));
  AssertFalse('nothing created', FileExists(Path('a.sqlite')));
end;

procedure TCliTests.ReportsALibraryThatIsNotSqlite;
const
{$IF defined(WINDOWS)}
  OtherLibrary = 'kernel32.dll';
{$ELSEIF defined(DARWIN)}
  OtherLibrary = '/usr/lib/libSystem.B.dylib';
{$ELSE}
  OtherLibrary = 'libc.so.6';
{$ENDIF}
var
  Output: string;
begin
  AssertEquals(Output, ExitLogbookError, RunCli(['import', '--db', Path('a.sqlite'),
    GoldenDirectory + 'wsjtx.adi'], Output, 'MUNINN_SQLITE_LIBRARY=' + OtherLibrary));
  AssertTrue(Output, Pos('not an SQLite library', Output) > 0);
end;

procedure TCliTests.ImportsConcurrentlyIntoANewLogbook;
var
  Round: Integer;
  First, Second: TProcess;
  Database: TSqliteDatabase;
  LogbookName, Detail: string;
begin
  { Each waits for the other's lock instead of failing, and the migration is
    applied once. }
  for Round := 1 to 5 do
  begin
    LogbookName := Path(Format('c%d.sqlite', [Round]));
    First := StartCli(['import', '--db', LogbookName, GoldenDirectory + 'wsjtx.adi']);
    try
      Second := StartCli(['import', '--db', LogbookName, GoldenDirectory + 'wsjtx.adi']);
      try
        WaitForExit(First);
        WaitForExit(Second);
        Detail := Format('round %d: exit codes %d and %d',
          [Round, First.ExitCode, Second.ExitCode]);
        AssertEquals(Detail, ExitSuccess, First.ExitCode);
        AssertEquals(Detail, ExitSuccess, Second.ExitCode);
      finally
        Second.Free;
      end;
    finally
      First.Free;
    end;
    Database := TSqliteDatabase.Open(LogbookName);
    try
      AssertEquals('both imports stored', 4,
        Database.QueryInt64('SELECT count(*) FROM qso'));
    finally
      Database.Free;
    end;
  end;
end;

procedure TCliTests.KeepsEmptyStationCallsign;
var
  Output: string;
begin
  WriteFileBytes(Path('in.adi'), '<CALL:5>W1ZZZ <QSO_DATE:8>20240101 ' +
    '<TIME_ON:4>1200 <MODE:2>CW <BAND:3>20m <STATION_CALLSIGN:0> <EOR>' + #10);
  AssertEquals(ExitSuccess,
    RunCli(['import', '--db', Path('a.sqlite'), Path('in.adi')], Output));
  AssertEquals(ExitSuccess,
    RunCli(['export', '--db', Path('a.sqlite'), '--output', Path('a.adi')], Output));
  AssertTrue('empty STATION_CALLSIGN exported',
    Pos('<STATION_CALLSIGN:0>', ReadFileBytes(Path('a.adi'))) > 0);
end;

procedure TCliTests.RefusesNewerLogbook;
var
  Output: string;
  Database: TSqliteDatabase;
begin
  Database := TSqliteDatabase.Open(Path('new.sqlite'));
  try
    Database.Execute('PRAGMA user_version = 999');
  finally
    Database.Free;
  end;
  AssertEquals(ExitLogbookError,
    RunCli(['import', '--db', Path('new.sqlite'), GoldenDirectory + 'wsjtx.adi'], Output));
  AssertTrue(Output, Pos('newer MuninnLog', Output) > 0);
  AssertEquals(ExitLogbookError, RunCli(['export', '--db', Path('new.sqlite')], Output));
end;

procedure TCliTests.KeepsUserDefinedFieldsValid;
var
  Output, Exported: string;
begin
  AssertEquals(ExitDataErrors,
    RunCli(['import', '--db', Path('a.sqlite'), GoldenDirectory + 'japan.adi'], Output));
  AssertEquals(ExitSuccess,
    RunCli(['export', '--db', Path('a.sqlite'), '--output', Path('a.adi')], Output));
  Exported := ReadFileBytes(Path('a.adi'));
  AssertTrue('USERDEF exported', Pos('<USERDEF1:8:N>QRP_ARCI', Exported) > 0);
  AssertTrue('user field exported', Pos('<QRP_ARCI:4>1234', Exported) > 0);
end;

initialization
  Randomize;
  RegisterTest(TCliTests);
end.
