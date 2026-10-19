{
  DomainTypeTest.lpr

  Verifies the Rev.5.0 domain types: TRigMode, TRigErrorKind and the
  model catalogue.

  Rev.5.0 のドメイン型 (TRigMode、TRigErrorKind、モデルカタログ) を
  検証します。

  What is actually being checked / 実際に検査していること
  ------------------------------------------------------------------
  The point of these types is that application code no longer encodes
  values owned by another project. A test can therefore check two
  things that matter:

    1. round-tripping — every named mode survives
       TRigMode -> rmode_t -> TRigMode, and the bit values match the
       Hamlib headers (tools/check_abi.py checks the table against the
       headers; this test checks the code that uses the table);
    2. honest ignorance — an unknown bit, a zero, and a multi-bit mask
       all come back as rmUnknown with the raw value preserved, rather
       than as a plausible guess.

  これらの型の要点は、アプリケーションコードが他プロジェクト所有の値を
  埋め込まなくなることです。したがってテストでは次の 2 点を検査します。

    1. 往復変換 — すべての名前付きモードが
       TRigMode -> rmode_t -> TRigMode を生き延び、ビット値が Hamlib の
       ヘッダと一致すること (表とヘッダの照合は tools/check_abi.py、
       表を使うコードの検証が本テスト)。
    2. 正直な無知 — 未知のビット、ゼロ、複数ビットのマスクはいずれも、
       もっともらしい推測ではなく rmUnknown として返り、生値が保持
       されること。

  The error-kind checks matter because the sign convention is a known
  trap: Hamlib's RIG_E* are positive ordinals and its functions return
  the negation, so -6 is RIG_EIO. An earlier revision of this project's
  own manual got that wrong.

  エラー種別の検査が重要なのは、符号の慣習が既知の罠だからです。Hamlib の
  RIG_E* は正の序数で、関数はその符号反転を返すため -6 が RIG_EIO です。
  本プロジェクトのマニュアルの以前の版はこれを誤っていました。

  Build: fpc -Mobjfpc -Sh -Fu../src -FE. DomainTypeTest.lpr
}
program DomainTypeTest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  HamlibInterfaces, HamlibErrors, HamlibModeCodec, HamlibCatalog,
  HamlibService, HamlibTypes;

{ TFakeLoader implements IHamlibLoader and nothing else. It stands in
  for a Hamlib too old to enumerate, and for any application-supplied
  loader that does not opt into the catalogue role.
  TFakeLoader は IHamlibLoader のみを実装します。列挙できない古い Hamlib
  と、カタログ role に乗らないアプリ提供ローダの代役です。 }
{$I fakeloader.inc}

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

{ ====================================================================
  A loader that implements IHamlibCatalog with a fixed list, so the
  catalogue can be tested without a real Hamlib.
  固定リストで IHamlibCatalog を実装するローダ。実 Hamlib なしで
  カタログを検証できます。
  ==================================================================== }
type
  TCatalogLoader = class(TInterfacedObject, IHamlibLoader, IHamlibCatalog)
  private
    FAvailable: Boolean;
  public
    constructor Create(AAvailable: Boolean);

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

    { IHamlibCatalog }
    function  ListModels(out AList: TRigModelInfoArray): Boolean;
  end;

constructor TCatalogLoader.Create(AAvailable: Boolean);
begin
  inherited Create;
  FAvailable := AAvailable;
end;

