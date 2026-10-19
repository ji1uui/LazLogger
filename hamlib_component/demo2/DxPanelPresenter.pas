{
  DxPanelPresenter.pas

  TDxPresenter — all of DxPanel's behaviour, with no LCL dependency.

  TDxPresenter - DxPanel の振る舞いのすべて。LCL に依存しません。

  What this sample demonstrates that the first one did not
  最初のサンプルが示していなかったもの
  ------------------------------------------------------------------
    - a multi-step operation with rollback (TDxSplitSequence)
    - a level read on a timer, with application-level back-pressure so
      a slow rig cannot be made to accumulate meter requests
    - setting a float level (RF power) and an on/off function, with the
      capability answer used to decide whether to offer the control at
      all
    - a VFO operation (A/B toggle) as a single rig-side primitive
      rather than two reads and two writes
    - rig_get_caps_int shown for what it is: five fields, where empty
      means "not asked", not "not supported"

    - ロールバック付きの多段操作 (TDxSplitSequence)
    - タイマによるレベル読み取りと、アプリ水準のバックプレッシャ。遅い
      リグに対してメータ要求が溜まらないようにします
    - float レベル (RF 出力) とオン・オフ機能の設定。能力問い合わせの
      答えを使って、そのコントロールを出すかどうかを決めます
    - VFO 操作 (A/B トグル) を、2 回の読みと 2 回の書きではなくリグ側の
      プリミティブ 1 つとして扱う
    - rig_get_caps_int をありのまま示す。5 フィールドしかなく、空は
      「非対応」ではなく「問い合わせていない」を意味します

  Threading / スレッド
  ------------------------------------------------------------------
  Every method runs on the UI thread; the component delivers callbacks
  via TThread.Queue. No locks appear in this unit.

  全メソッドは UI スレッドで動きます。コンポーネントは TThread.Queue で
  コールバックを配送します。本ユニットにロックはありません。

  Layer:    demo2 (application)
  Depends:  HamlibInterfaces, HamlibErrors, HamlibCatalog, HamlibLevelCodec,
            HamlibTimeoutPolicy, HamlibFactory,
            DxPanelView, DxSplitSequence
}
unit DxPanelPresenter;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  HamlibInterfaces, HamlibErrors, HamlibCatalog, HamlibLevelCodec,
  HamlibTimeoutPolicy, HamlibFactory,
  DxPanelView, DxSplitSequence;

