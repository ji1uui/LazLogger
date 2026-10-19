{
  FeatureMatrixTest.lpr

  Exercises every operation added in Rev.6.0 against the REAL Hamlib
  library, using Hamlib's built-in dummy rig so no hardware is needed.

  Rev.6.0 で追加した全操作を、実 Hamlib ライブラリに対して動かします。
  Hamlib 内蔵のダミーリグを使うためハードウェアは不要です。

  Why this test is the important one / 本テストが重要な理由
  ------------------------------------------------------------------
  rig_get_level and rig_set_level carry a value_t, which is a C UNION
  passed BY VALUE. Getting its layout or its calling convention wrong
  does not fail to compile and does not crash — it reads the S-meter
  out of the wrong half of a register pair and returns a number that
  looks like a signal report. No fake loader can catch that, because a
  fake returns whatever the person who wrote it decided to return.

  rig_get_level / rig_set_level は value_t を運びます。これは C の
  「共用体」であり「値渡し」です。そのレイアウトや呼び出し規約を誤っても
  コンパイルは通り、クラッシュもしません。レジスタ対の誤った側から
  S メータを読み、信号強度らしく見える数値を返すだけです。フェイク
  ローダではこれを捕まえられません。フェイクは、それを書いた人が返すと
  決めた値を返すだけだからです。

  The method is round-tripping: set a value the rig cannot have had by
  accident, read it back, and require the same number. A wrong union
  layout cannot survive that.

  手法は往復検査です。偶然そうなるはずのない値を設定し、読み戻し、同じ
  数値を要求します。共用体のレイアウトが誤っていれば生き延びられません。

  Build: fpc -Mobjfpc -Sh -Fu../src -FE. FeatureMatrixTest.lpr
  Skips cleanly (exit 0) when Hamlib is not installed.
}
program FeatureMatrixTest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  HamlibInterfaces, HamlibErrors, HamlibLoader, HamlibLevelCodec,
  HamlibModeCodec, HamlibVfoCodec, HamlibTimeoutPolicy, HamlibService,
  HamlibFactory;

const
  MODEL_DUMMY = 1;

var
  Checks:   Integer = 0;
  Failures: Integer = 0;

procedure Check(const ALabel: string; ACondition: Boolean;
                const ADetail: string = '');
begin
  Inc(Checks);
  if ACondition then
    WriteLn('    [ok]   ', ALabel)
  else
  begin
    Inc(Failures);
    if ADetail <> '' then
      WriteLn('    [FAIL] ', ALabel, '  --> ', ADetail)
    else
      WriteLn('    [FAIL] ', ALabel);
  end;
end;

type
  THarness = class
    GotLevel:  Boolean;
    GotFunc:   Boolean;
    GotSplit:  Boolean;
    GotVfo:    Boolean;
    GotSet:    Boolean;
    Level:     TRigLevelResult;
    Func:      TRigFuncResult;
    Split:     TRigSplitResult;
    Vfo:       TRigVfoResult;
    SetResult: TRigResult;
    LastError: string;
    procedure OnLevel(const R: TRigLevelResult);
    procedure OnFunc(const R: TRigFuncResult);
    procedure OnSplit(const R: TRigSplitResult);
    procedure OnVfo(const R: TRigVfoResult);
    procedure OnSet(const R: TRigResult);
    procedure OnErr(Sender: TObject; AKind: TRigErrorKind;
                    ANativeCode: Integer; const AMsg: string);
    procedure Reset;
  end;

procedure THarness.OnLevel(const R: TRigLevelResult);
begin GotLevel := True; Level := R; end;
procedure THarness.OnFunc(const R: TRigFuncResult);
begin GotFunc := True; Func := R; end;
procedure THarness.OnSplit(const R: TRigSplitResult);
begin GotSplit := True; Split := R; end;
procedure THarness.OnVfo(const R: TRigVfoResult);
begin GotVfo := True; Vfo := R; end;
procedure THarness.OnSet(const R: TRigResult);
begin GotSet := True; SetResult := R; end;
procedure THarness.OnErr(Sender: TObject; AKind: TRigErrorKind;
                          ANativeCode: Integer; const AMsg: string);
