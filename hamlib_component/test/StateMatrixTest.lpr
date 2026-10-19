{
  StateMatrixTest.lpr

  Calls every public IRigService method in every lifecycle state, and
  with every class of bad argument, and insists each call fails in a
  defined way.

  公開 IRigService の全メソッドを、全ライフサイクル状態で、かつあらゆる
  種類の不正引数で呼び出し、各呼び出しが「定義された形で」失敗すること
  を要求します。

  The property / 検査する性質
  ------------------------------------------------------------------
  For every (method, state, argument) triple, exactly one of these
  must happen:

    - it succeeds, or
    - it raises an exception of a class the README names, or
    - it returns a result whose Status is not rcsSuccess.

  What must NOT happen is the fourth outcome: the call returns
  normally, reports nothing, and does nothing. A silent no-op is the
  worst failure mode an API has, because the caller's next line
  assumes it worked.

  (メソッド, 状態, 引数) の各組について、次のいずれか「ちょうど 1 つ」が
  起きなければなりません。

    - 成功する
    - README が挙げるクラスの例外を送出する
    - Status が rcsSuccess でない結果を返す

  起きてはならないのは 4 番目の帰結です。呼び出しが正常に戻り、何も報告
  せず、何もしない。沈黙する no-op は API の最悪の失敗様式です。呼び出し
  側の次の行が「成功した」前提で書かれているからです。

  Why the existing MisuseTest is not enough
  既存の MisuseTest では足りない理由
  ------------------------------------------------------------------
  MisuseTest predates Rev.6.0 and covers the frequency/mode/PTT
  surface. Rev.6.0 added twelve methods, each with its own argument
  validation, and none of them had been called in the not-open or
  after-close states.

  MisuseTest は Rev.6.0 より前のもので、周波数・モード・PTT の面を
  覆います。Rev.6.0 はメソッドを 12 個増やし、各々が独自の引数検証を
  持ちますが、いずれも「未接続」「切断後」の状態では一度も呼ばれて
  いませんでした。

  Build:
    fpc -Mobjfpc -Sh -Sa -Criot -gh -Fu../src -FE. StateMatrixTest.lpr
}
program StateMatrixTest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  HamlibInterfaces, HamlibErrors, HamlibTimeoutPolicy,
  HamlibService, HamlibFactory;

const
  MODEL_DUMMY = 1;

var
  Passed: Integer = 0;
  Failed: Integer = 0;
  Svc:    IRigService;

procedure Check(const ALabel: string; ACondition: Boolean;
                const ADetail: string = '');
begin
  if ACondition then
    Inc(Passed)
  else
  begin
    Inc(Failed);
    if ADetail <> '' then
      WriteLn('    [FAIL] ', ALabel, '  <-- ', ADetail)
    else
      WriteLn('    [FAIL] ', ALabel);
  end;
end;

procedure Pump(AMs: Integer);
var
  i: Integer;
begin
  for i := 1 to AMs div 10 do
  begin
    CheckSynchronize(5);
    Sleep(5);
  end;
end;

{ ------------------------------------------------------------------
  One call, described by a closure-free method pointer. FPC 3.2.2 has
  no anonymous methods, so each call under test is a plain procedure
  and the harness invokes it by pointer.

  コールバックを持たないメソッドポインタで記述した 1 呼び出し。
  FPC 3.2.2 に匿名メソッドはないため、検査対象の各呼び出しは通常の
  手続きとし、ハーネスはポインタ経由で起動します。
  ------------------------------------------------------------------ }
type
  TCallProc = procedure;

{ Runs ACall and reports which of the three permitted outcomes
  happened. AMustRaise says whether an exception is the REQUIRED
  outcome in this state.
  ACall を実行し、許された 3 つの帰結のどれが起きたかを報告します。
  AMustRaise は、この状態で例外が「必須の」帰結かどうかを示します。 }
procedure Expect(const AWhat: string; ACall: TCallProc;
                 AMustRaise: Boolean);
var
  Raised: Boolean;
  Msg:    string;
begin
  Raised := False;
  Msg    := '';
  try
    ACall();
  except
    on E: ERigServiceClosed do begin Raised := True; Msg := 'ERigServiceClosed'; end;
    on E: ERigServiceOpen   do begin Raised := True; Msg := 'ERigServiceOpen'; end;
    on E: EArgumentException do begin Raised := True; Msg := 'EArgumentException'; end;
    on E: ERigError          do begin Raised := True; Msg := 'ERigError'; end;
    on E: ERigModelUnknown   do begin Raised := True; Msg := 'ERigModelUnknown'; end;
    on E: EHamlibUnsupportedVersion do begin Raised := True; Msg := 'EHamlibUnsupportedVersion'; end;
    on E: Exception do
    begin
      { An exception outside the documented set is a defect even when
        the call "failed correctly": the application cannot catch what
        it was not told about.
        文書化された集合の外の例外は、たとえ呼び出しが「正しく失敗」
        していても欠陥です。アプリケーションは、知らされていないもの
        を捕捉できません。 }
      Inc(Failed);
      WriteLn('    [FAIL] ', AWhat, '  <-- undocumented exception ',
              E.ClassName, ': ', E.Message);
      Exit;
    end;
  end;

  if AMustRaise then
    Check(AWhat + ' is refused', Raised,
          'the call returned normally and did nothing')
  else
    Check(AWhat + ' is accepted', not Raised, Msg);
