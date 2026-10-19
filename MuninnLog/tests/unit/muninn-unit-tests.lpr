program MuninnUnitTests;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads, cwstring,{$ENDIF}
  Muninn.Core.Utf8Default,
  Classes, consoletestrunner,
  Muninn.Tests.Runtime,
  Muninn.Core.Version.Tests,
  Muninn.Core.Callsign.Tests,
  Muninn.Core.Band.Tests,
  Muninn.Core.Mode.Tests,
  Muninn.Core.Time.Tests,
  Muninn.Core.AdifModes.Tests,
  Muninn.Core.Adif.Tests,
  Muninn.Core.AdifQso.Tests,
  Muninn.UI.Bandmap.Tests,
  Muninn.UI.QsoEntry.Tests;

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
