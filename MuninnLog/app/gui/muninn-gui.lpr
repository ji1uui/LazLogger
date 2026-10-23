program MuninnGui;

{ The MuninnLog GUI (T12; screen technology: ADR 0009).

  muninn-gui [--light] [<logbook>]
  muninn-gui --demo [--light] [--measure <report.txt>]

  <logbook>  open this logbook (default: the most recently used one)
  --light    light colours (default: dark)
  --demo     the T10 prototype's demo data, without a logbook
  --measure  in the demo, measure the response times, write the report, and
             exit (exit code 1 if a paint was not seen in time)

  MUNINN_CONFIG_DIR overrides the settings directory (ADR 0010). }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads, cwstring,{$ENDIF}
  Interfaces, Forms, Classes, SysUtils, Muninn.UI.Clock, Muninn.UI.Theme,
  Muninn.UI.MainForm, Muninn.Storage.Logbook, Muninn.Storage.Settings,
  Muninn.App.Settings, Muninn.App.Prototype;

{$R *.res}

procedure Usage;
begin
  if IsConsole then
    WriteLn(StdErr, 'usage: muninn-gui [--light] [<logbook>]', LineEnding,
      '       muninn-gui --demo [--light] [--measure <report.txt>]');
  Halt(4);
end;

var
  StartedUs: Int64;
  MainForm: TMainForm;
  Theme: TUiTheme;
  Demo, Measure: Boolean;
  Output, LogbookPath: string;
  Index: Integer;
  RecentFile: TRecentLogbookFile;
  Recent: TStringList;
begin
  StartedUs := MicroTicks;
  Theme := DarkTheme;
  Demo := False;
  Measure := False;
  Output := '';
  LogbookPath := '';
  Index := 1;
  while Index <= ParamCount do
  begin
    if ParamStr(Index) = '--light' then
      Theme := LightTheme
    else if ParamStr(Index) = '--demo' then
      Demo := True
    else if (ParamStr(Index) = '--measure') and (Index < ParamCount) then
    begin
      Measure := True;
      Inc(Index);
      Output := ParamStr(Index);
    end
    else if (Copy(ParamStr(Index), 1, 1) <> '-') and (LogbookPath = '') then
      LogbookPath := ParamStr(Index)
    else
      Usage;
    Inc(Index);
  end;
  if (Measure and not Demo) or (Demo and (LogbookPath <> '')) then
    Usage;

  Application.Scaled := True;
  Application.Title := 'MuninnLog';
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  MainForm.ApplyTheme(Theme);
  RecentFile := TRecentLogbookFile.Create(SettingsDirectory);
  Recent := TStringList.Create;
  try
    if Demo then
    begin
      MainForm.EnableDemo;
      LoadDemoData(MainForm, 40, 20000);
    end
    else
    begin
      RecentFile.Load(Recent);
      MainForm.AttachLogbooks(TSqliteLogbookStore.Create, Recent, @RecentFile.Save);
    end;
    MainForm.Show;
    if not Demo then
      if LogbookPath <> '' then
        MainForm.Logbooks.OpenRequested(LogbookPath)
      else
        MainForm.Logbooks.OpenMostRecent;
    if Measure then
    begin
      if not RunMeasurements(MainForm, Output, StartedUs) then
        ExitCode := 1;
      MainForm.Close;
      Application.ProcessMessages;
      Exit;
    end;
    Application.Run;
  finally
    { The form's presenter saves through RecentFile; close it first. }
    if MainForm.Logbooks <> nil then
      MainForm.Logbooks.CloseRequested;
    Recent.Free;
    RecentFile.Free;
  end;
end.
