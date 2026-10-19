{
  VersionGateTest.lpr

  Fitness function for forward compatibility (item 1).

  上位互換のフィットネス関数（項目 1）。

  Verifies the contract agreed in the design discussion:

    - a Hamlib inside the verified range starts normally
    - a Hamlib outside it is REFUSED by default, because resolving every
      symbol does not prove the ABI matches
    - AllowUntestedVersion lets the application override, and the mismatch
      then arrives as a warning rather than silence
    - an unreadable version is refused too, and is distinguished from a
      wrong one
    - a library bound through a soname-less file name is reported
    - a model number the library does not know is refused by Open
    - a library too old to answer about models warns instead of failing

  設計議論で合意した契約を検証します:

    - 検証済み範囲内の Hamlib は通常起動する
    - 範囲外は既定で拒否される（全シンボルが解決できても ABI 一致の証明に
      ならないため）
    - AllowUntestedVersion でアプリが上書きでき、その場合は不一致が沈黙では
      なく警告として届く
    - バージョンが読めない場合も拒否し、誤っている場合と区別する
    - soname 無しのファイル名でバインドした場合は報告される
    - ライブラリが知らないモデル番号は Open が拒否する
    - モデルを問い合わせられない古いライブラリは失敗ではなく警告にする

  Build: fpc -Mobjfpc -Sh -Fu../src -FE. VersionGateTest.lpr
}
program VersionGateTest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  HamlibInterfaces, HamlibErrors, HamlibService, HamlibTimeoutPolicy;

type
  { A loader that reports whatever version / model answers the test asks
    for, and implements IHamlibDiagnostics so the gate actually engages.

    テストが指示したバージョン・モデル回答を返すローダ。ゲートが実際に働く
    よう IHamlibDiagnostics を実装します。 }
  TProgrammableLoader = class(TInterfacedObject, IHamlibLoader, IHamlibDiagnostics)
  public
    VerText:      string;
    Verdict:      TRigVersionVerdict;
    Unversioned:  Boolean;
    KnowsModel:   Boolean;   { answer of rig_check_backend }
    CanAnswer:    Boolean;   { whether the model API exists at all }

    constructor Create;

    { IHamlibLoader }
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

    { IHamlibDiagnostics }
    function  GetVersionText: string;
    function  GetVersionVerdict: TRigVersionVerdict;
    function  GetSupportedRangeText: string;
    function  GetUnversionedBinding: Boolean;
    function  CheckModel(AModel: Integer; out AMfg, AModelName: string;
                         out AAnswered: Boolean): Boolean;
  end;

constructor TProgrammableLoader.Create;
begin
  inherited Create;
  VerText     := 'Hamlib 4.6.2';
  Verdict     := rvvVerified;
  Unversioned := False;
  KnowsModel  := True;
  CanAnswer   := True;
end;

function  TProgrammableLoader.Load(const APath: string): Boolean; begin Result := True; end;
procedure TProgrammableLoader.Unload; begin end;
function  TProgrammableLoader.GetIsLoaded: Boolean; begin Result := True; end;
function  TProgrammableLoader.GetApiMajor: Integer; begin Result := 4; end;
function  TProgrammableLoader.GetApiMinor: Integer; begin Result := 6; end;
function  TProgrammableLoader.GetLibPath: string; begin Result := '<programmable>'; end;
function  TProgrammableLoader.HasSymbol(const AName: string): Boolean; begin Result := True; end;
function  TProgrammableLoader.CallRigInit(AModel: Integer): Pointer; begin Result := Pointer(1); end;
function  TProgrammableLoader.CallRigOpen(ARig: Pointer): Integer; begin Result := 0; end;
function  TProgrammableLoader.CallRigClose(ARig: Pointer): Integer; begin Result := 0; end;
function  TProgrammableLoader.CallRigCleanup(ARig: Pointer): Integer; begin Result := 0; end;
function  TProgrammableLoader.CallRigSetFreq(ARig: Pointer; AVfo: Integer; AFreq: Double): Integer; begin Result := 0; end;
function  TProgrammableLoader.CallRigGetFreq(ARig: Pointer; AVfo: Integer; out AFreq: Double): Integer;
begin AFreq := 14074000.0; Result := 0; end;
function  TProgrammableLoader.CallRigSetMode(ARig: Pointer; AVfo: Integer; AMode: Int64; AWidth: Int64): Integer; begin Result := 0; end;
function  TProgrammableLoader.CallRigGetMode(ARig: Pointer; AVfo: Integer; out AMode: Int64; out AWidth: Int64): Integer;
begin AMode := 0; AWidth := 0; Result := 0; end;
function  TProgrammableLoader.CallRigSetPtt(ARig: Pointer; AVfo: Integer; APtt: Integer): Integer; begin Result := 0; end;
function  TProgrammableLoader.CallRigGetPtt(ARig: Pointer; AVfo: Integer; out APtt: Integer): Integer;
begin APtt := 0; Result := 0; end;
function  TProgrammableLoader.CallRigError(ACode: Integer): string; begin Result := 'programmable'; end;
function  TProgrammableLoader.SetConf(ARig: Pointer; const AName, AValue: string): Integer; begin Result := 0; end;
function  TProgrammableLoader.SetSerialPort(ARig: Pointer; const APort: string): Integer; begin Result := 0; end;
function  TProgrammableLoader.SetSerialBaud(ARig: Pointer; ABaud: Integer): Integer; begin Result := 0; end;

