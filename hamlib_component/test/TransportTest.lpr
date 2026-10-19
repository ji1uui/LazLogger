{
  TransportTest.lpr

  Drives the component over a REAL transport — a serial port, or a TCP
  connection to rigctld — instead of Hamlib's in-process dummy backend.

  Hamlib のインプロセス・ダミーバックエンドではなく、実トランスポート
  (シリアルポート、または rigctld への TCP 接続) 上でコンポーネントを
  駆動します。

  Why / 目的
  ------------------------------------------------------------------
  Every other test in this project talks to the dummy backend, which
  answers in microseconds and never fails to answer. Four things stay
  unverified under it, and all four are failure modes an operator will
  eventually meet:

    - the serial path itself: the port string, the speed and handshake
      the component applies, and whether a real backend's protocol
      code is reached at all
    - the tier-1 timeout, which is Hamlib's own — a dummy rig cannot
      fail to reply
    - a malformed or truncated reply, which a marginal cable produces
    - the link going away mid-session

  本プロジェクトの他のすべてのテストはダミーバックエンドと会話します。
  マイクロ秒で応答し、応答に失敗することがありません。その下では 4 つが
  未検証のまま残り、4 つともオペレータがいずれ遭遇する失敗モードです
  (上記)。

  This program does not decide whether the outcome is correct. It runs
  a fixed sequence, prints what happened in a machine-readable form,
  and exits. tools/run_transport_tests.py sets up each scenario — a
  simulated rig told to go silent, a rigctld that is killed mid-session
  — and asserts the expected outcome. Keeping the judgement there means
  one place lists what each fault is supposed to produce.

  本プログラムは結果の正否を判定しません。決まった手順を実行し、何が
  起きたかを機械可読な形で表示して終了します。各シナリオ (沈黙するよう
  指示されたシミュレータ、セッション中に kill される rigctld) を用意し、
  期待する結果を表明するのは tools/run_transport_tests.py です。判定を
  そちらに置くことで、「どの障害が何を生むべきか」の一覧が 1 箇所に
  まとまります。

  Usage:
    TransportTest --model=2014 --port=/dev/pts/3 [--policy=slow]
                  [--commands=6] [--budget-ms=30000]

  Output: one KEY=value line per step, then VERDICT=completed.
}
program TransportTest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  HamlibInterfaces, HamlibErrors, HamlibTimeoutPolicy,
  HamlibService, HamlibFactory;

const
  { Deliberately not a frequency any simulator or backend starts on,
    so READBACK proves the write travelled rather than matching a
    value that was already there. The first version of this test wrote
    14.074 MHz, which the simulator happened to boot on — the check
    passed without the write having to work.

    どのシミュレータやバックエンドも初期値としない周波数を意図的に
    選びます。READBACK が、既にそこにあった値との一致ではなく、書き込み
    が届いたことを示すためです。本テストの初版は 14.074 MHz を書いて
    おり、それはたまたまシミュレータの初期値でした。書き込みが働かなく
    ても検査は通っていました。 }
  TEST_FREQ = 18100000;

type
  { Collects one asynchronous result. The component delivers on the UI
    thread, so a console program pumps CheckSynchronize.
    非同期結果を 1 つ受け取ります。コンポーネントは UI スレッドで配送
    するため、コンソールプログラムは CheckSynchronize を回します。 }
  { Captures the push-model events. Open starts the worker and
    returns; the connection attempt itself happens on the worker
    thread, so whether the attempt succeeded arrives as an event and
    not as the return of Open. A test that does not subscribe sees
    "OPEN=ok" for a rig that never answered, which is what the first
    version of this program reported.

    Push モデルのイベントを捕捉します。Open はワーカーを開始して戻り、
    接続の試行自体はワーカースレッドで起きます。したがって試行が成功
    したかはイベントとして届き、Open の戻り値としては届きません。
    購読しないテストは、一度も応答しなかったリグに対して "OPEN=ok" を
    見ます。本プログラムの初版が報告したのがそれです。 }
  TEvents = class
  public
    Connects:    Integer;
    Disconnects: Integer;
    Errors:      Integer;
    FirstKind:   TRigErrorKind;
    FirstNative: Integer;
    FirstMsg:    string;
    procedure OnConnection(Sender: TObject; AConnected: Boolean);
    procedure OnError(Sender: TObject; AKind: TRigErrorKind;
                      ANativeCode: Integer; const AMsg: string);
  end;

  TCollector = class
  public
    { Counts callbacks as well as recording the last one, because the
      property that matters under a broken link is not only "what did
      it say" but "did it say anything, exactly once".
      最後の 1 件を記録するだけでなくコールバックを数えます。壊れた回線
      で重要なのは「何と言ったか」だけでなく「ちょうど 1 回言ったか」
      だからです。 }
    Count:      Integer;
    Got:        Boolean;
    Status:     TRigCommandStatus;
    Kind:       TRigErrorKind;
    Native:     Integer;
    Msg:        string;
    Freq:       Double;
    procedure OnResult(const AResult: TRigResult);
    procedure OnFreq(const AResult: TRigFreqResult);
    procedure Reset;
  end;