function  TCatalogLoader.Load(const APath: string): Boolean; begin Result := True; end;
procedure TCatalogLoader.Unload; begin end;
function  TCatalogLoader.GetIsLoaded: Boolean; begin Result := True; end;
function  TCatalogLoader.GetApiMajor: Integer; begin Result := 4; end;
function  TCatalogLoader.GetApiMinor: Integer; begin Result := 7; end;
function  TCatalogLoader.GetLibPath: string; begin Result := '<catalog>'; end;
function  TCatalogLoader.HasSymbol(const AName: string): Boolean; begin Result := True; end;
function  TCatalogLoader.CallRigInit(AModel: Integer): Pointer; begin Result := Pointer(1); end;
function  TCatalogLoader.CallRigOpen(ARig: Pointer): Integer; begin Result := 0; end;
function  TCatalogLoader.CallRigClose(ARig: Pointer): Integer; begin Result := 0; end;
function  TCatalogLoader.CallRigCleanup(ARig: Pointer): Integer; begin Result := 0; end;
function  TCatalogLoader.CallRigSetFreq(ARig: Pointer; AVfo: Integer; AFreq: Double): Integer;
begin Result := 0; end;
function  TCatalogLoader.CallRigGetFreq(ARig: Pointer; AVfo: Integer; out AFreq: Double): Integer;
begin AFreq := 14074000.0; Result := 0; end;
function  TCatalogLoader.CallRigSetMode(ARig: Pointer; AVfo: Integer; AMode: Int64; AWidth: Int64): Integer;
begin Result := 0; end;
function  TCatalogLoader.CallRigGetMode(ARig: Pointer; AVfo: Integer; out AMode: Int64; out AWidth: Int64): Integer;
begin
  { Report a bit this binding has no name for (bit 20 is unassigned in
    every Hamlib 4.x header), to prove an unknown mode degrades rather
    than being mis-named.
    本バインディングに名前が無いビットを報告します (ビット 20 は
    Hamlib 4.x の全ヘッダで未割り当て)。未知のモードが誤った名前に
    なるのではなく縮退することを示します。 }
  AMode  := Int64(1) shl 20;
  AWidth := 2700;
  Result := 0;
end;
function  TCatalogLoader.CallRigSetPtt(ARig: Pointer; AVfo: Integer; APtt: Integer): Integer;
begin Result := 0; end;
function  TCatalogLoader.CallRigGetPtt(ARig: Pointer; AVfo: Integer; out APtt: Integer): Integer;
begin APtt := 0; Result := 0; end;
function  TCatalogLoader.CallRigError(ACode: Integer): string;
begin Result := Format('catalog-loader error %d', [ACode]); end;
function  TCatalogLoader.SetConf(ARig: Pointer; const AName, AValue: string): Integer;
begin Result := 0; end;
function  TCatalogLoader.SetSerialPort(ARig: Pointer; const APort: string): Integer;
begin Result := 0; end;
function  TCatalogLoader.SetSerialBaud(ARig: Pointer; ABaud: Integer): Integer;
begin Result := 0; end;

function TCatalogLoader.ListModels(out AList: TRigModelInfoArray): Boolean;
begin
  SetLength(AList, 0);
  Result := FAvailable;
  if not Result then Exit;

  { Deliberately out of order, with a mixed-case duplicate manufacturer,
    so the sort is actually exercised.
    ソートが実際に働くよう、意図的に順不同とし、メーカー名の大小混在を
    含めています。 }
  SetLength(AList, 4);
  AList[0].ModelNumber := 3073;
  AList[0].Manufacturer := 'Icom';
  AList[0].ModelName := 'IC-7300';
  AList[0].BackendStatus := 'Stable';

  AList[1].ModelNumber := 1035;
  AList[1].Manufacturer := 'Yaesu';
  AList[1].ModelName := 'FT-991';
  AList[1].BackendStatus := 'Stable';

  AList[2].ModelNumber := 2029;
  AList[2].Manufacturer := 'Elecraft';
  AList[2].ModelName := 'K3';
  AList[2].BackendStatus := 'Beta';

  AList[3].ModelNumber := 3085;
  AList[3].Manufacturer := 'icom';
  AList[3].ModelName := 'IC-705';
  AList[3].BackendStatus := 'Alpha';
end;

{ ====================================================================
  Harness for the asynchronous mode result.
  非同期モード結果用ハーネス。
  ==================================================================== }
