{
  RigPanelPresenter.pas

  TRigPresenter — all of the RigPanel demo's behaviour, with no LCL
  dependency. This is the unit worth reading to see how the component is
  meant to be used from an application.

  TRigPresenter - RigPanel デモの振る舞いのすべて。LCL に依存しません。
  コンポーネントをアプリケーションからどう使うかを見るには、本ユニットを
  読むのが最短です。

  What it demonstrates / 何を示すか
  ------------------------------------------------------------------
    - building the rig list from the library instead of hard-coding
      RIG_MODEL_* constants
    - Open / Close with the version gate and model verification active
    - every async call with and without a callback (callback = nil
      routes errors to OnError)
    - branching on TRigErrorKind, never on a raw Hamlib number
    - TRigMode as a value, with rmUnknown handled rather than ignored
    - the Pull-model snapshot used for a periodic UI refresh, alongside
      the Push-model events
    - cancellation of an in-flight command
    - ordered teardown, and what happens if the application forgets it

    - RIG_MODEL_* 定数をハードコードせず、ライブラリから機種一覧を作る
    - バージョンゲートとモデル検証が働いた状態での Open / Close
    - コールバックあり・なしの両方の非同期呼び出し
      (callback = nil はエラーを OnError へ経路設定)
    - 生の Hamlib 数値ではなく TRigErrorKind で分岐する
    - TRigMode を値として扱い、rmUnknown を無視せず処理する
    - Push モデルのイベントと並行して、Pull モデルのスナップショットを
      定期的な UI 更新に使う
    - 実行中コマンドのキャンセル
    - 順序を守った終了処理と、アプリが忘れた場合に何が起きるか

  Threading / スレッド
  ------------------------------------------------------------------
  Every method here runs on the UI thread. The component guarantees
  that: callbacks and events arrive via TThread.Queue, and the presenter
  never touches a worker thread itself. That is why no lock appears in
  this unit.

  本ユニットの全メソッドは UI スレッドで動きます。コンポーネントがそれを
  保証します。コールバックとイベントは TThread.Queue 経由で届き、
  presenter 自身がワーカースレッドに触れることはありません。だから本
  ユニットにロックは 1 つも出てきません。

  Layer:    demo (application)
  Depends:  HamlibInterfaces, HamlibErrors, HamlibModeCodec, HamlibCatalog,
            HamlibTimeoutPolicy, HamlibFactory, RigPanelView
}
unit RigPanelPresenter;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, StrUtils,
  HamlibInterfaces, HamlibErrors, HamlibModeCodec, HamlibCatalog,
  HamlibTimeoutPolicy, HamlibFactory,
  RigPanelView;