procedure TEvents.OnConnection(Sender: TObject; AConnected: Boolean);
begin
  if AConnected then
    Inc(Connects)
  else
    Inc(Disconnects);
end;

procedure TEvents.OnError(Sender: TObject; AKind: TRigErrorKind;
                           ANativeCode: Integer; const AMsg: string);
begin
  Inc(Errors);
  if Errors = 1 then
  begin
    FirstKind   := AKind;
    FirstNative := ANativeCode;
    FirstMsg    := StringReplace(AMsg, LineEnding, ' ', [rfReplaceAll]);
  end;
end;

procedure TCollector.Reset;
begin
  Count  := 0;
  Got    := False;
  Status := rcsSuccess;
  Kind   := rekNone;
  Native := 0;
  Msg    := '';
  Freq   := 0;
end;

procedure TCollector.OnResult(const AResult: TRigResult);
begin
  Inc(Count);
  Got    := True;
  Status := AResult.Status;
  Kind   := AResult.Error;
  Native := AResult.NativeCode;
  Msg    := AResult.ErrorMsg;
end;

procedure TCollector.OnFreq(const AResult: TRigFreqResult);
begin
  Inc(Count);
  Got    := True;
  Status := AResult.Status;
  Kind   := AResult.Error;
  Native := AResult.NativeCode;
  Msg    := AResult.ErrorMsg;
  Freq   := AResult.Freq;
end;

{ The Rev.6.0 result shapes. Each has its own dispatcher inside the
  component, so each needs its own callback here: a shape that fails
  to report would otherwise hide behind one that reports correctly.
  Rev.6.0 の結果の形。コンポーネント内でそれぞれ専用のディスパッチャを
  持つため、ここでも形ごとにコールバックが必要です。さもないと、報告
  しない形が、正しく報告する形の陰に隠れます。 }
type
  TTypedCollector = class
  public
    Level, Func, Split, Vfo: Integer;
    LastStatus: TRigCommandStatus;
    LastKind:   TRigErrorKind;
    procedure OnLevel(const A: TRigLevelResult);
    procedure OnFunc(const A: TRigFuncResult);
    procedure OnSplit(const A: TRigSplitResult);
    procedure OnVfo(const A: TRigVfoResult);
    function  Total: Integer;
  end;

procedure TTypedCollector.OnLevel(const A: TRigLevelResult);
begin Inc(Level); LastStatus := A.Status; LastKind := A.Error; end;
procedure TTypedCollector.OnFunc(const A: TRigFuncResult);
begin Inc(Func);  LastStatus := A.Status; LastKind := A.Error; end;
procedure TTypedCollector.OnSplit(const A: TRigSplitResult);
begin Inc(Split); LastStatus := A.Status; LastKind := A.Error; end;
procedure TTypedCollector.OnVfo(const A: TRigVfoResult);
begin Inc(Vfo);   LastStatus := A.Status; LastKind := A.Error; end;

function TTypedCollector.Total: Integer;
begin
  Result := Level + Func + Split + Vfo;
end;

var
  Started: QWord;

procedure Emit(const AKey, AValue: string);
begin
  WriteLn(Format('%s=%s', [AKey, AValue]));
  Flush(Output);
end;

procedure EmitElapsed(const AKey: string);
begin
  Emit(AKey, IntToStr(GetTickCount64 - Started));
end;

{ One line summarising an asynchronous outcome. The error kind is the
  interesting part: this test exists to find out which kind a real
  transport failure maps to.
  非同期の結果を 1 行にまとめます。重要なのはエラー種別です。実際の
  トランスポート障害がどの種別に写像されるかを知るために本テストが
  あります。 }
function Describe(ACol: TCollector): string;
begin
  if not ACol.Got then
    Exit('nocallback');
  case ACol.Status of
    rcsSuccess:   Result := 'ok';
    rcsCancelled: Result := 'cancelled';
    rcsTimeout:   Result := 'timeout';
    rcsRejected:  Result := 'rejected';
  else
    Result := 'error';
  end;
  if ACol.Status <> rcsSuccess then
    Result := Result + ' kind=' + RigErrorKindToString(ACol.Kind)
              + ' native=' + IntToStr(ACol.Native);
end;

