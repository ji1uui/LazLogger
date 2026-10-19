{
  HamlibService.pas

  Main facade implementing IRigService. This is the only class that
  application code (Presenters etc.) interacts with after construction.

  IRigService を実装する主 Facade。構築後はアプリケーションコード
  (Presenter など) が唯一相互作用するクラスです。

  Layer:    L4 (with internal L5 Poller / 内部 L5 ポーラーを含む)
  Depends:  Most other Hamlib units / 他の Hamlib ユニットの大半

  Application code typically obtains an IRigService via TRigServiceFactory
  rather than constructing TRigService directly.

  アプリケーションコードは通常 TRigService を直接構築せず、
  TRigServiceFactory 経由で IRigService を取得します。

  Key Rev.4.0 features:
    - Self-defending destructor: cleans up even if user forgot Close
    - Closures do not capture Self: safe even after Service.Free
    - Error fallback: nil callback errors route to OnError automatically
    - Default arguments: SetFrequencyAsync(freq) is a valid call
    - Pull model: CurrentState property returns latest snapshot

  Rev.4.0 の主要機能:
    - 自己防衛デストラクタ: 利用者が Close を忘れても確実に後始末
    - クロージャは Self を捕捉しない: Service.Free 後も安全
    - エラーフォールバック: nil コールバックのエラーは OnError へ自動経路
    - デフォルト引数: SetFrequencyAsync(freq) だけで呼び出し可能
    - Pull モデル: CurrentState プロパティが最新スナップショットを返す
}
unit HamlibService;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs,
  HamlibInterfaces, HamlibErrors, HamlibTimeoutPolicy, HamlibStateHolder,
  HamlibCancellation, HamlibCommandBase, HamlibDispatch,
  HamlibFreqCommands, HamlibModeCommands, HamlibPttCommands,
  HamlibRigCommands, HamlibLevelCodec,
  HamlibWorker, HamlibPoller;

