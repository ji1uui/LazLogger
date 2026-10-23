unit Muninn.Storage.Settings;

{ Where the application keeps its settings, and the list of recently used
  logbooks (T12). MUNINN_CONFIG_DIR overrides the directory (tests, portable
  use). The list file is replaced in one step, so a crash while saving leaves
  the old list. }

{$mode objfpc}{$H+}

interface

uses
  Classes;

{ Windows: %APPDATA%\MuninnLog; macOS: ~/Library/Application Support/MuninnLog;
  others: $XDG_CONFIG_HOME/muninnlog or ~/.config/muninnlog. Not created. }
function SettingsDirectory: string;
{ The recent-logbook list in ADirectory, one path per line. A missing file
  gives an empty list. }
procedure LoadRecentLogbooks(const ADirectory: string; const AList: TStrings);
{ Creates ADirectory when needed. }
procedure SaveRecentLogbooks(const ADirectory: string; const AList: TStrings);

implementation

uses
  SysUtils;

const
  RecentFileName = 'recent-logbooks.txt';

function SettingsDirectory: string;
var
  Base: string;
begin
  Result := GetEnvironmentVariable('MUNINN_CONFIG_DIR');
  if Result <> '' then
    Exit(ExcludeTrailingPathDelimiter(Result));
  {$IF defined(WINDOWS)}
  Base := GetEnvironmentVariable('APPDATA');
  if Base = '' then
    Base := GetUserDir;
  Result := IncludeTrailingPathDelimiter(Base) + 'MuninnLog';
  {$ELSEIF defined(DARWIN)}
  Result := IncludeTrailingPathDelimiter(GetUserDir) +
    'Library/Application Support/MuninnLog';
  {$ELSE}
  Base := GetEnvironmentVariable('XDG_CONFIG_HOME');
  if Base = '' then
    Base := IncludeTrailingPathDelimiter(GetUserDir) + '.config';
  Result := IncludeTrailingPathDelimiter(Base) + 'muninnlog';
  {$ENDIF}
end;

procedure LoadRecentLogbooks(const ADirectory: string; const AList: TStrings);
var
  FileName: string;
  Lines: TStringList;
  Index: Integer;
begin
  AList.Clear;
  FileName := IncludeTrailingPathDelimiter(ADirectory) + RecentFileName;
  if not FileExists(FileName) then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(FileName);
    for Index := 0 to Lines.Count - 1 do
      if Trim(Lines[Index]) <> '' then
        AList.Add(Lines[Index]);
  finally
    Lines.Free;
  end;
end;

procedure SaveRecentLogbooks(const ADirectory: string; const AList: TStrings);
var
  FileName, TempName: string;
  Lines: TStringList;
begin
  if not ForceDirectories(ADirectory) then
    raise EInOutError.CreateFmt('Cannot create %s', [ADirectory]);
  FileName := IncludeTrailingPathDelimiter(ADirectory) + RecentFileName;
  TempName := FileName + '.tmp';
  Lines := TStringList.Create;
  try
    Lines.LineBreak := #10;
    Lines.AddStrings(AList);
    Lines.SaveToFile(TempName);
  finally
    Lines.Free;
  end;
  { RenameFile does not replace an existing file on Windows. }
  if FileExists(FileName) and not DeleteFile(FileName) then
    raise EInOutError.CreateFmt('Cannot replace %s', [FileName]);
  if not RenameFile(TempName, FileName) then
    raise EInOutError.CreateFmt('Cannot write %s', [FileName]);
end;

end.