type
  TDxPresenter = class
  private
    FView:     IDxView;
    FFactory:  IRigServiceFactory;
    FService:  IRigService;
    FCatalog:  IRigModelCatalog;
    FSequence: TDxSplitSequence;

    FUiMode:   TDxUiMode;

    { Back-pressure for the meter. One strength read may be in flight;
      a tick that arrives while the previous read has not come back is
      dropped rather than queued.

      Without this the panel is a request generator: the timer fires
      every 250 ms, a serial rig answers rig_get_level in perhaps
      150 ms, and the first time the link stalls the queue grows for as
      long as the stall lasts. The component would survive it — the
      queue is bounded and the breaker would trip — but the operator
      would then wait for a hundred stale meter reads to drain before
      their next command ran. Dropping ticks is the correct behaviour
      for a meter: the newest reading is the only one anybody wants.

      メータのバックプレッシャ。強度読み取りは同時に 1 つだけ実行中に
      できます。前の読み取りが戻る前に来たティックは、キューに積まずに
      捨てます。

      これがないとパネルは要求生成器になります。タイマは 250 ms ごとに
      発火し、シリアル接続のリグは rig_get_level におそらく 150 ms かかり、
      リンクが一度詰まればキューは詰まっている間ずっと伸び続けます。
      コンポーネントは耐えます (キューは有界で、遮断器が働く) が、
      オペレータは次のコマンドが動くまでに古いメータ読み取り 100 件の
      消化を待つことになります。ティックを捨てるのがメータにとって
      正しい振る舞いです。最新の値だけが誰にとっても意味を持ちます。 }
    FMeterPending: Boolean;

    FLastDb:    Integer;
    FHasDb:     Boolean;

    { The raw vfo_t last reported, kept so the slow timer can redraw
      the VFO line without blanking the raw value that only the
      GetVfoAsync callback knows.
      最後に報告された生の vfo_t。遅いタイマが VFO 行を再描画するとき、
      GetVfoAsync のコールバックだけが知る生値を消さないために保持
      します。 }
    FLastRawVfo: Integer;

    { ---- component callbacks / コンポーネントのコールバック ---- }
    procedure HandleStrength(const AResult: TRigLevelResult);
    procedure HandleSimpleResult(const AResult: TRigResult);
    procedure HandleSplitRead(const AResult: TRigSplitResult);
    procedure HandleVfoRead(const AResult: TRigVfoResult);
    procedure HandleConnectionChanged(Sender: TObject; AConnected: Boolean);
    procedure HandleError(Sender: TObject; AKind: TRigErrorKind;
                          ANativeCode: Integer; const AMsg: string);
    procedure HandleLibraryWarning(Sender: TObject;
                                   const AStatus: TRigLibraryStatus;
                                   const AMessage: string);

    { ---- sequence events / シーケンスのイベント ---- }
    procedure HandleSequenceProgress(AStep: TDxSequenceStep;
                                     AIndex, ACount: Integer;
                                     const ACaption: string);
    procedure HandleSequenceFinished(ASucceeded: Boolean;
                                     AFailedStep: TDxSequenceStep;
                                     const AMessage: string);

    procedure SetUiMode(AMode: TDxUiMode);
    function  PolicyFor(const AName: string): TRigTimeoutPolicy;
    procedure PublishLibraryInfo;
    procedure PublishCapabilities;
    procedure ReleaseService;
  public
    constructor Create(const AView: IDxView;
                       const AFactory: IRigServiceFactory = nil);
    destructor  Destroy; override;

    { ---- one method per operator action / 操作 1 つにつき 1 メソッド ---- }

    procedure Initialise;
    procedure Connect(AModelNumber: Integer; const APort: string;
                      const APolicyName: string);
    procedure Disconnect;

    { Frequencies arrive in MHz because that is what the operator types
      off a DX cluster line; the conversion to Hz belongs here and not
      in the form.
      周波数は MHz で来ます。オペレータが DX クラスタの行から打つのが
      MHz だからです。Hz への変換はフォームではなくここに属します。 }
    procedure StartSplitSetup(ARxMHz, ATxMHz: Double);
    procedure AbortSplitSetup;

    { Plain split-off, for after the QSO. Not the sequence's rollback:
      this is a normal operator action that is allowed to fail
      visibly, whereas the rollback is a repair.
      交信後のための単純なスプリット解除。シーケンスのロールバックでは
      ありません。これは失敗が見えてよい通常操作であり、ロールバックは
      修復です。 }
    procedure ClearSplit;

    procedure ToggleVfo;
    procedure SetRfPowerPercent(APercent: Integer);
    procedure SetNoiseBlanker(AActive: Boolean);

    { Called from the view's fast timer (meter) and slow timer (state).
      Split in two because a meter wants to be read often and the
      snapshot costs nothing to read at all.
      view の速いタイマ (メータ) と遅いタイマ (状態) から呼ばれます。
      メータは頻繁に読みたく、スナップショットは読むコストが皆無である
      ため 2 つに分けています。 }
    procedure MeterTick;
    procedure StateTick;

    function  TryGetModel(AIndex: Integer; out AInfo: TRigModelInfo): Boolean;
  end;

implementation

{ ------------------------------------------------------------------
  Construction / 構築
  ------------------------------------------------------------------ }

constructor TDxPresenter.Create(const AView: IDxView;
                                 const AFactory: IRigServiceFactory);
begin
  inherited Create;
  Assert(Assigned(AView), 'AView must not be nil');
  FView    := AView;
  FFactory := AFactory;
  FUiMode  := duiDisconnected;
  FLastDb  := 0;
  FHasDb   := False;
  if not Assigned(FFactory) then
    FFactory := TRigServiceFactory.Create;
end;

destructor TDxPresenter.Destroy;
begin
  { Order matters: the sequence holds a cancellation token on the
    service, so it goes first.
    順序が重要です。シーケンスはサービスのキャンセルトークンを保持する
    ため、先に破棄します。 }
  FreeAndNil(FSequence);
  ReleaseService;
  FCatalog := nil;
  FFactory := nil;
  FView    := nil;
  inherited Destroy;
end;

