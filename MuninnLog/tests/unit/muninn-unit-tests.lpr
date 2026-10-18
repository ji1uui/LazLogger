program MuninnUnitTests;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads, cwstring,{$ENDIF}
  Classes, consoletestrunner,
  Muninn.Tests.Runtime,
  Muninn.Core.Version.Tests;

var
  Runner: TTestRunner;
begin
  Runner := TTestRunner.Create(nil);
  try
    Runner.Initialize;
    Runner.Title := 'MuninnLog unit tests';
    Runner.Run;
  finally
    Runner.Free;
  end;
end.
