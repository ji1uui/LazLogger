program MuninnCli;

{ muninn-cli: command-line front end of MuninnLog (ADR 0006).

    muninn-cli import --db <logbook> <file.adi>
    muninn-cli export --db <logbook> [--format adif] [--output <file.adi>]
    muninn-cli --version | --help

  Results go to standard output; warnings and errors to standard error.
  Exit codes: 0 success, 1 file error, 2 unsupported format, 4 invalid
  arguments, 5 data errors (some records not imported), 6 logbook error.
  3 is reserved for package signature errors (Omoikane). }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads, cwstring,{$ENDIF}
  Muninn.Core.Utf8Default,
  Classes, SysUtils, DateUtils, Muninn.Core.Version, Muninn.Core.Adif,
  Muninn.Core.Time, Muninn.Storage.Sqlite, Muninn.Storage.Schema,
  Muninn.Storage.AdifTransfer;

const
  ExitSuccess = 0;
  ExitFileError = 1;
  ExitUnsupportedFormat = 2;
  ExitInvalidArguments = 4;
  ExitDataErrors = 5;
  ExitLogbookError = 6;

type
  EUsageError = class(Exception);

  TOptions = record
    Command: string;
    DatabasePath: string;
    Format: string;
    OutputPath: string;
    InputPath: string;
  end;

procedure WriteUsage(var AOutput: Text);
begin
  WriteLn(AOutput, 'Usage:');
  WriteLn(AOutput, '  muninn-cli import --db <logbook> <file.adi>');
  WriteLn(AOutput, '  muninn-cli export --db <logbook> [--format adif] [--output <file.adi>]');
  WriteLn(AOutput, '  muninn-cli --version');
  WriteLn(AOutput, '  muninn-cli --help');
end;