type
  TRigPresenter = class
  private
    FView:     IRigView;
    FFactory:  IRigServiceFactory;
    FService:  IRigService;
    FCatalog:  IRigModelCatalog;

    { The one command token the panel keeps, so a slow read can be
      abandoned. Held as an interface, so it is released automatically.
      パネルが保持する唯一のコマンドトークン。遅い読み取りを中断できる
      ようにします。インターフェースで保持するため自動解放されます。 }
    FPendingRead: ICancellationToken;

    { Last values shown, so a refresh does not blank the display when
      the snapshot has not been updated yet.
      最後に表示した値。スナップショットが未更新のときに表示を空に
      しないためです。 }
    FLastFreq: Double;
    FLastMode: TRigMode;

    { What the panel is currently showing. OnConnectionChanged carries
      only a Boolean, so "the attempt failed" and "the established link
      dropped" look identical from the component's side. The application
      knows which it asked for, and that is enough to word the message
      correctly — richer event arguments would be a bigger API for
      information the caller already has.

      パネルが現在表示している状態。OnConnectionChanged は Boolean 1 つ
      しか運ばないため、「試行が失敗した」と「確立済みリンクが切れた」は
      コンポーネント側からは同じに見えます。どちらを依頼したかはアプリ
      が知っており、メッセージを正しく書くにはそれで足ります。イベント
      引数を増やすのは、呼び出し側が既に持つ情報のために API を大きく
      することです。 }
    FUiMode:   TRigUiMode;

    { ---- component callbacks and events / コンポーネントのコールバックとイベント ---- }
    procedure HandleSetDone(const AResult: TRigResult);
    procedure HandleFreqRead(const AResult: TRigFreqResult);
    procedure HandleModeRead(const AResult: TRigModeResult);
    procedure HandleConnectionChanged(Sender: TObject; AConnected: Boolean);
    procedure HandleFrequencyChanged(Sender: TObject; AFreq: Double);
    procedure HandleError(Sender: TObject; AKind: TRigErrorKind;
                          ANativeCode: Integer; const AMsg: string);
    procedure HandleLibraryWarning(Sender: TObject;
                                   const AStatus: TRigLibraryStatus;
                                   const AMessage: string);

    { Turn a failure into one sentence an operator can act on. The point
      of TRigErrorKind is that this function can exist at all.
      失敗を、オペレータが行動できる 1 文にします。TRigErrorKind の意義は
      この関数が成立すること自体にあります。 }
    function  AdviceFor(AKind: TRigErrorKind; const AMsg: string): string;

    { One line naming the library actually in use. rig_version() already
      begins with "Hamlib" and carries a build date and git hash, so
      formatting it as 'Hamlib %s' produced "Hamlib Hamlib 4.5.5 Apr 05
      ... SHA=6eecd3" and overflowed the label. Running the program is
      what showed that; it reads fine in a debugger.

      実際に使用中のライブラリを示す 1 行。rig_version() は既に "Hamlib"
      で始まり、ビルド日時と git ハッシュを含みます。そのため
      'Hamlib %s' と整形すると "Hamlib Hamlib 4.5.5 Apr 05 ... SHA=6eecd3"
      になりラベルから溢れました。これはプログラムを実行して初めて
      分かることで、デバッガ上では問題なく読めます。 }
    function  DescribeLibrary(const AVersion, APath, ARange: string): string;
  public
    { AView is required; AFactory may be nil, in which case the real
      TRigServiceFactory is used. Tests pass their own factory.
      AView は必須です。AFactory が nil のときは実物の
      TRigServiceFactory を使います。テストは独自のファクトリを渡します。 }
    constructor Create(const AView: IRigView;
                       const AFactory: IRigServiceFactory = nil);
    destructor  Destroy; override;

    { ---- called by the view, one per user action ----
      ---- view から呼ばれる。ユーザ操作 1 つにつき 1 メソッド ---- }

    { Load the library and populate the rig list. Separate from Connect
      because an operator expects to see the rig list before choosing a
      serial port.
      ライブラリをロードし機種一覧を埋めます。オペレータはシリアル
      ポートを選ぶ前に機種一覧を見たいので、Connect とは分けます。 }
    procedure Initialise;

    { AModelNumber comes from the catalogue entry the operator picked,
      or from the fallback entry field.
      AModelNumber はオペレータが選んだカタログ項目、またはフォール
      バックの入力欄から来ます。 }
    procedure Connect(AModelNumber: Integer; const APort: string;
                      const APolicyName: string);
    procedure Disconnect;

    procedure RequestFrequency;
    procedure RequestMode;
    procedure SetFrequency(AHz: Double);
    procedure SetMode(AMode: TRigMode; APassbandHz: Integer);
    procedure SetPtt(AActive: Boolean);
    procedure CancelPendingRead;

    { Called from the view's timer. Reads the snapshot — no I/O, no
      waiting — and refreshes the parts of the UI that the push events
      do not cover.
      view のタイマから呼ばれます。スナップショットを読むだけで I/O も
      待機もありません。push イベントが覆わない部分を更新します。 }
    procedure RefreshFromSnapshot;

    { Catalogue entry by list index, for the view's selection handler.
      Returns False when the index is not valid.
      一覧の添字からカタログ項目を取得します。添字が無効なら False。 }
    function  TryGetModel(AIndex: Integer; out AInfo: TRigModelInfo): Boolean;

    property Catalog: IRigModelCatalog read FCatalog;
  end;

