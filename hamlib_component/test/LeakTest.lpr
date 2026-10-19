program LeakTest;
{$mode objfpc}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  HamlibInterfaces, HamlibService, HamlibTimeoutPolicy;
{$I fakeloader.inc}
var
  Svc: IRigService;
  i: Integer;
begin
  SetHeapTraceOutput('leak_report.txt');
  Svc := TRigService.Create(TFakeLoader.Create);
  Svc.Open(1, 'none');
  Sleep(50);
  { コマンドを投入して即Close（配送されないコマンドが残る状況） }
  for i := 1 to 50 do
    Svc.SetFrequencyAsync(14074000.0 + i);
  Svc.CancelAllPending;
  Svc.Close;
  Svc := nil;
  CheckSynchronize(300);
  WriteLn('LeakTest finished');
end.
