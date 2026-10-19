{
  HamlibDispatch.pas

  Internal delivery helpers used by TRigService to wrap user callbacks
  with the error-fallback routing logic. NOT for application use.

  TRigService がユーザコールバックをエラーフォールバック経路ロジックで
  ラップするための内部配送ヘルパー。アプリケーションは使用しません。

  Why this unit exists:
  --------------------
  In Rev.4.0 design, when a user calls SetFrequencyAsync(freq) without a
  callback, errors must be routed to OnError. With anonymous methods
  (Delphi/FPC trunk), this is one inline closure. FPC 3.2.x lacks
  Delphi-style anonymous methods, so we use small dispatch objects that
  hold the user callback and the OnError snapshot by value, and
  implement the routing logic in a regular method.

  本ユニットの存在理由:
  --------------------
  Rev.4.0 設計では、利用者がコールバックなしで SetFrequencyAsync(freq) を
  呼ぶ場合、エラーは OnError に経路設定されます。匿名メソッド (Delphi/FPC
  trunk) があれば 1 つのインラインクロージャで済みます。FPC 3.2.x は
  Delphi 形式の匿名メソッドがないため、ユーザコールバックと OnError
  スナップショットを値で保持し、経路ロジックを通常のメソッドで実装する
  小さな配送オブジェクトを使います。

  Layer:    L4 (used by Service)
  Depends:  HamlibInterfaces, HamlibCommandBase
}
unit HamlibDispatch;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  HamlibInterfaces, HamlibStateHolder, HamlibCommandBase, HamlibFreqCommands,
  HamlibModeCommands, HamlibRigCommands;