{ True when APath names the logbook file or one of SQLite's files next to it. }
function WritesOverLogbook(const APath, ADatabasePath: string): Boolean;
var
  Target, Logbook: string;
begin
  Target := ExpandFileName(APath);
  Logbook := ExpandFileName(ADatabasePath);
  Result := SameFileName(Target, Logbook) or SameFileName(Target, Logbook + '-wal') or
    SameFileName(Target, Logbook + '-shm') or SameFileName(Target, Logbook + '-journal');
end;

function ParseOptions: TOptions;
var
  Index: Integer;
  Argument: string;

  function NextValue: string;
  begin
    Inc(Index);
    if Index > ParamCount then
      raise EUsageError.CreateFmt('%s needs a value', [Argument]);
    Result := ParamStr(Index);
  end;

begin
  Result := Default(TOptions);
  Result.Format := 'adif';
  if ParamCount = 0 then
    raise EUsageError.Create('no command given');
  Result.Command := ParamStr(1);
  Index := 1;
  while Index < ParamCount do
  begin
    Inc(Index);
    Argument := ParamStr(Index);
    if Argument = '--db' then
      Result.DatabasePath := NextValue
    else if Argument = '--format' then
      Result.Format := LowerCase(NextValue)
    else if Argument = '--output' then
      Result.OutputPath := NextValue
    else if (Argument <> '') and (Argument[1] = '-') then
      raise EUsageError.CreateFmt('unknown option %s', [Argument])
    else if Result.InputPath = '' then
      Result.InputPath := Argument
    else
      raise EUsageError.CreateFmt('unexpected argument %s', [Argument]);
  end;
  if Result.DatabasePath = '' then
    raise EUsageError.Create('--db is required');
  if (Result.Command = 'import') and (Result.InputPath = '') then
    raise EUsageError.Create('import needs an ADIF file');
  if (Result.Command = 'import') and (Result.OutputPath <> '') then
    raise EUsageError.Create('--output is for export');
  if (Result.Command = 'export') and (Result.InputPath <> '') then
    raise EUsageError.CreateFmt('unexpected argument %s', [Result.InputPath]);
  if (Result.OutputPath <> '') and WritesOverLogbook(Result.OutputPath,
    Result.DatabasePath) then
    raise EUsageError.Create('--output must not be the logbook or its journal files');
end;

function NowUtcMs: Int64;
var
  Utc: TDateTime;
begin
  Utc := LocalTimeToUniversal(Now);
  Result := DateTimeToUnix(Utc) * 1000 + MilliSecondOf(Utc);
end;

{ Writes bytes as they are, without code page conversion of the console. }
procedure WriteStandardOutput(const AText: string);
var
  Stream: THandleStream;
begin
  Stream := THandleStream.Create(StdOutputHandle);
  try
    if AText <> '' then
      Stream.WriteBuffer(AText[1], Length(AText));
  finally
    Stream.Free;
  end;
end;

function RunImport(const AOptions: TOptions): Integer;
var
  Database: TSqliteDatabase;
  Issues: TAdifIssues;
  Summary: TAdifImportSummary;
begin
  if not FileExists(AOptions.InputPath) then
  begin
    WriteLn(StdErr, 'muninn-cli: file not found: ', AOptions.InputPath);
    Exit(ExitFileError);
  end;
  Issues := TAdifIssues.Create;
  try
    Database := OpenLogDatabase(AOptions.DatabasePath);
    try
      Summary := ImportAdifFile(Database, AOptions.InputPath, NowUtcMs, Issues);
    finally
      Database.Free;
    end;
    Write(StdErr, Issues.ToText);
    WriteLn(Format('Imported %d of %d records into %s (%d rejected, %d issues).',
      [Summary.Imported, Summary.RecordCount, AOptions.DatabasePath,
      Summary.Rejected, Issues.Count]));
    if Issues.ErrorCount > 0 then
      Result := ExitDataErrors
    else
      Result := ExitSuccess;
  finally
    Issues.Free;
  end;
end;

function RunExport(const AOptions: TOptions): Integer;
var
  Database: TSqliteDatabase;
  Text: string;
begin
  if AOptions.Format <> 'adif' then
  begin
    WriteLn(StdErr, 'muninn-cli: unsupported format: ', AOptions.Format);
    Exit(ExitUnsupportedFormat);
  end;
  if not FileExists(AOptions.DatabasePath) then
  begin
    WriteLn(StdErr, 'muninn-cli: logbook not found: ', AOptions.DatabasePath);
    Exit(ExitFileError);
  end;
  Database := OpenLogDatabase(AOptions.DatabasePath);
  try
    Text := ExportAdifText(Database, TUtcInstant.FromUnixMs(NowUtcMs), ApplicationVersion);
  finally
    Database.Free;
  end;
  if AOptions.OutputPath = '' then
    WriteStandardOutput(Text)
  else
  begin
    WriteFileBytes(AOptions.OutputPath, Text);
    WriteLn(StdErr, 'Exported to ', AOptions.OutputPath);
  end;
  Result := ExitSuccess;
end;

function Run: Integer;
var
  Options: TOptions;
begin
  if (ParamCount = 1) and ((ParamStr(1) = '--version') or (ParamStr(1) = 'version')) then
  begin
    WriteLn(VersionText);
    Exit(ExitSuccess);
  end;
  if (ParamCount = 0) or ((ParamCount = 1) and
    ((ParamStr(1) = '--help') or (ParamStr(1) = 'help'))) then
  begin
    WriteUsage(Output);
    Exit(ExitSuccess);
  end;
  try
    Options := ParseOptions;
    if Options.Command = 'import' then
      Result := RunImport(Options)
    else if Options.Command = 'export' then
      Result := RunExport(Options)
    else
      raise EUsageError.CreateFmt('unknown command %s', [Options.Command]);
  except
    on E: EUsageError do
    begin
      WriteLn(StdErr, 'muninn-cli: ', E.Message);
      WriteUsage(StdErr);
      Result := ExitInvalidArguments;
    end;
    on E: ESqliteError do
    begin
      WriteLn(StdErr, 'muninn-cli: logbook error: ', E.Message);
      Result := ExitLogbookError;
    end;
    on E: ESchemaError do
    begin
      WriteLn(StdErr, 'muninn-cli: logbook error: ', E.Message);
      Result := ExitLogbookError;
    end;
    on E: EFileNotFoundException do
    begin
      WriteLn(StdErr, 'muninn-cli: ', E.Message);
      Result := ExitFileError;
    end;
    on E: EStreamError do
    begin
      WriteLn(StdErr, 'muninn-cli: file error: ', E.Message);
      Result := ExitFileError;
    end;
  end;
end;

begin
  ExitCode := Run;
end.