begin
  LastError := Format('%s [%s]', [AMsg, RigErrorKindToString(AKind)]);
end;
procedure THarness.Reset;
begin
  GotLevel := False; GotFunc := False; GotSplit := False;
  GotVfo := False;   GotSet := False;  LastError := '';
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

{ Run one command and wait for its result, so each check reads as one
  statement instead of five.
  コマンドを 1 つ実行して結果を待ちます。各検査が 5 行ではなく 1 文で
  読めるようにするためです。 }

var
  Svc:     IRigService;
  Factory: IRigServiceFactory;
  H:       THarness;
  Caps:    TRigCapabilities;
  Loader:  IHamlibLoader;
  Probe:   IHamlibRigControl;
  Ok:      Boolean;
  S:       TRigState;

begin
  WriteLn('=== Rev.6.0 feature matrix against the real Hamlib ===');
  WriteLn;

  { ---- is Hamlib here at all? ---- }
  Loader := THamlibLoader.Create;
  if not Loader.Load then
  begin
    WriteLn('Hamlib is not installed — skipping.');
    WriteLn('RESULT: SKIPPED (no Hamlib)');
    Halt(0);
  end;
  WriteLn('Library : ', Loader.LibPath, '  (API ', Loader.ApiMajor, '.',
          Loader.ApiMinor, ')');

  Check('the loader offers the extended control role',
        Supports(Loader, IHamlibRigControl, Probe));
  Loader := nil;
  Probe  := nil;
  WriteLn;

  H       := THarness.Create;
  Factory := TRigServiceFactory.Create;
  Svc     := Factory.CreateServiceWithPolicy(RigPolicy_Default);
  try
    Svc.SetOnError(@H.OnErr);

    { ---- conf tokens, before Open ----
      The dummy rig has no PTT port, which is why Rev.5.1's PTT test
      had to settle for checking the refusal. ptt_type=RIG is exactly
      the setting an application needs for a real rig, so this is both
      a test of AddConfToken and the fix for that limitation.

      ダミーリグには PTT ポートがなく、Rev.5.1 の PTT テストが拒否の
      確認で妥協したのはそのためです。ptt_type=RIG は実機でアプリが
      必要とする設定そのものであり、本検査は AddConfToken の検証であると
      同時にその制限の解消でもあります。 }
    Svc.AddConfToken('ptt_type', 'RIG');

    Ok := False;
    try
      Svc.AddConfToken('', 'x');
    except
      on E: EArgumentException do Ok := True;
    end;
    Check('an empty conf token name is rejected', Ok);

    Svc.Open(MODEL_DUMMY, '');
    Pump(600);
    Check('the rig opened with an application conf token applied',
          Svc.IsOpen, H.LastError);

    Ok := False;
    try
      Svc.AddConfToken('ptt_type', 'RIG');
    except
      on E: ERigServiceOpen do Ok := True;
    end;
    Check('adding a conf token after Open is refused', Ok);
    WriteLn;

    { ---- capabilities ---- }
    WriteLn('CAPABILITIES — what the library says this rig can do');
    Caps := Svc.GetCapabilities;
    WriteLn('    known=', Caps.Known, ' targetable_vfo=', Caps.TargetableVfo,
            ' ptt_type=', Caps.PttType, ' has_ptt=', Caps.HasPtt);
    WriteLn('    get-levels: ', THamlibLevelCodec.ToDisplayString(rlvStrength),
            '=', rlvStrength in Caps.GetLevels,
            ', ', THamlibLevelCodec.ToDisplayString(rlvRfPower),
            '=', rlvRfPower in Caps.GetLevels);
    Check('rig_get_caps_int answered', Caps.Known);
    Check('the dummy rig reports the S-meter among its levels',
          rlvStrength in Caps.GetLevels);
    { rig_get_caps_int reports the MODEL's static ptt_type, which stays
      0 for the dummy rig however it is configured. HasPtt is the
      answer to "can this rig key as configured", so it must be True
      because the application supplied ptt_type=RIG.

      rig_get_caps_int が報告するのは機種の静的な ptt_type で、ダミー
      リグではどう設定しても 0 のままです。HasPtt は「設定された状態で
      送信できるか」への答えなので、アプリが ptt_type=RIG を与えた以上
      True でなければなりません。 }
    Check('the model''s static ptt_type is still RIG_PTT_NONE',
          Caps.PttType = 0, Format('%d', [Caps.PttType]));
    Check('but HasPtt follows the conf token the application supplied',
          Caps.HasPtt);
    WriteLn;

    { ================================================================
      LEVELS — the value_t union, round-tripped
      ================================================================ }
    WriteLn('LEVELS — value_t carried by value, checked by round trip');

    { An int level. Keyer speed is in WPM and 27 is not a default
      anywhere, so reading 27 back cannot be a coincidence.
      int のレベル。キーヤ速度は WPM で、27 はどこの既定値でもないため、
      27 が読み戻せたなら偶然ではありません。 }
    H.Reset;
    Svc.SetLevelIntAsync(rlvKeySpeed, 27, @H.OnSet);
    Pump(500);
    Check('an int level was accepted (keyer speed 27 WPM)',
          H.GotSet and (H.SetResult.Status = rcsSuccess),
          H.SetResult.ErrorMsg);

    H.Reset;
    Svc.GetLevelAsync(rlvKeySpeed, @H.OnLevel);
    Pump(500);
    WriteLn('    keyer speed read back: ', H.Level.IntValue,
            ' (is_float=', H.Level.IsFloat, ')');
    Check('INT round trip: value_t.i survives the call',
          H.GotLevel and (not H.Level.IsFloat) and (H.Level.IntValue = 27),
          Format('got %d', [H.Level.IntValue]));

    { A float level. 0.42 is not a round number and not a default.
      float のレベル。0.42 は切りのよい数でも既定値でもありません。 }
    H.Reset;
    Svc.SetLevelFloatAsync(rlvRfPower, 0.42, @H.OnSet);
    Pump(500);
    Check('a float level was accepted (RF power 0.42)',
          H.GotSet and (H.SetResult.Status = rcsSuccess),
          H.SetResult.ErrorMsg);

    H.Reset;
    Svc.GetLevelAsync(rlvRfPower, @H.OnLevel);
    Pump(500);
    WriteLn('    RF power read back: ', FormatFloat('0.000', H.Level.FloatValue),
            ' (is_float=', H.Level.IsFloat, ')');
    Check('FLOAT round trip: value_t.f survives the call',
          H.GotLevel and H.Level.IsFloat
          and (Abs(H.Level.FloatValue - 0.42) < 0.001),
          Format('got %.4f', [H.Level.FloatValue]));

    { The S-meter. The dummy rig returns a fixed value; what matters is
      that it is a plausible dB figure and not a reinterpreted float.
      A float 0.42 read as an int is 1051260355, which is exactly the
      failure this check exists to catch.

      S メータ。ダミーリグは固定値を返します。重要なのは、それが
      もっともらしい dB 値であり、float を読み替えた値ではないことです。
      float の 0.42 を int として読むと 1051260355 になります。本検査は
      まさにその失敗を捕まえるために存在します。 }
    H.Reset;
    Svc.GetLevelAsync(rlvStrength, @H.OnLevel);
    Pump(500);
    WriteLn('    S-meter: ', H.Level.IntValue, ' dB relative to S9');
    Check('the S-meter reads as a plausible dB figure',
          H.GotLevel and (H.Level.Status = rcsSuccess)
          and (H.Level.IntValue > -200) and (H.Level.IntValue < 100),
          Format('%d — a float reinterpreted as an int lands in the '
                 + 'hundreds of millions', [H.Level.IntValue]));
    Check('and it reached the Pull-model snapshot',
          Svc.CurrentState.HasStrength
          and (Svc.CurrentState.StrengthDb = H.Level.IntValue),
          Format('snapshot %d', [Svc.CurrentState.StrengthDb]));

    { Meters cannot be set, and that is a programming error rather than
      a rig limitation, so it must not cost a round trip.
      メータは設定できません。これはリグの制限ではなくプログラミングの
      誤りなので、往復 1 回を費やしてはなりません。 }
    Ok := False;
    try
      Svc.SetLevelFloatAsync(rlvStrength, 1.0);
    except
      on E: EArgumentException do Ok := True;
    end;
    Check('setting the S-meter is refused without asking the rig', Ok);

    Ok := False;
    try
      Svc.SetLevelIntAsync(rlvRfPower, 1);
    except
      on E: EArgumentException do Ok := True;
    end;
    Check('using the int setter on a float level is refused', Ok);

    Ok := False;
    try
      Svc.SetLevelFloatAsync(rlvKeySpeed, 1.0);
    except
      on E: EArgumentException do Ok := True;
    end;
    Check('using the float setter on an int level is refused', Ok);
    WriteLn;

    { ================================================================
      FUNCTIONS
      ================================================================ }
    WriteLn('FUNCTIONS — on/off settings');
    H.Reset;
    Svc.SetFuncAsync(rfnNoiseBlanker, True, @H.OnSet);
    Pump(500);
    Check('a function was switched on',
          H.GotSet and (H.SetResult.Status = rcsSuccess),
          H.SetResult.ErrorMsg);

    H.Reset;
    Svc.GetFuncAsync(rfnNoiseBlanker, @H.OnFunc);
    Pump(500);
    Check('and reads back as on',
          H.GotFunc and (H.Func.Status = rcsSuccess) and H.Func.Active,
          H.Func.ErrorMsg);

    H.Reset;
    Svc.SetFuncAsync(rfnNoiseBlanker, False, @H.OnSet);
    Pump(400);
    H.Reset;
    Svc.GetFuncAsync(rfnNoiseBlanker, @H.OnFunc);
    Pump(400);
    Check('and off again', H.GotFunc and (not H.Func.Active));
    WriteLn;

    { ================================================================
      VFO SELECTION
      ================================================================ }
    WriteLn('VFO — selection and read-back');
    H.Reset;
    Svc.SetVfoAsync(rvfoB, @H.OnSet);
    Pump(500);
    Check('VFO B was selected',
          H.GotSet and (H.SetResult.Status = rcsSuccess),
          H.SetResult.ErrorMsg);

    H.Reset;
    Svc.GetVfoAsync(@H.OnVfo);
    Pump(500);
    WriteLn('    rig answers: enum ', Ord(H.Vfo.Vfo), '  raw $',
            HexStr(H.Vfo.RawVfo, 8));

    { Hamlib 4.5.5 answers RIG_VFO_SUB after being told RIG_VFO_B, so
      "=" is the wrong comparison and RigVfoSelectionMatches is the
      right one. This check is the reason that function exists.

      Hamlib 4.5.5 は RIG_VFO_B を指示された後 RIG_VFO_SUB と答えます。
      したがって "=" は誤った比較であり、RigVfoSelectionMatches が正しい
      比較です。本検査こそがその関数の存在理由です。 }
    Check('the selection took effect (B, which Hamlib reports as SUB)',
          H.GotVfo and (H.Vfo.Status = rcsSuccess)
          and RigVfoSelectionMatches(rvfoB, H.Vfo.Vfo),
          Format('enum %d', [Ord(H.Vfo.Vfo)]));
    Check('the raw vfo_t was preserved for the application',
          H.Vfo.RawVfo <> 0, Format('%d', [H.Vfo.RawVfo]));
    Check('a plain "=" comparison would have been wrong here',
          H.Vfo.Vfo <> rvfoB,
          'Hamlib answered exactly what was asked — the normalisation '
          + 'this check documents may not apply to this build');
    Check('the selected VFO reached the snapshot',
          RigVfoSelectionMatches(rvfoB, Svc.CurrentState.SelectedVfo));

    Ok := False;
    try
      Svc.SetVfoAsync(rvfoCurr);
    except
      on E: EArgumentException do Ok := True;
    end;
    Check('selecting "the current VFO" is refused as meaningless', Ok);

    H.Reset;
    Svc.SetVfoAsync(rvfoA, @H.OnSet);
    Pump(400);
    WriteLn;

    { ================================================================
      SPLIT — the operation WSJT-X leans on
      ================================================================ }
    WriteLn('SPLIT — what WSJT-X uses for every QSO');
    H.Reset;
    Svc.SetFrequencyAsync(14074000.0, rvfoA, @H.OnSet);
    Pump(400);

    H.Reset;
    Svc.SetSplitAsync(True, rvfoB, @H.OnSet);
    Pump(500);
    Check('split was turned on with VFO B transmitting',
          H.GotSet and (H.SetResult.Status = rcsSuccess),
          H.SetResult.ErrorMsg);

    H.Reset;
    Svc.SetSplitFreqAsync(14076500.0, @H.OnSet);
    Pump(500);
    Check('a transmit frequency was set',
          H.GotSet and (H.SetResult.Status = rcsSuccess),
          H.SetResult.ErrorMsg);

    H.Reset;
    Svc.GetSplitAsync(@H.OnSplit);
    Pump(600);
    WriteLn('    split=', H.Split.SplitOn, ' tx_vfo=', Ord(H.Split.TxVfo),
            ' tx_freq=', FormatFloat('#,##0', H.Split.TxFreq));
    Check('the rig reports split as on',
          H.GotSplit and (H.Split.Status = rcsSuccess) and H.Split.SplitOn,
          H.Split.ErrorMsg);
    Check('and the transmit frequency round-tripped',
          Abs(H.Split.TxFreq - 14076500.0) < 1.0,
          Format('%.0f', [H.Split.TxFreq]));

    S := Svc.CurrentState;
    Check('split state reached the snapshot',
          S.SplitOn and (Abs(S.TxFreq - 14076500.0) < 1.0),
          Format('on=%s tx=%.0f', [BoolToStr(S.SplitOn, True), S.TxFreq]));

    H.Reset;
    Svc.SetSplitAsync(False, rvfoCurr, @H.OnSet);
    Pump(500);
    H.Reset;
    Svc.GetSplitAsync(@H.OnSplit);
    Pump(600);
    Check('split turns off again',
          H.GotSplit and (not H.Split.SplitOn));
    Check('and the snapshot clears the transmit frequency',
          Svc.CurrentState.TxFreq = 0,
          Format('%.0f', [Svc.CurrentState.TxFreq]));

    Ok := False;
    try
      Svc.SetSplitFreqAsync(-1);
    except
      on E: EArgumentException do Ok := True;
    end;
    Check('a negative transmit frequency is refused', Ok);
    WriteLn;

    { ================================================================
      VFO OPERATIONS — how WSJT-X fakes split on rigs without it
      ================================================================ }
    WriteLn('VFO OPERATIONS — copy, exchange, toggle');
    H.Reset;
    Svc.SetFrequencyAsync(21074000.0, rvfoA, @H.OnSet);
    Pump(400);

    H.Reset;
    Svc.VfoOpAsync(rvoCopy, @H.OnSet);
    Pump(500);
    Check('VFO A was copied to VFO B',
          H.GotSet and (H.SetResult.Status = rcsSuccess),
          H.SetResult.ErrorMsg);

    H.Reset;
    Svc.VfoOpAsync(rvoExchange, @H.OnSet);
    Pump(500);
    Check('VFO A and B were exchanged',
          H.GotSet and (H.SetResult.Status = rcsSuccess),
          H.SetResult.ErrorMsg);

    Ok := False;
    try
      Svc.VfoOpAsync(rvoNone);
    except
      on E: EArgumentException do Ok := True;
    end;
    Check('rvoNone is refused', Ok);
    WriteLn;

    { ================================================================
      POLLING still works with everything else going on
      ================================================================ }
    Svc.EnablePolling(120);
    Pump(800);
    Svc.DisablePolling;
    Check('polling still updates the snapshot alongside the new calls',
          Svc.CurrentState.Timestamp > 0);
    Check('and the circuit breaker stayed closed',
          not Svc.CircuitBreakerOpen);

    Svc.CancelAllPending;
    Svc.Close;
    Check('the rig closed cleanly', not Svc.IsOpen);
  finally
    Svc     := nil;
    Factory := nil;
    Pump(300);
    H.Free;
  end;

  WriteLn;
  WriteLn('--- ', Checks - Failures, ' / ', Checks, ' checks passed ---');
  if Failures = 0 then
    WriteLn('RESULT: OK (the Rev.6.0 surface holds against the real library)')
  else
  begin
    WriteLn('RESULT: *** ', Failures, ' FAILURE(S) ***');
    ExitCode := 1;
  end;
end.