type
  { ====================================================================
    TRigService — main facade implementing IRigService
    TRigService - IRigService を実装する主 Facade
    ==================================================================== }
  TRigService = class(TInterfacedObject, IRigService)
  private
    FLoader:    IHamlibLoader;
    FWorker:    TRigWorker;
    { The poll result handler, reference-counted and owned here rather
      than by the poller thread, so that freeing the thread cannot
      strand a delivery that is already on its way back. See the
      comment on TRigPollFreqSink.
      ポーリング結果のハンドラ。参照カウント管理され、ポーラスレッドでは
      なくここが保持します。スレッドを解放しても、戻る途中の配送が宙吊り
      にならないようにするためです。TRigPollFreqSink のコメントを参照。 }
    FPollSinkObj: TRigPollFreqSink;
    FPollSink:    IRigDeliveryKeepAlive;

    FPoller:    TRigPollerThread;     { Hidden from application code.
                                        アプリケーションコードからは不可視。 }
    FPolicy:    TRigTimeoutPolicy;
    FOpen:      Boolean;

    { Snapshot lock and state for Pull model.
      Pull モデル用のスナップショットロックと状態。 }
    { Reference-counted so an in-flight dispatcher can still write to it
      after this Service has been destroyed. See HamlibStateHolder.pas.
      参照カウント管理のため、本 Service 破棄後でも実行中のディスパッチャが
      書き込めます。HamlibStateHolder.pas を参照。 }
    FStateHolder: IRigStateHolder;

    { Hamlib conf tokens the application asked for, applied by the
      Worker right after rig_init. Held as "name=value" lines because
      that is all the component knows about them — see AddConfToken.
      アプリケーションが要求した Hamlib の設定トークン。Worker が
      rig_init 直後に適用します。"name=value" 行として保持します。
      コンポーネントがそれらについて知っているのはそれだけだからです
      (AddConfToken 参照)。 }
    FConfTokens:  TStringList;

    { Filled once in Open. アプリ向けに Open で 1 度だけ埋めます。 }
    FCaps: TRigCapabilities;

    { Event handlers. すべて UI スレッドから発火。 }
    FOnConnectionChanged: TRigConnectEvent;
    FOnFrequencyChanged:  TRigFreqChangedEvent;
    FOnError:             TRigErrorEvent;
    FOnLibraryWarning:    TRigLibraryWarningEvent;

    { Library / model verification result. Library fields are filled in
      Create, model fields in Open.
      ライブラリ・モデル検証の結果。ライブラリ系は Create、モデル系は
      Open で埋めます。 }
    FLibStatus: TRigLibraryStatus;

    procedure CaptureLibraryStatus;
    procedure VerifyModel(AModel: Integer);
    procedure RaiseLibraryWarning(const AMessage: string);

    { ----------------------------------------------------------------
      Internal helpers
      内部ヘルパー
      ---------------------------------------------------------------- }

    { Worker event handlers. They run on the UI thread (queued).
      Worker のイベントハンドラ。UI スレッドで実行 (Queue 経由)。 }
    procedure HandleWorkerConnectionChanged(Sender: TObject; AConnected: Boolean);
    procedure HandleWorkerError(Sender: TObject; AKind: TRigErrorKind;
                                ANativeCode: Integer;
                                const AMsg: string);

    { Poller callback. Updates state snapshot and forwards event.
      Poller コールバック。状態スナップショットを更新しイベントを転送。 }
    procedure HandlePollerFreqChanged(Sender: TObject; AFreq: Double);

    { ----------------------------------------------------------------
      Poller hooks (Rev.4.1). Passed to TRigPollerThread as METHOD
      POINTERS so the poller never takes a reference count on this
      Service. See the header of HamlibPoller.pas for why.

      Poller 用フック (Rev.4.1)。TRigPollerThread にメソッドポインタとして
      渡すため、poller が本 Service の参照カウントを取ることはありません。
      理由は HamlibPoller.pas のヘッダを参照。
      ---------------------------------------------------------------- }
    function  PollerCanRun: Boolean;
    procedure PollerTick(ACallback: TRigPollerFreqCallback);

    { Guard helpers used by every public async method. They raise real
      exceptions (not Assert) so the checks survive release builds.

      全公開非同期メソッドが使うガードヘルパー。Assert ではなく実際の例外を
      発生させるため、リリースビルドでも検査が残ります。 }
    procedure EnsureOpen;

    { Fill FCaps from the loader's IHamlibRigControl role, leaving it
      Known = False when the role or the symbol is absent.
      ローダの IHamlibRigControl role から FCaps を埋めます。role または
      シンボルが無い場合は Known = False のままにします。 }
    procedure CaptureCapabilities(AModel: Integer);

    { Clears FCaps. See the implementation for why Close needs it.
      FCaps を消去します。Close がこれを必要とする理由は実装を参照。 }
    procedure ForgetCapabilities;

    { ----------------------------------------------------------------
      Dispatcher factories. Each builds a one-shot dispatch object that
      holds the user callback plus a snapshot of OnError, and returns a
      method pointer to its delivery entry point. The dispatch object
      frees itself after one delivery, so there is nothing to track here.

      Centralising this removes the same five-line boilerplate from every
      async method and keeps the "never capture Self" rule in one place.

      ディスパッチャ生成関数。ユーザコールバックと OnError のスナップショットを
      保持する使い捨て配送オブジェクトを作り、その配送エントリポイントへの
      メソッドポインタを返します。配送オブジェクトは 1 回の配送後に自己破棄
      するため、ここで追跡する必要はありません。

      集約により各非同期メソッドから同じ 5 行の定型句が消え、
      「Self を捕捉しない」規則が 1 箇所に収まります。
      ---------------------------------------------------------------- }
    function MakeCommandSink(ACallback: TRigCommandCallback): TRigInternalCallback;
    function MakeFreqSink(ACallback: TRigFreqCallback;
                          AVfo: TRigVfo;
                          AKeepAlive: IRigDeliveryKeepAlive = nil): TRigFreqInternalCallback;
    function MakeModeSink(ACallback: TRigModeCallback): TRigModeInternalCallback;

    { Like MakeCommandSink, but also records the commanded PTT state in
      the snapshot when the rig accepts it.
      MakeCommandSink と同様ですが、リグが受理した場合に指示した PTT
      状態をスナップショットに記録します。 }
    function MakePttSink(ACallback: TRigCommandCallback;
                         ARequestedActive: Boolean): TRigInternalCallback;

    { Sinks for the Rev.6.0 result types. Same "never capture Self"
      rule as the others.
      Rev.6.0 の結果型用シンク。他と同じ「Self を捕捉しない」規則に
      従います。 }
    function MakeLevelSink(ACallback: TRigLevelCallback): TRigLevelInternalCallback;
    function MakeFuncSink(ACallback: TRigFuncCallback): TRigFuncInternalCallback;
    function MakeSplitSink(ACallback: TRigSplitCallback): TRigSplitInternalCallback;
    function MakeVfoSink(ACallback: TRigVfoCallback): TRigVfoInternalCallback;

    { Snapshot updaters - thread-safe.
      スナップショット更新ヘルパー (スレッドセーフ)。 }
    procedure UpdateStateFreq(AVfo: TRigVfo; AFreq: Double);
    procedure UpdateStateConnected(AConnected: Boolean);

  protected
    { ----------------------------------------------------------------
      Test injection point — protected so a subclass (e.g.
      TTestableRigService) can simulate poller results without going
      through the real Worker.

      テスト注入ポイント — サブクラス (例: TTestableRigService) が
      実際の Worker を経由せずポーラー結果をシミュレートできるよう
      protected にしています。
      ---------------------------------------------------------------- }
    procedure InjectPollerFreqResult(const AResult: TRigFreqResult); virtual;

  public
    { Construct with a pre-loaded IHamlibLoader. The loader's lifetime
      is managed by the IRigService reference count.

      事前ロード済みの IHamlibLoader で生成します。ローダの生存期間は
      IRigService の参照カウントで管理されます。 }
    constructor Create(ALoader: IHamlibLoader);

    { Self-defending destructor. Cleans up even if the user forgot to
      call Close, CancelAllPending, or DisablePolling. The order is
      critical and is documented in the implementation.

      自己防衛デストラクタ。利用者が Close、CancelAllPending、
      DisablePolling を呼び忘れた場合でも後始末します。順序が重要で
      実装内にドキュメント化されています。 }
    destructor Destroy; override;

    { ----------------- IRigService implementation ----------------- }

    procedure Open(AModel: Integer; const APort: string);
    procedure Close;
    function  GetIsOpen: Boolean;

    procedure EnablePolling(AIntervalMs: Cardinal = 200);
    procedure DisablePolling;

    function SetFrequencyAsync(AFreq: Double;
                               AVfo: TRigVfo = rvfoCurr;
                               ACallback: TRigCommandCallback = nil): ICancellationToken;
    function GetFrequencyAsync(AVfo: TRigVfo = rvfoCurr;
                               ACallback: TRigFreqCallback = nil): ICancellationToken;
    function SetModeAsync(AMode: TRigMode;
                          APassbandHz: Integer = 0;
                          AVfo: TRigVfo = rvfoCurr;
                          ACallback: TRigCommandCallback = nil): ICancellationToken;
    function GetModeAsync(AVfo: TRigVfo = rvfoCurr;
                          ACallback: TRigModeCallback = nil): ICancellationToken;
    function SetPttAsync(AState: TRigPttState;
                         ACallback: TRigCommandCallback = nil): ICancellationToken;

    function GetLevelAsync(ALevel: TRigLevel;
                           ACallback: TRigLevelCallback = nil;
                           AVfo: TRigVfo = rvfoCurr): ICancellationToken;
    function SetLevelFloatAsync(ALevel: TRigLevel; AValue: Double;
                                ACallback: TRigCommandCallback = nil;
                                AVfo: TRigVfo = rvfoCurr): ICancellationToken;
    function SetLevelIntAsync(ALevel: TRigLevel; AValue: Integer;
                              ACallback: TRigCommandCallback = nil;
                              AVfo: TRigVfo = rvfoCurr): ICancellationToken;
    function GetFuncAsync(AFunc: TRigFunc;
                          ACallback: TRigFuncCallback = nil;
                          AVfo: TRigVfo = rvfoCurr): ICancellationToken;
    function SetFuncAsync(AFunc: TRigFunc; AActive: Boolean;
                          ACallback: TRigCommandCallback = nil;
                          AVfo: TRigVfo = rvfoCurr): ICancellationToken;
    function SetSplitAsync(AEnabled: Boolean;
                           ATxVfo: TRigVfo = rvfoCurr;
                           ACallback: TRigCommandCallback = nil): ICancellationToken;
    function GetSplitAsync(ACallback: TRigSplitCallback = nil): ICancellationToken;
    function SetSplitFreqAsync(AFreq: Double;
                               ACallback: TRigCommandCallback = nil): ICancellationToken;
    function SetVfoAsync(AVfo: TRigVfo;
                         ACallback: TRigCommandCallback = nil): ICancellationToken;
    function GetVfoAsync(ACallback: TRigVfoCallback = nil): ICancellationToken;
    function VfoOpAsync(AOp: TRigVfoOp;
                        ACallback: TRigCommandCallback = nil;
                        AVfo: TRigVfo = rvfoCurr): ICancellationToken;
    function GetCapabilities: TRigCapabilities;
    procedure AddConfToken(const AName, AValue: string);

    procedure CancelAllPending;
    procedure ApplyTimeoutPolicy(const APolicy: TRigTimeoutPolicy);
    function  GetCurrentPolicy: TRigTimeoutPolicy;

    procedure SetOnConnectionChanged(AHandler: TRigConnectEvent);
    procedure SetOnFrequencyChanged(AHandler: TRigFreqChangedEvent);
    procedure SetOnError(AHandler: TRigErrorEvent);
    procedure SetOnLibraryWarning(AHandler: TRigLibraryWarningEvent);

    function GetLibraryStatus: TRigLibraryStatus;
    function GetCurrentState: TRigState;
    function GetQueueDepth: Integer;
    function GetCircuitBreakerOpen: Boolean;
  end;

implementation

const
  { Lower bound for EnablePolling. Anything faster floods a serial rig.
    EnablePolling の下限。これより速いとシリアルリグを圧迫します。 }
  MIN_POLL_INTERVAL_MS   = 50;

  { The poller skips a tick when the command queue is at least this deep,
    so interactive commands are never starved by background polling.
    コマンドキューがこの深さ以上のとき poller はティックを飛ばし、
    対話操作がバックグラウンドポーリングに埋もれないようにします。 }
  POLL_QUEUE_HIGH_WATER  = 3;

  { Sanity ceiling for SetFrequencyAsync. 100 GHz is far above any
    amateur allocation and catches unit mistakes (MHz passed as Hz).
    SetFrequencyAsync の上限。100 GHz はあらゆるアマチュアバンドより
    遥かに上で、単位の取り違え (MHz を Hz として渡す等) を検出します。 }
  MAX_FREQ_HZ: Double    = 100.0e9;

