{
  SmokeTest.lpr

  Smoke test program: verifies the component compiles cleanly and
  basic API surface works with a fake loader. NO real Hamlib library
  is required to run this.

  スモークテストプログラム: コンポーネントがクリーンにコンパイルされ、
  Fake ローダで基本 API が動作することを検証します。実 Hamlib ライブラリは
  不要です。

  Build:    fpc -Mobjfpc -Sh -Fu../src -Fu../test SmokeTest.lpr
  Run:      ./SmokeTest
}
program SmokeTest;

{$mode objfpc}{$H+}

uses
  { cthreads MUST come first in a Unix console program: the component
    uses TThread and TEvent, and without it this program aborts with
    "Failed to create OS basic event" or runtime error 232. The README
    says so; this example did not follow its own instruction until
    Rev.5.0.

    Unix のコンソールプログラムでは cthreads を必ず最初に置きます。本
    コンポーネントは TThread と TEvent を使うため、これがないと
    "Failed to create OS basic event" または実行時エラー 232 で停止します。
    README に記載のとおりですが、本サンプルは Rev.5.0 までその指示に
    従っていませんでした。 }
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils, SyncObjs,
  HamlibInterfaces, HamlibErrors, HamlibTypes, HamlibModeCodec,
  HamlibTimeoutPolicy, HamlibService, HamlibCancellation,
  FakeHamlibLoader;

type
  { Test harness that holds Service callbacks.
    Service コールバックを保持するテストハーネス。 }
  TSmokeTest = class
  private
    FService: IRigService;
    FDoneEvent: TEvent;
    FLastFreq: Double;
    FLastError: string;
    procedure HandleSetFreqDone(const AResult: TRigResult);
    procedure HandleGetFreqDone(const AResult: TRigFreqResult);
    procedure HandleError(Sender: TObject; AKind: TRigErrorKind;
                          ANativeCode: Integer; const AMsg: string);
  public
    constructor Create;
    destructor  Destroy; override;
    procedure   Run;
  end;

constructor TSmokeTest.Create;
var
  FakeLoader: IHamlibLoader;
  Svc: TRigService;
begin
  inherited Create;
  FDoneEvent := TEvent.Create(nil, True, False, '');

  { Inject a fake loader directly so we don't need a real DLL.
    実 DLL なしで動作させるため Fake ローダを直接注入。 }
  FakeLoader := TFakeHamlibLoader.Create;
  Svc        := TRigService.Create(FakeLoader);
  FService   := Svc;

  FService.SetOnError(@HandleError);
end;

destructor TSmokeTest.Destroy;
begin
  if Assigned(FService) then
  begin
    FService.DisablePolling;
    FService.CancelAllPending;
    FService.Close;
  end;
  FService := nil;
  FDoneEvent.Free;
  inherited;
end;

procedure TSmokeTest.HandleSetFreqDone(const AResult: TRigResult);
begin
  WriteLn(Format('  SetFreq result: status=%d error=%s native=%d msg=%s',
    [Ord(AResult.Status), RigErrorKindToString(AResult.Error),
     AResult.NativeCode, AResult.ErrorMsg]));
  FDoneEvent.SetEvent;
end;

procedure TSmokeTest.HandleGetFreqDone(const AResult: TRigFreqResult);
begin
  FLastFreq := AResult.Freq;
  WriteLn(Format('  GetFreq result: status=%d freq=%.0f Hz',
    [Ord(AResult.Status), AResult.Freq]));
  FDoneEvent.SetEvent;
end;

procedure TSmokeTest.HandleError(Sender: TObject; AKind: TRigErrorKind;
                                  ANativeCode: Integer; const AMsg: string);
begin
  FLastError := AMsg;
  { Branch on AKind in real code; the native number is for the log line.
    実コードでは AKind で分岐します。生の数値はログ用です。 }
  WriteLn(Format('  GLOBAL ERROR: %s (native %d) msg=%s',
    [RigErrorKindToString(AKind), ANativeCode, AMsg]));
end;

procedure TSmokeTest.Run;
var
  i: Integer;
  Token: ICancellationToken;
  State: TRigState;
begin
  WriteLn('=== HamlibComponent Smoke Test ===');
  WriteLn;

  WriteLn('1. Open service with RIG_MODEL_DUMMY...');
  FService.Open(RIG_MODEL_DUMMY, 'none');
  WriteLn('   IsOpen = ', FService.IsOpen);
  WriteLn;

  Sleep(50);   { Give worker thread time to connect.
                 Worker スレッドの接続時間を確保。 }

  WriteLn('2. SetFrequencyAsync(14.074 MHz)...');
  FDoneEvent.ResetEvent;
  FService.SetFrequencyAsync(14074000.0, rvfoA, @HandleSetFreqDone);
  if FDoneEvent.WaitFor(2000) <> wrSignaled then
    WriteLn('   TIMEOUT waiting for SetFreq result');

  { Manually pump the message queue so TThread.Queue callbacks fire.
    Required for console programs without Application.ProcessMessages.
    手動でメッセージキューをポンピング (TThread.Queue コールバック発火用)。
    Application.ProcessMessages を持たないコンソールプログラムでは必須。 }
  CheckSynchronize(500);
  Sleep(50);
  CheckSynchronize(500);
  WriteLn;

  WriteLn('3. GetFrequencyAsync...');
  FDoneEvent.ResetEvent;
  Token := FService.GetFrequencyAsync(rvfoA, @HandleGetFreqDone);
  WriteLn('   Token IsCancelled = ', Token.IsCancelled);
  for i := 1 to 10 do
  begin
    CheckSynchronize(100);
    Sleep(50);
    if FDoneEvent.WaitFor(0) = wrSignaled then Break;
  end;
  WriteLn;

  WriteLn('4. Snapshot via CurrentState (Pull model)...');
  State := FService.CurrentState;
  WriteLn(Format('   State.CurrentFreq = %.0f Hz, Timestamp = %d',
    [State.CurrentFreq, State.Timestamp]));
  WriteLn;

  WriteLn('5. Apply VerySlowCat policy at runtime...');
  FService.ApplyTimeoutPolicy(RigPolicy_VerySlowCat);
  WriteLn('   CommandTimeout now: ',
    FService.GetCurrentPolicy.CommandTimeoutMs, ' ms');
  WriteLn;

  WriteLn('6. CancelAllPending and Close...');
  FService.CancelAllPending;
  FService.Close;
  WriteLn('   IsOpen = ', FService.IsOpen);
  WriteLn;

  WriteLn('=== Smoke Test Completed ===');
end;

var
  Test: TSmokeTest;
begin
  try
    Test := TSmokeTest.Create;
    try
      Test.Run;
    finally
      Test.Free;
    end;
    { Final synchronize pump.
      最終同期ポンピング。 }
    CheckSynchronize(1000);
    WriteLn;
    WriteLn('OK.');
  except
    on E: Exception do
    begin
      WriteLn(Format('FAILED: %s: %s', [E.ClassName, E.Message]));
      ExitCode := 1;
    end;
  end;
end.