type
  { ====================================================================
    TUserCallbackDispatch (generic / void result)
    TUserCallbackDispatch (汎用 / 戻り値なし結果)
    ====================================================================
    Wraps a TRigCommandCallback. If the user callback is assigned, calls
    it; otherwise routes error-class statuses to the snapshot OnError.

    TRigCommandCallback をラップします。ユーザコールバックが代入されて
    いればそれを呼び、そうでない場合はエラー系ステータスをスナップショット
    OnError へ経路設定します。 }
  TUserCallbackDispatch = class
  private
    FUserCallback:  TRigCommandCallback;
    FErrSnapshot:   TRigErrorEvent;
  public
    constructor Create(AUserCallback: TRigCommandCallback;
                       AErrSnapshot: TRigErrorEvent);

    { Bridge method passed to the Command as TRigInternalCallback. The
      Worker's DeliverAndFree invokes this on the UI thread.

      コマンドに TRigInternalCallback として渡されるブリッジメソッド。
      Worker の DeliverAndFree が UI スレッドでこれを呼びます。 }
    procedure InternalCallback(const AResult: TRigResult);
  end;

  { ====================================================================
    TUserFreqCallbackDispatch (frequency get result)
    TUserFreqCallbackDispatch (周波数取得結果)
    ====================================================================
    On success it also refreshes the Pull-model snapshot. The snapshot
    lives in a reference-counted IRigStateHolder, so it stays alive for
    as long as this dispatcher does — even if the Service was destroyed
    while this callback was still queued on the UI thread.

    成功時には Pull モデルのスナップショットも更新します。スナップショットは
    参照カウント管理の IRigStateHolder に置かれるため、本ディスパッチャが
    生存する限り有効です。コールバックが UI スレッドのキューに残っている
    間に Service が破棄されても安全です。 }
  TUserFreqCallbackDispatch = class
  private
    FUserCallback:  TRigFreqCallback;
    FErrSnapshot:   TRigErrorEvent;
    FStateHolder:   IRigStateHolder;    { refcounted — never dangles
                                          参照カウント管理 — ダングリングしない }
    FTargetVfo:     TRigVfo;

    { Optional. When the callback belongs to an object the component
      itself owns and may free before this delivery runs — the poller's
      result handler is the one such case — that object is held here by
      reference count so it cannot be freed underneath us.

      任意。コールバックがコンポーネント自身の所有物であり、本配送の実行
      前に解放されうるオブジェクトに属する場合 (該当するのはポーラの結果
      ハンドラ 1 つだけ)、そのオブジェクトをここで参照カウント保持し、
      足元で解放されないようにします。 }
    FKeepAlive:     IRigDeliveryKeepAlive;
  public
    constructor Create(AUserCallback: TRigFreqCallback;
                       AErrSnapshot: TRigErrorEvent;
                       AStateHolder: IRigStateHolder;
                       ATargetVfo: TRigVfo;
                       AKeepAlive: IRigDeliveryKeepAlive = nil);
    destructor  Destroy; override;

    procedure InternalFreqCallback(const AResult: TRigFreqResult);
  end;

  { ====================================================================
    TUserPttCallbackDispatch (PTT set result)
    TUserPttCallbackDispatch (PTT 設定結果)
    ====================================================================
    A PTT *set* has no reply value, but a successful one tells us what
    the rig is now doing: it is the state we just commanded and the rig
    confirmed. Recording that is not a guess, and it is the only source
    the snapshot has for PttActive — IRigService exposes no PTT query.

    PTT の set には応答値がありませんが、成功した set は現在リグが何を
    しているかを教えます。こちらが指示し、リグが受理した状態そのもの
    です。これを記録するのは推測ではありません。かつ IRigService に PTT
    の問い合わせ API が無いため、スナップショットの PttActive の情報源は
    これだけです。

    On failure nothing is recorded: a rejected set leaves the rig in
    whatever state it was already in, which we do not know.
    失敗時は何も記録しません。拒否された set はリグを元の状態に残し、
    その状態は我々には分からないためです。 }
  TUserPttCallbackDispatch = class
  private
    FUserCallback: TRigCommandCallback;
    FErrSnapshot:  TRigErrorEvent;
    FStateHolder:  IRigStateHolder;
    FRequested:    Boolean;
  public
    constructor Create(AUserCallback: TRigCommandCallback;
                       AErrSnapshot: TRigErrorEvent;
                       AStateHolder: IRigStateHolder;
                       ARequestedActive: Boolean);
    destructor  Destroy; override;
    procedure InternalCallback(const AResult: TRigResult);
  end;

  { ====================================================================
    TUserModeCallbackDispatch
    ==================================================================== }
  TUserModeCallbackDispatch = class
  private
    FUserCallback: TRigModeCallback;
    FErrSnapshot:  TRigErrorEvent;
    FStateHolder:  IRigStateHolder;    { refcounted — never dangles
                                         参照カウント管理 — ダングリングしない }
  public
    constructor Create(AUserCallback: TRigModeCallback;
                       AErrSnapshot: TRigErrorEvent;
                       AStateHolder: IRigStateHolder);
    destructor  Destroy; override;
    procedure InternalModeCallback(const AResult: TRigModeResult);
  end;

  { ====================================================================
    Dispatchers for the Rev.6.0 result types.
    Rev.6.0 の結果型に対するディスパッチャ。
    ====================================================================
    Same contract as the others: call the user callback if there is
    one, otherwise route error-class statuses to the OnError snapshot,
    then self-destruct. The level dispatcher additionally feeds the
    S-meter into the Pull-model snapshot, because a meter is exactly
    the kind of value a UI wants to read on a timer rather than
    receive as an event.

    他と同じ契約です。ユーザコールバックがあれば呼び、なければエラー系
    ステータスを OnError スナップショットへ経路設定し、自己破棄します。
    レベルのディスパッチャは加えて S メータを Pull モデルのスナップ
    ショットに流し込みます。メータは、イベントで受け取るよりタイマで
    読みたい類の値だからです。 }
  TUserLevelCallbackDispatch = class
  private
    FUserCallback: TRigLevelCallback;
    FErrSnapshot:  TRigErrorEvent;
    FStateHolder:  IRigStateHolder;
  public
    constructor Create(AUserCallback: TRigLevelCallback;
                       AErrSnapshot: TRigErrorEvent;
                       AStateHolder: IRigStateHolder);
    destructor  Destroy; override;
    procedure InternalLevelCallback(const AResult: TRigLevelResult);
  end;

  TUserFuncCallbackDispatch = class
  private
    FUserCallback: TRigFuncCallback;
    FErrSnapshot:  TRigErrorEvent;
  public
    constructor Create(AUserCallback: TRigFuncCallback;
                       AErrSnapshot: TRigErrorEvent);
    procedure InternalFuncCallback(const AResult: TRigFuncResult);
  end;

  TUserSplitCallbackDispatch = class
  private
    FUserCallback: TRigSplitCallback;
    FErrSnapshot:  TRigErrorEvent;
    FStateHolder:  IRigStateHolder;
  public
    constructor Create(AUserCallback: TRigSplitCallback;
                       AErrSnapshot: TRigErrorEvent;
                       AStateHolder: IRigStateHolder);
    destructor  Destroy; override;
    procedure InternalSplitCallback(const AResult: TRigSplitResult);
  end;

  TUserVfoCallbackDispatch = class
  private
    FUserCallback: TRigVfoCallback;
    FErrSnapshot:  TRigErrorEvent;
    FStateHolder:  IRigStateHolder;
  public
    constructor Create(AUserCallback: TRigVfoCallback;
                       AErrSnapshot: TRigErrorEvent;
                       AStateHolder: IRigStateHolder);
    destructor  Destroy; override;
    procedure InternalVfoCallback(const AResult: TRigVfoResult);
  end;

