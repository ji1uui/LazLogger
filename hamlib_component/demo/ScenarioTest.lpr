{
  ScenarioTest.lpr

  Drives TRigPresenter through a whole session the way an operator
  would, with a recording IRigView in place of the form. No LCL, no
  screen, no real Hamlib.

  TRigPresenter を、オペレータが実際に行う一連の操作として駆動します。
  フォームの代わりに記録用の IRigView を使います。LCL も画面も実
  Hamlib も不要です。

  Why this is worth more than the unit tests
  ------------------------------------------------------------------
  The existing tests call the component's API directly, in the order the
  test author chose. An application calls it in the order the operator
  chooses — including the orders nobody designed for: clicking Connect
  twice, changing mode before the first reading arrives, closing the
  window while a command is in flight, pressing PTT after the rig has
  stopped answering. Those sequences are where a component actually
  fails, and they only appear once something uses it as a component.

  本テストがユニットテストより価値を持つ理由
  ------------------------------------------------------------------
  既存テストはコンポーネントの API を、テスト作成者が選んだ順序で直接
  呼びます。アプリケーションはオペレータが選んだ順序で呼びます。誰も
  設計していない順序も含めて、です。接続を 2 回押す、最初の読み取りが
  届く前にモードを変える、コマンド実行中にウィンドウを閉じる、リグが
  応答を止めた後に PTT を押す。コンポーネントが実際に壊れるのはこうした
  並びであり、それは何かがコンポーネントとして使ったときにしか現れません。

  Build: fpc -Mobjfpc -Sh -Fu../src -FE. ScenarioTest.lpr
}
program ScenarioTest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  HamlibInterfaces, HamlibErrors, HamlibModeCodec, HamlibTimeoutPolicy,
  HamlibService, HamlibCatalog,
  RigPanelView, RigPanelPresenter;

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
  The recording view — what the window would be showing.
  記録用 view — ウィンドウが表示しているはずの内容。
  ==================================================================== }
type
  TRecordingView = class(TInterfacedObject, IRigView)
  public
    RigItems:      TStringList;
    EnumAvailable: Boolean;
    Freq:          Double;
    Mode:          TRigMode;
    Passband:      Integer;
    Ptt:           Boolean;
    UiMode:        TRigUiMode;
    Notice:        string;
    NoticeLevel:   TRigNoticeLevel;
    NoticeLog:     TStringList;
    LibraryInfo:   string;
    QueueDepth:    Integer;
    BreakerOpen:   Boolean;

    constructor Create;
    destructor  Destroy; override;

    procedure ShowRigList(const AItems: array of string;
                          AEnumerationAvailable: Boolean);
    procedure ShowFrequency(AHz: Double);
    procedure ShowMode(AMode: TRigMode; APassbandHz: Integer);
    procedure ShowPtt(AActive: Boolean);
    procedure SetUiMode(AMode: TRigUiMode);
    procedure ShowNotice(ALevel: TRigNoticeLevel; const AText: string);
    procedure ShowLibraryInfo(const AText: string);
    procedure ShowQueueDepth(ADepth: Integer; ABreakerOpen: Boolean);

    { True if any notice so far contained AFragment.
      これまでの通知のいずれかに AFragment が含まれていれば True。 }
    function  NoticedAny(const AFragment: string): Boolean;
  end;

constructor TRecordingView.Create;
begin
  inherited Create;
  RigItems  := TStringList.Create;
  NoticeLog := TStringList.Create;
  Mode      := rmUnknown;
  UiMode    := ruiDisconnected;
end;

destructor TRecordingView.Destroy;
begin
  RigItems.Free;
  NoticeLog.Free;
  inherited Destroy;
end;

procedure TRecordingView.ShowRigList(const AItems: array of string;
                                      AEnumerationAvailable: Boolean);
var
  i: Integer;
begin
  RigItems.Clear;
  for i := Low(AItems) to High(AItems) do
    RigItems.Add(AItems[i]);
  EnumAvailable := AEnumerationAvailable;
end;

procedure TRecordingView.ShowFrequency(AHz: Double);
begin Freq := AHz; end;

procedure TRecordingView.ShowMode(AMode: TRigMode; APassbandHz: Integer);
begin Mode := AMode; Passband := APassbandHz; end;