implementation

{ ------------------------------------------------------------------
  Construction / 構築
  ------------------------------------------------------------------ }

constructor TRigPresenter.Create(const AView: IRigView;
                                  const AFactory: IRigServiceFactory);
begin
  inherited Create;
  Assert(Assigned(AView), 'AView must not be nil');
  FView     := AView;
  FFactory  := AFactory;
  FLastFreq := 0;
  FLastMode := rmUnknown;
  FUiMode   := ruiDisconnected;
  if not Assigned(FFactory) then
    FFactory := TRigServiceFactory.Create;
end;

destructor TRigPresenter.Destroy;
begin
  { Order matters, and this is the order an application should copy.
    CancelAllPending first, so no callback can arrive into a presenter
    that is being destroyed; then Close; then release the reference.
    The component's destructor does all of this as a fail-safe, but
    doing it here means the window closes immediately instead of
    waiting for the last callback.

    順序が重要で、アプリケーションはこの順序を踏襲すべきです。まず
    CancelAllPending により、破棄中の presenter にコールバックが届かない
    ようにします。次に Close、最後に参照を解放します。コンポーネントの
    デストラクタもフェイルセーフとして同じことをしますが、ここで行うと
    最後のコールバックを待たずにウィンドウが閉じます。 }
  if Assigned(FService) then
  begin
    FService.DisablePolling;
    FService.CancelAllPending;
    FService.Close;
  end;
  FPendingRead := nil;
  FService     := nil;
  FCatalog     := nil;
  FFactory     := nil;
  FView        := nil;
  inherited Destroy;
end;

{ ------------------------------------------------------------------
  Initialise — load the library, build the rig list
  Initialise - ライブラリをロードし機種一覧を構築
  ------------------------------------------------------------------ }

procedure TRigPresenter.Initialise;
var
  Items: array of string;
  i:     Integer;
begin
  SetLength(Items, 0);
  try
    FCatalog := FFactory.CreateModelCatalog;
  except
    { The version gate fires here, before any serial port is touched.
      An application that wants to run on a newer Hamlib anyway sets
      AllowUntestedVersion and calls Initialise again; this demo simply
      reports it, because silently proceeding is what the gate exists
      to prevent.

      バージョンゲートはここで、シリアルポートに触れる前に発火します。
      新しい Hamlib でも動かしたいアプリは AllowUntestedVersion を
      設定して再度 Initialise を呼びます。本デモは報告するだけに
      します。黙って進むことこそ、ゲートが防ぐために存在するものだ
      からです。 }
    on E: EHamlibUnsupportedVersion do
    begin
      FView.ShowNotice(rnlError, E.Message);
      FView.ShowRigList(Items, False);
      FUiMode := ruiDisconnected;
      FView.SetUiMode(ruiDisconnected);
      Exit;
    end;
    on E: EHamlibLoadError do
    begin
      FView.ShowNotice(rnlError,
        'Hamlib could not be loaded: ' + E.Message);
      FView.ShowRigList(Items, False);
      FUiMode := ruiDisconnected;
      FView.SetUiMode(ruiDisconnected);
      Exit;
    end;
  end;

  if FCatalog.IsAvailable then
  begin
    SetLength(Items, FCatalog.Count);
    for i := 0 to FCatalog.Count - 1 do
      Items[i] := RigModelInfoToString(FCatalog.Items[i]);
    FView.ShowRigList(Items, True);
    FView.ShowNotice(rnlInfo,
      Format('%d rigs available', [FCatalog.Count]));
  end
  else
  begin
    { Degraded, not broken: the operator types a model number instead.
      壊れたのではなく機能低下です。オペレータが機種番号を入力します。 }
    FView.ShowRigList(Items, False);
    FView.ShowNotice(rnlWarning,
      'This Hamlib build cannot list its rigs; enter a model number ' +
      'from "rigctl --list"');
  end;

  FUiMode := ruiDisconnected;
  FView.SetUiMode(ruiDisconnected);
  FView.ShowFrequency(0);
  FView.ShowMode(rmUnknown, 0);
  FView.ShowPtt(False);
