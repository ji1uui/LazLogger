program MuninnIntegrationTests;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads, cwstring,{$ENDIF}
  Muninn.Core.Utf8Default,
  Classes, consoletestrunner,
  Muninn.Storage.Schema.Tests,
  Muninn.Storage.QsoRepository.Tests,
  Muninn.Cli.Tests;

var
  Runner: TTestRunner;
begin
  Runner := TTestRunner.Create(nil);
  try
    Runner.Initialize;
    Runner.Title := 'MuninnLog integration tests';
    Runner.Run;
  finally
    Runner.Free;
  end;
end.