constructor TRigService.Create(ALoader: IHamlibLoader);
begin
  { Argument validation uses exceptions, not Assert: Assert is compiled
    out in release builds (-Sa absent) and these are public-API contracts.
    引数検証には Assert ではなく例外を使います。Assert はリリースビルド
    (-Sa なし) で削除されますが、これは公開 API の契約だからです。 }
  if not Assigned(ALoader) then
    raise EArgumentException.Create('ALoader must not be nil');
  if not ALoader.IsLoaded then
    raise EArgumentException.Create(
      'ALoader must be loaded before creating the Service');

  inherited Create;
  FLoader    := ALoader;
  FPolicy    := RigPolicy_Default;
  CaptureLibraryStatus;
  FStateHolder := TRigStateHolder.Create;
  FConfTokens  := TStringList.Create;

  { Created once and kept for the Service's whole life. The interface
    reference is what keeps it alive; FPollSinkObj is the same object,
    held only so its methods can be reached without a cast.
    一度だけ生成し、Service の生存期間を通じて保持します。生かしている
    のはインターフェース参照であり、FPollSinkObj は同じオブジェクトを、
    キャストなしでメソッドへ到達するためだけに保持しています。 }
  FPollSinkObj := TRigPollFreqSink.Create;
  FPollSink    := FPollSinkObj;
end;

destructor TRigService.Destroy;
begin
  { Self-defending shutdown sequence. Order matters:

    自己防衛シャットダウンシーケンス。順序が重要:

    1) Clear event handlers FIRST. This prevents any in-flight callback
       (already queued via TThread.Queue) from invoking a stale handler
       on the partially-destroyed Service.

       1) イベントハンドラを最初にクリア。これにより、すでに TThread.Queue
          経由で積まれている処理中のコールバックが、部分的に破棄された
          Service 上で古いハンドラを呼ぶことを防ぎます。

    2) Stop the Poller (no more new GetFreq commands).
       2) Poller を停止 (新規 GetFreq コマンドの投入を止める)。

    3) Cancel all pending commands. Their callbacks will fire with
       rcsCancelled, which the closure handles harmlessly because
       it does not capture Self.

       3) 保留中の全コマンドをキャンセル。コールバックは rcsCancelled で
          発火しますが、クロージャは Self を捕捉していないため無害に処理されます。

    4) Stop the Worker and wait for completion. After WaitFor returns,
       all DoExecute calls are done and all TThread.Queue calls have
       been issued (though may not yet run on UI thread).

       4) Worker を停止し完了を待ちます。WaitFor が戻ると、すべての
          DoExecute は完了し、TThread.Queue 呼び出しはすべて発行済みです
          (UI スレッドでまだ実行されていない可能性はあります)。

    5) Free critical section.
       5) クリティカルセクションを解放。

    6) Release IHamlibLoader reference (DLL unloads if last ref).
       6) IHamlibLoader 参照を解放 (最後の参照なら DLL アンロード)。 }

  FOnError             := nil;
  FOnConnectionChanged := nil;
  FOnFrequencyChanged  := nil;
  FOnLibraryWarning    := nil;

  DisablePolling;
  CancelAllPending;

  if Assigned(FWorker) then
  begin
    FWorker.RequestStop;

    { Only join a thread that was actually resumed. A Worker exists
      from the moment Open constructs it, which is before Open starts
      it: if anything between those two points raises, the Service is
      left holding an unstarted Worker, and WaitFor on it would hang
      the application forever rather than fail. Its destructor
      terminates it correctly without a join.
      実際に再開されたスレッドだけを join します。Worker は Open が構築
      した時点から存在し、それは Open が開始するより前です。その 2 点の
      間で何かが例外を投げると、Service は未開始の Worker を抱えたまま
      になり、それに対する WaitFor はアプリケーションを失敗させるのでは
      なく永久に停止させます。join なしでも、そのデストラクタが正しく
      終了させます。 }
    if FWorker.Started then
      FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;

  { Release our reference. Any dispatcher still queued on the UI thread
    keeps the holder alive until it has run.
    参照を解放します。UI スレッドのキューに残るディスパッチャがあれば、
    実行されるまでホルダーは生存します。 }
  FStateHolder := nil;

  { Released last, and only as an interface: any delivery still queued
    on the UI thread holds its own reference and keeps the sink alive
    until it has run. This is the same rule FStateHolder follows, and
    it is the rule the poller used to break.
    最後に、かつインターフェースとしてのみ解放します。UI スレッドのキュー
    に残る配送は自前の参照を持ち、実行されるまでシンクを生かします。
    これは FStateHolder が従うのと同じ規則であり、ポーラが破っていた規則
    です。 }
  FPollSinkObj := nil;
  FPollSink    := nil;

  FLoader := nil;
  FreeAndNil(FConfTokens);
  inherited;
end;

{ ----------------- Library and model verification ----------------- }

procedure TRigService.CaptureLibraryStatus;
var
  Diag: IHamlibDiagnostics;
begin
  FillChar(FLibStatus, SizeOf(FLibStatus), 0);
  FLibStatus.LibPath  := FLoader.LibPath;
  FLibStatus.ApiMajor := FLoader.ApiMajor;
  FLibStatus.ApiMinor := FLoader.ApiMinor;

  { Diagnostics is an optional role interface. A loader that does not
    implement it (notably a test fake) leaves the verdict at rvvUnknown
    and verification is skipped — the component still works.

    Diagnostics は任意の role interface です。実装しないローダ (特にテスト
    フェイク) では verdict は rvvUnknown のままで検証が省略されます。
    コンポーネントは動作し続けます。 }
  if Supports(FLoader, IHamlibDiagnostics, Diag) then
  begin
    FLibStatus.VersionText        := Diag.GetVersionText;
    FLibStatus.Verdict            := Diag.GetVersionVerdict;
    FLibStatus.SupportedRange     := Diag.GetSupportedRangeText;
    FLibStatus.UnversionedBinding := Diag.GetUnversionedBinding;
  end
  else
  begin
    FLibStatus.Verdict        := rvvUnknown;
    FLibStatus.SupportedRange := '(loader does not report a range)';
  end;
end;

procedure TRigService.RaiseLibraryWarning(const AMessage: string);
var
  HandlerCopy: TRigLibraryWarningEvent;
begin
  HandlerCopy := FOnLibraryWarning;
  if Assigned(HandlerCopy) then
    HandlerCopy(nil, FLibStatus, AMessage);
end;

procedure TRigService.VerifyModel(AModel: Integer);
var
  Diag:     IHamlibDiagnostics;
  Mfg:      string;
  ModelNm:  string;
  Answered: Boolean;
begin
  FLibStatus.ModelNumber    := AModel;
  FLibStatus.ModelMfg       := '';
  FLibStatus.ModelName      := '';
  FLibStatus.ModelValidated := False;

  if not Supports(FLoader, IHamlibDiagnostics, Diag) then Exit;

  if Diag.CheckModel(AModel, Mfg, ModelNm, Answered) then
  begin
    FLibStatus.ModelMfg       := Mfg;
    FLibStatus.ModelName      := ModelNm;
    FLibStatus.ModelValidated := True;
    Exit;
  end;

  if not Answered then
  begin
    { The library is too old to be asked. Not an error — just unverified.
      ライブラリが古くて問い合わせできません。エラーではなく未検証です。 }
    RaiseLibraryWarning(Format(
      'This Hamlib build cannot confirm model numbers, so model %d was ' +
      'accepted unverified.', [AModel]));
    Exit;
  end;

  { Answered, and the answer is that this build has no such model. Refuse:
    continuing would connect through an arbitrary backend, which is how a
    wrong constant turns into "a rig that half works".

    回答があり、内容は「このビルドにそのモデインは無い」です。拒否します。
    続行すれば任意のバックエンド経由で接続してしまい、誤った定数が
    「半分だけ動くリグ」に化けます。 }
  raise ERigModelUnknown.CreateFmt(
    'Rig model %d is not known to the loaded Hamlib (%s). ' +
    'Check the constant against riglist.h or run "rigctl --list".',
    [AModel, FLibStatus.LibPath]);
end;

{ ----------------- Connection management ----------------- }

