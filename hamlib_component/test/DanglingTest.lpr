program DanglingTest;
{$mode objfpc}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  HamlibInterfaces, HamlibService, HamlibTimeoutPolicy;

type
  TFakeLoader = class(TInterfacedObject, IHamlibLoader)
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
function  TFakeLoader.CallRigSetFreq(ARig: Pointer; AVfo: Integer; AFreq: Double): Integer;
begin Sleep(5); Result := 0; end;
function  TFakeLoader.CallRigGetFreq(ARig: Pointer; AVfo: Integer; out AFreq: Double): Integer;
begin Sleep(5); AFreq := 14074000.0; Result := 0; end;
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

{ ---- 「破棄済み」を検出する擬似 Presenter ---- }
type
  TPseudoPresenter = class
  private
    FMagic: LongWord;        { 生存中は $A11VE、破棄後は 0 }
  public
    Alive: Boolean;
    constructor Create;
    destructor  Destroy; override;
    procedure OnFreqResult(const R: TRigFreqResult);
    procedure OnSetResult(const R: TRigResult);
  end;

var
  DeadCallbackCount:  Integer = 0;
  StatusAfterDeath:   TRigCommandStatus;
  GotCallbackAfterDeath: Boolean = False;

constructor TPseudoPresenter.Create;
begin
  inherited;
  FMagic := $A11FE;
  Alive  := True;
end;

destructor TPseudoPresenter.Destroy;
begin
  FMagic := 0;      { 破棄マーク }
  Alive  := False;
  inherited;
end;

procedure TPseudoPresenter.OnFreqResult(const R: TRigFreqResult);
begin
  if FMagic <> $A11FE then
  begin
    Inc(DeadCallbackCount);
    StatusAfterDeath := R.Status;
    GotCallbackAfterDeath := True;
    WriteLn(Format('    !! callback on DESTROYED object, status=%d freq=%.0f',
      [Ord(R.Status), R.Freq]));
  end;
end;

procedure TPseudoPresenter.OnSetResult(const R: TRigResult);
begin
  if FMagic <> $A11FE then
  begin
    Inc(DeadCallbackCount);
    StatusAfterDeath := R.Status;
    GotCallbackAfterDeath := True;
    WriteLn(Format('    !! callback on DESTROYED object, status=%d', [Ord(R.Status)]));
  end;
end;

{ =================== TEST 4 =================== }
procedure Test4_CallbackAfterDestroy;
var
  Svc: IRigService;
  P:   TPseudoPresenter;
  i:   Integer;
begin
  WriteLn('TEST 4: Does a callback fire on a DESTROYED presenter after CancelAllPending?');
  DeadCallbackCount := 0;
  GotCallbackAfterDeath := False;

  Svc := TRigService.Create(TFakeLoader.Create);
  Svc.Open(1, 'none');
  Sleep(50);

  P := TPseudoPresenter.Create;

  { 大量のコマンドを投入し、Workerが処理中の状態を作る }
  for i := 1 to 40 do
    Svc.GetFrequencyAsync(rvfoA, @P.OnFreqResult);

  Sleep(20);   { Worker が処理を始めた頃合い }

  { 利用者が推奨手順どおりに片付ける }
  Svc.DisablePolling;
  Svc.CancelAllPending;
  Svc.Close;

  { Presenter を破棄 }
  P.Free;

  { UI スレッドのキューを処理（Lazarus なら Application が自動でやる） }
  for i := 1 to 20 do
  begin
    CheckSynchronize(50);
    Sleep(10);
  end;

  Svc := nil;
  CheckSynchronize(200);

  WriteLn('    callbacks delivered to destroyed object: ', DeadCallbackCount);
  if GotCallbackAfterDeath then
  begin
    if StatusAfterDeath = rcsCancelled then
      WriteLn('    RESULT: acceptable (all were rcsCancelled)')
    else
      WriteLn('    RESULT: *** UNSAFE - non-cancelled status reached dead object ***');
  end
  else
    WriteLn('    RESULT: OK (no callback after destroy)');
  WriteLn;
end;

begin
  WriteLn('=== Dangling Callback Verification ===');
  WriteLn;
  Test4_CallbackAfterDestroy;
  WriteLn('=== Done ===');
end.