end;

{ ------------------------------------------------------------------
  The calls under test. One procedure per call so Expect can take a
  pointer to it.
  検査対象の呼び出し。Expect がポインタを取れるよう 1 呼び出し 1 手続き。
  ------------------------------------------------------------------ }

procedure C_GetLevel;      begin Svc.GetLevelAsync(rlvStrength); end;
procedure C_SetLevelFloat; begin Svc.SetLevelFloatAsync(rlvRfPower, 0.5); end;
procedure C_SetLevelInt;   begin Svc.SetLevelIntAsync(rlvKeySpeed, 20); end;
procedure C_GetFunc;       begin Svc.GetFuncAsync(rfnNoiseBlanker); end;
procedure C_SetFunc;       begin Svc.SetFuncAsync(rfnNoiseBlanker, True); end;
procedure C_SetSplit;      begin Svc.SetSplitAsync(True, rvfoB); end;
procedure C_GetSplit;      begin Svc.GetSplitAsync; end;
procedure C_SetSplitFreq;  begin Svc.SetSplitFreqAsync(14205000); end;
procedure C_SetVfo;        begin Svc.SetVfoAsync(rvfoA); end;
procedure C_GetVfo;        begin Svc.GetVfoAsync; end;
procedure C_VfoOp;         begin Svc.VfoOpAsync(rvoToggle); end;
procedure C_SetFreq;       begin Svc.SetFrequencyAsync(14200000); end;
procedure C_GetFreq;       begin Svc.GetFrequencyAsync; end;
procedure C_SetMode;       begin Svc.SetModeAsync(rmUSB); end;
procedure C_GetMode;       begin Svc.GetModeAsync; end;
procedure C_SetPtt;        begin Svc.SetPttAsync(rpttOff); end;

{ ---- calls that must be refused by ARGUMENT, in any state ----
  ---- 状態によらず「引数によって」拒否されるべき呼び出し ---- }
procedure A_LevelNone;     begin Svc.GetLevelAsync(rlvNone); end;
procedure A_SetLevelNone;  begin Svc.SetLevelFloatAsync(rlvNone, 0.5); end;
procedure A_SetMeter;      begin Svc.SetLevelFloatAsync(rlvStrength, 0.5); end;
procedure A_FloatAsInt;    begin Svc.SetLevelIntAsync(rlvRfPower, 1); end;
procedure A_IntAsFloat;    begin Svc.SetLevelFloatAsync(rlvKeySpeed, 0.5); end;
procedure A_FuncNone;      begin Svc.SetFuncAsync(rfnNone, True); end;
procedure A_GetFuncNone;   begin Svc.GetFuncAsync(rfnNone); end;
procedure A_VfoOpNone;     begin Svc.VfoOpAsync(rvoNone); end;
procedure A_SetVfoCurr;    begin Svc.SetVfoAsync(rvfoCurr); end;
procedure A_SplitOnCurr;   begin Svc.SetSplitAsync(True, rvfoCurr); end;
procedure A_SplitOnDefault; begin Svc.SetSplitAsync(True); end;
procedure A_NegSplitFreq;  begin Svc.SetSplitFreqAsync(-1); end;
procedure A_ZeroSplitFreq; begin Svc.SetSplitFreqAsync(0); end;
procedure A_NegFreq;       begin Svc.SetFrequencyAsync(-1); end;
procedure A_ModeUnknown;   begin Svc.SetModeAsync(rmUnknown); end;
procedure A_NegPassband;   begin Svc.SetModeAsync(rmUSB, -1); end;
procedure A_ConfAfterOpen; begin Svc.AddConfToken('ptt_type', 'RIG'); end;
procedure A_EmptyConfName; begin Svc.AddConfToken('', 'RIG'); end;

{ ------------------------------------------------------------------
  The matrix / マトリクス
  ------------------------------------------------------------------ }