implementation

{ ============= TUserCallbackDispatch ============= }

constructor TUserCallbackDispatch.Create(AUserCallback: TRigCommandCallback;
                                          AErrSnapshot: TRigErrorEvent);
begin
  inherited Create;
  FUserCallback := AUserCallback;
  FErrSnapshot  := AErrSnapshot;
end;

procedure TUserCallbackDispatch.InternalCallback(const AResult: TRigResult);
begin
  try
    { User callback wins if assigned. ユーザコールバック優先。 }
    if Assigned(FUserCallback) then
    begin
      FUserCallback(AResult);
      Exit;
    end;
    { Fallback: route error-class statuses to OnError snapshot.
      rcsCancelled is normal lifecycle, not an error.
      フォールバック: エラー系ステータスを OnError スナップショットへ。
      rcsCancelled は正常ライフサイクルでありエラーではない。 }
    if (AResult.Status in [rcsError, rcsTimeout, rcsRejected])
       and Assigned(FErrSnapshot) then
      FErrSnapshot(nil, AResult.Error, AResult.NativeCode, AResult.ErrorMsg);
  finally
    Free;   { Self-destruct after one delivery. 1 回配送後に自己破棄。 }
  end;
end;

{ ============= TUserFreqCallbackDispatch ============= }

constructor TUserFreqCallbackDispatch.Create(AUserCallback: TRigFreqCallback;
                                              AErrSnapshot: TRigErrorEvent;
                                              AStateHolder: IRigStateHolder;
                                              ATargetVfo: TRigVfo;
                                             AKeepAlive: IRigDeliveryKeepAlive);
begin
  inherited Create;
  FUserCallback := AUserCallback;
  FErrSnapshot  := AErrSnapshot;
  FStateHolder  := AStateHolder;   { takes a reference / 参照を取得 }
  FTargetVfo    := ATargetVfo;
  FKeepAlive    := AKeepAlive;     { takes a reference / 参照を取得 }
end;

destructor TUserFreqCallbackDispatch.Destroy;
begin
  FKeepAlive   := nil;             { releases it / 参照を解放 }
  FStateHolder := nil;             { releases it / 参照を解放 }
  inherited;
end;

procedure TUserFreqCallbackDispatch.InternalFreqCallback(const AResult: TRigFreqResult);
begin
  try
    if (AResult.Status = rcsSuccess) and Assigned(FStateHolder) then
      FStateHolder.SetFreq(FTargetVfo, AResult.Freq);

    if Assigned(FUserCallback) then
    begin
      FUserCallback(AResult);
      Exit;
    end;
    if (AResult.Status in [rcsError, rcsTimeout, rcsRejected])
       and Assigned(FErrSnapshot) then
      FErrSnapshot(nil, AResult.Error, AResult.NativeCode, AResult.ErrorMsg);
  finally
    Free;
  end;