procedure TDxPresenter.ReleaseService;
begin
  if not Assigned(FService) then
    Exit;

  { Detach the handlers before closing. A handler that fires during
    Close would be told about a connection change the presenter has
    already decided about.
    クローズ前にハンドラを外します。Close 中に発火したハンドラは、
    presenter が既に結論を出した接続変化を報告してきます。 }
  FService.SetOnConnectionChanged(nil);
  FService.SetOnError(nil);
  FService.SetOnLibraryWarning(nil);
  FService.DisablePolling;
  if FService.IsOpen then
    FService.Close;
  FService := nil;
end;

{ ------------------------------------------------------------------
  Start-up / 起動
  ------------------------------------------------------------------ }

procedure TDxPresenter.Initialise;
var
  Items: array of string;
  i:     Integer;
begin
  SetLength(Items, 0);

  FService := FFactory.CreateService;
  FService.SetOnConnectionChanged(@HandleConnectionChanged);
  FService.SetOnError(@HandleError);
  FService.SetOnLibraryWarning(@HandleLibraryWarning);

  { LibraryStatus is deliberately not read here: the component fills
    it when it loads the library, which happens on Open. Reading it
    before then returns a blank record, and a panel that printed that
    would claim "Hamlib (unknown)" on a perfectly working system.
    Building the catalogue is what forces the load, and it is also
    where the version gate fires — before any serial port is touched.

    ここで LibraryStatus を読まないのは意図的です。コンポーネントが
    これを埋めるのはライブラリをロードしたとき、すなわち Open 時です。
    それ以前に読むと空レコードが返り、それを表示するパネルは正常な
    システムで「Hamlib (不明)」と主張します。ロードを強制するのは
    カタログの構築であり、そこがバージョンゲートの発火点でもあります
    — シリアルポートに触れる前に。 }
  try
    FCatalog := FFactory.CreateModelCatalog;
  except
    on E: EHamlibUnsupportedVersion do
    begin
      FView.ShowRigList(Items, False);
      FView.ShowNotice(dnlError, E.Message);
      SetUiMode(duiDisconnected);
      Exit;
    end;
    on E: EHamlibLoadError do
    begin
      FView.ShowRigList(Items, False);
      FView.ShowNotice(dnlError,
        'Hamlib could not be loaded: ' + E.Message);
      SetUiMode(duiDisconnected);
      Exit;
    end;
  end;

  if FCatalog.IsAvailable then
  begin
    SetLength(Items, FCatalog.Count);
    for i := 0 to FCatalog.Count - 1 do
      Items[i] := RigModelInfoToString(FCatalog.Items[i]);
    FView.ShowRigList(Items, True);
    FView.ShowNotice(dnlInfo, Format('%d models available',
                                     [FCatalog.Count]));
  end
  else
  begin
    FView.ShowRigList(Items, False);
    FView.ShowNotice(dnlWarning,
      'this Hamlib build cannot list its rigs — enter a model number '
      + 'from "rigctl --list"');
  end;

  FView.ShowSignal(0, False);
  FView.ShowSequenceProgress(0, TDxSplitSequence.StepCount, 'idle');
  SetUiMode(duiDisconnected);
end;

function TDxPresenter.PolicyFor(const AName: string): TRigTimeoutPolicy;
begin
  if SameText(AName, 'slow') then
    Result := RigPolicy_SlowCat
  else if SameText(AName, 'veryslow') then
    Result := RigPolicy_VerySlowCat
  else if SameText(AName, 'fast') then
    Result := RigPolicy_FastUsb
  else
    Result := RigPolicy_Default;
end;

procedure TDxPresenter.PublishLibraryInfo;
var
  { Not named Verdict. Inside `with FService.LibraryStatus do` that
    name resolves to the record's field, so `case Verdict of` compiled
    against the field while `Verdict := '...'` tried to assign a string
    to it — three type errors that look like the record is wrong when
    it is the `with` that is.

    Verdict という名前にはしません。`with FService.LibraryStatus do` の
    内側ではその名前はレコードのフィールドに解決されるため、
    `case Verdict of` はフィールドを見る一方 `Verdict := '...'` は
    そこへ文字列を代入しようとします。レコードが間違っているように見えて、
    実は with が原因である型エラー 3 件です。 }
  Note: string;
begin
  with FService.LibraryStatus do
  begin
    case Verdict of
      rvvVerified: Note := 'verified';
      rvvUntested: Note := 'OUTSIDE the verified range ' + SupportedRange;
    else
      Note := 'version could not be determined';
    end;
    FView.ShowLibraryInfo(Format('%s  [%s]  %s',
                                 [VersionText, LibPath, Note]));
  end;