procedure RunAllCommands(const AState: string; AMustRaise: Boolean);
begin
  WriteLn;
  WriteLn('STATE: ', AState,
          '  — every command must ',
          specialize IfThen<string>(AMustRaise, 'be refused', 'be accepted'));

  Expect('GetLevelAsync',      @C_GetLevel,      AMustRaise);
  Expect('SetLevelFloatAsync', @C_SetLevelFloat, AMustRaise);
  Expect('SetLevelIntAsync',   @C_SetLevelInt,   AMustRaise);
  Expect('GetFuncAsync',       @C_GetFunc,       AMustRaise);
  Expect('SetFuncAsync',       @C_SetFunc,       AMustRaise);
  Expect('SetSplitAsync',      @C_SetSplit,      AMustRaise);
  Expect('GetSplitAsync',      @C_GetSplit,      AMustRaise);
  Expect('SetSplitFreqAsync',  @C_SetSplitFreq,  AMustRaise);
  Expect('SetVfoAsync',        @C_SetVfo,        AMustRaise);
  Expect('GetVfoAsync',        @C_GetVfo,        AMustRaise);
  Expect('VfoOpAsync',         @C_VfoOp,         AMustRaise);
  Expect('SetFrequencyAsync',  @C_SetFreq,       AMustRaise);
  Expect('GetFrequencyAsync',  @C_GetFreq,       AMustRaise);
  Expect('SetModeAsync',       @C_SetMode,       AMustRaise);
  Expect('GetModeAsync',       @C_GetMode,       AMustRaise);
  Expect('SetPttAsync',        @C_SetPtt,        AMustRaise);
end;

procedure RunBadArguments;
begin
  WriteLn;
  WriteLn('ARGUMENTS — every one of these must be refused, while open');

  Expect('a level of rlvNone',                @A_LevelNone,     True);
  Expect('setting a level of rlvNone',        @A_SetLevelNone,  True);
  Expect('setting a meter (read-only level)', @A_SetMeter,      True);
  Expect('a float level set as an integer',   @A_FloatAsInt,    True);
  Expect('an integer level set as a float',   @A_IntAsFloat,    True);
  Expect('a function of rfnNone',             @A_FuncNone,      True);
  Expect('reading a function of rfnNone',     @A_GetFuncNone,   True);
  Expect('a VFO op of rvoNone',               @A_VfoOpNone,     True);
  Expect('selecting "the current VFO"',       @A_SetVfoCurr,    True);

  { Found by the differential test against rigctld: splitting onto "the
    current VFO" means transmitting on the receive frequency, and
    rvfoCurr is this parameter's DEFAULT, so the shortest form of the
    call was the dangerous one.
    rigctld との差分テストで発見。「現在の VFO」へスプリットすることは
    受信周波数で送信することを意味し、しかも rvfoCurr はこの引数の
    「既定値」でした。最短形の呼び出しこそが危険だったのです。 }
  Expect('splitting onto "the current VFO"',  @A_SplitOnCurr,   True);
  Expect('SetSplitAsync(True) with no TX VFO at all',
                                              @A_SplitOnDefault, True);
  Expect('a negative split frequency',        @A_NegSplitFreq,  True);
  Expect('a zero split frequency',            @A_ZeroSplitFreq, True);
  Expect('a negative frequency',              @A_NegFreq,       True);
  Expect('a mode of rmUnknown',               @A_ModeUnknown,   True);
  Expect('a negative passband',               @A_NegPassband,   True);
  Expect('a conf token after Open',           @A_ConfAfterOpen, True);
end;

{ ------------------------------------------------------------------
  Non-command methods, which have their own rules
  コマンド以外のメソッド。独自の規則を持ちます
  ------------------------------------------------------------------ }
procedure RunQueryMethods(const AState: string; AOpen: Boolean);
var
  St:   TRigState;
  Caps: TRigCapabilities;
  Pol:  TRigTimeoutPolicy;
  Lib:  TRigLibraryStatus;
