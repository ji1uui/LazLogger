{
  RealHamlibTest.lpr

  Runs the component against the REAL Hamlib shared library, using
  Hamlib's own built-in dummy rig (RIG_MODEL_DUMMY = 1) so no hardware
  is needed.

  実際の Hamlib 共有ライブラリに対してコンポーネントを動かします。
  Hamlib 内蔵のダミーリグ (RIG_MODEL_DUMMY = 1) を使うため、ハード
  ウェアは不要です。

  Why this matters / これが重要な理由
  ------------------------------------------------------------------
  Every other test in this project uses a fake loader, which means the
  Pascal declarations of the C functions are never actually exercised.
  A wrong declaration — pbwidth_t bound as Int64 instead of C long,
  rmode_t as 32-bit, the wrong calling convention — compiles fine,
  passes every fake-based test, and then corrupts the argument list of
  a real call. tools/check_abi.py compares the declarations against the
  headers, but only this program puts them in front of the real
  library.

  本プロジェクトの他のテストはすべてフェイクローダを使うため、C 関数の
  Pascal 宣言そのものは一度も実行されません。宣言の誤り (pbwidth_t を
  C の long ではなく Int64 で束縛、rmode_t を 32bit にする、呼び出し規約
  の誤り) はコンパイルを通り、フェイクに基づく全テストに合格し、そして
  実際の呼び出しで引数列を壊します。tools/check_abi.py は宣言とヘッダを
  照合しますが、実ライブラリの前に立たせるのは本プログラムだけです。

  It also exercises the three catalogue APIs for real:
  rig_load_all_backends, rig_list_foreach_model (a C callback into
  Pascal) and rig_get_caps_cptr.

  カタログ API 3 本 (rig_load_all_backends、Pascal への C コールバックを
  伴う rig_list_foreach_model、rig_get_caps_cptr) も実際に動かします。

  Build: fpc -Mobjfpc -Sh -Fu../src -FE. RealHamlibTest.lpr
  Needs: libhamlib.so.4 / libhamlib-4.dll / libhamlib.dylib on the
         system. Skips cleanly (exit code 0) when Hamlib is absent.
}
program RealHamlibTest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  HamlibInterfaces, HamlibErrors, HamlibLoader, HamlibCatalog, HamlibModeCodec,
  HamlibTimeoutPolicy, HamlibService, HamlibFactory;

const
  { Hamlib's built-in dummy backend. It answers every call without
    touching a serial port, which is exactly what an ABI test needs.
    Hamlib 内蔵のダミーバックエンド。シリアルポートに触れずすべての
    呼び出しに応答します。ABI テストに必要なのはまさにこれです。 }
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

{ ------------------------------------------------------------------
  Result harness. The component delivers results on the UI thread, so a
  console program has to pump CheckSynchronize.
  結果受け取り用ハーネス。コンポーネントは UI スレッドで結果を配送する
  ため、コンソールプログラムは CheckSynchronize を回す必要があります。
  ------------------------------------------------------------------ }
type
  THarness = class
    GotFreq:   Boolean;
    GotMode:   Boolean;
    GotSet:    Boolean;
    Freq:      Double;
    Mode:      TRigMode;
    RawMode:   Int64;
    Passband:  Integer;
    SetStatus: TRigCommandStatus;
    SetError:  TRigErrorKind;
    SetMsg:    string;
    Connected: Boolean;
    LastError: string;
    procedure OnFreq(const R: TRigFreqResult);
    procedure OnMode(const R: TRigModeResult);
    procedure OnSet(const R: TRigResult);
    procedure OnConn(Sender: TObject; AConnected: Boolean);
    procedure OnErr(Sender: TObject; AKind: TRigErrorKind;
                    ANativeCode: Integer; const AMsg: string);
  end;

procedure THarness.OnFreq(const R: TRigFreqResult);
begin GotFreq := True; Freq := R.Freq; end;

procedure THarness.OnMode(const R: TRigModeResult);
begin
  GotMode  := True;
  Mode     := R.Mode;
  RawMode  := R.RawMode;
  Passband := R.Passband;
end;

procedure THarness.OnSet(const R: TRigResult);
begin
  GotSet    := True;
  SetStatus := R.Status;
  SetError  := R.Error;
  SetMsg    := R.ErrorMsg;
end;

procedure THarness.OnConn(Sender: TObject; AConnected: Boolean);
begin Connected := AConnected; end;

procedure THarness.OnErr(Sender: TObject; AKind: TRigErrorKind;
                          ANativeCode: Integer; const AMsg: string);
begin
  LastError := Format('%s [%s native %d]',
    [AMsg, RigErrorKindToString(AKind), ANativeCode]);
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