{ Pump until the collector has its answer or the budget runs out. The
  budget is what turns "it hung" into a reportable outcome instead of
  a test that never ends.
  結果が届くか予算が尽きるまで回します。予算があるからこそ「停止した」
  が、終わらないテストではなく報告可能な結果になります。 }
function WaitFor(ACol: TCollector; ABudgetMs: Integer): Boolean;
var
  Deadline: QWord;
begin
  Deadline := GetTickCount64 + QWord(ABudgetMs);
  while (not ACol.Got) and (GetTickCount64 < Deadline) do
  begin
    CheckSynchronize(5);
    Sleep(5);
  end;
  Result := ACol.Got;
end;

function ArgValue(const AName: string; const ADefault: string): string;
var
  i: Integer;
  P: string;
begin
  Result := ADefault;
  for i := 1 to ParamCount do
  begin
    P := ParamStr(i);
    if Copy(P, 1, Length(AName) + 3) = '--' + AName + '=' then
      Exit(Copy(P, Length(AName) + 4, MaxInt));
  end;
end;

function PolicyByName(const AName: string): TRigTimeoutPolicy;
begin
  if SameText(AName, 'fast') then
    Result := RigPolicy_FastUsb
  else if SameText(AName, 'slow') then
    Result := RigPolicy_SlowCat
  else if SameText(AName, 'veryslow') then
    Result := RigPolicy_VerySlowCat
  else
    Result := RigPolicy_Default;
end;

var
  Factory:  IRigServiceFactory;
  Svc:      IRigService;
  Col:      TCollector;
  Model:    Integer;
  Port:     string;
  Policy:   string;
  Commands: Integer;
  Budget:   Integer;
  i:        Integer;
  Gap:      Integer;
  Deadline: QWord;
  Opened:   Boolean;
  Ev:       TEvents;
  Typed:    TTypedCollector;