end;

function TRigPresenter.TryGetModel(AIndex: Integer;
                                    out AInfo: TRigModelInfo): Boolean;
begin
  Result := False;
  AInfo.ModelNumber   := 0;
  AInfo.Manufacturer  := '';
  AInfo.ModelName     := '';
  AInfo.BackendStatus := '';
  if not Assigned(FCatalog) then Exit;
  if (AIndex < 0) or (AIndex >= FCatalog.Count) then Exit;
  AInfo  := FCatalog.Items[AIndex];
  Result := True;
end;

{ ------------------------------------------------------------------
  Connect / Disconnect
  ------------------------------------------------------------------ }

procedure TRigPresenter.Connect(AModelNumber: Integer; const APort: string;
                                 const APolicyName: string);
var
  Policy: TRigTimeoutPolicy;
  Info:   TRigModelInfo;
begin
  if Assigned(FService) and FService.IsOpen then
  begin
    FView.ShowNotice(rnlWarning, 'Already connected');
    Exit;
  end;

  { Pick the timing profile by rig family. A modern USB rig and a 1990s
    CAT radio need different budgets, and getting this wrong shows up as
    spurious timeouts rather than as an obvious failure.

    機種ファミリごとにタイミングプロファイルを選びます。現代の USB 機と
    1990 年代の CAT 機では必要な予算が違い、誤ると明確な失敗ではなく
    偽のタイムアウトとして現れます。 }
  if SameText(APolicyName, 'slow') then
    Policy := RigPolicy_SlowCat
  else if SameText(APolicyName, 'veryslow') then
    Policy := RigPolicy_VerySlowCat
  else if SameText(APolicyName, 'fast') then
    Policy := RigPolicy_FastUsb
  else
    Policy := RigPolicy_Default;

  FUiMode := ruiConnecting;
  FView.SetUiMode(ruiConnecting);
  FView.ShowNotice(rnlInfo, 'Connecting...');

  try
    FService := FFactory.CreateServiceWithPolicy(Policy);

    { Handlers are installed before Open, so a failure during the
      connection attempt is reported through the same path as any later
      error.
      ハンドラは Open の前に設定します。接続試行中の失敗も、以降の
      エラーと同じ経路で報告されるようにするためです。 }
    FService.SetOnConnectionChanged(@HandleConnectionChanged);
    FService.SetOnFrequencyChanged(@HandleFrequencyChanged);
    FService.SetOnError(@HandleError);
    FService.SetOnLibraryWarning(@HandleLibraryWarning);

    FService.Open(AModelNumber, APort);
  except
    on E: ERigModelUnknown do
    begin
      FService := nil;
      FUiMode  := ruiDisconnected;
      FView.SetUiMode(ruiDisconnected);
      FView.ShowNotice(rnlError, E.Message);
      Exit;
    end;
    on E: EHamlibUnsupportedVersion do
    begin
      FService := nil;
      FUiMode  := ruiDisconnected;
      FView.SetUiMode(ruiDisconnected);
      FView.ShowNotice(rnlError, E.Message);
      Exit;
    end;
    on E: EArgumentException do
    begin
      FService := nil;
      FUiMode  := ruiDisconnected;
      FView.SetUiMode(ruiDisconnected);
      FView.ShowNotice(rnlError, E.Message);
      Exit;
    end;
    on E: Exception do
    begin
      FService := nil;
      FUiMode  := ruiDisconnected;
      FView.SetUiMode(ruiDisconnected);
      FView.ShowNotice(rnlError,
        Format('Could not open the rig: %s', [E.Message]));
      Exit;
    end;
  end;

  { Where the library came from is worth showing once: on Windows the
    wrong DLL on the PATH is a common and confusing failure.
    ライブラリの出自は 1 度表示する価値があります。Windows では PATH 上の
    誤った DLL が、よくある分かりにくい失敗の原因です。 }
  with FService.LibraryStatus do
    FView.ShowLibraryInfo(DescribeLibrary(VersionText, LibPath,
                                          SupportedRange));

  if Assigned(FCatalog) and FCatalog.FindByNumber(AModelNumber, Info) then
    FView.ShowNotice(rnlInfo,
      Format('Opening %s %s on %s',
             [Info.Manufacturer, Info.ModelName, APort]))
  else
    FView.ShowNotice(rnlInfo,
      Format('Opening model %d on %s', [AModelNumber, APort]));

  { Polling gives a frequency display that follows the operator turning
    the VFO knob. 250 ms is slow enough for a CAT rig and fast enough to
    feel live.
    ポーリングにより、オペレータが VFO を回したときに追従する周波数表示に
    なります。250ms は CAT 機に十分遅く、かつ追従を感じられる速さです。 }
  FService.EnablePolling(250);
