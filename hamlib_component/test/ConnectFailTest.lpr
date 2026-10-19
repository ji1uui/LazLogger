{
  ConnectFailTest.lpr

  Verifies P0-3: when the rig fails to connect, commands must be rejected
  rather than executed against a nil PRIG handle. The fake loader records
  whether rig_set_freq was ever reached with ARig = nil, which is exactly
  the condition that segfaults the real Hamlib C library.

  P0-3 の検証: リグへの接続に失敗した場合、コマンドは nil の PRIG ハンドルに
  対して実行されるのではなく拒否されなければなりません。Fake ローダは
  ARig = nil のまま rig_set_freq に到達したかを記録します。これは実際の
  Hamlib C ライブラリがセグフォルトする条件そのものです。

  Build: fpc -Mobjfpc -Sh -Fu../src -FE. ConnectFailTest.lpr
}
program ConnectFailTest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  HamlibInterfaces, HamlibService, HamlibTimeoutPolicy;

var
  NilRigCalls:  Integer = 0;   { ARig = nil で実呼び出しに到達した回数 }
  LastStatus:   TRigCommandStatus;
  GotResult:    Boolean = False;

type
  { A loader whose rig_open always fails, so the Worker never obtains a
    valid PRIG. rig_init still returns a handle, mirroring Hamlib: the
    handle exists but is unusable until rig_open succeeds.

    rig_open が常に失敗するローダ。Worker は有効な PRIG を得られません。
    rig_init はハンドルを返します (Hamlib と同じ挙動: ハンドルは存在するが
    rig_open 成功までは使用不可)。 }
  TFailingLoader = class(TInterfacedObject, IHamlibLoader)
  public
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

function  TFailingLoader.Load(const APath: string): Boolean; begin Result := True; end;
procedure TFailingLoader.Unload; begin end;
function  TFailingLoader.GetIsLoaded: Boolean; begin Result := True; end;
function  TFailingLoader.GetApiMajor: Integer; begin Result := 4; end;
function  TFailingLoader.GetApiMinor: Integer; begin Result := 5; end;
function  TFailingLoader.GetLibPath: string; begin Result := '<failing>'; end;
function  TFailingLoader.HasSymbol(const AName: string): Boolean; begin Result := True; end;
function  TFailingLoader.CallRigInit(AModel: Integer): Pointer; begin Result := Pointer(1); end;

function  TFailingLoader.CallRigOpen(ARig: Pointer): Integer;
begin
  Result := -6;   { RIG_EIO — port busy / rig powered off }
end;

function  TFailingLoader.CallRigClose(ARig: Pointer): Integer; begin Result := 0; end;
function  TFailingLoader.CallRigCleanup(ARig: Pointer): Integer; begin Result := 0; end;

function  TFailingLoader.CallRigSetFreq(ARig: Pointer; AVfo: Integer; AFreq: Double): Integer;
begin
  { Reaching here with ARig = nil is the crash condition we are testing.
    ARig = nil でここに到達することが、検証対象のクラッシュ条件です。 }
  if ARig = nil then Inc(NilRigCalls);
  Result := 0;
end;

function  TFailingLoader.CallRigGetFreq(ARig: Pointer; AVfo: Integer; out AFreq: Double): Integer;
begin
  if ARig = nil then Inc(NilRigCalls);
  AFreq := 0; Result := 0;
end;

function  TFailingLoader.CallRigSetMode(ARig: Pointer; AVfo: Integer; AMode: Int64; AWidth: Int64): Integer;
begin
  if ARig = nil then Inc(NilRigCalls);
  Result := 0;
end;

function  TFailingLoader.CallRigGetMode(ARig: Pointer; AVfo: Integer; out AMode: Int64; out AWidth: Int64): Integer;
begin
  if ARig = nil then Inc(NilRigCalls);
  AMode := 0; AWidth := 0; Result := 0;
end;

function  TFailingLoader.CallRigSetPtt(ARig: Pointer; AVfo: Integer; APtt: Integer): Integer;
begin
  if ARig = nil then Inc(NilRigCalls);
  Result := 0;
end;

function  TFailingLoader.CallRigGetPtt(ARig: Pointer; AVfo: Integer; out APtt: Integer): Integer;
begin
  if ARig = nil then Inc(NilRigCalls);
  APtt := 0; Result := 0;
end;

function  TFailingLoader.CallRigError(ACode: Integer): string;
begin Result := Format('simulated I/O error %d', [ACode]); end;

function  TFailingLoader.SetConf(ARig: Pointer; const AName, AValue: string): Integer;
begin Result := 0; end;

function  TFailingLoader.SetSerialPort(ARig: Pointer; const APort: string): Integer; begin Result := 0; end;
function  TFailingLoader.SetSerialBaud(ARig: Pointer; ABaud: Integer): Integer; begin Result := 0; end;

type
  THarness = class
    procedure OnResult(const R: TRigResult);
  end;

procedure THarness.OnResult(const R: TRigResult);
begin
  LastStatus := R.Status;
  GotResult  := True;
end;

var
  Svc: IRigService;
  H:   THarness;
  i:   Integer;
begin
  WriteLn('=== Connect-failure safety test (P0-3) ===');
  WriteLn;

  H   := THarness.Create;
  Svc := TRigService.Create(TFailingLoader.Create);
  try
    Svc.Open(1, 'none');     { rig_open will fail inside the Worker }
    Sleep(150);

    WriteLn('Issuing commands while the rig is NOT connected...');
    Svc.SetFrequencyAsync(14074000.0, rvfoA, @H.OnResult);

    for i := 1 to 20 do
    begin
      CheckSynchronize(50);
      Sleep(10);
      if GotResult then Break;
    end;

    WriteLn('  callback fired      : ', GotResult);
    if GotResult then
      WriteLn('  status              : ', Ord(LastStatus),
              '  (4 = rcsRejected)');
    WriteLn('  nil-PRIG call count : ', NilRigCalls);
    WriteLn;

    if NilRigCalls > 0 then
      WriteLn('RESULT: *** UNSAFE - a nil PRIG reached the Hamlib call ***')
    else if GotResult and (LastStatus = rcsRejected) then
      WriteLn('RESULT: OK (command rejected, no nil PRIG dereference)')
    else
      WriteLn('RESULT: inconclusive');
  finally
    Svc.CancelAllPending;
    Svc.Close;
    Svc := nil;
    CheckSynchronize(200);
    H.Free;
  end;

  WriteLn;
  WriteLn('=== Done ===');
end.