end;

{ ------------------------------------------------------------------
  Connection / 接続
  ------------------------------------------------------------------ }

procedure TDxPresenter.Connect(AModelNumber: Integer; const APort: string;
                                const APolicyName: string);
begin
  if not Assigned(FService) then
  begin
    FView.ShowNotice(dnlError, 'Initialise has not run');
    Exit;
  end;
  if FService.IsOpen then
    Exit;

  FService.ApplyTimeoutPolicy(PolicyFor(APolicyName));

  { A conf token the application chooses, applied before Open. WSJT-X
    and fldigi both set ptt_type, because the rig's default is often
    not how the station is actually wired. The component applies tokens
    after the port and before its own timeouts, so this cannot
    silently override the policy just selected.

    アプリが選ぶ conf トークンを Open 前に設定します。WSJT-X と fldigi
    はどちらも ptt_type を設定します。リグの既定値が、実際の配線と
    異なることが多いからです。コンポーネントはトークンをポート設定の
    後、自身のタイムアウトの前に適用するため、今選んだポリシーを黙って
    上書きすることはありません。 }
  FService.AddConfToken('ptt_type', 'RIG');

  SetUiMode(duiConnecting);
  FView.ShowNotice(dnlInfo, Format('opening model %d on "%s"...',
                                   [AModelNumber, APort]));
  try
    FService.Open(AModelNumber, APort);
  except
    on E: ERigError do
    begin
      SetUiMode(duiDisconnected);
      FView.ShowNotice(dnlError, Format('%s (%s)',
        [E.Message, RigErrorKindToString(E.Kind)]));
      Exit;
    end;
    on E: Exception do
    begin
      SetUiMode(duiDisconnected);
      FView.ShowNotice(dnlError, E.Message);
      Exit;
    end;
  end;

  PublishLibraryInfo;

  FreeAndNil(FSequence);
  FSequence := TDxSplitSequence.Create(FService);
  FSequence.OnProgress := @HandleSequenceProgress;
  FSequence.OnFinished := @HandleSequenceFinished;

  FMeterPending := False;
  FHasDb        := False;
  FLastRawVfo   := 0;

  FService.EnablePolling(500);
  PublishCapabilities;
  FService.GetVfoAsync(@HandleVfoRead);
  FService.GetSplitAsync(@HandleSplitRead);
  SetUiMode(duiConnected);
end;

procedure TDxPresenter.Disconnect;
begin
  if not Assigned(FService) then
    Exit;

  { The sequence is destroyed before the service is closed, so its
    token is cancelled while the service can still honour the cancel.
    シーケンスはサービスのクローズ前に破棄します。サービスがまだ
    キャンセルを処理できるうちにトークンをキャンセルするためです。 }
  FreeAndNil(FSequence);

  FService.DisablePolling;
  FService.CancelAllPending;
  if FService.IsOpen then
    FService.Close;

  FHasDb := False;
  FView.ShowSignal(0, False);
  FView.ShowSequenceProgress(0, TDxSplitSequence.StepCount, 'idle');
  FView.ShowCapabilities([]);
  SetUiMode(duiDisconnected);
end;

{ ------------------------------------------------------------------
  The split sequence / スプリットシーケンス
  ------------------------------------------------------------------ }

procedure TDxPresenter.StartSplitSetup(ARxMHz, ATxMHz: Double);
begin
  if not Assigned(FSequence) then
  begin
    FView.ShowNotice(dnlError, 'not connected');
    Exit;
  end;

  if not FSequence.Start(ARxMHz * 1E6, ATxMHz * 1E6) then
  begin
    { Start refuses rather than raises, so the reason has to be worked
      out here. Each of the three is an operator-visible mistake.
      Start は例外ではなく拒否を返すため、理由はここで判断します。
      3 つのいずれもオペレータに見える誤りです。 }
    if FSequence.Active then
      FView.ShowNotice(dnlWarning, 'a setup is already running')
    else if (ARxMHz <= 0) or (ATxMHz <= 0) then
      FView.ShowNotice(dnlError,
        'both frequencies must be given, in MHz')
    else
      FView.ShowNotice(dnlError, 'the rig is not open');
    Exit;
  end;

  SetUiMode(duiSequenceRunning);
end;

procedure TDxPresenter.AbortSplitSetup;
begin
  if Assigned(FSequence) then
    FSequence.Abort;
end;