procedure TRigService.Open(AModel: Integer; const APort: string);
begin
  if AModel <= 0 then
    raise EArgumentException.CreateFmt(
      'Invalid rig model number: %d', [AModel]);
  { An empty port is legitimate and is the ONLY correct form for a
    backend that does not own a serial device: Hamlib's built-in dummy
    rig, and network backends that carry their address in a conf token.
    The Worker simply does not call rig_set_conf('rig_pathname') when
    APort is empty, leaving the backend's own default in place.

    Rev.4.2 rejected an empty port and told the caller to pass 'none'
    instead. Tested against real Hamlib 4.5.5, that advice is actively
    wrong: rig_open treats 'none' as a NETWORK HOST NAME, fails to
    resolve it and returns -RIG_ECONF, so the documented way to open
    the dummy rig could not work. Verified: with the port left unset,
    empty, or /dev/null, rig_open on model 1 returns RIG_OK.

    空のポートは正当で、シリアルデバイスを持たないバックエンド
    (Hamlib 内蔵ダミーリグ、アドレスを conf トークンで持つネットワーク
    バックエンド) では唯一の正しい形です。APort が空のとき Worker は
    rig_set_conf('rig_pathname') を呼ばず、バックエンド既定値を残します。

    Rev.4.2 は空のポートを拒否し、代わりに 'none' を渡すよう案内して
    いました。実 Hamlib 4.5.5 で検証した結果、この案内は誤りです。
    rig_open は 'none' をネットワークホスト名として扱い、解決に失敗して
    -RIG_ECONF を返します。つまり文書化されたダミーリグの開き方は動作
    しませんでした。確認済み: ポートを未設定・空・/dev/null のいずれに
    しても、モデル 1 の rig_open は RIG_OK を返します。 }
  if FOpen then
    raise ERigServiceOpen.Create(
      'Service is already open. Call Close before opening again.');

  { Ask the library whether it actually knows this model, before any
    serial port is touched. Fails fast with a message naming the number.
    シリアルポートに触れる前に、ライブラリがこのモデルを実際に知っているか
    問い合わせます。番号を明示したメッセージで即座に失敗します。 }
  VerifyModel(AModel);

  { Ask what this rig can do before anything is built on top of it, so
    GetCapabilities is valid from the moment Open returns rather than
    only after the first successful command.
    リグの上に何かを積む前に、その能力を問い合わせます。GetCapabilities
    が最初のコマンド成功後ではなく Open の戻り時点から有効になるように
    するためです。 }
  CaptureCapabilities(AModel);

  FWorker := TRigWorker.Create(FLoader, AModel, APort);
  FWorker.SetConfTokens(FConfTokens);
  FWorker.ApplyPolicy(FPolicy);
  FWorker.OnConnectionChanged := @HandleWorkerConnectionChanged;
  FWorker.OnError             := @HandleWorkerError;
  FWorker.Start;
  FOpen := True;

  { Record the connection in the snapshot now, synchronously.

    The worker also announces it, but that announcement travels through
    TThread.Queue and is therefore delivered only when the application
    next runs a message pump. A console program, a scheduled job or any
    code that calls Open and then reads CurrentState without pumping
    would see Connected = False for as long as it never pumps —
    measured as indefinitely, not briefly.

    Close has always updated the snapshot synchronously (via
    FStateHolder.Reset), so the two halves of the lifecycle disagreed
    about whether the snapshot is allowed to lag. It is not: the
    snapshot is the Pull model's source of truth, and Open is the one
    moment it is cheapest to be right. The worker's later announcement
    sets the same flag again, which is harmless.

    Found by RandomSequenceTest, which checks "CurrentState.Connected
    always agrees with IsOpen" after every few operations.

    接続をいま、同期的にスナップショットへ記録します。

    ワーカーもこれを通知しますが、その通知は TThread.Queue を通るため、
    アプリケーションが次にメッセージポンプを回したときにしか配送されま
    せん。コンソールプログラム、スケジュール実行のジョブ、あるいは Open
    の後にポンプを回さず CurrentState を読むコードは、ポンプを回さない
    限り Connected = False を見続けます。実測では「短時間」ではなく
    「無期限」でした。

    Close は以前から (FStateHolder.Reset 経由で) 同期的にスナップショット
    を更新していました。つまりライフサイクルの両端が、スナップショットの
    遅れを許すかどうかで食い違っていました。許しません。スナップショットは
    Pull モデルにおける真実の源であり、Open はそれを正しく保つのが最も安価
    な瞬間です。ワーカーの後続通知は同じフラグを再度立てるだけで無害です。

    RandomSequenceTest が発見しました。数操作ごとに「CurrentState.Connected
    は常に IsOpen と一致する」を検査しています。 }
  UpdateStateConnected(True);
end;

procedure TRigService.Close;
begin
  if not FOpen then Exit;

  DisablePolling;
  CancelAllPending;

  if Assigned(FWorker) then
  begin
    FWorker.RequestStop;

    { Only join a thread that was actually resumed. A Worker exists
      from the moment Open constructs it, which is before Open starts
      it: if anything between those two points raises, the Service is
      left holding an unstarted Worker, and WaitFor on it would hang
      the application forever rather than fail. Its destructor
      terminates it correctly without a join.
      実際に再開されたスレッドだけを join します。Worker は Open が構築
      した時点から存在し、それは Open が開始するより前です。その 2 点の
      間で何かが例外を投げると、Service は未開始の Worker を抱えたまま
      になり、それに対する WaitFor はアプリケーションを失敗させるのでは
      なく永久に停止させます。join なしでも、そのデストラクタが正しく
      終了させます。 }
    if FWorker.Started then
      FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;

  { Reset snapshot to indicate disconnection.
    切断を示すためスナップショットをリセット。 }
  FStateHolder.Reset;
  ForgetCapabilities;

  FOpen := False;
end;

function TRigService.GetIsOpen: Boolean;
begin
  Result := FOpen;
end;

{ ----------------- Polling control ----------------- }

procedure TRigService.EnablePolling(AIntervalMs: Cardinal);
begin
  if AIntervalMs < MIN_POLL_INTERVAL_MS then
    raise EArgumentException.CreateFmt(
      'Poll interval must be at least %d ms (got %d)',
      [MIN_POLL_INTERVAL_MS, AIntervalMs]);

  if Assigned(FPoller) then
  begin
    FPoller.SetIntervalMs(AIntervalMs);
    Exit;
  end;

  { Rev.4.1: pass METHOD POINTERS, not Self-as-IRigService. A method
    pointer carries no reference count, so no Service<->Poller cycle
    is created and the self-defending destructor can actually run.

    Rev.4.1: Self を IRigService として渡さず、メソッドポインタを渡します。
    メソッドポインタは参照カウントを持たないため Service⇄Poller の循環が
    生じず、自己防衛デストラクタが実際に機能します。 }
  FPollSinkObj.SetThresholdHz(FPolicy.FreqChangeThresholdHz);
  FPollSinkObj.SetOnFrequencyChanged(@HandlePollerFreqChanged);
  FPollSinkObj.Activate;

  FPoller := TRigPollerThread.Create(@PollerTick, @PollerCanRun,
                                     @FPollSinkObj.HandleFreqResult,
                                     AIntervalMs);
  FPoller.Start;
end;

{ Called by the poller thread immediately before each tick.
  各ティックの直前に poller スレッドから呼ばれます。 }
function TRigService.PollerCanRun: Boolean;
begin
  Result := FOpen and Assigned(FWorker)
            and (FWorker.QueueDepth < POLL_QUEUE_HIGH_WATER);
end;

{ Called by the poller thread to issue exactly one frequency query.
  1 回分の周波数問い合わせを発行するため poller スレッドから呼ばれます。 }
procedure TRigService.PollerTick(ACallback: TRigPollerFreqCallback);
var
  Token: ICancellationToken;