end;

procedure TRigPresenter.Disconnect;
begin
  if not Assigned(FService) then Exit;

  FService.DisablePolling;
  FService.CancelAllPending;
  FService.Close;
  FService     := nil;
  FPendingRead := nil;

  FLastFreq := 0;
  FLastMode := rmUnknown;
  FUiMode   := ruiDisconnected;

  FView.SetUiMode(ruiDisconnected);
  FView.ShowFrequency(0);
  FView.ShowMode(rmUnknown, 0);
  FView.ShowPtt(False);
  FView.ShowQueueDepth(0, False);
  FView.ShowNotice(rnlInfo, 'Disconnected');
end;

{ ------------------------------------------------------------------
  Operator actions / オペレータ操作
  ------------------------------------------------------------------
  Each one is guarded the same way. The component raises
  ERigServiceClosed if called while closed — including in release
  builds — so the guard here is for the message, not for safety.

  いずれも同じ形で保護します。閉じている状態で呼ぶとコンポーネントが
  ERigServiceClosed を発生させます (リリースビルドでも)。したがって
  ここのガードは安全のためではなくメッセージのためです。 }

procedure TRigPresenter.RequestFrequency;
begin
  if not (Assigned(FService) and FService.IsOpen) then
  begin
    FView.ShowNotice(rnlWarning, 'Not connected');
    Exit;
  end;
  { Keep the token: a rig that has stopped answering leaves this command
    in the queue, and the operator can abandon it.
    トークンを保持します。応答を止めたリグではこのコマンドがキューに
    残り、オペレータが中断できます。 }
  FPendingRead := FService.GetFrequencyAsync(rvfoCurr, @HandleFreqRead);
end;

procedure TRigPresenter.RequestMode;
begin
  if not (Assigned(FService) and FService.IsOpen) then
  begin
    FView.ShowNotice(rnlWarning, 'Not connected');
    Exit;
  end;
  FService.GetModeAsync(rvfoCurr, @HandleModeRead);
end;

procedure TRigPresenter.SetFrequency(AHz: Double);
begin
  if not (Assigned(FService) and FService.IsOpen) then
  begin
    FView.ShowNotice(rnlWarning, 'Not connected');
    Exit;
  end;

  { Argument validation belongs to the component: it raises
    EArgumentException for a frequency outside the sane range, in
    release builds too. The demo catches it so a typo in the entry
    field does not look like a crash.

    引数の検査はコンポーネントの責務です。常識的な範囲外の周波数には
    リリースビルドでも EArgumentException を発生させます。デモ側で
    捕まえるのは、入力欄の打ち間違いがクラッシュに見えないようにする
    ためです。 }
  try
    FService.SetFrequencyAsync(AHz, rvfoCurr, @HandleSetDone);
  except
    on E: EArgumentException do
      FView.ShowNotice(rnlError, E.Message);
  end;
end;

