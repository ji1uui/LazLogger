program MuninnGui;

{ The UI prototype (T10, ADR 0009): the QSO entry line and the band map with
  demo data.

  muninn-gui [--light] [--measure <report.txt>]

  --light    light colours (default: dark)
  --measure  measure the response times, write the report, and exit
             (exit code 1 if a paint was not seen in time) }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads, cwstring,{$ENDIF}
  Interfaces, Forms, SysUtils, Muninn.UI.Clock, Muninn.UI.Theme,
  Muninn.UI.MainForm, Muninn.App.Prototype;

{$R *.res}

var
  StartedUs: Int64;
  MainForm: TMainForm;
  Theme: TUiTheme;
  Measure: Boolean;
  Output: string;
  Index: Integer;
begin
  StartedUs := MicroTicks;
  Theme := DarkTheme;
  Measure := False;
  Output := '';
  Index := 1;
  while Index <= ParamCount do
  begin
    if ParamStr(Index) = '--light' then
      Theme := LightTheme
    else if (ParamStr(Index) = '--measure') and (Index < ParamCount) then
    begin
      Measure := True;
      Inc(Index);
      Output := ParamStr(Index);
    end
    else
    begin
      if IsConsole then
        WriteLn(StdErr, 'usage: muninn-gui [--light] [--measure <report.txt>]');
      Halt(4);
    end;
    Inc(Index);
  end;

  Application.Scaled := True;
  Application.Title := 'MuninnLog';
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  MainForm.ApplyTheme(Theme);
  LoadDemoData(MainForm, 40, 20000);
  MainForm.Show;
  if Measure then
  begin
    if not RunMeasurements(MainForm, Output, StartedUs) then
      ExitCode := 1;
    MainForm.Close;
    Application.ProcessMessages;
    Exit;
  end;
  Application.Run;
end.