begin
  if not (FOpen and Assigned(FWorker)) then Exit;

  { Posted directly rather than through GetFrequencyAsync, because the
    poll result's delivery has to carry a reference to the sink that
    will receive it. The public method cannot: it has no business
    knowing about the component's internal keep-alive rule, and an
    application callback cannot be kept alive this way in any case —
    the component does not own the application's objects.

    GetFrequencyAsync 経由ではなく直接投稿します。ポーリング結果の配送は、
    それを受け取るシンクへの参照を運ぶ必要があるからです。公開メソッドに
    それはできません。コンポーネント内部の生存保持規則を知るべき立場に
    なく、そもそもアプリケーションのコールバックをこの方法で生かすことは
    できません。アプリケーションのオブジェクトはコンポーネントの所有物で
    はないからです。 }
  Token := TRigCancellationToken.Create;
  FWorker.PostCommand(
    TGetFreqCommand.Create(
      rvfoCurr, Token,
      MakeFreqSink(TRigFreqCallback(ACallback), rvfoCurr, FPollSink)));
end;

{ Shared guard for the public async API. Raises instead of asserting.
  公開非同期 API 共通のガード。Assert ではなく例外を発生させます。 }
{ Forget everything known about the connected model. Called when the
  capabilities are about to be re-read, and on Close.

  Capabilities describe the rig the Service is connected to. After a
  Close there is no such rig, so continuing to answer Known = True
  reports the previous model's capabilities to an application that may
  be about to open a different one — stale state crossing a lifecycle
  boundary, in the one query that was not already reset. The second
  sample application had to blank its capability panel by hand on
  disconnect, which is the component making every caller do its
  clearing for it.

  接続中の機種について分かっていることをすべて忘れます。能力を再読する
  直前と、Close 時に呼ばれます。

  能力は Service が接続しているリグを記述します。Close の後にそのような
  リグは存在しないため、Known = True を返し続けることは、別の機種を開こう
  としているかもしれないアプリケーションに前の機種の能力を報告すること
  になります。これはライフサイクル境界をまたぐ陳腐化した状態であり、
  リセットされていなかった唯一の問い合わせでした。2 つ目のサンプルアプリは
  切断時に能力パネルを手で空にする必要がありましたが、それは
  コンポーネントが自分の後始末を全呼び出し側にさせていたということです。 }
procedure TRigService.ForgetCapabilities;
begin
  FCaps.Known         := False;
  FCaps.TargetableVfo := False;
  FCaps.PttType       := 0;
  FCaps.HasPtt        := False;
  FCaps.GetLevels     := [];
  FCaps.SetLevels     := [];
  FCaps.GetFuncs      := [];
  FCaps.SetFuncs      := [];
  FCaps.VfoOps        := [];
end;

procedure TRigService.CaptureCapabilities(AModel: Integer);
var
  Ext:     IHamlibRigControl;
  PttConf: string;
begin
  ForgetCapabilities;

  if not Supports(FLoader, IHamlibRigControl, Ext) then Exit;
  Ext.QueryCapabilities(AModel, FCaps);

  { rig_get_caps_int reads the model's STATIC capability table, so a
    ptt_type conf token the application supplied does not appear there
    — measured against real Hamlib 4.5.5, where ptt_type stayed 0 for
    the dummy rig after AddConfToken('ptt_type', 'RIG').

    The application told us it wired up a PTT line, and that is better
    information than the model default. Trusting it here is what makes
    Capabilities.HasPtt answer the question a UI actually asks.

    rig_get_caps_int は機種の「静的な」能力表を読むため、アプリケーションが
    与えた ptt_type の設定トークンはそこに現れません (実 Hamlib 4.5.5 で
    実測。ダミーリグに AddConfToken('ptt_type','RIG') を行っても ptt_type は
    0 のままでした)。

    PTT 線を接続したとアプリケーションが告げているなら、それは機種既定より
    良い情報です。ここでそれを信頼することが、Capabilities.HasPtt を UI が
    実際に問う内容への答えにします。 }
  if FConfTokens.IndexOfName('ptt_type') >= 0 then
  begin
    PttConf := UpperCase(Trim(FConfTokens.Values['ptt_type']));
    if (PttConf <> '') and (PttConf <> 'NONE')
       and (PttConf <> 'RIG_PTT_NONE') then
      FCaps.HasPtt := True;
  end;
end;

procedure TRigService.EnsureOpen;
begin
  if (not FOpen) or (not Assigned(FWorker)) then
    raise ERigServiceClosed.Create(
      'Service is not open. Call Open() before issuing commands.');
end;

{ ----------------- Dispatcher factories ----------------- }

{ NOTE: each factory assigns the new object to a local variable before
  taking the method pointer. Writing @TSomeClass.Create(...).Method in one
  expression is NOT equivalent — FPC binds the address against a temporary
  and the resulting method pointer carries a bogus Self, which corrupts the
  call when the UI thread finally runs it. Keep the local variable.

  注意: 各ファクトリはメソッドポインタを取る前に、生成したオブジェクトを
  ローカル変数へ代入しています。@TSomeClass.Create(...).Method と 1 式で
  書くのは等価ではありません。FPC は一時オブジェクトに対してアドレスを
  解決し、得られるメソッドポインタは不正な Self を持つため、UI スレッドが
  実行した時点で呼び出しが壊れます。ローカル変数を省略しないこと。 }

{ Note 5027 ("assigned but never used") is a false positive here: FPC does
  not count taking a method pointer (@Sink.Method) as a read of Sink.
  Suppressed narrowly, and restored with POP right after the factories.

  ここでの Note 5027 (「代入されたが未使用」) は誤検知です。FPC は
  メソッドポインタの取得 (@Sink.Method) を Sink の読み出しとみなしません。
  範囲を限定して抑制し、ファクトリ直後に POP で元に戻します。 }
{$PUSH}
{$WARN 5027 OFF}

function TRigService.MakeCommandSink(
  ACallback: TRigCommandCallback): TRigInternalCallback;
var
  Sink: TUserCallbackDispatch;
begin
  Sink   := TUserCallbackDispatch.Create(ACallback, FOnError);
  Result := @Sink.InternalCallback;
end;

function TRigService.MakeFreqSink(ACallback: TRigFreqCallback;
                                   AVfo: TRigVfo;
                                   AKeepAlive: IRigDeliveryKeepAlive): TRigFreqInternalCallback;
var
  Sink: TUserFreqCallbackDispatch;
begin
  { The freq dispatcher also refreshes the Pull-model snapshot on success.
    It receives the state pointer and its lock; Destroy guarantees the
    holder is reference-counted, so it cannot dangle.

    周波数ディスパッチャは成功時に Pull モデルのスナップショットも更新します。
    ホルダーは参照カウント管理のためダングリングしません。 }
  Sink := TUserFreqCallbackDispatch.Create(
    ACallback, FOnError, FStateHolder, AVfo, AKeepAlive);
  Result := @Sink.InternalFreqCallback;
end;

function TRigService.MakeModeSink(
  ACallback: TRigModeCallback): TRigModeInternalCallback;
var
  Sink: TUserModeCallbackDispatch;
begin
  Sink   := TUserModeCallbackDispatch.Create(ACallback, FOnError, FStateHolder);
  Result := @Sink.InternalModeCallback;
end;

function TRigService.MakePttSink(ACallback: TRigCommandCallback;
  ARequestedActive: Boolean): TRigInternalCallback;
var
  Sink: TUserPttCallbackDispatch;
begin
  { Assign to a local first. Taking @TClass.Create(...).Method directly
    yields a method pointer with a bogus Self — see the warning on the
    other Make*Sink factories.
    まず局所変数に代入します。@TClass.Create(...).Method を直接取ると
    Self が不正なメソッドポインタになります。他の Make*Sink の警告を
    参照してください。 }
  Sink   := TUserPttCallbackDispatch.Create(ACallback, FOnError,
                                            FStateHolder, ARequestedActive);
  Result := @Sink.InternalCallback;
