program LifecycleTest;
{$mode objfpc}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  HamlibInterfaces, HamlibService, HamlibTimeoutPolicy;

{ ---- 最小のFakeローダ（テスト内に自前で持つ） ---- }
type
  TFakeLoader = class(TInterfacedObject, IHamlibLoader)
  public
    destructor Destroy; override;
    function  Load(const APath: string = ''): Boolean;
    procedure Unload;
    function  GetIsLoaded: Boolean;
    function  GetApiMajor: Integer;
    function  GetApiMinor: Integer;
    function  GetLibPath:  string;
    function  HasSymbol(const AName: string): Boolean;
    function  CallRigInit(AModel: Integer): Pointer;
    function  CallRigOpen(ARig: Pointer): Integer;
    function  CallRigClose(ARig: Pointer): Integer;
    function  CallRigCleanup(ARig: Pointer): Integer;
    function  CallRigSetFreq(ARig: Pointer; AVfo: Integer; AFreq: Double): Integer;
    function  CallRigGetFreq(ARig: Pointer; AVfo: Integer; out AFreq: Double): Integer;
    function  CallRigSetMode(ARig: Pointer; AVfo: Integer; AMode: Int64; AWidth: Int64): Integer;
    function  CallRigGetMode(ARig: Pointer; AVfo: Integer; out AMode: Int64; out AWidth: Int64): Integer;
    function  CallRigSetPtt(ARig: Pointer; AVfo: Integer; APtt: Integer): Integer;
    function  CallRigGetPtt(ARig: Pointer; AVfo: Integer; out APtt: Integer): Integer;
    function  CallRigError(ACode: Integer): string;
    function  SetConf(ARig: Pointer; const AName, AValue: string): Integer;
    function  SetSerialPort(ARig: Pointer; const APort: string): Integer;
    function  SetSerialBaud(ARig: Pointer; ABaud: Integer): Integer;
  end;

var
  { Watched because the Service holds the loader by interface: if the
    Service is freed and the loader is not, a reference survives
    somewhere and the library is never unloaded. Up to this revision
    the test recorded this and never looked at it, which is a check
    that cannot fail — worse than no check, because it reads like one.

    Service がローダをインターフェースで保持するため監視します。
    Service が解放されてローダが解放されないなら、どこかに参照が残り、
    ライブラリは決してアンロードされません。本リビジョンまで、テストは
    これを記録するだけで参照していませんでした。それは失敗しえない検査
    であり、検査に見えるぶん、検査が無いより悪いものです。 }
  LoaderFreed:  Boolean = False;
  ServiceFreed: Boolean = False;

destructor TFakeLoader.Destroy; begin LoaderFreed := True; inherited; end;
function  TFakeLoader.Load(const APath: string): Boolean; begin Result := True; end;
procedure TFakeLoader.Unload; begin end;
function  TFakeLoader.GetIsLoaded: Boolean; begin Result := True; end;
function  TFakeLoader.GetApiMajor: Integer; begin Result := 4; end;
function  TFakeLoader.GetApiMinor: Integer; begin Result := 5; end;
function  TFakeLoader.GetLibPath: string; begin Result := '<fake>'; end;
function  TFakeLoader.HasSymbol(const AName: string): Boolean; begin Result := True; end;
function  TFakeLoader.CallRigInit(AModel: Integer): Pointer; begin Result := Pointer(1); end;
function  TFakeLoader.CallRigOpen(ARig: Pointer): Integer; begin Result := 0; end;
function  TFakeLoader.CallRigClose(ARig: Pointer): Integer; begin Result := 0; end;
function  TFakeLoader.CallRigCleanup(ARig: Pointer): Integer; begin Result := 0; end;
function  TFakeLoader.CallRigSetFreq(ARig: Pointer; AVfo: Integer; AFreq: Double): Integer; begin Result := 0; end;
function  TFakeLoader.CallRigGetFreq(ARig: Pointer; AVfo: Integer; out AFreq: Double): Integer;
begin AFreq := 14074000.0; Result := 0; end;
function  TFakeLoader.CallRigSetMode(ARig: Pointer; AVfo: Integer; AMode: Int64; AWidth: Int64): Integer; begin Result := 0; end;
function  TFakeLoader.CallRigGetMode(ARig: Pointer; AVfo: Integer; out AMode: Int64; out AWidth: Int64): Integer;
begin AMode := 4; AWidth := 2700; Result := 0; end;
function  TFakeLoader.CallRigSetPtt(ARig: Pointer; AVfo: Integer; APtt: Integer): Integer; begin Result := 0; end;
function  TFakeLoader.CallRigGetPtt(ARig: Pointer; AVfo: Integer; out APtt: Integer): Integer;
begin APtt := 0; Result := 0; end;
function  TFakeLoader.CallRigError(ACode: Integer): string; begin Result := 'fake'; end;
function  TFakeLoader.SetConf(ARig: Pointer; const AName, AValue: string): Integer;
begin Result := 0; end;