procedure TDxPresenter.HandleSequenceProgress(AStep: TDxSequenceStep;
                                               AIndex, ACount: Integer;
                                               const ACaption: string);
begin
  FView.ShowSequenceProgress(AIndex, ACount, ACaption);
end;

procedure TDxPresenter.HandleSequenceFinished(ASucceeded: Boolean;
                                               AFailedStep: TDxSequenceStep;
                                               const AMessage: string);
var
  Text: string;
begin
  if ASucceeded then
    Text := AMessage
  else if AFailedStep = dxsIdle then
    Text := AMessage
  else
    Text := Format('%s: %s',
                   [TDxSplitSequence.StepCaption(AFailedStep), AMessage]);

  FView.ShowSequenceOutcome(ASucceeded, Text);

  { Read the split state back from the component's snapshot path rather
    than trusting the sequence's own record, so the panel shows what
    the rig says even when the sequence failed.
    シーケンス自身の記録を信じるのではなく、コンポーネントのスナップ
    ショット経路から読み戻します。シーケンスが失敗した場合でも、
    パネルがリグの言う内容を表示するためです。 }
  if Assigned(FService) and FService.IsOpen then
    FService.GetSplitAsync(@HandleSplitRead);

  if FUiMode = duiSequenceRunning then
    SetUiMode(duiConnected);
end;

{ ------------------------------------------------------------------
  Individual operator actions / 個別の操作
  ------------------------------------------------------------------ }

procedure TDxPresenter.ClearSplit;
begin
  if not (Assigned(FService) and FService.IsOpen) then
    Exit;
  FService.SetSplitAsync(False, rvfoCurr, @HandleSimpleResult);
  FService.GetSplitAsync(@HandleSplitRead);
end;

procedure TDxPresenter.ToggleVfo;
begin
  if not (Assigned(FService) and FService.IsOpen) then
    Exit;

  { One rig-side operation. Doing this as get-VFO then set-the-other
    would be two round trips and would race with the rig's own front
    panel; rvoToggle is what the rig's A/B button does.
    リグ側の操作 1 つです。VFO を読んで他方を設定する実装は往復 2 回に
    なり、リグ本体のパネル操作と競合します。rvoToggle はリグの A/B
    ボタンと同じものです。 }
  FService.VfoOpAsync(rvoToggle, @HandleSimpleResult);
  FService.GetVfoAsync(@HandleVfoRead);
end;

procedure TDxPresenter.SetRfPowerPercent(APercent: Integer);
begin
  if not (Assigned(FService) and FService.IsOpen) then
    Exit;
  if (APercent < 0) or (APercent > 100) then
  begin
    FView.ShowNotice(dnlError, 'RF power must be 0..100 %');
    Exit;
  end;

  { RIG_LEVEL_RFPOWER is a float level in 0..1 — this is the conversion
    an application must do, and getting it wrong by a factor of 100 is
    the mistake the component's float/int split is there to prevent.
    RIG_LEVEL_RFPOWER は 0..1 の float レベルです。この変換はアプリが
    行うべきもので、100 倍を間違えることが、コンポーネントの float/int
    分離が防ごうとしている誤りです。 }
  FService.SetLevelFloatAsync(rlvRfPower, APercent / 100.0,
                              @HandleSimpleResult);
end;

procedure TDxPresenter.SetNoiseBlanker(AActive: Boolean);
begin
  if not (Assigned(FService) and FService.IsOpen) then
    Exit;
  FService.SetFuncAsync(rfnNoiseBlanker, AActive, @HandleSimpleResult);
end;

{ ------------------------------------------------------------------
  Timers / タイマ
  ------------------------------------------------------------------ }

procedure TDxPresenter.MeterTick;
begin
  if not (Assigned(FService) and FService.IsOpen) then
    Exit;

  { No meter traffic while a sequence is running. The worker serialises
    commands, so a meter read sitting between two sequence steps delays
    the step behind it — and the one number nobody needs during setup
    is the S-meter.
    シーケンス実行中はメータの通信を行いません。ワーカーはコマンドを
    直列化するため、2 つのステップの間に挟まったメータ読み取りは後続の
    ステップを遅らせます。そして設定中に誰も必要としない数値こそ
    S メータです。 }
  if Assigned(FSequence) and FSequence.Active then
    Exit;

  if FMeterPending then
    Exit;
  if FService.CircuitBreakerOpen then
    Exit;

  FMeterPending := True;
  FService.GetLevelAsync(rlvStrength, @HandleStrength);
