program LeakTest2;
{$mode objfpc}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  HamlibInterfaces, HamlibService, HamlibTimeoutPolicy;
{$I fakeloader.inc}
var
  Svc: IRigService;
begin
  SetHeapTraceOutput('leak_report2.txt');
  Svc := TRigService.Create(TFakeLoader.Create);
  Svc.Open(1, 'none');
  Svc.EnablePolling(100);
  Sleep(250);
  CheckSynchronize(200);
  { 利用者が Close を呼び忘れて参照を捨てる }
  Svc := nil;
  CheckSynchronize(300);
  WriteLn('LeakTest2 finished (Close was NOT called)');
end.