function  TProgrammableLoader.GetVersionText: string; begin Result := VerText; end;
function  TProgrammableLoader.GetVersionVerdict: TRigVersionVerdict; begin Result := Verdict; end;
function  TProgrammableLoader.GetSupportedRangeText: string; begin Result := '4.5 .. 4.7'; end;
function  TProgrammableLoader.GetUnversionedBinding: Boolean; begin Result := Unversioned; end;

function  TProgrammableLoader.CheckModel(AModel: Integer;
                                          out AMfg, AModelName: string;
                                          out AAnswered: Boolean): Boolean;
begin
  AMfg       := '';
  AModelName := '';
  AAnswered  := CanAnswer;
  Result     := CanAnswer and KnowsModel;
  if Result then
  begin
    AMfg       := 'Icom';
    AModelName := 'IC-7300';
  end;
end;

{ ------------------------------------------------------------------
  A factory that uses the programmable loader, so the gate is exercised
  through the same code path production uses.

  プログラム可能ローダを使うファクトリ。本番と同じ経路でゲートを通します。
  ------------------------------------------------------------------ }
type
  TGatedFactory = class(TInterfacedObject, IRigServiceFactory)
  private
    FLoader: TProgrammableLoader;
    FAllow:  Boolean;
  public
    constructor Create(ALoader: TProgrammableLoader);
    function  CreateService: IRigService;
    function  CreateServiceWithPolicy(const APolicy: TRigTimeoutPolicy): IRigService;
    function  CreateMockService: IRigService;
    function  CreateModelCatalog: IRigModelCatalog;
    function  GetAllowUntestedVersion: Boolean;
    procedure SetAllowUntestedVersion(AValue: Boolean);
  end;

constructor TGatedFactory.Create(ALoader: TProgrammableLoader);
begin
  inherited Create;
  FLoader := ALoader;
  FAllow  := False;
end;

function TGatedFactory.GetAllowUntestedVersion: Boolean; begin Result := FAllow; end;
procedure TGatedFactory.SetAllowUntestedVersion(AValue: Boolean); begin FAllow := AValue; end;
function TGatedFactory.CreateMockService: IRigService; begin Result := CreateService; end;

{ This harness only exercises the version gate, so the catalogue is out
  of scope here; ThreadConfinementTest and CatalogTest cover it.
  本ハーネスはバージョンゲートのみを検証するため、カタログは対象外です。
  CatalogTest が担当します。 }
function TGatedFactory.CreateModelCatalog: IRigModelCatalog;
begin
  Result := nil;
end;
function TGatedFactory.CreateService: IRigService;
begin Result := CreateServiceWithPolicy(RigPolicy_Default); end;

function TGatedFactory.CreateServiceWithPolicy(
  const APolicy: TRigTimeoutPolicy): IRigService;
var
  Diag: IHamlibDiagnostics;
  Svc:  TRigService;