function  TFakeLoader.SetSerialPort(ARig: Pointer; const APort: string): Integer; begin Result := 0; end;
function  TFakeLoader.SetSerialBaud(ARig: Pointer; ABaud: Integer): Integer; begin Result := 0; end;

{ ---- Serviceの破棄を検知するサブクラス ---- }
type
  TTracedService = class(TRigService)
  public
    destructor Destroy; override;
  end;

destructor TTracedService.Destroy;
begin
  ServiceFreed := True;
  WriteLn('    >> TRigService.Destroy CALLED');
  inherited;
end;

{ =================== TEST 1: ポーリングなし =================== }
procedure Test1_NoPolling;
var
  Svc: IRigService;
begin
  WriteLn('TEST 1: Open/Close without EnablePolling');
  ServiceFreed := False; LoaderFreed := False;
  Svc := TTracedService.Create(TFakeLoader.Create);
  Svc.Open(1, 'none');
  Sleep(80);
  Svc.Close;
  Svc := nil;
  WriteLn('    ServiceFreed = ', ServiceFreed, '   LoaderFreed = ', LoaderFreed);
  if ServiceFreed and LoaderFreed then WriteLn('    RESULT: OK')
  else WriteLn('    RESULT: *** LEAK ***');
  WriteLn;
end;

{ =================== TEST 2: ポーリングあり =================== }
procedure Test2_WithPolling;
var
  Svc: IRigService;
begin
  WriteLn('TEST 2: EnablePolling then Close (DisablePolling NOT called explicitly)');
  ServiceFreed := False; LoaderFreed := False;
  Svc := TTracedService.Create(TFakeLoader.Create);
  Svc.Open(1, 'none');
  Svc.EnablePolling(100);
  Sleep(250);
  CheckSynchronize(200);
  Svc.Close;            { Close 内部で DisablePolling を呼ぶ }
  Svc := nil;
  CheckSynchronize(200);
  WriteLn('    ServiceFreed = ', ServiceFreed, '   LoaderFreed = ', LoaderFreed);
  if ServiceFreed and LoaderFreed then WriteLn('    RESULT: OK')
  else WriteLn('    RESULT: *** LEAK ***');
  WriteLn;
end;

{ =================== TEST 3: 利用者が Close を忘れた =================== }
procedure Test3_ForgotClose;
var
  Svc: IRigService;
begin
  WriteLn('TEST 3: EnablePolling, user FORGETS Close (self-defending destructor test)');
  ServiceFreed := False; LoaderFreed := False;
  Svc := TTracedService.Create(TFakeLoader.Create);
  Svc.Open(1, 'none');
  Svc.EnablePolling(100);
  Sleep(250);
  CheckSynchronize(200);
  Svc := nil;           { Close を呼ばずに解放 }
  CheckSynchronize(500);
  WriteLn('    ServiceFreed = ', ServiceFreed, '   LoaderFreed = ', LoaderFreed);
  if ServiceFreed and LoaderFreed then
    WriteLn('    RESULT: OK (self-defending destructor worked)')
  else if ServiceFreed then
    WriteLn('    RESULT: *** LEAK - the Service went but the loader did not ***')
  else
    WriteLn('    RESULT: *** LEAK - destructor never ran ***');
  WriteLn;
end;

begin
  WriteLn('=== HamlibComponent Lifecycle Verification ===');
  WriteLn;
  Test1_NoPolling;
  Test2_WithPolling;
  Test3_ForgotClose;
  WriteLn('=== Done ===');
end.