end;

{$POP}

procedure TRigService.DisablePolling;
begin
  { Deactivate the sink BEFORE the thread goes. Results already queued
    will still be delivered — they must be, the queue cannot be
    un-written — and a deactivated sink turns each of them into a
    no-op instead of an announcement about a rig that is no longer
    being polled.
    スレッドを落とす「前」にシンクを非活性にします。既にキューにある
    結果は配送されます (キューは書き戻せないため、されざるをえません)。
    非活性のシンクは、それらを「もはやポーリングしていないリグについての
    通知」ではなく無処理に変えます。 }
  if Assigned(FPollSinkObj) then
    FPollSinkObj.Deactivate;

  if not Assigned(FPoller) then Exit;
  FPoller.Stop;
  FPoller.WaitFor;
  FreeAndNil(FPoller);
end;

{ ----------------- Async APIs ----------------- }
{
  Every async method follows the same three steps:
    1. validate arguments (real exceptions, effective in release builds)
    2. create a cancellation token and return it to the caller
    3. build the command with a dispatcher sink and hand it to the Worker

  The sink factories above guarantee the command never captures Self, so a
  late callback cannot touch a freed Service.

  各非同期メソッドは同じ 3 ステップに従います:
    1. 引数検証 (実例外。リリースビルドでも有効)
    2. キャンセルトークンを作成し呼び出し元へ返す
    3. ディスパッチャ sink を付けてコマンドを構築し Worker へ渡す

  上記の sink 生成関数により、コマンドが Self を捕捉することはなく、
  遅延したコールバックが解放済み Service に触れることはありません。
}

function TRigService.SetFrequencyAsync(AFreq: Double; AVfo: TRigVfo;
                                        ACallback: TRigCommandCallback): ICancellationToken;
var
  Token: TRigCancellationToken;
begin
  if (AFreq <= 0) or (AFreq > MAX_FREQ_HZ) then
    raise EArgumentException.CreateFmt(
      'Frequency out of range: %.0f Hz (expected 0 < f <= %.0f)',
      [AFreq, MAX_FREQ_HZ]);
  EnsureOpen;

  Token  := TRigCancellationToken.Create;
  Result := Token;
  FWorker.PostCommand(
    TSetFreqCommand.Create(AVfo, AFreq, Token, MakeCommandSink(ACallback)));
end;

function TRigService.GetFrequencyAsync(AVfo: TRigVfo;
                                        ACallback: TRigFreqCallback): ICancellationToken;
var
  Token: TRigCancellationToken;
begin
  EnsureOpen;

  Token  := TRigCancellationToken.Create;
  Result := Token;
  FWorker.PostCommand(
    TGetFreqCommand.Create(AVfo, Token, MakeFreqSink(ACallback, AVfo)));
end;

function TRigService.SetModeAsync(AMode: TRigMode; APassbandHz: Integer;
                                   AVfo: TRigVfo;
                                   ACallback: TRigCommandCallback): ICancellationToken;
var
  Token: TRigCancellationToken;
begin
  { rmUnknown is what GetMode reports for a value this binding could not
    name. It is not something that can be sent: no rmode_t means
    "unknown". Rejecting it turns code that echoes a get straight back
    into a set into a visible programming error, instead of silently
    sending RIG_MODE_NONE.

    rmUnknown は GetMode が名前を付けられなかった値を報告するための
    ものです。送信できる値ではありません。「未知」を意味する rmode_t は
    存在しないためです。ここで弾くことで、get の値をそのまま set に
    送り返すコードが、静かに RIG_MODE_NONE を送るのではなく明示的な
    プログラミングエラーになります。 }
  if AMode = rmUnknown then
    raise EArgumentException.Create(
      'AMode must be a concrete mode (e.g. rmUSB), not rmUnknown');
  if APassbandHz < 0 then
    raise EArgumentException.CreateFmt(
      'APassbandHz must be >= 0 (0 = rig default), got %d', [APassbandHz]);
  EnsureOpen;

  Token  := TRigCancellationToken.Create;
  Result := Token;
  FWorker.PostCommand(
    TSetModeCommand.Create(AMode, APassbandHz, AVfo, Token,
                           MakeCommandSink(ACallback)));
end;

function TRigService.GetModeAsync(AVfo: TRigVfo;
                                   ACallback: TRigModeCallback): ICancellationToken;
var
  Token: TRigCancellationToken;
begin
  EnsureOpen;

  Token  := TRigCancellationToken.Create;
  Result := Token;
  FWorker.PostCommand(
    TGetModeCommand.Create(AVfo, Token, MakeModeSink(ACallback)));
end;

function TRigService.SetPttAsync(AState: TRigPttState;
                                  ACallback: TRigCommandCallback): ICancellationToken;
var
  Token: TRigCancellationToken;
begin
  EnsureOpen;

  Token  := TRigCancellationToken.Create;
  Result := Token;
  FWorker.PostCommand(
    TSetPttCommand.Create(AState, Token,
      MakePttSink(ACallback, AState <> rpttOff)));
end;

procedure TRigService.CancelAllPending;
begin
  if Assigned(FWorker) then
    FWorker.CancelAllQueued;
end;

{ ----------------- Hardware policy ----------------- }

procedure TRigService.ApplyTimeoutPolicy(const APolicy: TRigTimeoutPolicy);
var
  ErrMsg: string;
begin
  if not ValidatePolicy(APolicy, ErrMsg) then
    raise EArgumentException.Create('Invalid policy: ' + ErrMsg);

  FPolicy := APolicy;
  if Assigned(FWorker) then
    FWorker.ApplyPolicy(APolicy);
  if Assigned(FPoller) then
    FPoller.SetIntervalMs(APolicy.PollIntervalMs);
  { The change threshold now lives with the handler that applies it,
    not with the thread that triggers the poll.
    変化しきい値は、それを適用するハンドラと同じ場所に置きます。
    ポーリングを起こすスレッドではありません。 }
  if Assigned(FPollSinkObj) then
    FPollSinkObj.SetThresholdHz(APolicy.FreqChangeThresholdHz);
end;

function TRigService.GetCurrentPolicy: TRigTimeoutPolicy;
begin
  Result := FPolicy;
end;

{ ----------------- Event setters ----------------- }

procedure TRigService.SetOnConnectionChanged(AHandler: TRigConnectEvent);
begin
  FOnConnectionChanged := AHandler;
end;

procedure TRigService.SetOnFrequencyChanged(AHandler: TRigFreqChangedEvent);
begin
  FOnFrequencyChanged := AHandler;
end;

procedure TRigService.SetOnError(AHandler: TRigErrorEvent);
begin
  FOnError := AHandler;
end;

procedure TRigService.SetOnLibraryWarning(AHandler: TRigLibraryWarningEvent);
begin
  FOnLibraryWarning := AHandler;
end;

function TRigService.GetLibraryStatus: TRigLibraryStatus;
begin
  Result := FLibStatus;
end;

{ ----------------- State snapshot (Pull model) ----------------- }


{ ====================================================================
  Rev.6.0 — levels, functions, split and VFO
  Rev.6.0 - レベル・ファンクション・スプリット・VFO
  ==================================================================== }

{$PUSH}{$WARN 5027 OFF}
function TRigService.MakeLevelSink(
  ACallback: TRigLevelCallback): TRigLevelInternalCallback;
var
  Sink: TUserLevelCallbackDispatch;