procedure TRigPresenter.SetMode(AMode: TRigMode; APassbandHz: Integer);
begin
  if not (Assigned(FService) and FService.IsOpen) then
  begin
    FView.ShowNotice(rnlWarning, 'Not connected');
    Exit;
  end;

  { rmUnknown reaches here if the operator's mode box still shows a mode
    the rig reported that this binding cannot name. Sending it is
    meaningless, so say so rather than letting the component raise.

    リグが報告した「本バインディングが名前を付けられないモード」が
    モード欄に残っている場合、rmUnknown がここに来ます。送っても
    無意味なので、コンポーネントに例外を出させる前に伝えます。 }
  if AMode = rmUnknown then
  begin
    FView.ShowNotice(rnlWarning,
      'The current mode is one this build has no name for; pick a mode ' +
      'from the list to change it');
    Exit;
  end;

  try
    FService.SetModeAsync(AMode, APassbandHz, rvfoCurr, @HandleSetDone);
  except
    on E: EArgumentException do
      FView.ShowNotice(rnlError, E.Message);
  end;
end;

procedure TRigPresenter.SetPtt(AActive: Boolean);
var
  State: TRigPttState;
begin
  if not (Assigned(FService) and FService.IsOpen) then
  begin
    FView.ShowNotice(rnlWarning, 'Not connected');
    Exit;
  end;

  if AActive then
    State := rpttOn
  else
    State := rpttOff;

  { No callback: a PTT failure is exactly the case where routing to
    OnError is what you want, because the operator must be told
    regardless of which control they touched.
    コールバックなし。PTT の失敗はまさに OnError 経路が欲しい場面です。
    どのコントロールを触ったかに関わらずオペレータに伝える必要がある
    からです。 }
  FService.SetPttAsync(State);

  { Optimistic UI is wrong here. The indicator is driven by the snapshot
    (RefreshFromSnapshot), which only changes after the rig accepts the
    command, so the lamp means "the rig is transmitting", not "we asked".

    ここで楽観的 UI 更新をするのは誤りです。インジケータはスナップ
    ショット (RefreshFromSnapshot) が駆動し、それはリグがコマンドを
    受理した後にのみ変化します。したがってランプは「依頼した」ではなく
    「リグが送信中」を意味します。 }
end;

procedure TRigPresenter.CancelPendingRead;
begin
  if not Assigned(FPendingRead) then
  begin
    FView.ShowNotice(rnlInfo, 'Nothing to cancel');
    Exit;
  end;
  FPendingRead.Cancel;
  FPendingRead := nil;
  FView.ShowNotice(rnlInfo, 'Read cancelled');
end;

{ ------------------------------------------------------------------
  Periodic refresh from the Pull-model snapshot
  Pull モデルのスナップショットによる定期更新
  ------------------------------------------------------------------ }

procedure TRigPresenter.RefreshFromSnapshot;
var
  S: TRigState;
begin
  if not (Assigned(FService) and FService.IsOpen) then Exit;

  { One lock-free read of a consistent copy. Reading each field through
    a separate call could mix values from two different polls.
    一貫したコピーをロックなしで 1 回読みます。フィールドごとに別の
    呼び出しで読むと、2 回のポーリングの値が混ざり得ます。 }
  S := FService.CurrentState;

  if S.Timestamp = 0 then Exit;   { nothing collected yet / 未収集 }

  { CurrentFreq, not VfoAFreq: the poller reports the selected VFO's
    frequency, whichever VFO that is. This panel is a single-VFO panel,
    so "the frequency" is exactly what it wants to show — and it is
    now showing the field that actually means that.
    VfoAFreq ではなく CurrentFreq です。ポーラは選択中の VFO の周波数を
    報告します。本パネルは単一 VFO のパネルであり、表示したいのはまさに
    「その周波数」です。そして今、それを実際に意味するフィールドを見て
    います。 }
  if S.CurrentFreq > 0 then
  begin
    FLastFreq := S.CurrentFreq;
    FView.ShowFrequency(S.CurrentFreq);
  end;

  if (S.Mode <> rmUnknown) or (S.RawMode <> 0) then
  begin
    FLastMode := S.Mode;
    FView.ShowMode(S.Mode, S.Passband);
  end;

  FView.ShowPtt(S.PttActive);
  FView.ShowQueueDepth(FService.QueueDepth, FService.CircuitBreakerOpen);
