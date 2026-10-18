program MuninnCli;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads, cwstring,{$ENDIF}
  SysUtils, Muninn.Core.Version;

const
  ExitSuccess = 0;
  ExitInvalidArguments = 4;

procedure WriteUsage;
begin
  WriteLn('Usage: muninn-cli [--version | --help]');
end;

begin
  if (ParamCount = 1) and (ParamStr(1) = '--version') then
  begin
    WriteLn(VersionText);
    Halt(ExitSuccess);
  end;

  if (ParamCount = 0) or ((ParamCount = 1) and (ParamStr(1) = '--help')) then
  begin
    WriteUsage;
    Halt(ExitSuccess);
  end;

  WriteUsage;
  Halt(ExitInvalidArguments);
end.