end;

{ ============= TUserPttCallbackDispatch ============= }

constructor TUserPttCallbackDispatch.Create(AUserCallback: TRigCommandCallback;
                                             AErrSnapshot: TRigErrorEvent;
                                             AStateHolder: IRigStateHolder;
                                             ARequestedActive: Boolean);
begin
  inherited Create;
  FUserCallback := AUserCallback;
  FErrSnapshot  := AErrSnapshot;
  FStateHolder  := AStateHolder;   { takes a reference / 参照を取得 }
  FRequested    := ARequestedActive;
end;

destructor TUserPttCallbackDispatch.Destroy;
begin
  FStateHolder := nil;
  inherited Destroy;
end;

procedure TUserPttCallbackDispatch.InternalCallback(const AResult: TRigResult);
begin
  try
    if (AResult.Status = rcsSuccess) and Assigned(FStateHolder) then
      FStateHolder.SetPtt(FRequested);

    if Assigned(FUserCallback) then
    begin
      FUserCallback(AResult);
      Exit;
    end;
    if (AResult.Status in [rcsError, rcsTimeout, rcsRejected])
       and Assigned(FErrSnapshot) then
      FErrSnapshot(nil, AResult.Error, AResult.NativeCode, AResult.ErrorMsg);
  finally
    Free;
  end;
end;

{ ============= TUserModeCallbackDispatch ============= }

constructor TUserModeCallbackDispatch.Create(AUserCallback: TRigModeCallback;
                                              AErrSnapshot: TRigErrorEvent;
                                              AStateHolder: IRigStateHolder);
begin
  inherited Create;
  FUserCallback := AUserCallback;
  FErrSnapshot  := AErrSnapshot;
  FStateHolder  := AStateHolder;   { takes a reference / 参照を取得 }
end;

destructor TUserModeCallbackDispatch.Destroy;
begin
  FStateHolder := nil;             { release the reference / 参照を解放 }
  inherited Destroy;
end;

procedure TUserModeCallbackDispatch.InternalModeCallback(const AResult: TRigModeResult);
begin
  try
    { Refresh the Pull-model snapshot before invoking the user callback,
      so an application that reads CurrentState from inside its callback
      sees the value it was just handed.

      ユーザコールバック呼び出しの前に Pull モデルのスナップショットを
      更新します。コールバック内で CurrentState を読むアプリケーションが、
      いま渡された値と同じものを見られるようにするためです。 }
    if (AResult.Status = rcsSuccess) and Assigned(FStateHolder) then
      FStateHolder.SetMode(AResult.Mode, AResult.Passband, AResult.RawMode);

    if Assigned(FUserCallback) then
    begin
      FUserCallback(AResult);
      Exit;
    end;
    if (AResult.Status in [rcsError, rcsTimeout, rcsRejected])
       and Assigned(FErrSnapshot) then
      FErrSnapshot(nil, AResult.Error, AResult.NativeCode, AResult.ErrorMsg);
  finally
    Free;
  end;
end;

{ ============= TUserLevelCallbackDispatch ============= }

constructor TUserLevelCallbackDispatch.Create(AUserCallback: TRigLevelCallback;
                                               AErrSnapshot: TRigErrorEvent;
                                               AStateHolder: IRigStateHolder);
begin
  inherited Create;
  FUserCallback := AUserCallback;
  FErrSnapshot  := AErrSnapshot;
  FStateHolder  := AStateHolder;
end;

destructor TUserLevelCallbackDispatch.Destroy;
begin
  FStateHolder := nil;
  inherited Destroy;
end;

procedure TUserLevelCallbackDispatch.InternalLevelCallback(
  const AResult: TRigLevelResult);
