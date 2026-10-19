{
  TimeoutTest.lpr

  Verifies the two-tier command timeout.

  二段構えのコマンドタイムアウトを検証します。

  Tier 1 (Hamlib's own timeout/retry conf) cannot be exercised without a
  real serial device, so this test targets tier 2: a loader whose
  rig_get_freq blocks far longer than the budget, simulating a wedged
  USB adapter that never returns from read().

  第 1 段 (Hamlib 自身の timeout/retry conf) は実シリアルデバイスなしでは
  動かせないため、本テストは第 2 段を対象にします。rig_get_freq が予算を
  大きく超えてブロックするローダを使い、read() から戻らない固まった
  USB 変換器を模擬します。

  Checks:
    - the command completes instead of hanging forever
    - its status is rcsTimeout (not rcsSuccess, not a generic error)
    - the watchdog's abort was actually invoked (rig_close called from
      a thread other than the one blocked in rig_get_freq)

  確認項目:
    - 永久に固まらずコマンドが完了すること
    - ステータスが rcsTimeout であること (rcsSuccess でも汎用エラーでもない)
    - watchdog の中断が実際に起動したこと (rig_get_freq でブロック中の
      スレッドとは別スレッドから rig_close が呼ばれたこと)

  Build: fpc -Mobjfpc -Sh -Fu../src -FE. TimeoutTest.lpr
}
program TimeoutTest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils, SyncObjs,
  HamlibInterfaces, HamlibService, HamlibTimeoutPolicy;

var
  CloseCalled:     Boolean = False;
  CloseFromOther:  Boolean = False;
  BlockingThread:  TThreadID = 0;
  ConfSet:         TStringList;
  ResultStatus:    TRigCommandStatus;
  GotResult:       Boolean = False;
  Elapsed:         QWord = 0;

type
  { rig_get_freq blocks for BLOCK_MS, far beyond the command budget,
    unless the handle is closed underneath it — which is exactly what
    the watchdog does. We emulate "the close unblocks the read" by
    polling a flag, the way a real driver would return EBADF.

    rig_get_freq は BLOCK_MS の間ブロックし、コマンド予算を大きく超えます。
    ただし下からハンドルを閉じられた場合は別で、それこそが watchdog の
    動作です。実ドライバが EBADF を返す様子を、フラグのポーリングで模擬します。 }
  TStuckLoader = class(TInterfacedObject, IHamlibLoader)
  private
    FAborted: Boolean;
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

const
  BLOCK_MS = 8000;   { far beyond any budget used here / ここで使う予算を大きく超える }

function  TStuckLoader.Load(const APath: string): Boolean; begin Result := True; end;
procedure TStuckLoader.Unload; begin end;
function  TStuckLoader.GetIsLoaded: Boolean; begin Result := True; end;
function  TStuckLoader.GetApiMajor: Integer; begin Result := 4; end;
function  TStuckLoader.GetApiMinor: Integer; begin Result := 7; end;
function  TStuckLoader.GetLibPath: string; begin Result := '<stuck>'; end;
function  TStuckLoader.HasSymbol(const AName: string): Boolean; begin Result := True; end;
function  TStuckLoader.CallRigInit(AModel: Integer): Pointer; begin Result := Pointer(1); end;
function  TStuckLoader.CallRigOpen(ARig: Pointer): Integer; begin FAborted := False; Result := 0; end;

function  TStuckLoader.CallRigClose(ARig: Pointer): Integer;
begin
  CloseCalled := True;
  if GetCurrentThreadId <> BlockingThread then
    CloseFromOther := True;
  FAborted := True;        { unblocks the pending read / 待機中の読み取りを解除 }
  Result := 0;
end;

function  TStuckLoader.CallRigCleanup(ARig: Pointer): Integer; begin Result := 0; end;
function  TStuckLoader.CallRigSetFreq(ARig: Pointer; AVfo: Integer; AFreq: Double): Integer; begin Result := 0; end;

function  TStuckLoader.CallRigGetFreq(ARig: Pointer; AVfo: Integer; out AFreq: Double): Integer;
var
  Waited: Integer;
begin
  BlockingThread := GetCurrentThreadId;
  AFreq  := 0;
  Waited := 0;
  while (Waited < BLOCK_MS) and (not FAborted) do
  begin
    Sleep(20);
    Inc(Waited, 20);
  end;
  if FAborted then
    Result := -6     { -RIG_EIO, as a real driver reports a closed fd }
  else
  begin
    AFreq  := 14074000.0;
    Result := 0;
  end;