type
  THarness = class
    Got:      Boolean;
    ModeSeen: TRigMode;
    RawSeen:  Int64;
    PassSeen: Integer;
    procedure OnMode(const R: TRigModeResult);
  end;

procedure THarness.OnMode(const R: TRigModeResult);
begin
  Got      := True;
  ModeSeen := R.Mode;
  RawSeen  := R.RawMode;
  PassSeen := R.Passband;
end;

{ ==================================================================== }

procedure TestModeRoundTrip;
var
  M, Back: TRigMode;
  Raw:     Int64;
  Bad:     Integer;
  Names:   Integer;
begin
  WriteLn('MODE CODEC - round trip and honest ignorance');

  Bad   := 0;
  Names := 0;
  for M := Low(TRigMode) to High(TRigMode) do
  begin
    if M = rmUnknown then Continue;
    Raw  := THamlibModeCodec.ToHamlib(M);
    Back := THamlibModeCodec.FromHamlib(Raw);
    if Back <> M then Inc(Bad);
    { Exactly one bit must be set — a mode is a single rmode_t flag.
      ビットはちょうど 1 本であること。モードは単一の rmode_t フラグです。 }
    if (Raw = 0) or ((Raw and (Raw - 1)) <> 0) then Inc(Bad);
    if THamlibModeCodec.ToDisplayString(M) <> '' then Inc(Names);
  end;

  Check('every named mode round-trips to itself',
        Bad = 0, Format('%d modes failed', [Bad]));
  Check('every named mode has a display label',
        Names = Ord(High(TRigMode)),
        Format('%d labels for %d modes', [Names, Ord(High(TRigMode))]));

  { Spot-check the bits an operator would notice immediately. These are
    the values tools/check_abi.py verifies against rig.h.
    オペレータが即座に気づく値を抜き取り検査します。これらは
    tools/check_abi.py が rig.h と照合している値です。 }
  Check('rmUSB is bit 2',  THamlibModeCodec.ToHamlib(rmUSB) = (Int64(1) shl 2));
  Check('rmLSB is bit 3',  THamlibModeCodec.ToHamlib(rmLSB) = (Int64(1) shl 3));
  Check('rmPktUSB is bit 11 (FT8 etc.)',
        THamlibModeCodec.ToHamlib(rmPktUSB) = (Int64(1) shl 11));
  Check('rmFMN is bit 21, not 20 (the gap in rig.h)',
        THamlibModeCodec.ToHamlib(rmFMN) = (Int64(1) shl 21));

  Check('zero decodes to rmUnknown',
        THamlibModeCodec.FromHamlib(0) = rmUnknown);
  Check('an unassigned bit decodes to rmUnknown, not a guess',
        THamlibModeCodec.FromHamlib(Int64(1) shl 20) = rmUnknown);
  Check('a future bit decodes to rmUnknown',
        THamlibModeCodec.FromHamlib(Int64(1) shl 62) = rmUnknown);
  Check('a multi-bit capability mask decodes to rmUnknown',
        THamlibModeCodec.FromHamlib((Int64(1) shl 2) or (Int64(1) shl 3))
          = rmUnknown);

  Check('an unknown raw value still formats identifiably',
        Pos('$', THamlibModeCodec.FormatRaw(Int64(1) shl 20)) > 0,
        THamlibModeCodec.FormatRaw(Int64(1) shl 20));

  { A capability mask is what SetFromHamlib is for.
    能力マスクには SetFromHamlib を使います。 }
  Check('a capability mask expands to a set of named modes',
        THamlibModeCodec.SetFromHamlib(
          (Int64(1) shl 2) or (Int64(1) shl 3) or (Int64(1) shl 11))
          = [rmUSB, rmLSB, rmPktUSB]);
  Check('unnamed bits are dropped from the set, not guessed',
        THamlibModeCodec.SetFromHamlib(
          (Int64(1) shl 2) or (Int64(1) shl 20)) = [rmUSB]);

  { The legacy helper must not grow a second mode table.
    旧ヘルパーが 2 つ目のモード表を持ってはなりません。 }
  Check('the legacy HamlibModeToString agrees with the codec',
        HamlibModeToString(Int64(1) shl 2)
          = THamlibModeCodec.FormatRaw(Int64(1) shl 2),
        HamlibModeToString(Int64(1) shl 2));
  WriteLn;