begin
  WriteLn;
  WriteLn('QUERIES in state: ', AState,
          '  — these must answer, never raise');

  { A query that raised when the rig is closed would force every UI
    refresh to sit inside a try/except. These must always answer.
    リグが閉じているときに例外を出す問い合わせは、UI の更新をすべて
    try/except の中に押し込めます。これらは常に答えなければなりません。 }
  try
    St := Svc.CurrentState;
    Check('CurrentState answers', True);
    Check('and agrees with IsOpen about being connected',
          St.Connected = AOpen,
          Format('Connected=%s IsOpen=%s',
                 [BoolToStr(St.Connected, True), BoolToStr(AOpen, True)]));
  except
    on E: Exception do
      Check('CurrentState answers', False, E.ClassName);
  end;

  try
    Caps := Svc.GetCapabilities;
    Check('GetCapabilities answers', True);
    if not AOpen then
      Check('and reports nothing known while closed', not Caps.Known,
            'capabilities survived a Close');
  except
    on E: Exception do
      Check('GetCapabilities answers', False, E.ClassName);
  end;

  try
    Pol := Svc.GetCurrentPolicy;
    Check('GetCurrentPolicy answers', Pol.CommandTimeoutMs > 0,
          Format('%d ms', [Pol.CommandTimeoutMs]));
  except
    on E: Exception do
      Check('GetCurrentPolicy answers', False, E.ClassName);
  end;

  try
    Lib := Svc.LibraryStatus;
    Check('LibraryStatus answers', True);
    if AOpen then
      Check('and names the library once open', Lib.VersionText <> '',
            'empty VersionText while open');
  except
    on E: Exception do
      Check('LibraryStatus answers', False, E.ClassName);
  end;

  try
    Check('QueueDepth is never negative', Svc.QueueDepth >= 0,
          Format('%d', [Svc.QueueDepth]));
    Svc.GetCircuitBreakerOpen;
    Check('CircuitBreakerOpen answers', True);
    Check('IsOpen agrees with the state under test', Svc.IsOpen = AOpen);
  except
    on E: Exception do
      Check('the cheap queries answer', False, E.ClassName);
  end;

  { Idempotence. Calling these twice, or when they have nothing to do,
    is what an application does on a close button pressed twice.
    冪等性。これらを 2 度呼ぶこと、何もすることがないときに呼ぶことは、
    閉じるボタンを 2 回押したアプリケーションがすることです。 }
  try
    Svc.CancelAllPending;
    Svc.CancelAllPending;
    Svc.DisablePolling;
    Svc.DisablePolling;
    Check('CancelAllPending and DisablePolling are idempotent', True);
  except
    on E: Exception do
      Check('CancelAllPending and DisablePolling are idempotent',
            False, E.ClassName);
  end;
end;

{ ------------------------------------------------------------------
  Main
  ------------------------------------------------------------------ }
var
  Factory: IRigServiceFactory;
  Threw:   Boolean;

begin
  WriteLn('StateMatrixTest — every method, every state, every bad argument');
  WriteLn('===============================================================');

  Factory := TRigServiceFactory.Create;
  Svc     := Factory.CreateService;

  { ---- state 1: created, never opened ---- }
  RunQueryMethods('created, never opened', False);
  RunAllCommands('created, never opened', True);

  { A conf token BEFORE Open is the one thing that must be accepted
    here and refused later — the mirror image of every other call.
    Open 前の conf トークンは、ここでは受理され後で拒否されねばならない
    唯一のものです。他のすべての呼び出しと鏡像の関係にあります。 }
  Threw := False;
  try
    Svc.AddConfToken('ptt_type', 'RIG');
  except
    on E: Exception do Threw := True;
  end;
  Check('AddConfToken is accepted before Open', not Threw);

  Threw := False;
  try
    Svc.AddConfToken('', 'RIG');
  except
    on E: EArgumentException do Threw := True;
  end;
  Check('but an empty token name is refused', Threw);

  { ---- state 2: open ---- }
  Svc.ApplyTimeoutPolicy(RigPolicy_FastUsb);
  Svc.Open(MODEL_DUMMY, '');
  Check('the dummy rig opened', Svc.IsOpen);
  Pump(200);

  RunQueryMethods('open', True);
  RunAllCommands('open', False);
  Pump(600);
  RunBadArguments;

  { Opening twice must be refused, not silently ignored: the second
    Open's arguments would otherwise be thrown away without a word.
    2 度目の Open は黙殺ではなく拒否されねばなりません。さもないと
    2 度目の引数が一言もなく捨てられます。 }
  Threw := False;
  try
    Svc.Open(MODEL_DUMMY, '');
  except
    on E: ERigServiceOpen do Threw := True;
    on E: Exception do Threw := True;
  end;
  Check('a second Open while open is refused', Threw);

  { ---- state 3: after Close ---- }
  Svc.Close;
  Pump(300);
  Check('the rig closed', not Svc.IsOpen);

  RunQueryMethods('after Close', False);
  RunAllCommands('after Close', True);

  { Close twice. An application whose error handler calls Close, from
    inside a handler reached because Close failed, does this.
    Close を 2 度。Close が失敗したために到達したハンドラの中から
    Close を呼ぶアプリケーションがこれをします。 }
  Threw := False;
  try
    Svc.Close;
  except
    on E: Exception do Threw := True;
  end;
  Check('a second Close is harmless', not Threw);

  { ---- state 4: reopened ---- }
  Svc.Open(MODEL_DUMMY, '');
  Check('the service can be reopened after a Close', Svc.IsOpen);
  Pump(200);
  RunAllCommands('reopened', False);
  Pump(600);
  Svc.Close;

  Svc     := nil;
  Factory := nil;

  WriteLn;
  WriteLn(Format('--- %d / %d checks passed ---',
                 [Passed, Passed + Failed]));
  if Failed = 0 then
  begin
    WriteLn('RESULT: OK');
    ExitCode := 0;
  end
  else
  begin
    WriteLn(Format('RESULT: %d FAILED', [Failed]));
    ExitCode := 1;
  end;
end.