begin
  Started  := GetTickCount64;
  Model    := StrToIntDef(ArgValue('model', '1'), 1);
  Port     := ArgValue('port', '');
  Policy   := ArgValue('policy', 'default');
  Commands := StrToIntDef(ArgValue('commands', '5'), 5);
  Budget   := StrToIntDef(ArgValue('budget-ms', '20000'), 20000);

  { A pause between commands, so a scenario that breaks the link part
    way through has a session long enough to break. Without it the
    whole run finished in 0.2 s and the fault injection never
    overlapped it.
    コマンド間の休止。回線を途中で壊すシナリオが、壊すだけの長さの
    セッションを持てるようにします。これがないと全体が 0.2 秒で終わり、
    障害注入が重ならないままでした。 }
  Gap      := StrToIntDef(ArgValue('gap-ms', '0'), 0);

  Emit('MODEL',  IntToStr(Model));
  Emit('PORT',   Port);
  Emit('POLICY', Policy);

  Col     := TCollector.Create;
  Ev      := TEvents.Create;
  Typed   := TTypedCollector.Create;
  Factory := TRigServiceFactory.Create;
  Opened  := False;
  try
    Svc := Factory.CreateService;
    Svc.ApplyTimeoutPolicy(PolicyByName(Policy));
    Svc.SetOnConnectionChanged(@Ev.OnConnection);
    Svc.SetOnError(@Ev.OnError);

    { ---- open / 接続 ---- }
    try
      Svc.Open(Model, Port);
      Opened := Svc.IsOpen;
      Emit('OPEN', 'ok');
    except
      on E: ERigError do
        Emit('OPEN', Format('fail kind=%s native=%d msg=%s',
                            [RigErrorKindToString(E.Kind), E.Code,
                             StringReplace(E.Message, LineEnding, ' ',
                                           [rfReplaceAll])]));
      on E: Exception do
        Emit('OPEN', 'fail kind=exception msg=' +
                     StringReplace(E.Message, LineEnding, ' ',
                                   [rfReplaceAll]));
    end;
    EmitElapsed('OPEN_MS');

    { Give the worker a moment to make the connection attempt and
      report it, since Open does not wait for it.
      Open は待たないため、ワーカーが接続を試み報告する時間を与えます。 }
    for i := 1 to 200 do
    begin
      CheckSynchronize(5);
      Sleep(5);
      if (Ev.Connects > 0) or (Ev.Disconnects > 0) then Break;
    end;
    Emit('CONNECT_EVENT',
         Format('connects=%d disconnects=%d', [Ev.Connects, Ev.Disconnects]));

    if Opened then
    begin
      Emit('LIBVERSION', Svc.LibraryStatus.VersionText);

      { ---- a read, which is where a silent rig shows up ----
        ---- 読み取り。沈黙するリグが姿を現すのはここです ---- }
      for i := 1 to Commands do
      begin
        Col.Reset;
        Svc.GetFrequencyAsync(rvfoCurr, @Col.OnFreq);
        WaitFor(Col, Budget);
        if (Col.Got) and (Col.Status = rcsSuccess) then
          Emit(Format('GETFREQ%d', [i]),
               Format('ok value=%.0f', [Col.Freq]))
        else
          Emit(Format('GETFREQ%d', [i]), Describe(Col));
        Emit(Format('BREAKER%d', [i]),
             BoolToStr(Svc.CircuitBreakerOpen, 'open', 'closed'));
        if Gap > 0 then
        begin
          Deadline := GetTickCount64 + QWord(Gap);
          while GetTickCount64 < Deadline do
          begin
            CheckSynchronize(5);
            Sleep(5);
          end;
        end;
      end;

      { ---- a write ---- }
      Col.Reset;
      Svc.SetFrequencyAsync(TEST_FREQ, rvfoCurr, @Col.OnResult);
      WaitFor(Col, Budget);
      Emit('SETFREQ', Describe(Col));

      { ---- read it back: proves the write reached the other end ----
        ---- 読み戻し。書き込みが相手に届いたことを示します ---- }
      Col.Reset;
      Svc.GetFrequencyAsync(rvfoCurr, @Col.OnFreq);
      WaitFor(Col, Budget);
      if Col.Got and (Col.Status = rcsSuccess) then
        Emit('READBACK', Format('ok value=%.0f', [Col.Freq]))
      else
        Emit('READBACK', Describe(Col));

      { ---- mode, split and a level: a real backend may refuse any of
             these, and refusing is a legitimate answer ----
        ---- モード、スプリット、レベル。実バックエンドはいずれも拒否
             しえます。拒否も正当な答えです ---- }
      Col.Reset;
      Svc.SetModeAsync(rmUSB, 0, rvfoCurr, @Col.OnResult);
      WaitFor(Col, Budget);
      Emit('SETMODE', Describe(Col));

      Col.Reset;
      Svc.SetSplitAsync(True, rvfoB, @Col.OnResult);
      WaitFor(Col, Budget);
      Emit('SETSPLIT', Describe(Col));

      Col.Reset;
      Svc.SetSplitAsync(False, rvfoCurr, @Col.OnResult);
      WaitFor(Col, Budget);
      Emit('CLEARSPLIT', Describe(Col));

      { The four Rev.6.0 result shapes, each issued once. Whatever the
        link is doing, each must report exactly once — a shape that
        stays silent leaves an application waiting forever.
        Rev.6.0 の 4 つの結果の形を 1 回ずつ発行します。回線が何をして
        いようと、各々ちょうど 1 回報告しなければなりません。黙って
        いる形は、アプリケーションを永久に待たせます。 }
      Svc.GetLevelAsync(rlvStrength, @Typed.OnLevel);
      Svc.GetFuncAsync(rfnNoiseBlanker, @Typed.OnFunc);
      Svc.GetSplitAsync(@Typed.OnSplit);
      Svc.GetVfoAsync(@Typed.OnVfo);

      Deadline := GetTickCount64 + QWord(Budget);
      while (Typed.Total < 4) and (GetTickCount64 < Deadline) do
      begin
        CheckSynchronize(5);
        Sleep(5);
      end;
      Emit('TYPED_SHAPES',
           Format('level=%d func=%d split=%d vfo=%d',
                  [Typed.Level, Typed.Func, Typed.Split, Typed.Vfo]));

      Emit('QUEUE', IntToStr(Svc.QueueDepth));
      Emit('EVENTS', Format('connects=%d disconnects=%d errors=%d',
                            [Ev.Connects, Ev.Disconnects, Ev.Errors]));
      if Ev.Errors > 0 then
        Emit('FIRST_ERROR',
             Format('kind=%s native=%d msg=%s',
                    [RigErrorKindToString(Ev.FirstKind), Ev.FirstNative,
                     Ev.FirstMsg]));
      Emit('BREAKER_FINAL',
           BoolToStr(Svc.CircuitBreakerOpen, 'open', 'closed'));

      Svc.CancelAllPending;
      Svc.Close;
      Emit('CLOSE', BoolToStr(not Svc.IsOpen, 'ok', 'still-open'));
    end;
  finally
    if Assigned(Svc) then
    begin
      Svc.SetOnConnectionChanged(nil);
      Svc.SetOnError(nil);
    end;
    Svc := nil;
    Factory := nil;
    Col.Free;
    Ev.Free;
    Typed.Free;
  end;

  EmitElapsed('TOTAL_MS');
  Emit('VERDICT', 'completed');
  ExitCode := 0;
end.