end;

procedure TestErrorKinds;
begin
  WriteLn('ERROR KINDS - the sign convention and unknown codes');

  Check('0 is rekNone', RigErrorKindFromCode(0) = rekNone);

  { Hamlib returns the negation, so these are the values that actually
    arrive in TRigResult.NativeCode.
    Hamlib は符号反転した値を返すため、実際に TRigResult.NativeCode に
    届くのはこれらです。 }
  Check('-5 is a timeout (RIG_ETIMEOUT = 5)',
        RigErrorKindFromCode(-5) = rekTimeout);
  Check('-6 is an I/O error (RIG_EIO = 6)',
        RigErrorKindFromCode(-6) = rekIo);
  Check('-3 is out of memory, NOT I/O',
        RigErrorKindFromCode(-3) = rekOutOfMemory);
  Check('-11 is "not available on this rig"',
        RigErrorKindFromCode(-11) = rekNotAvailable);
  Check('-22 is access denied (port in use)',
        RigErrorKindFromCode(-22) = rekAccessDenied);

  { A caller who passes the positive ordinal by mistake gets the same
    classification rather than a wrong one.
    正の序数を誤って渡した呼び出し元にも、誤った分類ではなく同じ分類を
    返します。 }
  Check('a positive ordinal is classified the same way',
        RigErrorKindFromCode(5) = rekTimeout);

  Check('a code beyond the known range is rekUnrecognised',
        RigErrorKindFromCode(-99) = rekUnrecognised);
  Check('rekUnrecognised is not silently mapped to an internal error',
        RigErrorKindFromCode(-99) <> rekInternal);

  Check('every kind has a label',
        (RigErrorKindToString(rekTimeout) <> '')
        and (RigErrorKindToString(rekCircuitOpen) <> '')
        and (RigErrorKindToString(rekUnrecognised) <> ''));

  { ERigError must carry the classification, since that is what the
    Worker copies into the result.
    ERigError が分類を保持していなければなりません。Worker はそれを結果に
    コピーするためです。 }
  try
    raise ERigError.CreateFromHamlib(-5, nil);
  except
    on E: ERigError do
    begin
      Check('ERigError classifies its own code', E.Kind = rekTimeout);
      Check('ERigError keeps the raw code too', E.Code = -5);
    end;
  end;
  WriteLn;
end;

procedure TestCatalog;
var
  Cat:   IRigModelCatalog;
  Info:  TRigModelInfo;
  Ok:    Boolean;
