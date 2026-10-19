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
  {$IFDEF UNIX}BaseUnix,{$ENDIF}
  {$IFDEF WINDOWS}Windows,{$ENDIF}
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

{ True when both paths exist and are the same file, also through a symbolic or
  hard link or a different letter case on a case-insensitive file system. }
function IsSameExistingFile(const AFirst, ASecond: string): Boolean;
{$IFDEF UNIX}
var
  First, Second: Stat;
begin
  First := Default(Stat);
  Second := Default(Stat);
  Result := (FpStat(AFirst, First) = 0) and (FpStat(ASecond, Second) = 0) and
    (First.st_dev = Second.st_dev) and (First.st_ino = Second.st_ino);
end;
{$ENDIF}
{$IFDEF WINDOWS}

  function TryFileIdentity(const APath: string;
    out AInfo: BY_HANDLE_FILE_INFORMATION): Boolean;
  var
    Handle: THandle;
  begin
    Handle := CreateFileW(PWideChar(UnicodeString(APath)), 0,
      FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil,
      OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0);
    Result := Handle <> INVALID_HANDLE_VALUE;
    if Result then
    begin
      Result := GetFileInformationByHandle(Handle, AInfo);
      CloseHandle(Handle);
    end;
  end;

var
  First, Second: BY_HANDLE_FILE_INFORMATION;
begin
  Result := TryFileIdentity(AFirst, First) and TryFileIdentity(ASecond, Second) and
    (First.dwVolumeSerialNumber = Second.dwVolumeSerialNumber) and
    (First.nFileIndexHigh = Second.nFileIndexHigh) and
    (First.nFileIndexLow = Second.nFileIndexLow);
end;
{$ENDIF}

{ True when APath names the logbook file or one of SQLite's files next to it. }
function WritesOverLogbook(const APath, ADatabasePath: string): Boolean;
const
  Suffixes: array[0..3] of string = ('', '-wal', '-shm', '-journal');
var
  Target, Logbook: string;
  Index: Integer;
begin
  Target := ExpandFileName(APath);
  Logbook := ExpandFileName(ADatabasePath);
  for Index := Low(Suffixes) to High(Suffixes) do
    if SameFileName(Target, Logbook + Suffixes[Index]) or
      IsSameExistingFile(Target, Logbook + Suffixes[Index]) then
      Exit(True);
  Result := False;
end;

function ParseOptions: TOptions;
var
  Index: Integer;
  FormatGiven: Boolean;
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
  FormatGiven := False;
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
    begin
      Result.Format := LowerCase(NextValue);
      FormatGiven := True;
    end
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
  if (Result.Command = 'import') and FormatGiven then
    raise EUsageError.Create('--format is for export; import reads ADIF');
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