end;

{ ------------------------------------------------------------------
  Component callbacks / コンポーネントのコールバック
  ------------------------------------------------------------------ }

procedure TRigPresenter.HandleSetDone(const AResult: TRigResult);
begin
  case AResult.Status of
    rcsSuccess:
      FView.ShowNotice(rnlInfo, 'Done');
    rcsCancelled:
      FView.ShowNotice(rnlInfo, 'Cancelled');
  else
    FView.ShowNotice(rnlError,
      AdviceFor(AResult.Error, AResult.ErrorMsg));
  end;
end;

procedure TRigPresenter.HandleFreqRead(const AResult: TRigFreqResult);
begin
  FPendingRead := nil;   { the command is finished / コマンド完了 }

  if AResult.Status <> rcsSuccess then
  begin
    if AResult.Status <> rcsCancelled then
      FView.ShowNotice(rnlError,
        AdviceFor(AResult.Error, AResult.ErrorMsg));
    Exit;
  end;

  FLastFreq := AResult.Freq;
  FView.ShowFrequency(AResult.Freq);
end;

procedure TRigPresenter.HandleModeRead(const AResult: TRigModeResult);
begin
  if AResult.Status <> rcsSuccess then
  begin
    if AResult.Status <> rcsCancelled then
      FView.ShowNotice(rnlError,
        AdviceFor(AResult.Error, AResult.ErrorMsg));
    Exit;
  end;

  FLastMode := AResult.Mode;
  FView.ShowMode(AResult.Mode, AResult.Passband);

  { An unnamed mode is not an error, and the raw value is still useful:
    showing it lets an operator report "my rig says $100000" instead of
    "it says ---".
    名前の無いモードはエラーではなく、生値は依然有用です。表示すれば
    オペレータは「--- と出る」ではなく「$100000 と出る」と報告できます。 }
  if AResult.Mode = rmUnknown then
    FView.ShowNotice(rnlWarning,
      Format('The rig reports a mode this build has no name for (%s)',
             [THamlibModeCodec.FormatRaw(AResult.RawMode)]));
end;

procedure TRigPresenter.HandleConnectionChanged(Sender: TObject;
                                                 AConnected: Boolean);
begin
  if AConnected then
  begin
    FUiMode := ruiConnected;
    FView.SetUiMode(ruiConnected);
    FView.ShowNotice(rnlInfo, 'Connected');
    { First readings, so the panel is populated before the first poll.
      最初のポーリングを待たずにパネルを埋めるための初回読み取り。 }
    RequestFrequency;
    RequestMode;
  end
  else
  begin
    { Two different events, same Boolean: if we were still trying to
      connect, the attempt failed; if we were connected, the rig went
      away. The specific reason follows on the error channel, so this
      notice stays deliberately plain and does not overwrite it.

      同じ Boolean で届く 2 つの別の出来事。接続試行中であれば試行の
      失敗、接続済みであればリグが消えたということです。具体的な理由は
      エラーチャネルで続いて届くため、本通知は意図的に簡素にし、それを
      上書きしないようにします。 }
    if FUiMode = ruiConnecting then
      FView.ShowNotice(rnlWarning, 'Could not connect')
    else
      FView.ShowNotice(rnlWarning, 'The rig stopped responding');
    FUiMode := ruiDisconnected;
    FView.SetUiMode(ruiDisconnected);
  end;
end;