begin
  WriteLn('CATALOG - the rig list, sorted, searchable, degradable');

  Cat := TRigModelCatalog.Create(TCatalogLoader.Create(True));
  Check('a catalogue is available when the library can enumerate',
        Cat.IsAvailable);
  Check('all entries are present', Cat.Count = 4,
        Format('%d entries', [Cat.Count]));

  { Sorted by manufacturer then model, case-insensitively — so the two
    Icom entries are adjacent despite the different capitalisation.
    メーカー名→機種名で大文字小文字を無視してソートされるため、綴りの
    大小が違っても Icom の 2 件は隣接します。 }
  Check('sorted: Elecraft first', Cat.Items[0].Manufacturer = 'Elecraft',
        Cat.Items[0].Manufacturer);
  Check('sorted: the two Icom entries are adjacent',
        SameText(Cat.Items[1].Manufacturer, 'Icom')
        and SameText(Cat.Items[2].Manufacturer, 'Icom'),
        Cat.Items[1].Manufacturer + ', ' + Cat.Items[2].Manufacturer);
  Check('sorted: IC-705 before IC-7300',
        Cat.Items[1].ModelName = 'IC-705',
        Cat.Items[1].ModelName);
  Check('sorted: Yaesu last', Cat.Items[3].Manufacturer = 'Yaesu',
        Cat.Items[3].Manufacturer);

  Ok := Cat.FindByNumber(3073, Info);
  Check('FindByNumber locates the model Open would be given',
        Ok and (Info.ModelName = 'IC-7300'));

  Ok := Cat.FindByName('icom', 'ic-7300', Info);
  Check('FindByName is case-insensitive and yields the number',
        Ok and (Info.ModelNumber = 3073),
        Format('found=%s number=%d', [BoolToStr(Ok, True), Info.ModelNumber]));

  Ok := Cat.FindByNumber(9999, Info);
  Check('an absent number is reported as absent, not guessed', not Ok);

  Check('the display label carries maker, model and maturity',
        RigModelInfoToString(Cat.Items[3]) = 'Yaesu FT-991 (Stable)',
        RigModelInfoToString(Cat.Items[3]));

  { Out-of-range access must raise in release builds too, because the
    index usually comes from a UI selection.
    範囲外アクセスはリリースビルドでも例外でなければなりません。添字は
    通常 UI の選択から来るためです。 }
  Ok := False;
  try
    Info := Cat.Items[99];
  except
    on E: EArgumentException do Ok := True;
  end;
  Check('an out-of-range index raises EArgumentException', Ok);

  Cat := nil;

  { The degraded paths: a library that cannot enumerate, and a loader
    with no catalogue role at all. Neither may raise.
    縮退経路: 列挙できないライブラリと、カタログ role を持たないローダ。
    どちらも例外を出してはなりません。 }
  Cat := TRigModelCatalog.Create(TCatalogLoader.Create(False));
  Check('a library that cannot enumerate yields IsAvailable = False',
        not Cat.IsAvailable);
  Check('and an empty, safely readable list', Cat.Count = 0);
  Ok := Cat.FindByNumber(3073, Info);
  Check('lookups on an empty catalogue simply fail', not Ok);
  Cat := nil;

  Cat := TRigModelCatalog.Create(TFakeLoader.Create);
  Check('a loader without the catalogue role degrades instead of raising',
        not Cat.IsAvailable);
  Check('and reports no entries', Cat.Count = 0);
  Cat := nil;
  WriteLn;
end;

procedure TestEndToEnd;
var
  Svc: IRigService;
  H:   THarness;
  i:   Integer;
  Ok:  Boolean;