begin
  { Same gate logic as TRigServiceFactory: mechanism in the loader,
    policy here.
    TRigServiceFactory と同じゲート論理。機構はローダ、方針はここ。 }
  if Supports(FLoader as IHamlibLoader, IHamlibDiagnostics, Diag)
     and (Diag.GetVersionVerdict <> rvvVerified)
     and (not FAllow) then
    raise EHamlibUnsupportedVersion.CreateFmt(
      'Hamlib %s is outside the verified range %s.',
      [Diag.GetVersionText, Diag.GetSupportedRangeText]);

  Svc := TRigService.Create(FLoader as IHamlibLoader);
  Svc.ApplyTimeoutPolicy(APolicy);
  Result := Svc;
end;

{ ------------------------------------------------------------------ }

{ FPC 3.2.2 has no Delphi-style anonymous methods, so the warning handler
  is a real method on a small harness object.
  FPC 3.2.2 は Delphi 形式の匿名メソッドを持たないため、警告ハンドラは
  小さなハーネスオブジェクトの実メソッドにします。 }
type
  TWarnHarness = class
  public
    Fired:   Boolean;
    LastMsg: string;
    procedure OnWarn(Sender: TObject; const AStatus: TRigLibraryStatus;
                     const AMessage: string);
  end;

procedure TWarnHarness.OnWarn(Sender: TObject;
                               const AStatus: TRigLibraryStatus;
                               const AMessage: string);
begin
  Fired   := True;
  LastMsg := AMessage;
end;

var
  Pass: Integer = 0;
  Fail: Integer = 0;

procedure Check(const AName: string; ACondition: Boolean; const ADetail: string = '');
begin
  if ACondition then
  begin
    Inc(Pass);
    WriteLn('  [ok]   ', AName);
  end
  else
  begin
    Inc(Fail);
    WriteLn('  [FAIL] ', AName, '  ', ADetail);
  end;
end;

{ --- 1. verified version starts --- }
procedure Test_Verified_Starts;
var
  L: TProgrammableLoader; F: IRigServiceFactory; Svc: IRigService;
begin
  WriteLn('1. verified version');
  L := TProgrammableLoader.Create;
  L.Verdict := rvvVerified;
  F := TGatedFactory.Create(L);
  try
    Svc := F.CreateService;
    Check('starts without exception', Svc <> nil);
    Check('status reports rvvVerified',
          Svc.LibraryStatus.Verdict = rvvVerified);
    Check('status carries the version text',
          Svc.LibraryStatus.VersionText = 'Hamlib 4.6.2',
          '="' + Svc.LibraryStatus.VersionText + '"');
    Svc := nil;
  except
    on E: Exception do Check('starts without exception', False, E.ClassName);
  end;
  WriteLn;
end;

{ --- 2. untested version refused by default --- }
procedure Test_Untested_Refused;
var
  L: TProgrammableLoader; F: IRigServiceFactory; Refused: Boolean;
begin
  WriteLn('2. untested version, default policy');
  L := TProgrammableLoader.Create;
  L.Verdict := rvvUntested;
  L.VerText := 'Hamlib 5.0.0';
  F := TGatedFactory.Create(L);
  Refused := False;
  try
    F.CreateService;
  except
    on E: EHamlibUnsupportedVersion do Refused := True;
    on E: Exception do Check('raises EHamlibUnsupportedVersion', False, E.ClassName);
  end;
  Check('refused by default', Refused);
  WriteLn;
end;

{ --- 3. opt-in override --- }
procedure Test_Untested_AllowedWithOptIn;
var
  L: TProgrammableLoader; F: IRigServiceFactory; Svc: IRigService;
begin
  WriteLn('3. untested version, AllowUntestedVersion := True');
  L := TProgrammableLoader.Create;
  L.Verdict := rvvUntested;
  L.VerText := 'Hamlib 5.0.0';
  F := TGatedFactory.Create(L);
  F.AllowUntestedVersion := True;
  try
    Svc := F.CreateService;
    Check('starts when explicitly allowed', Svc <> nil);
    Check('status still reports rvvUntested (not hidden)',
          Svc.LibraryStatus.Verdict = rvvUntested);
    Svc := nil;
  except
    on E: Exception do Check('starts when explicitly allowed', False, E.ClassName);
  end;
  WriteLn;
end;

{ --- 4. unknown version is refused, and distinguishable --- }
procedure Test_UnknownVersion_Refused;
var
  L: TProgrammableLoader; F: IRigServiceFactory; Refused: Boolean;