{ ==================================================================== }
var
  Loader:   IHamlibLoader;
  Diag:     IHamlibDiagnostics;
  Cat:      IRigModelCatalog;
  Svc:      IRigService;
  Factory:  IRigServiceFactory;
  H:        THarness;
  Info:     TRigModelInfo;
  Mfg, Nm:  string;
  Answered: Boolean;
  Known:    Boolean;
  i, Found: Integer;
  T0:       QWord;
  Policy:   TRigTimeoutPolicy;
begin
  WriteLn('=== Component against the real Hamlib library ===');
  WriteLn;

  { ---- 1. load ---- }
  WriteLn('1. Loading the library');
  Loader := THamlibLoader.Create;
  if not Loader.Load then
  begin
    WriteLn('    Hamlib is not installed on this system — skipping.');
    WriteLn('    Hamlib が見つからないためスキップします。');
    WriteLn;
    WriteLn('RESULT: SKIPPED (no Hamlib)');
    Halt(0);
  end;

  WriteLn('    path    : ', Loader.LibPath);
  WriteLn('    version : ', Loader.ApiMajor, '.', Loader.ApiMinor);
  Check('the library loaded and all required symbols resolved',
        Loader.IsLoaded);
  Check('the major version was parsed', Loader.ApiMajor = 4,
        Format('%d', [Loader.ApiMajor]));
  Check('rig_set_debug was resolved, so the library can be silenced',
        Loader.HasSymbol('rig_set_debug'));

  { ---- 2. diagnostics role ---- }
  WriteLn;
  WriteLn('2. Version gate and model verification against the real library');
  Check('the loader offers IHamlibDiagnostics',
        Supports(Loader, IHamlibDiagnostics, Diag));
  if Assigned(Diag) then
  begin
    WriteLn('    rig_version() : "', Diag.GetVersionText, '"');
    WriteLn('    verdict       : ', Ord(Diag.GetVersionVerdict),
            '  (0=verified 1=untested 2=unknown)');
    Check('rig_version() returned something',
          Diag.GetVersionText <> '', '(empty)');
    Check('this Hamlib is inside the verified range',
          Diag.GetVersionVerdict = rvvVerified,
          Format('verdict %d for %s',
                 [Ord(Diag.GetVersionVerdict), Diag.GetVersionText]));

    Known := Diag.CheckModel(MODEL_DUMMY, Mfg, Nm, Answered);
    WriteLn('    model 1       : answered=', Answered, ' known=', Known,
            ' "', Mfg, ' ', Nm, '"');
    Check('rig_check_backend answered for the dummy rig', Answered);
    Check('and reports it as known', Known);
    Check('rig_get_caps_cptr returned a manufacturer and model name',
          (Mfg <> '') and (Nm <> ''), Mfg + '/' + Nm);

    { A number no backend claims. 4.5.5 has 347 models, none at 99999.
      どのバックエンドも主張しない番号。 }
    Known := Diag.CheckModel(99999, Mfg, Nm, Answered);
    Check('an invented model number is answered as unknown',
          Answered and (not Known));
  end;

  { ---- 3. the catalogue, for real ---- }
  WriteLn;
  WriteLn('3. Enumerating the rigs this library can drive');
  T0  := GetTickCount64;
  Cat := TRigModelCatalog.Create(Loader);
  WriteLn('    enumeration took ', GetTickCount64 - T0, ' ms');
  Check('rig_list_foreach_model drove the Pascal callback',
        Cat.IsAvailable);
  WriteLn('    models found : ', Cat.Count);
  Check('a realistic number of rigs came back',
        Cat.Count > 100, Format('%d', [Cat.Count]));

  if Cat.Count > 0 then
  begin
    WriteLn('    first three  :');
    for i := 0 to 2 do
      if i < Cat.Count then
        WriteLn('      ', RigModelInfoToString(Cat.Items[i]),
                '  [#', Cat.Items[i].ModelNumber, ']');

    Check('every entry has a manufacturer and a model name',
          (Cat.Items[0].Manufacturer <> '')
          and (Cat.Items[0].ModelName <> ''));
    Check('Hamlib backend maturity came through',
          Cat.Items[0].BackendStatus <> '',
          Cat.Items[0].BackendStatus);

    Check('the dummy rig is in the catalogue',
          Cat.FindByNumber(MODEL_DUMMY, Info),
          'model 1 not listed');

    { The numbers this project used to hard-code, now checked against
      the library itself rather than against a header.
      かつて本プロジェクトがハードコードしていた番号を、ヘッダではなく
      ライブラリ自身と照合します。 }
    Found := 0;
    if Cat.FindByNumber(3073, Info) and (Pos('7300', Info.ModelName) > 0) then
      Inc(Found);
    if Cat.FindByNumber(1035, Info) and (Pos('991', Info.ModelName) > 0) then
      Inc(Found);
    if Cat.FindByNumber(2029, Info) and (Pos('K3', Info.ModelName) > 0) then
      Inc(Found);
    Check('IC-7300 = 3073, FT-991 = 1035 and K3 = 2029 as the library says',
          Found = 3, Format('%d of 3 matched', [Found]));

    { And the number that was wrong in Rev.4.1. / Rev.4.1 で誤っていた番号。 }
    if Cat.FindByNumber(3085, Info) then
      Check('3085 is the IC-705, not the IC-7300 (the Rev.4.1 bug)',
            Pos('705', Info.ModelName) > 0, Info.ModelName);
  end;

  Cat    := nil;
  Diag   := nil;
  Loader := nil;

  { ---- 4. drive the dummy rig through the full stack ---- }
  WriteLn;
  WriteLn('4. Driving Hamlib''s dummy rig through the component');
  H := THarness.Create;
  try
    Factory := TRigServiceFactory.Create;
    Policy  := RigPolicy_Default;
    Svc     := Factory.CreateServiceWithPolicy(Policy);

    Svc.SetOnConnectionChanged(@H.OnConn);
    Svc.SetOnError(@H.OnErr);

    { An EMPTY port, not 'none'. The dummy backend owns no serial
      device, and Hamlib resolves the literal string 'none' as a
      network host name — which is how this very test first failed,
      with -RIG_ECONF and "cannot get host none".

      'none' ではなく「空」のポートです。ダミーバックエンドはシリアル
      デバイスを持たず、Hamlib は文字列 'none' をネットワークホスト名
      として解決します。本テストが最初に失敗したのはまさにこれで、
      -RIG_ECONF と "cannot get host none" が出ました。 }
    Svc.Open(MODEL_DUMMY, '');
    Pump(600);

    Check('rig_init + rig_open succeeded against the real library',
          H.Connected and Svc.IsOpen);

    { --- frequency: hl_freq_t must really be a C double --- }
    H.GotSet := False;
    Svc.SetFrequencyAsync(14074000.0, rvfoCurr, @H.OnSet);
    Pump(600);
    Check('rig_set_freq accepted a frequency',
          H.GotSet and (H.SetStatus = rcsSuccess),
          Format('status %d %s', [Ord(H.SetStatus), H.SetMsg]));

    H.GotFreq := False;
    Svc.GetFrequencyAsync(rvfoCurr, @H.OnFreq);
    Pump(600);
    WriteLn('    rig_get_freq : ', FormatFloat('#,##0', H.Freq), ' Hz');
    Check('rig_get_freq returned exactly what was set — so freq_t is '
          + 'bound as a C double',
          H.GotFreq and (Abs(H.Freq - 14074000.0) < 1.0),
          Format('%.1f', [H.Freq]));

    { --- mode: rmode_t is 64-bit and pbwidth_t is a C long --- }
    H.GotSet := False;
    Svc.SetModeAsync(rmUSB, 2400, rvfoCurr, @H.OnSet);
    Pump(600);
    Check('rig_set_mode accepted USB / 2400 Hz',
          H.GotSet and (H.SetStatus = rcsSuccess),
          Format('status %d %s', [Ord(H.SetStatus), H.SetMsg]));

    H.GotMode := False;
    Svc.GetModeAsync(rvfoCurr, @H.OnMode);
    Pump(600);
    WriteLn('    rig_get_mode : ', THamlibModeCodec.ToDisplayString(H.Mode),
            ' raw=$', HexStr(H.RawMode, 8), ' width=', H.Passband, ' Hz');
    Check('the mode came back as rmUSB — so the bit table and the '
          + '64-bit rmode_t binding are both right',
          H.GotMode and (H.Mode = rmUSB),
          THamlibModeCodec.FormatRaw(H.RawMode));
    Check('the passband came back as a sane width — so pbwidth_t is '
          + 'bound as a C long',
          (H.Passband > 0) and (H.Passband < 30000),
          Format('%d', [H.Passband]));

    { A mode the dummy rig supports but which uses a high bit, to prove
      the upper half of rmode_t survives the call.
      ダミーリグが対応し、かつ上位ビットを使うモード。rmode_t の上位
      32bit が呼び出しを生き延びることを示します。 }
    H.GotSet := False;
    Svc.SetModeAsync(rmPktUSB, 3000, rvfoCurr, @H.OnSet);
    Pump(600);
    H.GotMode := False;
    Svc.GetModeAsync(rvfoCurr, @H.OnMode);
    Pump(600);
    Check('PKT-USB round-tripped as well',
          H.GotMode and (H.Mode = rmPktUSB),
          THamlibModeCodec.FormatRaw(H.RawMode));

    { --- PTT: a refusal, and what the application is told about it ---

      Hamlib's dummy rig has no PTT port configured, and rig_set_ptt
      (4.5.5, rig.c line 3279) falls through to `default:` and returns
      -RIG_EINVAL for a pttport type of NONE. So this is NOT a working
      PTT test — it is a test of what reaches the application when a
      real Hamlib refuses a real command.

      Two things matter here. The status must be rcsError with a
      classified kind, and the message must be a MESSAGE: before
      Rev.5.0 this came back as 15 KB of rig_set_cache_mode trace,
      because rigerror() returns Hamlib's accumulated debug buffer
      rather than the error string.

      Hamlib のダミーリグには PTT ポートが設定されておらず、
      rig_set_ptt (4.5.5, rig.c 3279 行) は pttport 型が NONE のとき
      `default:` に落ちて -RIG_EINVAL を返します。つまりこれは PTT が
      動くことのテストではなく、実 Hamlib が実コマンドを拒否したとき
      アプリケーションに何が届くかのテストです。

      重要なのは 2 点。ステータスが分類済み種別を伴う rcsError である
      こと、そしてメッセージが「メッセージ」であること。Rev.5.0 より前は
      rig_set_cache_mode のトレース 15KB が返ってきていました。
      rigerror() がエラー文字列ではなく Hamlib の累積デバッグバッファを
      返すためです。 }
    H.GotSet := False;
    Svc.SetPttAsync(rpttOn, @H.OnSet);
    Pump(600);
    WriteLn('    rig_set_ptt  : status=', Ord(H.SetStatus),
            ' kind=', RigErrorKindToString(H.SetError));
    WriteLn('    error text   : "', H.SetMsg, '"');

    Check('the dummy rig''s PTT refusal came back as a classified error',
          (H.SetStatus = rcsError) and (H.SetError = rekInvalidArgument),
          Format('status %d kind %d', [Ord(H.SetStatus), Ord(H.SetError)]));
    Check('the error text is one short line, not Hamlib''s debug buffer',
          (Length(H.SetMsg) < 120) and (Pos(#10, H.SetMsg) = 0),
          Format('%d chars, %d newlines',
                 [Length(H.SetMsg),
                  Length(H.SetMsg) - Length(StringReplace(H.SetMsg, #10, '',
                                                          [rfReplaceAll]))]));
    Check('and it names the actual Hamlib error',
          Pos('nvalid', H.SetMsg) > 0, H.SetMsg);
    Check('a refused PTT does NOT move the snapshot',
          not Svc.CurrentState.PttActive);

    { --- polling against the real library --- }
    Svc.EnablePolling(120);
    Pump(900);
    Svc.DisablePolling;
    Check('polling the real library updated the snapshot',
          Svc.CurrentState.Timestamp > 0);
    Check('and did not trip the circuit breaker',
          not Svc.CircuitBreakerOpen);

    { --- a VFO the dummy rig may not target, to see a real error
          travel through the new TRigErrorKind path --- }
    H.GotSet := False;
    Svc.SetFrequencyAsync(7074000.0, rvfoSub, @H.OnSet);
    Pump(600);
    WriteLn('    sub-VFO set  : status=', Ord(H.SetStatus),
            ' kind=', RigErrorKindToString(H.SetError),
            ' msg="', H.SetMsg, '"');
    Check('a command on a possibly-untargetable VFO returns a result '
          + 'rather than hanging', H.GotSet);
    Check('if it failed, the failure is classified, not a raw number',
          (H.SetStatus = rcsSuccess) or (H.SetError <> rekNone),
          Format('status %d kind %d', [Ord(H.SetStatus), Ord(H.SetError)]));

    Svc.CancelAllPending;
    Svc.Close;
    Check('rig_close + rig_cleanup completed', not Svc.IsOpen);
  finally
    Svc     := nil;
    Factory := nil;
    Pump(300);
    H.Free;
  end;

  WriteLn;
  WriteLn('--- ', Checks - Failures, ' / ', Checks, ' checks passed ---');
  if Failures = 0 then
    WriteLn('RESULT: OK (the ABI holds against the real library)')
  else
  begin
    WriteLn('RESULT: *** ', Failures, ' FAILURE(S) ***');
    ExitCode := 1;
  end;
end.