begin
  { Assign to a local first — @TClass.Create(...).Method yields a
    method pointer with a bogus Self. The same trap as every other
    Make*Sink in this unit.
    まず局所変数に代入します。@TClass.Create(...).Method は Self が
    不正なメソッドポインタになります。本ユニットの他の Make*Sink と
    同じ罠です。 }
  Sink   := TUserLevelCallbackDispatch.Create(ACallback, FOnError, FStateHolder);
  Result := @Sink.InternalLevelCallback;
end;

function TRigService.MakeFuncSink(
  ACallback: TRigFuncCallback): TRigFuncInternalCallback;
var
  Sink: TUserFuncCallbackDispatch;
begin
  Sink   := TUserFuncCallbackDispatch.Create(ACallback, FOnError);
  Result := @Sink.InternalFuncCallback;
end;

function TRigService.MakeSplitSink(
  ACallback: TRigSplitCallback): TRigSplitInternalCallback;
var
  Sink: TUserSplitCallbackDispatch;
begin
  Sink   := TUserSplitCallbackDispatch.Create(ACallback, FOnError, FStateHolder);
  Result := @Sink.InternalSplitCallback;
end;

function TRigService.MakeVfoSink(
  ACallback: TRigVfoCallback): TRigVfoInternalCallback;
var
  Sink: TUserVfoCallbackDispatch;
begin
  Sink   := TUserVfoCallbackDispatch.Create(ACallback, FOnError, FStateHolder);
  Result := @Sink.InternalVfoCallback;
end;
{$POP}

function TRigService.GetLevelAsync(ALevel: TRigLevel;
                                    ACallback: TRigLevelCallback;
                                    AVfo: TRigVfo): ICancellationToken;
var
  Token: TRigCancellationToken;
begin
  if ALevel = rlvNone then
    raise EArgumentException.Create(
      'ALevel must name a level (e.g. rlvStrength for the S-meter)');
  EnsureOpen;

  Token  := TRigCancellationToken.Create;
  Result := Token;
  FWorker.PostCommand(
    TGetLevelCommand.Create(ALevel, AVfo, Token, MakeLevelSink(ACallback)));
end;

function TRigService.SetLevelFloatAsync(ALevel: TRigLevel; AValue: Double;
                                         ACallback: TRigCommandCallback;
                                         AVfo: TRigVfo): ICancellationToken;
var
  Token: TRigCancellationToken;
begin
  if ALevel = rlvNone then
    raise EArgumentException.Create('ALevel must name a level');

  { A meter is a reading, not a setting. Hamlib would return an error,
    but the caller would have to wait for a round trip to learn that
    their code is wrong rather than their rig.
    メータは読み値であって設定ではありません。Hamlib もエラーを返し
    ますが、それでは「リグではなく自分のコードが誤っている」ことを知る
    のに往復を 1 回待つことになります。 }
  if THamlibLevelCodec.IsReadOnlyLevel(ALevel) then
    raise EArgumentException.CreateFmt(
      '%s is a meter and cannot be set',
      [THamlibLevelCodec.ToDisplayString(ALevel)]);

  if not THamlibLevelCodec.IsFloatLevel(ALevel) then
    raise EArgumentException.CreateFmt(
      '%s takes an integer; use SetLevelIntAsync',
      [THamlibLevelCodec.ToDisplayString(ALevel)]);

  EnsureOpen;
  Token  := TRigCancellationToken.Create;
  Result := Token;
  FWorker.PostCommand(
    TSetLevelCommand.CreateFloat(ALevel, AValue, AVfo, Token,
                                 MakeCommandSink(ACallback)));
end;

function TRigService.SetLevelIntAsync(ALevel: TRigLevel; AValue: Integer;
                                       ACallback: TRigCommandCallback;
                                       AVfo: TRigVfo): ICancellationToken;
var
  Token: TRigCancellationToken;
begin
  if ALevel = rlvNone then
    raise EArgumentException.Create('ALevel must name a level');
  if THamlibLevelCodec.IsReadOnlyLevel(ALevel) then
    raise EArgumentException.CreateFmt(
      '%s is a meter and cannot be set',
      [THamlibLevelCodec.ToDisplayString(ALevel)]);
  if THamlibLevelCodec.IsFloatLevel(ALevel) then
    raise EArgumentException.CreateFmt(
      '%s takes a float 0.0..1.0; use SetLevelFloatAsync',
      [THamlibLevelCodec.ToDisplayString(ALevel)]);

  EnsureOpen;
  Token  := TRigCancellationToken.Create;
  Result := Token;
  FWorker.PostCommand(
    TSetLevelCommand.CreateInt(ALevel, AValue, AVfo, Token,
                               MakeCommandSink(ACallback)));
end;

function TRigService.GetFuncAsync(AFunc: TRigFunc;
                                   ACallback: TRigFuncCallback;
                                   AVfo: TRigVfo): ICancellationToken;
var
  Token: TRigCancellationToken;
begin
  if AFunc = rfnNone then
    raise EArgumentException.Create('AFunc must name a function');
  EnsureOpen;
  Token  := TRigCancellationToken.Create;
  Result := Token;
  FWorker.PostCommand(
    TGetFuncCommand.Create(AFunc, AVfo, Token, MakeFuncSink(ACallback)));
end;

function TRigService.SetFuncAsync(AFunc: TRigFunc; AActive: Boolean;
                                   ACallback: TRigCommandCallback;
                                   AVfo: TRigVfo): ICancellationToken;
var
  Token: TRigCancellationToken;
begin
  if AFunc = rfnNone then
    raise EArgumentException.Create('AFunc must name a function');
  EnsureOpen;
  Token  := TRigCancellationToken.Create;
  Result := Token;
  FWorker.PostCommand(
    TSetFuncCommand.Create(AFunc, AActive, AVfo, Token,
                           MakeCommandSink(ACallback)));
end;

function TRigService.SetSplitAsync(AEnabled: Boolean; ATxVfo: TRigVfo;
                                    ACallback: TRigCommandCallback): ICancellationToken;
var
  Token: TRigCancellationToken;
begin
  { Turning split ON requires a transmit VFO that is not "the current
    one". rvfoCurr here tells the rig to transmit on the VFO it is
    already receiving on, which is not split at all — but the rig
    accepts it, the call succeeds, and the application believes it is
    set up to work a DX station while transmitting on the station's own
    frequency.

    SetVfoAsync already refuses rvfoCurr as meaningless. This call
    accepted it while being far more dangerous, because rvfoCurr is the
    parameter's default: SetSplitAsync(True) — the shortest form — was
    the hazardous one.

    スプリットを「入れる」には、「現在の VFO」ではない送信 VFO が必要
    です。ここで rvfoCurr を渡すことは、既に受信している VFO で送信せよ
    とリグに告げることであり、それはスプリットではありません。しかもリグ
    は受理し、呼び出しは成功し、アプリケーションは DX 局と交信する準備が
    できたと信じたまま、その局自身の周波数で送信します。

    SetVfoAsync は既に rvfoCurr を無意味として拒否しています。本呼び出し
    ははるかに危険でありながら受理していました。rvfoCurr がこの引数の
    既定値だからです。最短形である SetSplitAsync(True) こそが危険でした。 }
  if AEnabled and (ATxVfo = rvfoCurr) then
    raise EArgumentException.Create(
      'ATxVfo must name the transmit VFO (rvfoA, rvfoB, rvfoMain or '
      + 'rvfoSub). Splitting onto "the current VFO" would transmit on '
      + 'the receive frequency.');

  EnsureOpen;
  Token  := TRigCancellationToken.Create;
  Result := Token;
  FWorker.PostCommand(
    TSetSplitCommand.Create(AEnabled, ATxVfo, Token,
                            MakeCommandSink(ACallback)));
end;

function TRigService.GetSplitAsync(
  ACallback: TRigSplitCallback): ICancellationToken;
var
  Token: TRigCancellationToken;