end;

function  TStuckLoader.CallRigSetMode(ARig: Pointer; AVfo: Integer; AMode: Int64; AWidth: Int64): Integer; begin Result := 0; end;
function  TStuckLoader.CallRigGetMode(ARig: Pointer; AVfo: Integer; out AMode: Int64; out AWidth: Int64): Integer;
begin AMode := 0; AWidth := 0; Result := 0; end;
function  TStuckLoader.CallRigSetPtt(ARig: Pointer; AVfo: Integer; APtt: Integer): Integer; begin Result := 0; end;
function  TStuckLoader.CallRigGetPtt(ARig: Pointer; AVfo: Integer; out APtt: Integer): Integer;
begin APtt := 0; Result := 0; end;
function  TStuckLoader.CallRigError(ACode: Integer): string;
begin Result := Format('stuck-loader error %d', [ACode]); end;

function  TStuckLoader.SetConf(ARig: Pointer; const AName, AValue: string): Integer;
begin
  { Record tier-1 configuration so the test can assert it was applied.
    第 1 段の設定を記録し、適用されたことをテストで検証できるようにします。 }
  ConfSet.Values[AName] := AValue;
  Result := 0;
end;

function  TStuckLoader.SetSerialPort(ARig: Pointer; const APort: string): Integer;
begin Result := SetConf(ARig, 'rig_pathname', APort); end;
function  TStuckLoader.SetSerialBaud(ARig: Pointer; ABaud: Integer): Integer;
begin Result := SetConf(ARig, 'serial_speed', IntToStr(ABaud)); end;

type
  THarness = class
    procedure OnFreq(const R: TRigFreqResult);
  end;

procedure THarness.OnFreq(const R: TRigFreqResult);
begin
  ResultStatus := R.Status;
  GotResult    := True;
end;

var
  Svc:     IRigService;
  H:       THarness;
  Policy:  TRigTimeoutPolicy;
  i:       Integer;
  T0:      QWord;
begin
  WriteLn('=== Two-tier command timeout ===');
  WriteLn;

  ConfSet := TStringList.Create;
  H       := THarness.Create;

  Policy := RigPolicy_Default;
  Policy.CommandTimeoutMs := 1000;   { budget under test / 検証対象の予算 }

  Svc := TRigService.Create(TStuckLoader.Create);
  try
    Svc.ApplyTimeoutPolicy(Policy);
    Svc.Open(1, 'none');
    Sleep(150);

    WriteLn('Tier 1 — configuration pushed into Hamlib:');
    WriteLn('    timeout = ', ConfSet.Values['timeout'], ' ms');
    WriteLn('    retry   = ', ConfSet.Values['retry']);
    WriteLn;

    WriteLn('Tier 2 — issuing a command whose I/O blocks for ', BLOCK_MS, ' ms');
    WriteLn('          against a budget of ', Policy.CommandTimeoutMs, ' ms...');

    T0 := GetTickCount64;
    Svc.GetFrequencyAsync(rvfoA, @H.OnFreq);

    for i := 1 to 400 do        { up to ~6 s of waiting / 最大約 6 秒待機 }
    begin
      CheckSynchronize(10);
      Sleep(5);
      if GotResult then Break;
    end;
    Elapsed := GetTickCount64 - T0;

    WriteLn('    callback fired : ', GotResult);
    WriteLn('    elapsed        : ', Elapsed, ' ms');
    if GotResult then
      WriteLn('    status         : ', Ord(ResultStatus), '  (3 = rcsTimeout)');
    WriteLn('    rig_close called          : ', CloseCalled);
    WriteLn('    ...from a different thread: ', CloseFromOther);
    WriteLn;

    if not GotResult then
      WriteLn('RESULT: *** FAIL - command never completed (still hung) ***')
    else if ResultStatus <> rcsTimeout then
      WriteLn('RESULT: *** FAIL - completed but status is not rcsTimeout ***')
    else if not CloseFromOther then
      WriteLn('RESULT: *** FAIL - watchdog did not abort the stuck I/O ***')
    else if Elapsed > 4000 then
      WriteLn('RESULT: *** FAIL - took too long to give up ***')
    else
      WriteLn('RESULT: OK (aborted and reported as rcsTimeout)');
  finally
    Svc.CancelAllPending;
    Svc.Close;
    Svc := nil;
    CheckSynchronize(300);
    H.Free;
    ConfSet.Free;
  end;

  WriteLn;
  WriteLn('=== Done ===');
end.
