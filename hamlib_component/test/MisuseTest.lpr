program MisuseTest;
{$mode objfpc}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  HamlibInterfaces, HamlibService;
{$I fakeloader.inc}
var
  Svc: IRigService;
begin
  Svc := TRigService.Create(TFakeLoader.Create);
  WriteLn('Calling SetFrequencyAsync BEFORE Open (release build, asserts off)...');
  try
    Svc.SetFrequencyAsync(14074000.0);
    WriteLn('  -> returned without error (silently wrong?)');
  except
    on E: Exception do WriteLn('  -> exception: ', E.ClassName, ': ', E.Message);
  end;
  WriteLn('Survived.');
end.