procedure TRigPresenter.HandleFrequencyChanged(Sender: TObject; AFreq: Double);
begin
  { Push model: fires only when the polled frequency moved by more than
    the policy's threshold, so this does not repaint on every poll.
    Push モデル。ポーリングした周波数がポリシーの閾値を超えて動いた
    ときのみ発火するため、毎回のポーリングで再描画しません。 }
  FLastFreq := AFreq;
  FView.ShowFrequency(AFreq);
end;

procedure TRigPresenter.HandleError(Sender: TObject; AKind: TRigErrorKind;
                                     ANativeCode: Integer;
                                     const AMsg: string);
begin
  { rekNone on this channel is an informational notice, not a failure —
    circuit-breaker recovery arrives this way.
    本チャネルの rekNone は失敗ではなく通知です。Circuit Breaker の
    回復がこの形で届きます。 }
  if AKind = rekNone then
  begin
    FView.ShowNotice(rnlInfo, AMsg);
    Exit;
  end;
  FView.ShowNotice(rnlError, AdviceFor(AKind, AMsg));
end;

procedure TRigPresenter.HandleLibraryWarning(Sender: TObject;
                                              const AStatus: TRigLibraryStatus;
                                              const AMessage: string);
begin
  FView.ShowNotice(rnlWarning, AMessage);
  FView.ShowLibraryInfo(DescribeLibrary(AStatus.VersionText,
                                        AStatus.LibPath,
                                        AStatus.SupportedRange));
end;

{ ------------------------------------------------------------------
  Turning a failure kind into operator-facing advice
  失敗種別をオペレータ向けの助言にする
  ------------------------------------------------------------------ }

function TRigPresenter.DescribeLibrary(const AVersion, APath,
                                        ARange: string): string;
var
  V: string;
  P: Integer;
begin
  V := Trim(AVersion);

  { Keep "Hamlib 4.5.5" and drop the build date and hash after it.
    "Hamlib 4.5.5" を残し、その後のビルド日時とハッシュを落とします。 }
  P := Pos(' ', V);
  if (P > 0) and (LowerCase(Copy(V, 1, P - 1)) = 'hamlib') then
  begin
    P := PosEx(' ', V, P + 1);
    if P > 0 then
      V := Copy(V, 1, P - 1);
  end;
  if V = '' then
    V := 'Hamlib (version unknown)';

  Result := Format('%s — %s — tested against %s', [V, APath, ARange]);
end;

function TRigPresenter.AdviceFor(AKind: TRigErrorKind;
                                  const AMsg: string): string;
begin
  case AKind of
    rekNotConnected, rekConnectFailed:
      Result := 'The rig is not responding. Check that it is powered on, ' +
                'the cable is connected, and the right port is selected.';
    rekAccessDenied:
      Result := 'The serial port is in use by another application. ' +
                'Close the other program and try again.';
    rekTimeout:
      Result := 'The rig did not answer in time. If this happens often, ' +
                'choose a slower timing profile.';
    rekPowerOff:
      Result := 'The rig reports that it is powered off.';
    rekNotAvailable, rekNotImplemented:
      Result := 'This rig does not support that function.';
    rekVfoNotTargetable:
      Result := 'This rig cannot be told which VFO to use; select the ' +
                'VFO on the rig itself.';
    rekRigRejected:
      Result := 'The rig refused the command. It may be in a mode that ' +
                'does not allow it.';
    rekCircuitOpen:
      Result := 'Too many failures in a row, so commands are paused ' +
                'briefly. They will resume automatically.';
    rekInvalidArgument, rekOutOfDomain, rekInvalidVfo:
      Result := 'That value is out of range for this rig. (' + AMsg + ')';
    rekComponentFault:
      Result := 'Internal error in the rig control component — please ' +
                'report this. (' + AMsg + ')';
  else
    { Unknown and unrecognised kinds keep Hamlib's own wording, which is
      more informative than anything this function could invent.
      未知・未分類の種別は Hamlib 自身の文面を使います。本関数が捏造
      するより情報量があります。 }
    Result := AMsg + ' (' + RigErrorKindToString(AKind) + ')';
  end;
end;

end.