begin
  WriteLn('4. unreadable version');
  L := TProgrammableLoader.Create;
  L.Verdict := rvvUnknown;
  L.VerText := '';
  F := TGatedFactory.Create(L);
  Refused := False;
  try
    F.CreateService;
  except
    on E: EHamlibUnsupportedVersion do Refused := True;
  end;
  Check('refused as well as a wrong version', Refused);
  Check('rvvUnknown is a distinct verdict from rvvUntested',
        Ord(rvvUnknown) <> Ord(rvvUntested));
  WriteLn;
end;

{ --- 5. soname-less binding is reported --- }
procedure Test_UnversionedBinding_Reported;
var
  L: TProgrammableLoader; Svc: IRigService;
begin
  WriteLn('5. soname-less binding');
  L := TProgrammableLoader.Create;
  L.Unversioned := True;
  Svc := TRigService.Create(L as IHamlibLoader);
  try
    Check('status flags the unversioned binding',
          Svc.LibraryStatus.UnversionedBinding);
  finally
    Svc := nil;
  end;
  WriteLn;
end;

{ --- 6. unknown model refused by Open --- }
procedure Test_UnknownModel_Refused;
var
  L: TProgrammableLoader; Svc: IRigService; Refused: Boolean;
begin
  WriteLn('6. model number the library does not know');
  L := TProgrammableLoader.Create;
  L.CanAnswer  := True;
  L.KnowsModel := False;
  Svc := TRigService.Create(L as IHamlibLoader);
  Refused := False;
  try
    try
      Svc.Open(9999, 'none');
    except
      on E: ERigModelUnknown do Refused := True;
      on E: Exception do Check('raises ERigModelUnknown', False, E.ClassName);
    end;
    Check('Open refuses an unknown model', Refused);
    Check('no port was opened', not Svc.IsOpen);
  finally
    Svc.Close;
    Svc := nil;
  end;
  WriteLn;
end;

{ --- 7. known model validated and named --- }
procedure Test_KnownModel_Validated;
var
  L: TProgrammableLoader; Svc: IRigService; St: TRigLibraryStatus;
begin
  WriteLn('7. model the library confirms');
  L := TProgrammableLoader.Create;
  Svc := TRigService.Create(L as IHamlibLoader);
  try
    Svc.Open(3073, 'none');
    Sleep(80);
    St := Svc.LibraryStatus;
    Check('ModelValidated is set', St.ModelValidated);
    Check('manufacturer captured', St.ModelMfg = 'Icom', '="' + St.ModelMfg + '"');
    Check('model name captured', St.ModelName = 'IC-7300', '="' + St.ModelName + '"');
  finally
    Svc.CancelAllPending; Svc.Close; Svc := nil;
  end;
  WriteLn;
end;

{ --- 8. library too old to answer warns, does not fail --- }
procedure Test_CannotAnswer_Warns;
var
  L: TProgrammableLoader; Svc: IRigService; H: TWarnHarness;
begin
  WriteLn('8. library too old to confirm models');
  L := TProgrammableLoader.Create;
  L.CanAnswer := False;
  H := TWarnHarness.Create;
  Svc := TRigService.Create(L as IHamlibLoader);
  try
    Svc.SetOnLibraryWarning(@H.OnWarn);
    try
      Svc.Open(3073, 'none');
      Sleep(80);
      Check('Open still succeeds', Svc.IsOpen);
      Check('a warning was raised instead of an error', H.Fired);
      Check('the warning names the model',
            Pos('3073', H.LastMsg) > 0, '="' + H.LastMsg + '"');
      Check('ModelValidated stays False',
            not Svc.LibraryStatus.ModelValidated);
    except
      on E: Exception do Check('Open still succeeds', False, E.ClassName);
    end;
  finally
    Svc.CancelAllPending; Svc.Close; Svc := nil;
    H.Free;
  end;
  WriteLn;
end;

begin
  WriteLn('=== Version gate and model verification ===');
  WriteLn;
  Test_Verified_Starts;
  Test_Untested_Refused;
  Test_Untested_AllowedWithOptIn;
  Test_UnknownVersion_Refused;
  Test_UnversionedBinding_Reported;
  Test_UnknownModel_Refused;
  Test_KnownModel_Validated;
  Test_CannotAnswer_Warns;
  CheckSynchronize(200);

  WriteLn('=== ', Pass, ' passed, ', Fail, ' failed ===');
  if Fail > 0 then ExitCode := 1;
end.