end;

procedure TDxPresenter.StateTick;
var
  S: TRigState;
begin
  if not Assigned(FService) then
    Exit;

  FView.ShowQueueDepth(FService.QueueDepth, FService.CircuitBreakerOpen);

  if not FService.IsOpen then
    Exit;

  S := FService.CurrentState;
  { The receive frequency is the selected VFO's frequency. In split
    the rig transmits on the other one, so this is the frequency the
    operator is listening to — which is what the RX display means.
    受信周波数とは、選択中の VFO の周波数です。スプリットではリグは
    もう一方で送信するため、これはオペレータが聞いている周波数であり、
    RX 表示が意味するものです。 }
  FView.ShowRxFrequency(S.CurrentFreq);
  FView.ShowTxFrequency(S.SplitOn, S.TxVfo, S.TxFreq);
  FView.ShowSelectedVfo(S.SelectedVfo, FLastRawVfo);
end;

{ ------------------------------------------------------------------
  Callbacks / コールバック
  ------------------------------------------------------------------ }

procedure TDxPresenter.HandleStrength(const AResult: TRigLevelResult);
begin
  FMeterPending := False;

  if AResult.Status <> rcsSuccess then
  begin
    { A rig that will not report strength is normal — many backends
      answer RIG_ENAVAIL. The meter is blanked and no error is shown,
      because repeating "no S-meter" every 250 ms would bury every
      other message.
      強度を報告しないリグは普通にあります (多くのバックエンドは
      RIG_ENAVAIL を返す)。メータは空白にし、エラーは表示しません。
      250 ms ごとに「S メータなし」を繰り返せば他のメッセージがすべて
      埋もれるからです。 }
    FHasDb := False;
    FView.ShowSignal(0, False);
    Exit;
  end;

  { rlvStrength is an integer level: dB relative to S9. Reading it as a
    float would produce a number in the hundreds of millions, which is
    why the result record carries IsFloat rather than leaving the
    caller to guess.
    rlvStrength は整数レベルで、S9 を基準とした dB です。float として
    読めば数億の値になります。だから結果レコードは IsFloat を運び、
    呼び出し側に推測させません。 }
  if AResult.IsFloat then
    FLastDb := Round(AResult.FloatValue)
  else
    FLastDb := AResult.IntValue;

  FHasDb := True;
  FView.ShowSignal(FLastDb, True);
end;

procedure TDxPresenter.HandleSimpleResult(const AResult: TRigResult);
begin
  if AResult.Status = rcsSuccess then
    Exit;
  if AResult.Status = rcsCancelled then
    Exit;
  FView.ShowNotice(dnlError, Format('%s (%s)',
    [AResult.ErrorMsg, RigErrorKindToString(AResult.Error)]));
end;

procedure TDxPresenter.HandleSplitRead(const AResult: TRigSplitResult);
begin
  if AResult.Status <> rcsSuccess then
  begin
    FView.ShowTxFrequency(False, rvfoCurr, 0);
    Exit;
  end;
  FView.ShowTxFrequency(AResult.SplitOn, AResult.TxVfo, AResult.TxFreq);
end;

procedure TDxPresenter.HandleVfoRead(const AResult: TRigVfoResult);
begin
  if AResult.Status <> rcsSuccess then
    Exit;

  { Both the domain value and the raw vfo_t are passed on. Hamlib
    answers RIG_VFO_SUB after being told RIG_VFO_B on several
    backends, and an operator comparing the panel with the rig's own
    display needs to see that rather than a panel that silently
    disagrees with the radio.
    ドメイン値と生の vfo_t の両方を渡します。複数のバックエンドで
    Hamlib は RIG_VFO_B を指示された後 RIG_VFO_SUB と答えます。パネルと
    リグ本体の表示を見比べるオペレータには、黙って食い違うパネルでは
    なく、その事実が見える必要があります。 }
  FLastRawVfo := AResult.RawVfo;
  FView.ShowSelectedVfo(AResult.Vfo, AResult.RawVfo);
end;

procedure TDxPresenter.HandleConnectionChanged(Sender: TObject;
                                                AConnected: Boolean);