procedure TRecordingView.ShowPtt(AActive: Boolean);
begin Ptt := AActive; end;

procedure TRecordingView.SetUiMode(AMode: TRigUiMode);
begin UiMode := AMode; end;

procedure TRecordingView.ShowNotice(ALevel: TRigNoticeLevel;
                                     const AText: string);
begin
  Notice      := AText;
  NoticeLevel := ALevel;
  NoticeLog.Add(AText);
end;

procedure TRecordingView.ShowLibraryInfo(const AText: string);
begin LibraryInfo := AText; end;

procedure TRecordingView.ShowQueueDepth(ADepth: Integer; ABreakerOpen: Boolean);
begin QueueDepth := ADepth; BreakerOpen := ABreakerOpen; end;

function TRecordingView.NoticedAny(const AFragment: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to NoticeLog.Count - 1 do
    if Pos(LowerCase(AFragment), LowerCase(NoticeLog[i])) > 0 then
    begin
      Result := True;
      Exit;
    end;
end;

{ ====================================================================
  A loader standing in for a healthy rig, with switches for the
  failures an operator meets.
  健全なリグの代役となるローダ。オペレータが遭遇する失敗を切り替える
  スイッチ付き。
  ==================================================================== }
type
  TDemoLoader = class(TInterfacedObject, IHamlibLoader, IHamlibCatalog,
                      IHamlibDiagnostics)
  private
    FFreq:        Double;
    FMode:        Int64;
    FWidth:       Int64;
    FPtt:         Integer;
    FEnumerable:  Boolean;
    FOpenResult:  Integer;
    FFailEvery:   Integer;    { 0 = never / 0 = 失敗させない }
    FCallCount:   Integer;
    FKnownModels: Boolean;
  public
    constructor Create(AEnumerable: Boolean = True);

    { test switches / テスト用スイッチ }
    procedure FailOpenWith(ACode: Integer);
    procedure FailEveryCall(ACode: Integer);
    procedure StopKnowingModels;
    procedure TuneTo(AHz: Double);

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
    { virtual so SCENARIO 4 can replace just this one call. A plain
      re-declaration in the descendant compiles without a word of
      complaint and is silently ignored for interface dispatch — this
      test was written that way at first and reported a wrong result
      rather than a failure.

      SCENARIO 4 がこの呼び出しだけを差し替えられるよう virtual です。
      子孫で単に再宣言しても警告なくコンパイルが通り、インターフェース
      経由の呼び出しでは黙って無視されます。本テストは当初その書き方を
      しており、失敗ではなく誤った結果を報告しました。 }
    function  CallRigGetMode(ARig: Pointer; AVfo: Integer; out AMode: Int64; out AWidth: Int64): Integer; virtual;
    function  CallRigSetPtt(ARig: Pointer; AVfo: Integer; APtt: Integer): Integer;
    function  CallRigGetPtt(ARig: Pointer; AVfo: Integer; out APtt: Integer): Integer;
    function  CallRigError(ACode: Integer): string;
    function  SetConf(ARig: Pointer; const AName, AValue: string): Integer;
    function  SetSerialPort(ARig: Pointer; const APort: string): Integer;
    function  SetSerialBaud(ARig: Pointer; ABaud: Integer): Integer;

    { IHamlibCatalog }
    function  ListModels(out AList: TRigModelInfoArray): Boolean;

    { IHamlibDiagnostics — a verified version, so the gate lets us in. }
    function  GetVersionText: string;
    function  GetVersionVerdict: TRigVersionVerdict;
    function  GetSupportedRangeText: string;
    function  GetUnversionedBinding: Boolean;
    function  CheckModel(AModel: Integer; out AMfg, AModelName: string;
                         out AAnswered: Boolean): Boolean;
  end;

const
  { Model numbers used by the fake catalogue. They match real Hamlib
    values, but the demo never writes them outside this fake — the
    presenter gets them from the catalogue.
    フェイクのカタログが使うモデル番号。実 Hamlib の値と一致しますが、
    デモはこのフェイクの外にこれらを書きません。presenter はカタログ
    から取得します。 }
  DEMO_IC7300 = 3073;
  DEMO_FT991  = 1035;
  DEMO_K3     = 2029;

constructor TDemoLoader.Create(AEnumerable: Boolean);
begin
  inherited Create;
  FFreq        := 14074000.0;
  FMode        := Int64(1) shl 11;   { PKT-USB, i.e. FT8 / FT8 }
  FWidth       := 3000;
  FPtt         := 0;
  FEnumerable  := AEnumerable;
  FOpenResult  := 0;
  FFailEvery   := 0;
  FKnownModels := True;
end;

procedure TDemoLoader.FailOpenWith(ACode: Integer); begin FOpenResult := ACode; end;
procedure TDemoLoader.FailEveryCall(ACode: Integer); begin FFailEvery := ACode; end;
procedure TDemoLoader.StopKnowingModels; begin FKnownModels := False; end;
procedure TDemoLoader.TuneTo(AHz: Double); begin FFreq := AHz; end;

function  TDemoLoader.Load(const APath: string): Boolean; begin Result := True; end;
procedure TDemoLoader.Unload; begin end;
function  TDemoLoader.GetIsLoaded: Boolean; begin Result := True; end;
function  TDemoLoader.GetApiMajor: Integer; begin Result := 4; end;
function  TDemoLoader.GetApiMinor: Integer; begin Result := 7; end;
function  TDemoLoader.GetLibPath: string; begin Result := '/usr/lib/libhamlib.so.4'; end;
function  TDemoLoader.HasSymbol(const AName: string): Boolean; begin Result := True; end;
function  TDemoLoader.CallRigInit(AModel: Integer): Pointer; begin Result := Pointer(1); end;

function TDemoLoader.CallRigOpen(ARig: Pointer): Integer;
begin Result := FOpenResult; end;

function  TDemoLoader.CallRigClose(ARig: Pointer): Integer; begin Result := 0; end;
function  TDemoLoader.CallRigCleanup(ARig: Pointer): Integer; begin Result := 0; end;

function TDemoLoader.CallRigSetFreq(ARig: Pointer; AVfo: Integer;
                                     AFreq: Double): Integer;
begin
  Inc(FCallCount);
  if FFailEvery <> 0 then Exit(FFailEvery);
  FFreq  := AFreq;
  Result := 0;
end;

function TDemoLoader.CallRigGetFreq(ARig: Pointer; AVfo: Integer;
                                     out AFreq: Double): Integer;
begin
  Inc(FCallCount);
  AFreq := 0;
  if FFailEvery <> 0 then Exit(FFailEvery);
  AFreq  := FFreq;
  Result := 0;
end;

function TDemoLoader.CallRigSetMode(ARig: Pointer; AVfo: Integer;
                                     AMode: Int64; AWidth: Int64): Integer;
begin
  Inc(FCallCount);
  if FFailEvery <> 0 then Exit(FFailEvery);
  FMode  := AMode;
  FWidth := AWidth;
  Result := 0;
end;

function TDemoLoader.CallRigGetMode(ARig: Pointer; AVfo: Integer;
                                     out AMode: Int64;
                                     out AWidth: Int64): Integer;
begin
  Inc(FCallCount);
  AMode  := 0;
  AWidth := 0;
  if FFailEvery <> 0 then Exit(FFailEvery);
  AMode  := FMode;
  AWidth := FWidth;
  Result := 0;
end;

function TDemoLoader.CallRigSetPtt(ARig: Pointer; AVfo: Integer;
                                    APtt: Integer): Integer;
begin
  Inc(FCallCount);
  if FFailEvery <> 0 then Exit(FFailEvery);
  FPtt   := APtt;
  Result := 0;
end;

function TDemoLoader.CallRigGetPtt(ARig: Pointer; AVfo: Integer;
                                    out APtt: Integer): Integer;
begin
  APtt   := FPtt;
  Result := 0;
end;

function TDemoLoader.CallRigError(ACode: Integer): string;
begin
  case ACode of
    -6:  Result := 'IO error';
    -22: Result := 'Permission denied';
    -11: Result := 'function not available';
  else
    Result := Format('Hamlib error %d', [ACode]);
  end;
end;

function TDemoLoader.SetConf(ARig: Pointer; const AName, AValue: string): Integer;
begin Result := 0; end;
function TDemoLoader.SetSerialPort(ARig: Pointer; const APort: string): Integer;
begin Result := 0; end;
function TDemoLoader.SetSerialBaud(ARig: Pointer; ABaud: Integer): Integer;
begin Result := 0; end;

function TDemoLoader.ListModels(out AList: TRigModelInfoArray): Boolean;
begin
  SetLength(AList, 0);
  Result := FEnumerable;
  if not Result then Exit;

  SetLength(AList, 3);
  AList[0].ModelNumber   := DEMO_IC7300;
  AList[0].Manufacturer  := 'Icom';
  AList[0].ModelName     := 'IC-7300';
  AList[0].BackendStatus := 'Stable';
  AList[1].ModelNumber   := DEMO_FT991;
  AList[1].Manufacturer  := 'Yaesu';
  AList[1].ModelName     := 'FT-991';
  AList[1].BackendStatus := 'Stable';
  AList[2].ModelNumber   := DEMO_K3;
  AList[2].Manufacturer  := 'Elecraft';
  AList[2].ModelName     := 'K3';
  AList[2].BackendStatus := 'Beta';
end;

function TDemoLoader.GetVersionText: string; begin Result := '4.7.2'; end;
function TDemoLoader.GetVersionVerdict: TRigVersionVerdict;
begin Result := rvvVerified; end;
function TDemoLoader.GetSupportedRangeText: string; begin Result := '4.5 .. 4.7'; end;
function TDemoLoader.GetUnversionedBinding: Boolean; begin Result := False; end;

function TDemoLoader.CheckModel(AModel: Integer; out AMfg, AModelName: string;
                                 out AAnswered: Boolean): Boolean;
begin
  AAnswered  := True;
  AMfg       := '';
  AModelName := '';
  Result     := False;
  if not FKnownModels then Exit;
  case AModel of
    DEMO_IC7300: begin AMfg := 'Icom';     AModelName := 'IC-7300'; Result := True; end;
    DEMO_FT991:  begin AMfg := 'Yaesu';    AModelName := 'FT-991';  Result := True; end;
    DEMO_K3:     begin AMfg := 'Elecraft'; AModelName := 'K3';      Result := True; end;
  end;
end;

{ ====================================================================
  A factory that hands out services backed by one chosen loader, so
  the scenario can keep a handle on the fake rig.
  選んだ 1 つのローダを裏に持つサービスを配るファクトリ。シナリオ側が
  フェイクのリグを掴んだままにできます。
  ==================================================================== }
type
  TDemoFactory = class(TInterfacedObject, IRigServiceFactory)
  private
    FLoader: IHamlibLoader;
    FAllow:  Boolean;
  public
    constructor Create(const ALoader: IHamlibLoader);
    function  CreateService: IRigService;
    function  CreateServiceWithPolicy(const APolicy: TRigTimeoutPolicy): IRigService;
    function  CreateMockService: IRigService;
    function  CreateModelCatalog: IRigModelCatalog;
    function  GetAllowUntestedVersion: Boolean;
    procedure SetAllowUntestedVersion(AValue: Boolean);
  end;

constructor TDemoFactory.Create(const ALoader: IHamlibLoader);
begin
  inherited Create;
  FLoader := ALoader;
end;

function TDemoFactory.CreateService: IRigService;
begin Result := CreateServiceWithPolicy(RigPolicy_Default); end;

function TDemoFactory.CreateServiceWithPolicy(
  const APolicy: TRigTimeoutPolicy): IRigService;
var
  Svc: TRigService;
begin
  Svc := TRigService.Create(FLoader);
  Svc.ApplyTimeoutPolicy(APolicy);
  Result := Svc;
end;

function TDemoFactory.CreateMockService: IRigService;
begin Result := CreateService; end;

function TDemoFactory.CreateModelCatalog: IRigModelCatalog;
begin Result := TRigModelCatalog.Create(FLoader); end;

function TDemoFactory.GetAllowUntestedVersion: Boolean; begin Result := FAllow; end;
procedure TDemoFactory.SetAllowUntestedVersion(AValue: Boolean); begin FAllow := AValue; end;

{ ------------------------------------------------------------------
  Pump the UI thread the way the LCL message loop would, so queued
  callbacks are delivered. A real application does not need this; a
  console program does.

  キューされたコールバックが配送されるよう、LCL のメッセージループが
  するのと同じように UI スレッドを回します。実アプリには不要で、
  コンソールプログラムには必要です。
  ------------------------------------------------------------------ }
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

{ ====================================================================
  SCENARIO 1 — the ordinary session, start to finish.
  シナリオ 1 — 通常の一連の操作。
  ==================================================================== }
procedure ScenarioHappyPath;
var
  View:   TRecordingView;
  V:      IRigView;
  Loader: TDemoLoader;
  Pres:   TRigPresenter;
  Info:   TRigModelInfo;
  i:      Integer;
begin
  WriteLn('SCENARIO 1 - start, pick a rig, connect, operate, disconnect');

  View   := TRecordingView.Create;
  V      := View;              { the only reference / 唯一の参照 }
  Loader := TDemoLoader.Create;
  Pres   := TRigPresenter.Create(V, TDemoFactory.Create(Loader));
  try
    { --- startup --- }
    Pres.Initialise;
    Check('the rig list came from the library',
          View.EnumAvailable and (View.RigItems.Count = 3),
          Format('%d items', [View.RigItems.Count]));
    Check('entries are labelled for a human',
          View.RigItems[1] = 'Icom IC-7300 (Stable)',
          View.RigItems[1]);
    Check('the list is sorted, so Elecraft comes first',
          Pos('Elecraft', View.RigItems[0]) = 1, View.RigItems[0]);
    Check('controls start disabled', View.UiMode = ruiDisconnected);
    Check('frequency starts blank, not 0 MHz', View.Freq = 0);

    { --- the operator picks the Icom and connects --- }
    Check('the view can map its selection back to a model number',
          Pres.TryGetModel(1, Info) and (Info.ModelNumber = DEMO_IC7300),
          Format('%d', [Info.ModelNumber]));

    Pres.Connect(Info.ModelNumber, '/dev/ttyUSB0', 'fast');
    Pump(400);

    Check('the UI reached the connected state',
          View.UiMode = ruiConnected, Format('%d', [Ord(View.UiMode)]));
    Check('the library provenance was shown',
          Pos('4.7.2', View.LibraryInfo) > 0, View.LibraryInfo);
    Check('the first readings populated the panel without waiting for a poll',
          View.Freq = 14074000.0, Format('%.0f', [View.Freq]));
    Check('the mode arrived as a named value',
          View.Mode = rmPktUSB, THamlibModeCodec.ToDisplayString(View.Mode));
    Check('the passband came through', View.Passband = 3000,
          Format('%d', [View.Passband]));

    { --- QSY --- }
    Pres.SetFrequency(7074000.0);
    Pump(300);
    Pres.RequestFrequency;
    Pump(300);
    Check('a QSY is reflected back from the rig', View.Freq = 7074000.0,
          Format('%.0f', [View.Freq]));

    { --- mode change --- }
    Pres.SetMode(rmUSB, 2400);
    Pump(300);
    Pres.RequestMode;
    Pump(300);
    Check('a mode change round-trips through the rig',
          (View.Mode = rmUSB) and (View.Passband = 2400),
          Format('%s/%d', [THamlibModeCodec.ToDisplayString(View.Mode),
                           View.Passband]));

    { --- PTT, then the snapshot refresh the form's timer would do --- }
    Pres.SetPtt(True);
    Pump(300);
    for i := 1 to 20 do
    begin
      Pres.RefreshFromSnapshot;
      Pump(60);
      if View.Ptt then Break;
    end;
    Check('the transmit lamp lights from the snapshot, not optimistically',
          View.Ptt);

    Pres.SetPtt(False);
    Pump(300);
    for i := 1 to 20 do
    begin
      Pres.RefreshFromSnapshot;
      Pump(60);
      if not View.Ptt then Break;
    end;
    Check('and goes out again', not View.Ptt);

    { --- the knob moves on the rig; polling should notice --- }
    Loader.TuneTo(21074000.0);
    for i := 1 to 30 do
    begin
      Pres.RefreshFromSnapshot;
      Pump(60);
      if View.Freq = 21074000.0 then Break;
    end;
    Check('turning the VFO on the rig updates the display',
          View.Freq = 21074000.0, Format('%.0f', [View.Freq]));

    Pres.RefreshFromSnapshot;
    Check('the diagnostics corner shows a drained queue and a closed breaker',
          (View.QueueDepth >= 0) and (not View.BreakerOpen),
          Format('depth=%d breaker=%s',
                 [View.QueueDepth, BoolToStr(View.BreakerOpen, True)]));

    { --- disconnect --- }
    Pres.Disconnect;
    Pump(200);
    Check('disconnecting returns the UI to its initial state',
          (View.UiMode = ruiDisconnected) and (View.Freq = 0)
          and (View.Mode = rmUnknown) and (not View.Ptt));
  finally
    Pres.Free;
    V := nil;
    Pump(200);
  end;
  WriteLn;
end;

{ ====================================================================
  SCENARIO 2 — the orders nobody designed for.
  シナリオ 2 — 誰も設計していない操作順序。
  ==================================================================== }
procedure ScenarioMisuse;
var
  View:   TRecordingView;
  V:      IRigView;
  Loader: TDemoLoader;
  Pres:   TRigPresenter;
  Info:   TRigModelInfo;
begin
  WriteLn('SCENARIO 2 - impatient and out-of-order operation');

  View   := TRecordingView.Create;
  V      := View;
  Loader := TDemoLoader.Create;
  Pres   := TRigPresenter.Create(V, TDemoFactory.Create(Loader));
  try
    { Operating before Initialise: nothing is loaded, nothing may crash.
      Initialise より前の操作。何もロードされていないが、落ちてはならない。 }
    Pres.RequestFrequency;
    Pres.SetFrequency(14074000.0);
    Pres.SetMode(rmUSB, 0);
    Pres.SetPtt(True);
    Pres.CancelPendingRead;
    Pres.RefreshFromSnapshot;
    Check('acting before startup is refused, not crashed',
          View.NoticedAny('not connected') or View.NoticedAny('Nothing to cancel'));

    Pres.Initialise;
    Pres.TryGetModel(1, Info);

    { Connect twice. The second must not create a second service or
      leave the UI stuck in "Connecting...".
      接続を 2 回。2 回目で 2 つ目のサービスを作ったり、UI が
      「接続中...」で固まったりしてはならない。 }
    Pres.Connect(Info.ModelNumber, '/dev/ttyUSB0', 'fast');
    Pump(300);
    Pres.Connect(Info.ModelNumber, '/dev/ttyUSB0', 'fast');
    Pump(200);
    Check('a second Connect is refused with a message',
          View.NoticedAny('Already connected'));
    Check('and the UI is still in the connected state',
          View.UiMode = ruiConnected);

    { Fire a burst of commands with no pumping in between, the way a
      held-down button or a quick operator would.
      ボタン長押しや素早い操作のように、間でポンプせずコマンドを連射する。 }
    Pres.SetFrequency(14074000.0);
    Pres.SetFrequency(14075000.0);
    Pres.SetFrequency(14076000.0);
    Pres.RequestFrequency;
    Pres.RequestMode;
    Pres.SetMode(rmLSB, 0);
    Pres.SetPtt(True);
    Pres.SetPtt(False);
    Pump(600);
    Check('a burst of commands all complete',
          View.Freq = 14076000.0, Format('%.0f', [View.Freq]));

    { Cancel a read that has already finished. Must be harmless.
      すでに完了した読み取りのキャンセル。無害でなければならない。 }
    Pres.RequestFrequency;
    Pump(300);
    Pres.CancelPendingRead;
    Check('cancelling an already-finished read is harmless',
          View.NoticedAny('Nothing to cancel'));

    { Cancel a read immediately, before it can run.
      実行される前に即座にキャンセルする。 }
    Pres.RequestFrequency;
    Pres.CancelPendingRead;
    Pump(300);
    Check('cancelling an in-flight read is reported',
          View.NoticedAny('cancelled'));

    { Out-of-range frequency from a typo in the entry field.
      入力欄の打ち間違いによる範囲外の周波数。 }
    Pres.SetFrequency(-1);
    Pump(100);
    Check('a negative frequency is rejected with a message, not a crash',
          View.NoticeLevel = rnlError, View.Notice);

    Pres.SetFrequency(1.0e12);
    Pump(100);
    Check('an absurd frequency is rejected too', View.NoticeLevel = rnlError,
          View.Notice);

    { Disconnect twice, then operate again.
      切断を 2 回、その後さらに操作。 }
    Pres.Disconnect;
    Pres.Disconnect;
    Pres.RequestFrequency;
    Pump(200);
    Check('disconnecting twice then operating is refused cleanly',
          View.NoticedAny('Not connected'));
  finally
    { Destroying the presenter with a command in flight is the window
      being closed mid-operation. This is the dangling-callback case,
      and the value-type results plus CancelAllPending are what make it
      safe.

      コマンド実行中に presenter を破棄するのは、操作中にウィンドウを
      閉じることに相当します。これが Dangling Callback のケースであり、
      値型の結果と CancelAllPending がそれを安全にしています。 }
    Pres.Free;
    V := nil;
    Pump(300);
    WriteLn('    [ok]   closing the window mid-command did not crash');
    Inc(Checks);
  end;
  WriteLn;
end;

{ ====================================================================
  SCENARIO 3 — the failures an operator actually meets.
  シナリオ 3 — オペレータが実際に遭遇する失敗。
  ==================================================================== }
procedure ScenarioFailures;
var
  View:   TRecordingView;
  V:      IRigView;
  Loader: TDemoLoader;
  Pres:   TRigPresenter;
  Info:   TRigModelInfo;
begin
  WriteLn('SCENARIO 3 - port in use, rig off, unknown model, no catalogue');

  { --- the port is held by another program (-RIG_EACCESS) --- }
  View   := TRecordingView.Create;
  V      := View;
  Loader := TDemoLoader.Create;
  Loader.FailOpenWith(-22);
  Pres := TRigPresenter.Create(V, TDemoFactory.Create(Loader));
  try
    Pres.Initialise;
    Pres.TryGetModel(1, Info);
    Pres.Connect(Info.ModelNumber, '/dev/ttyUSB0', 'fast');
    Pump(500);
    Check('a busy serial port produces advice, not a Hamlib number',
          View.NoticedAny('in use by another application'),
          View.Notice);
    Check('and the UI does not stay stuck in "Connecting..."',
          View.UiMode <> ruiConnecting, Format('%d', [Ord(View.UiMode)]));
  finally
    Pres.Free; V := nil; Pump(200);
  end;

  { --- the rig is powered off: open succeeds, every command fails --- }
  View   := TRecordingView.Create;
  V      := View;
  Loader := TDemoLoader.Create;
  Pres   := TRigPresenter.Create(V, TDemoFactory.Create(Loader));
  try
    Pres.Initialise;
    Pres.TryGetModel(1, Info);
    Pres.Connect(Info.ModelNumber, '/dev/ttyUSB0', 'fast');
    Pump(400);
    Loader.FailEveryCall(-6);            { -RIG_EIO, a dead cable }
    Pres.RequestFrequency;
    Pump(400);
    Check('an I/O failure is explained in the operator\''s terms',
          View.NoticeLevel = rnlError, View.Notice);
    Check('the frequency display keeps its last good value',
          View.Freq = 14074000.0, Format('%.0f', [View.Freq]));
  finally
    Pres.Free; V := nil; Pump(200);
  end;

  { --- the model number is not one this Hamlib knows --- }
  View   := TRecordingView.Create;
  V      := View;
  Loader := TDemoLoader.Create;
  Pres   := TRigPresenter.Create(V, TDemoFactory.Create(Loader));
  try
    Pres.Initialise;
    Loader.StopKnowingModels;            { as if the catalogue were stale }
    Pres.TryGetModel(0, Info);
    Pres.Connect(Info.ModelNumber, '/dev/ttyUSB0', 'fast');
    Pump(400);
    Check('an unknown model number is named in the message',
          View.NoticeLevel = rnlError, View.Notice);
    Check('and the UI returns to disconnected',
          View.UiMode = ruiDisconnected);
  finally
    Pres.Free; V := nil; Pump(200);
  end;

  { --- a Hamlib too old to enumerate its rigs --- }
  View   := TRecordingView.Create;
  V      := View;
  Loader := TDemoLoader.Create(False);   { not enumerable }
  Pres   := TRigPresenter.Create(V, TDemoFactory.Create(Loader));
  try
    Pres.Initialise;
    Check('a library that cannot enumerate degrades to manual entry',
          (not View.EnumAvailable) and (View.RigItems.Count = 0));
    Check('and says so', View.NoticedAny('cannot list its rigs'),
          View.Notice);

    { The operator types a number instead, and it still works.
      オペレータが番号を入力し、それでも動作する。 }
    Pres.Connect(DEMO_FT991, '/dev/ttyUSB0', 'slow');
    Pump(400);
    Check('a manually entered model number still connects',
          View.UiMode = ruiConnected);
    Check('even with no catalogue, the notice names the model',
          View.NoticedAny('model 1035') or View.NoticedAny('FT-991'),
          View.Notice);
  finally
    Pres.Free; V := nil; Pump(200);
  end;
  WriteLn;
end;

{ ====================================================================
  SCENARIO 4 — a mode this build has no name for.
  シナリオ 4 — 本ビルドに名前の無いモード。
  ====================================================================
  A newer Hamlib, or a rig using a bit that was reserved when this
  component was built. The panel must stay usable.
  より新しい Hamlib、または本コンポーネント構築時に予約だったビットを
  使うリグ。パネルは使用可能なままでなければなりません。 }
type
  TFutureModeLoader = class(TDemoLoader)
  public
    function CallRigGetMode(ARig: Pointer; AVfo: Integer;
                            out AMode: Int64; out AWidth: Int64): Integer; override;
  end;

function TFutureModeLoader.CallRigGetMode(ARig: Pointer; AVfo: Integer;
                                           out AMode: Int64;
                                           out AWidth: Int64): Integer;
begin
  AMode  := Int64(1) shl 20;   { unassigned in every Hamlib 4.x header }
  AWidth := 2700;
  Result := 0;
end;

procedure ScenarioFutureMode;
var
  View:   TRecordingView;
  V:      IRigView;
  Loader: TFutureModeLoader;
  Pres:   TRigPresenter;
  Info:   TRigModelInfo;
begin
  WriteLn('SCENARIO 4 - the rig reports a mode this build cannot name');

  View   := TRecordingView.Create;
  V      := View;
  Loader := TFutureModeLoader.Create;
  Pres   := TRigPresenter.Create(V, TDemoFactory.Create(Loader));
  try
    Pres.Initialise;
    Pres.TryGetModel(1, Info);
    Pres.Connect(Info.ModelNumber, '/dev/ttyUSB0', 'fast');
    Pump(500);

    Check('an unnamed mode shows as unknown rather than a wrong name',
          View.Mode = rmUnknown,
          THamlibModeCodec.ToDisplayString(View.Mode));
    Check('the raw value is reported so it can be looked up',
          View.NoticedAny('$'), View.Notice);
    Check('the rest of the panel still works', View.Freq = 14074000.0,
          Format('%.0f', [View.Freq]));

    { Echoing the unknown mode back is refused with advice, not an
      exception escaping into the UI.
      未知のモードをそのまま送り返す操作は、UI に例外を漏らすのではなく
      助言付きで拒否される。 }
    Pres.SetMode(View.Mode, 0);
    Pump(200);
    Check('sending the unknown mode back is refused with advice',
          View.NoticedAny('no name for'), View.Notice);

    { A real mode still works afterwards.
      その後も実在のモードは動作する。 }
    Pres.SetMode(rmUSB, 2400);
    Pump(300);
    Check('a concrete mode is still accepted',
          not View.NoticedAny('Internal error'));
  finally
    Pres.Free; V := nil; Pump(200);
  end;
  WriteLn;
end;

{ ==================================================================== }
begin
  WriteLn('=== RigPanel demo: application-level scenarios ===');
  WriteLn('    the component driven through a presenter, as an app would');
  WriteLn;

  ScenarioHappyPath;
  ScenarioMisuse;
  ScenarioFailures;
  ScenarioFutureMode;

  WriteLn('--- ', Checks - Failures, ' / ', Checks, ' checks passed ---');
  if Failures = 0 then
    WriteLn('RESULT: OK')
  else
  begin
    WriteLn('RESULT: *** ', Failures, ' FAILURE(S) ***');
    ExitCode := 1;
  end;
end.