begin
  EnsureOpen;
  Token  := TRigCancellationToken.Create;
  Result := Token;
  FWorker.PostCommand(
    TGetSplitCommand.Create(Token, MakeSplitSink(ACallback)));
end;

function TRigService.SetSplitFreqAsync(AFreq: Double;
                                        ACallback: TRigCommandCallback): ICancellationToken;
var
  Token: TRigCancellationToken;
begin
  { The same bounds as SetFrequencyAsync: a transmit frequency is a
    frequency, and the failure mode of a typo is identical.
    SetFrequencyAsync と同じ範囲検査です。送信周波数も周波数であり、
    打ち間違いの失敗の仕方も同じです。 }
  if AFreq <= 0 then
    raise EArgumentException.CreateFmt(
      'AFreq must be positive, got %.0f', [AFreq]);
  if AFreq > MAX_FREQ_HZ then
    raise EArgumentException.CreateFmt(
      'AFreq %.0f Hz is beyond any amateur rig (max %.0f)',
      [AFreq, MAX_FREQ_HZ]);
  EnsureOpen;
  Token  := TRigCancellationToken.Create;
  Result := Token;
  FWorker.PostCommand(
    TSetSplitFreqCommand.Create(AFreq, Token, MakeCommandSink(ACallback)));
end;

function TRigService.SetVfoAsync(AVfo: TRigVfo;
                                  ACallback: TRigCommandCallback): ICancellationToken;
var
  Token: TRigCancellationToken;
begin
  { rvfoCurr means "whichever is current", so selecting it is a
    no-operation dressed as a command.
    rvfoCurr は「現在のもの」という意味なので、それを選択するのは
    コマンドの体裁をした無操作です。 }
  if AVfo = rvfoCurr then
    raise EArgumentException.Create(
      'Name the VFO to select (rvfoA, rvfoB, rvfoMain, rvfoSub)');
  EnsureOpen;
  Token  := TRigCancellationToken.Create;
  Result := Token;
  FWorker.PostCommand(
    TSetVfoCommand.Create(AVfo, Token, MakeCommandSink(ACallback)));
end;

function TRigService.GetVfoAsync(
  ACallback: TRigVfoCallback): ICancellationToken;
var
  Token: TRigCancellationToken;
begin
  EnsureOpen;
  Token  := TRigCancellationToken.Create;
  Result := Token;
  FWorker.PostCommand(TGetVfoCommand.Create(Token, MakeVfoSink(ACallback)));
end;

function TRigService.VfoOpAsync(AOp: TRigVfoOp;
                                 ACallback: TRigCommandCallback;
                                 AVfo: TRigVfo): ICancellationToken;
var
  Token: TRigCancellationToken;
begin
  if AOp = rvoNone then
    raise EArgumentException.Create('AOp must name an operation');
  EnsureOpen;
  Token  := TRigCancellationToken.Create;
  Result := Token;
  FWorker.PostCommand(
    TVfoOpCommand.Create(AOp, AVfo, Token, MakeCommandSink(ACallback)));
end;

function TRigService.GetCapabilities: TRigCapabilities;
begin
  Result := FCaps;
end;

procedure TRigService.AddConfToken(const AName, AValue: string);
begin
  if Trim(AName) = '' then
    raise EArgumentException.Create('AName must be a Hamlib conf token name');

  { Before Open, because Hamlib applies most tokens while opening the
    port. Refusing afterwards is clearer than accepting a setting that
    will quietly do nothing.
    Open より前である必要があります。Hamlib は大半のトークンをポート
    オープン時に適用するためです。後から受け付けて静かに無効になるより、
    拒否する方が明確です。 }
  if FOpen then
    raise ERigServiceOpen.Create(
      'Conf tokens must be added before Open; Hamlib applies them ' +
      'while opening the port');

  FConfTokens.Values[Trim(AName)] := AValue;
end;

function TRigService.GetCurrentState: TRigState;
begin
  { The holder copies the whole record under its own lock, so the caller
    receives an independent value and may read it from any thread.
    ホルダーが自身のロック内で全レコードをコピーするため、呼び出し元は
    独立した値を受け取り、任意のスレッドから読めます。 }
  Result := FStateHolder.Snapshot;
end;

{ ----------------- Diagnostics ----------------- }

function TRigService.GetQueueDepth: Integer;
begin
  if Assigned(FWorker) then
    Result := FWorker.QueueDepth
  else
    Result := 0;
end;

function TRigService.GetCircuitBreakerOpen: Boolean;
begin
  Result := Assigned(FWorker) and FWorker.CircuitBreakerOpen;
end;

{ ----------------- Internal handlers ----------------- }

procedure TRigService.HandleWorkerConnectionChanged(Sender: TObject;
                                                     AConnected: Boolean);
var
  HandlerCopy: TRigConnectEvent;
begin
  UpdateStateConnected(AConnected);
  HandlerCopy := FOnConnectionChanged;
  if Assigned(HandlerCopy) then
    HandlerCopy(nil, AConnected);
end;

procedure TRigService.HandleWorkerError(Sender: TObject;
                                         AKind: TRigErrorKind;
                                         ANativeCode: Integer;
                                         const AMsg: string);
var
  HandlerCopy: TRigErrorEvent;
begin
  { Copy the handler before calling it: the application may free this
    Service from inside its own error handler.
    呼び出し前にハンドラをコピーします。アプリケーションが自身のエラー
    ハンドラの中から本 Service を破棄する可能性があるためです。 }
  HandlerCopy := FOnError;
  if Assigned(HandlerCopy) then
    HandlerCopy(nil, AKind, ANativeCode, AMsg);
end;

procedure TRigService.HandlePollerFreqChanged(Sender: TObject; AFreq: Double);
var
  HandlerCopy: TRigFreqChangedEvent;
begin
  { rvfoCurr, not rvfoA. The poller reads RIG_VFO_CURR and is told the
    frequency of whichever VFO the rig has selected; it is never told
    which one that is. Naming rvfoA here was the component asserting a
    fact it had not been given, and it made the snapshot report the
    transmit frequency as VFO A's whenever the operator was on VFO B.

    rvfoA ではなく rvfoCurr です。ポーラは RIG_VFO_CURR を読み、リグが
    選択している VFO の周波数を受け取りますが、それがどの VFO かは決して
    告げられません。ここで rvfoA と名指すことは、与えられていない事実を
    コンポーネントが主張することであり、オペレータが VFO B に居る間、
    スナップショットに送信周波数を VFO A のものとして報告させていました。 }
  UpdateStateFreq(rvfoCurr, AFreq);
  HandlerCopy := FOnFrequencyChanged;
  if Assigned(HandlerCopy) then
    HandlerCopy(nil, AFreq);
end;

{ Thin forwarders to the holder. Kept so the call sites read the same as
  before and so the snapshot stays the single source of truth.
  ホルダーへの薄い転送。呼び出し側の記述を従来どおりに保ち、
  スナップショットを唯一の真実の源として維持します。 }

procedure TRigService.UpdateStateFreq(AVfo: TRigVfo; AFreq: Double);
begin
  FStateHolder.SetFreq(AVfo, AFreq);
end;

procedure TRigService.UpdateStateConnected(AConnected: Boolean);
begin
  FStateHolder.SetConnected(AConnected);
end;

procedure TRigService.InjectPollerFreqResult(const AResult: TRigFreqResult);
begin
  { Test injection point. Subclass-only access via protected.
    テスト注入ポイント。protected によりサブクラスのみがアクセス可能。 }
  if AResult.Status = rcsSuccess then
  begin
    UpdateStateFreq(rvfoA, AResult.Freq);
    if Assigned(FOnFrequencyChanged) then
      FOnFrequencyChanged(Self, AResult.Freq);
  end;
end;

end.