begin
  WriteLn('END TO END - the types as they reach application code');

  H   := THarness.Create;
  Svc := TRigService.Create(TCatalogLoader.Create(True));
  try
    Svc.Open(1, 'none');
    Sleep(120);

    { The fake reports the unassigned bit 20. The application must get
      rmUnknown plus the raw value, and the state snapshot must agree.
      フェイクは未割り当てのビット 20 を報告します。アプリケーションは
      rmUnknown と生値を受け取り、状態スナップショットも一致しなければ
      なりません。 }
    Svc.GetModeAsync(rvfoA, @H.OnMode);
    for i := 1 to 100 do
    begin
      CheckSynchronize(10);
      Sleep(5);
      if H.Got then Break;
    end;

    Check('a mode result arrived', H.Got);
    Check('an unnamed mode arrives as rmUnknown',
          H.ModeSeen = rmUnknown);
    Check('its raw rmode_t is preserved for the application',
          H.RawSeen = (Int64(1) shl 20),
          Format('raw = %d', [H.RawSeen]));
    Check('the passband came through in Hz', H.PassSeen = 2700,
          Format('%d', [H.PassSeen]));

    { Rev.4.2 never updated the snapshot's mode: SetMode on the state
      holder had no caller at all, so CurrentState.Mode was permanently
      its initial value. This check exists so that cannot regress.

      Rev.4.2 ではスナップショットのモードが一切更新されませんでした。
      状態ホルダの SetMode に呼び出し元が存在せず、CurrentState.Mode は
      初期値のままでした。本検査はその退行を防ぐために存在します。 }
    Check('the Pull-model snapshot now carries the mode',
          Svc.CurrentState.RawMode = (Int64(1) shl 20),
          Format('snapshot raw = %d', [Svc.CurrentState.RawMode]));
    Check('and its passband', Svc.CurrentState.Passband = 2700,
          Format('%d', [Svc.CurrentState.Passband]));

    { rmUnknown is not sendable. Echoing a get straight back into a set
      must fail loudly rather than transmit RIG_MODE_NONE.
      rmUnknown は送信できません。get の値をそのまま set に返す操作は、
      RIG_MODE_NONE を送るのではなく明確に失敗しなければなりません。 }
    Ok := False;
    try
      Svc.SetModeAsync(H.ModeSeen);
    except
      on E: EArgumentException do Ok := True;
    end;
    Check('SetModeAsync(rmUnknown) raises EArgumentException', Ok);

    { A negative passband is a programming error in any build.
      負の帯域幅はどのビルドでもプログラミングエラーです。 }
    Ok := False;
    try
      Svc.SetModeAsync(rmUSB, -1);
    except
      on E: EArgumentException do Ok := True;
    end;
    Check('a negative passband raises EArgumentException', Ok);

    { A real mode must still work.
      実在のモードは引き続き通ること。 }
    Ok := True;
    try
      Svc.SetModeAsync(rmUSB, 2400, rvfoA);
    except
      Ok := False;
    end;
    Check('SetModeAsync(rmUSB) is accepted', Ok);

    for i := 1 to 40 do
    begin
      CheckSynchronize(10);
      Sleep(5);
    end;

    { PTT had the same gap as the mode: IRigStateHolder.SetPtt had no
      caller, so CurrentState.PttActive never changed. A successful set
      is not a guess — it is the state we commanded and the rig
      accepted — so that is now recorded.

      PTT もモードと同じ欠落がありました。IRigStateHolder.SetPtt の
      呼び出し元が無く、CurrentState.PttActive は変化しませんでした。
      成功した set は推測ではなく、こちらが指示しリグが受理した状態
      そのものなので、それを記録するようにしました。 }
    Svc.SetPttAsync(rpttOn);
    for i := 1 to 60 do
    begin
      CheckSynchronize(10);
      Sleep(5);
      if Svc.CurrentState.PttActive then Break;
    end;
    Check('a successful PTT set reaches the snapshot',
          Svc.CurrentState.PttActive);

    Svc.SetPttAsync(rpttOff);
    for i := 1 to 60 do
    begin
      CheckSynchronize(10);
      Sleep(5);
      if not Svc.CurrentState.PttActive then Break;
    end;
    Check('and so does releasing it',
          not Svc.CurrentState.PttActive);
  finally
    Svc.CancelAllPending;
    Svc.Close;
    Svc := nil;
    CheckSynchronize(300);
    H.Free;
  end;
  WriteLn;
end;

{ ==================================================================== }
begin
  WriteLn('=== Rev.5.0 domain types ===');
  WriteLn('    modes, error kinds and the rig catalogue');
  WriteLn;

  TestModeRoundTrip;
  TestErrorKinds;
  TestCatalog;
  TestEndToEnd;

  WriteLn('--- ', Checks - Failures, ' / ', Checks, ' checks passed ---');
  if Failures = 0 then
    WriteLn('RESULT: OK')
  else
  begin
    WriteLn('RESULT: *** ', Failures, ' FAILURE(S) ***');
    ExitCode := 1;
  end;
end.