begin
  if AConnected then
  begin
    FView.ShowNotice(dnlInfo, 'connected');
    Exit;
  end;

  { False means either "the attempt failed" or "the link dropped". The
    presenter knows which it asked for.
    False は「試行が失敗した」か「リンクが切れた」のいずれかです。
    どちらを依頼したかは presenter が知っています。 }
  if FUiMode in [duiConnected, duiSequenceRunning] then
    FView.ShowNotice(dnlError, 'the connection to the rig was lost')
  else
    FView.ShowNotice(dnlError, 'the rig could not be opened');

  FreeAndNil(FSequence);
  FHasDb := False;
  FView.ShowSignal(0, False);
  SetUiMode(duiDisconnected);
end;

procedure TDxPresenter.HandleError(Sender: TObject; AKind: TRigErrorKind;
                                    ANativeCode: Integer;
                                    const AMsg: string);
begin
  { Only failures with no callback of their own arrive here. The panel
    issues most commands with a callback, so this handler mostly sees
    poller failures.
    自前のコールバックを持たない失敗だけがここに届きます。パネルは
    ほとんどのコマンドをコールバック付きで発行するため、本ハンドラが
    主に見るのはポーラの失敗です。 }
  if AKind = rekCircuitOpen then
  begin
    FView.ShowNotice(dnlError,
      'too many consecutive failures — the component stopped talking '
      + 'to the rig; disconnect and check the cable');
    Exit;
  end;
  FView.ShowNotice(dnlWarning, Format('%s (%s)',
    [AMsg, RigErrorKindToString(AKind)]));
end;

procedure TDxPresenter.HandleLibraryWarning(Sender: TObject;
                                             const AStatus: TRigLibraryStatus;
                                             const AMessage: string);
begin
  FView.ShowNotice(dnlWarning, AMessage);
end;

{ ------------------------------------------------------------------
  Capability panel / 能力パネル
  ------------------------------------------------------------------ }

procedure TDxPresenter.PublishCapabilities;
var
  Caps:  TRigCapabilities;
  Lines: array of string;

  procedure Add(const AText: string);
  begin
    SetLength(Lines, Length(Lines) + 1);
    Lines[High(Lines)] := AText;
  end;

begin
  SetLength(Lines, 0);
  Caps := FService.GetCapabilities;

  if not Caps.Known then
  begin
    Add('this Hamlib build does not export rig_get_caps_int,');
    Add('so nothing can be said about the model''s capabilities.');
    FView.ShowCapabilities(Lines);
    Exit;
  end;

  if Caps.TargetableVfo then
    Add('VFO-targetable: a frequency can be set on the other VFO '
        + 'without selecting it first')
  else
    Add('not VFO-targetable: the VFO must be selected before it can '
        + 'be addressed');

  if Caps.HasPtt then
    Add('PTT: available as configured')
  else
    Add('PTT: none configured');
  Add(Format('the model''s own ptt_type is %d', [Caps.PttType]));

  if rlvStrength in Caps.GetLevels then
    Add('S-meter: rig_get_level reports RIG_LEVEL_STRENGTH')
  else
    Add('S-meter: not stated by rig_get_caps_int');

  { The honest line. rig_get_caps_int exposes five fields and nothing
    about which levels, functions or VFO operations a model supports,
    so these sets are empty for every rig. An application that read
    "empty" as "unsupported" would hide controls that work.

    正直な 1 行。rig_get_caps_int が公開するのは 5 フィールドで、どの
    レベル・機能・VFO 操作に対応するかは何も含みません。そのため
    これらの集合はどのリグでも空です。「空」を「非対応」と読むアプリは、
    動作するコントロールを隠すことになります。 }
  Add('');
  Add('Hamlib exposes only five capability fields through its stable');
  Add('C API, so the level, function and VFO-operation sets are empty.');
  Add('Empty means "not asked", never "not supported" — the only way');
  Add('to learn whether a rig does something is to ask it.');

  FView.ShowCapabilities(Lines);
end;

{ ------------------------------------------------------------------
  UI mode / UI モード
  ------------------------------------------------------------------ }

procedure TDxPresenter.SetUiMode(AMode: TDxUiMode);
begin
  FUiMode := AMode;
  FView.SetUiMode(AMode);
end;

function TDxPresenter.TryGetModel(AIndex: Integer;
                                   out AInfo: TRigModelInfo): Boolean;
begin
  Result := False;
  if not Assigned(FCatalog) then
    Exit;
  if (AIndex < 0) or (AIndex >= FCatalog.Count) then
    Exit;
  AInfo  := FCatalog.Items[AIndex];
  Result := True;
end;

end.