begin
  try
    { Only the S-meter goes into the snapshot. Putting every level
      there would mean a record that grows with Hamlib and a snapshot
      whose fields are mostly stale; the S-meter is the one value a
      panel redraws continuously.

      スナップショットに入れるのは S メータだけです。全レベルを入れると
      Hamlib とともに肥大するレコードと、大半が古い値のスナップショットに
      なります。パネルが連続的に再描画する値は S メータだけです。 }
    if (AResult.Status = rcsSuccess) and (AResult.Level = rlvStrength)
       and Assigned(FStateHolder) then
      FStateHolder.SetStrength(AResult.IntValue);

    if Assigned(FUserCallback) then
    begin
      FUserCallback(AResult);
      Exit;
    end;
    if (AResult.Status in [rcsError, rcsTimeout, rcsRejected])
       and Assigned(FErrSnapshot) then
      FErrSnapshot(nil, AResult.Error, AResult.NativeCode, AResult.ErrorMsg);
  finally
    Free;
  end;
end;

{ ============= TUserFuncCallbackDispatch ============= }

constructor TUserFuncCallbackDispatch.Create(AUserCallback: TRigFuncCallback;
                                              AErrSnapshot: TRigErrorEvent);
begin
  inherited Create;
  FUserCallback := AUserCallback;
  FErrSnapshot  := AErrSnapshot;
end;

procedure TUserFuncCallbackDispatch.InternalFuncCallback(
  const AResult: TRigFuncResult);
begin
  try
    if Assigned(FUserCallback) then
    begin
      FUserCallback(AResult);
      Exit;
    end;
    if (AResult.Status in [rcsError, rcsTimeout, rcsRejected])
       and Assigned(FErrSnapshot) then
      FErrSnapshot(nil, AResult.Error, AResult.NativeCode, AResult.ErrorMsg);
  finally
    Free;
  end;
end;

{ ============= TUserSplitCallbackDispatch ============= }

constructor TUserSplitCallbackDispatch.Create(AUserCallback: TRigSplitCallback;
                                               AErrSnapshot: TRigErrorEvent;
                                               AStateHolder: IRigStateHolder);
begin
  inherited Create;
  FUserCallback := AUserCallback;
  FErrSnapshot  := AErrSnapshot;
  FStateHolder  := AStateHolder;
end;

destructor TUserSplitCallbackDispatch.Destroy;
begin
  FStateHolder := nil;
  inherited Destroy;
end;

procedure TUserSplitCallbackDispatch.InternalSplitCallback(
  const AResult: TRigSplitResult);
begin
  try
    if (AResult.Status = rcsSuccess) and Assigned(FStateHolder) then
      FStateHolder.SetSplit(AResult.SplitOn, AResult.TxVfo, AResult.TxFreq);

    if Assigned(FUserCallback) then
    begin
      FUserCallback(AResult);
      Exit;
    end;
    if (AResult.Status in [rcsError, rcsTimeout, rcsRejected])
       and Assigned(FErrSnapshot) then
      FErrSnapshot(nil, AResult.Error, AResult.NativeCode, AResult.ErrorMsg);
  finally
    Free;
  end;
end;

{ ============= TUserVfoCallbackDispatch ============= }

constructor TUserVfoCallbackDispatch.Create(AUserCallback: TRigVfoCallback;
                                             AErrSnapshot: TRigErrorEvent;
                                             AStateHolder: IRigStateHolder);
begin
  inherited Create;
  FUserCallback := AUserCallback;
  FErrSnapshot  := AErrSnapshot;
  FStateHolder  := AStateHolder;
end;

destructor TUserVfoCallbackDispatch.Destroy;
begin
  FStateHolder := nil;
  inherited Destroy;
end;

procedure TUserVfoCallbackDispatch.InternalVfoCallback(
  const AResult: TRigVfoResult);
begin
  try
    if (AResult.Status = rcsSuccess) and Assigned(FStateHolder) then
      FStateHolder.SetSelectedVfo(AResult.Vfo);

    if Assigned(FUserCallback) then
    begin
      FUserCallback(AResult);
      Exit;
    end;
    if (AResult.Status in [rcsError, rcsTimeout, rcsRejected])
       and Assigned(FErrSnapshot) then
      FErrSnapshot(nil, AResult.Error, AResult.NativeCode, AResult.ErrorMsg);
  finally
    Free;
  end;
end;

end.
