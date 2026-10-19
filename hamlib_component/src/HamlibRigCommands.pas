{
  HamlibRigCommands.pas

  Commands for the operations added in Rev.6.0: levels (the S-meter),
  on/off functions, split operation, VFO selection and VFO operations.

  Rev.6.0 で追加した操作のコマンド: レベル (S メータ)、オン・オフ機能、
  スプリット運用、VFO 選択、VFO 操作。

  Why these are in their own unit / 独立ユニットにした理由
  ------------------------------------------------------------------
  HamlibFreqCommands, HamlibModeCommands and HamlibPttCommands are one
  unit per rig concept, and this file keeps that shape rather than
  growing a fourth concept into one of them. It is longer than the
  300-500 line guidance because splitting five small command pairs into
  five files would scatter one idea across the directory; the unit has
  no state and no logic beyond "translate, call, check".

  HamlibFreqCommands、HamlibModeCommands、HamlibPttCommands は「リグの
  概念 1 つにつき 1 ユニット」です。本ファイルもその形を保ち、4 つ目の
  概念をどれかに押し込むことはしていません。300〜500 行の指針を超えて
  いますが、小さなコマンド対 5 組を 5 ファイルに割ると 1 つの考えが
  ディレクトリ中に散らばります。本ユニットは状態を持たず、「変換し、
  呼び、検査する」以上のロジックもありません。

  All of them reach the rig through IHamlibRigControl, which a loader
  may not implement. When it does not, the command reports the same
  thing a Hamlib build without the symbol reports: not available.

  いずれも IHamlibRigControl 経由でリグに到達します。ローダがこれを実装
  しないこともあります。その場合コマンドは、シンボルを持たない Hamlib
  ビルドと同じ内容、すなわち「利用不可」を報告します。

  Layer:    L3
  Depends:  HamlibInterfaces, HamlibErrors, HamlibVfoCodec,
            HamlibLevelCodec, HamlibCommandBase
}
unit HamlibRigCommands;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  HamlibInterfaces, HamlibErrors, HamlibVfoCodec, HamlibLevelCodec,
  HamlibCommandBase;

type
  TRigLevelInternalCallback = procedure(const AResult: TRigLevelResult) of object;
  TRigFuncInternalCallback  = procedure(const AResult: TRigFuncResult)  of object;
  TRigSplitInternalCallback = procedure(const AResult: TRigSplitResult) of object;
  TRigVfoInternalCallback   = procedure(const AResult: TRigVfoResult)   of object;

  { ====================================================================
    TGetLevelCommand — read one level (the S-meter, SWR, RF power...).
    TGetLevelCommand - レベルを 1 つ読む (S メータ、SWR、送信出力など)。
    ==================================================================== }
  TGetLevelCommand = class(TRigCommand)
  private
    FVfo:           TRigVfo;
    FLevel:         TRigLevel;
    FIsFloat:       Boolean;
    FFloatValue:    Double;
    FIntValue:      Integer;
    FLevelCallback: TRigLevelInternalCallback;
  protected
    procedure DoExecute(ALoader: IHamlibLoader; ARig: Pointer); override;
  public
    constructor Create(ALevel: TRigLevel; AVfo: TRigVfo;
                       AToken: ICancellationToken;
                       ALevelCallback: TRigLevelInternalCallback);
    procedure BuildLevelResult(out AResult: TRigLevelResult;
                               AStatus: TRigCommandStatus;
                               AError: TRigErrorKind;
                               ANativeCode: Integer;
                               const AErrorMsg: string);
    property LevelCallback: TRigLevelInternalCallback read FLevelCallback;
  end;

  { ====================================================================
    TSetLevelCommand — write one level, as float or as int.
    TSetLevelCommand - レベルを 1 つ書く。float または int。
    ====================================================================
    Which of the two is correct is decided by THamlibLevelCodec, not by
    the caller; the Service passes what the codec said.
    どちらが正しいかは呼び出し側ではなく THamlibLevelCodec が決めます。
    Service はコーデックが言ったとおりに渡します。 }
  TSetLevelCommand = class(TRigCommand)
  private
    FVfo:        TRigVfo;
    FLevel:      TRigLevel;
    FAsFloat:    Boolean;
    FFloatValue: Double;
    FIntValue:   Integer;
  protected
    procedure DoExecute(ALoader: IHamlibLoader; ARig: Pointer); override;
  public
    constructor CreateFloat(ALevel: TRigLevel; AValue: Double; AVfo: TRigVfo;
                            AToken: ICancellationToken;
                            ACallback: TRigInternalCallback);
    constructor CreateInt(ALevel: TRigLevel; AValue: Integer; AVfo: TRigVfo;
                          AToken: ICancellationToken;
                          ACallback: TRigInternalCallback);
  end;

  { ====================================================================
    TGetFuncCommand / TSetFuncCommand — an on/off function.
    TGetFuncCommand / TSetFuncCommand - オン・オフ機能。
    ==================================================================== }
  TGetFuncCommand = class(TRigCommand)
  private
    FVfo:          TRigVfo;
    FFunc:         TRigFunc;
    FActive:       Boolean;
    FFuncCallback: TRigFuncInternalCallback;
  protected
    procedure DoExecute(ALoader: IHamlibLoader; ARig: Pointer); override;
  public
    constructor Create(AFunc: TRigFunc; AVfo: TRigVfo;
                       AToken: ICancellationToken;
                       AFuncCallback: TRigFuncInternalCallback);
    procedure BuildFuncResult(out AResult: TRigFuncResult;
                              AStatus: TRigCommandStatus;
                              AError: TRigErrorKind;
                              ANativeCode: Integer;
                              const AErrorMsg: string);
    property FuncCallback: TRigFuncInternalCallback read FFuncCallback;
  end;

  TSetFuncCommand = class(TRigCommand)
  private
    FVfo:    TRigVfo;
    FFunc:   TRigFunc;
    FActive: Boolean;
  protected
    procedure DoExecute(ALoader: IHamlibLoader; ARig: Pointer); override;
  public
    constructor Create(AFunc: TRigFunc; AActive: Boolean; AVfo: TRigVfo;
                       AToken: ICancellationToken;
                       ACallback: TRigInternalCallback);
  end;

  { ====================================================================
    TSetSplitCommand — turn split on or off.
    TSetSplitCommand - スプリットの入切。
    ==================================================================== }
  TSetSplitCommand = class(TRigCommand)
  private
    FEnabled: Boolean;
    FTxVfo:   TRigVfo;
  protected
    procedure DoExecute(ALoader: IHamlibLoader; ARig: Pointer); override;
  public
    constructor Create(AEnabled: Boolean; ATxVfo: TRigVfo;
                       AToken: ICancellationToken;
                       ACallback: TRigInternalCallback);
  end;

  { ====================================================================
    TGetSplitCommand — split state AND the transmit frequency.
    TGetSplitCommand - スプリット状態と送信周波数。
    ====================================================================
    Two Hamlib calls in one command, deliberately. An application that
    asks "am I split?" wants "split to where?" in the same breath, and
    issuing them as two commands lets the operator turn the VFO knob in
    between, producing a pair of readings that never existed together.

    意図的に Hamlib の 2 呼び出しを 1 コマンドにしています。「スプリット
    中か」を尋ねるアプリは同じ息で「どこへか」も知りたいからです。2 つの
    コマンドに分けると、その間にオペレータが VFO を回せてしまい、同時には
    存在しなかった値の組ができ上がります。

    The transmit frequency is only read when split is actually on: a rig
    that is not split has no meaningful answer, and asking anyway makes
    some backends report an error for a question nobody needed to ask.

    送信周波数はスプリットが実際に入っているときだけ読みます。スプリット
    していないリグに意味のある答えは無く、それでも尋ねると、誰も必要と
    しなかった問いに対してエラーを返すバックエンドがあります。 }
  TGetSplitCommand = class(TRigCommand)
  private
    FSplitOn:       Boolean;
    FTxVfoRaw:      Integer;
    FTxFreq:        Double;
    FSplitCallback: TRigSplitInternalCallback;
  protected
    procedure DoExecute(ALoader: IHamlibLoader; ARig: Pointer); override;
  public
    constructor Create(AToken: ICancellationToken;
                       ASplitCallback: TRigSplitInternalCallback);
    procedure BuildSplitResult(out AResult: TRigSplitResult;
                               AStatus: TRigCommandStatus;
                               AError: TRigErrorKind;
                               ANativeCode: Integer;
                               const AErrorMsg: string;
                               AApiMajor: Integer);
    property SplitCallback: TRigSplitInternalCallback read FSplitCallback;
  end;

  { TSetSplitFreqCommand — the transmit frequency used while split.
    TSetSplitFreqCommand - スプリット中に使う送信周波数。 }
  TSetSplitFreqCommand = class(TRigCommand)
  private
    FFreq: Double;
  protected
    procedure DoExecute(ALoader: IHamlibLoader; ARig: Pointer); override;
  public
    constructor Create(AFreq: Double; AToken: ICancellationToken;
                       ACallback: TRigInternalCallback);
  end;

  { ====================================================================
    TSetVfoCommand / TGetVfoCommand / TVfoOpCommand
    ==================================================================== }
  TSetVfoCommand = class(TRigCommand)
  private
    FVfo: TRigVfo;
  protected
    procedure DoExecute(ALoader: IHamlibLoader; ARig: Pointer); override;
  public
    constructor Create(AVfo: TRigVfo; AToken: ICancellationToken;
                       ACallback: TRigInternalCallback);
  end;

  TGetVfoCommand = class(TRigCommand)
  private
    FVfoRaw:      Integer;
    FVfoCallback: TRigVfoInternalCallback;
  protected
    procedure DoExecute(ALoader: IHamlibLoader; ARig: Pointer); override;
  public
    constructor Create(AToken: ICancellationToken;
                       AVfoCallback: TRigVfoInternalCallback);
    procedure BuildVfoResult(out AResult: TRigVfoResult;
                             AStatus: TRigCommandStatus;
                             AError: TRigErrorKind;
                             ANativeCode: Integer;
                             const AErrorMsg: string;
                             AApiMajor: Integer);
    property VfoCallback: TRigVfoInternalCallback read FVfoCallback;
  end;

  TVfoOpCommand = class(TRigCommand)
  private
    FVfo: TRigVfo;
    FOp:  TRigVfoOp;
  protected
    procedure DoExecute(ALoader: IHamlibLoader; ARig: Pointer); override;
  public
    constructor Create(AOp: TRigVfoOp; AVfo: TRigVfo;
                       AToken: ICancellationToken;
                       ACallback: TRigInternalCallback);
  end;

{ ------------------------------------------------------------------
  RIG_OP_* bit for a named operation, 0 for rvoNone.
  Kept here rather than in a codec unit of its own because it is one
  table used in one place.
  名前付き操作に対応する RIG_OP_* ビット。rvoNone は 0。1 箇所でしか
  使わない表 1 つなので、独立したコーデックユニットにはしていません。
  ------------------------------------------------------------------ }
function RigVfoOpToHamlib(AOp: TRigVfoOp): Integer;

implementation

const
  { RIG_ENAVAIL as returned by Hamlib (negated enum ordinal 11).
    Hamlib が返す RIG_ENAVAIL (enum 序数 11 の符号反転)。 }
  ENAVAIL = -11;

  { enum vfo_op_t from rig.h, verified against 4.5.5 and 4.7.2:
      CPY (1<<0) XCHG (1<<1) FROM_VFO (1<<2) TO_VFO (1<<3) MCL (1<<4)
      UP (1<<5) DOWN (1<<6) BAND_UP (1<<7) BAND_DOWN (1<<8)
      LEFT (1<<9) RIGHT (1<<10) TUNE (1<<11) TOGGLE (1<<12)
    rig.h の enum vfo_op_t。4.5.5 と 4.7.2 で照合済み。 }
  VFO_OP_BITS: array[TRigVfoOp] of Integer = (
    0,              { rvoNone }
    1 shl 0,        { rvoCopy }
    1 shl 1,        { rvoExchange }
    1 shl 2,        { rvoFromVfo }
    1 shl 3,        { rvoToVfo }
    1 shl 4,        { rvoMemClear }
    1 shl 5,        { rvoUp }
    1 shl 6,        { rvoDown }
    1 shl 7,        { rvoBandUp }
    1 shl 8,        { rvoBandDown }
    1 shl 9,        { rvoLeft }
    1 shl 10,       { rvoRight }
    1 shl 11,       { rvoTune }
    1 shl 12        { rvoToggle }
  );

function RigVfoOpToHamlib(AOp: TRigVfoOp): Integer;
begin
  Result := VFO_OP_BITS[AOp];
end;

{ ------------------------------------------------------------------
  Shared helper: obtain the extended role, or fail the way a Hamlib
  build without the symbols would.
  共通ヘルパー: 拡張 role を取得するか、シンボルを持たない Hamlib ビルド
  と同じ形で失敗します。
  ------------------------------------------------------------------ }
function NeedRigControl(ALoader: IHamlibLoader): IHamlibRigControl;
begin
  if not Supports(ALoader, IHamlibRigControl, Result) then
    raise ERigError.CreateFromHamlib(ENAVAIL, ALoader);
end;

{ ============= TGetLevelCommand ============= }

constructor TGetLevelCommand.Create(ALevel: TRigLevel; AVfo: TRigVfo;
                                     AToken: ICancellationToken;
                                     ALevelCallback: TRigLevelInternalCallback);
begin
  Assert(ALevel <> rlvNone, 'ALevel must name a level');
  inherited Create(AToken, nil);
  FVfo           := AVfo;
  FLevel         := ALevel;
  FIsFloat       := THamlibLevelCodec.IsFloatLevel(ALevel);
  FFloatValue    := 0;
  FIntValue      := 0;
  FLevelCallback := ALevelCallback;
end;

procedure TGetLevelCommand.DoExecute(ALoader: IHamlibLoader; ARig: Pointer);
var
  Ext:     IHamlibRigControl;
  RetCode: Integer;
  HlVfo:   Integer;
begin
  Ext     := NeedRigControl(ALoader);
  HlVfo   := TVfoCodec.ToHamlib(FVfo, ALoader.ApiMajor);
  RetCode := Ext.CallRigGetLevel(ARig, HlVfo,
                                 THamlibLevelCodec.ToHamlib(FLevel),
                                 FIsFloat, FFloatValue, FIntValue);
  CheckRig(RetCode, ALoader);
end;

procedure TGetLevelCommand.BuildLevelResult(out AResult: TRigLevelResult;
                                             AStatus: TRigCommandStatus;
                                             AError: TRigErrorKind;
                                             ANativeCode: Integer;
                                             const AErrorMsg: string);
begin
  AResult.Status     := AStatus;
  AResult.Level      := FLevel;
  AResult.IsFloat    := FIsFloat;
  AResult.FloatValue := FFloatValue;
  AResult.IntValue   := FIntValue;
  AResult.Error      := AError;
  AResult.NativeCode := ANativeCode;
  AResult.ErrorMsg   := AErrorMsg;
end;

{ ============= TSetLevelCommand ============= }

constructor TSetLevelCommand.CreateFloat(ALevel: TRigLevel; AValue: Double;
                                          AVfo: TRigVfo;
                                          AToken: ICancellationToken;
                                          ACallback: TRigInternalCallback);
begin
  Assert(ALevel <> rlvNone, 'ALevel must name a level');
  inherited Create(AToken, ACallback);
  FVfo        := AVfo;
  FLevel      := ALevel;
  FAsFloat    := True;
  FFloatValue := AValue;
  FIntValue   := 0;
end;

constructor TSetLevelCommand.CreateInt(ALevel: TRigLevel; AValue: Integer;
                                        AVfo: TRigVfo;
                                        AToken: ICancellationToken;
                                        ACallback: TRigInternalCallback);
begin
  Assert(ALevel <> rlvNone, 'ALevel must name a level');
  inherited Create(AToken, ACallback);
  FVfo        := AVfo;
  FLevel      := ALevel;
  FAsFloat    := False;
  FFloatValue := 0;
  FIntValue   := AValue;
end;

procedure TSetLevelCommand.DoExecute(ALoader: IHamlibLoader; ARig: Pointer);
var
  Ext:     IHamlibRigControl;
  RetCode: Integer;
  HlVfo:   Integer;
  Bit:     Int64;
begin
  Ext   := NeedRigControl(ALoader);
  HlVfo := TVfoCodec.ToHamlib(FVfo, ALoader.ApiMajor);
  Bit   := THamlibLevelCodec.ToHamlib(FLevel);

  if FAsFloat then
    RetCode := Ext.CallRigSetLevelFloat(ARig, HlVfo, Bit, FFloatValue)
  else
    RetCode := Ext.CallRigSetLevelInt(ARig, HlVfo, Bit, FIntValue);

  CheckRig(RetCode, ALoader);
end;

{ ============= TGetFuncCommand ============= }

constructor TGetFuncCommand.Create(AFunc: TRigFunc; AVfo: TRigVfo;
                                    AToken: ICancellationToken;
                                    AFuncCallback: TRigFuncInternalCallback);
begin
  Assert(AFunc <> rfnNone, 'AFunc must name a function');
  inherited Create(AToken, nil);
  FVfo          := AVfo;
  FFunc         := AFunc;
  FActive       := False;
  FFuncCallback := AFuncCallback;
end;

procedure TGetFuncCommand.DoExecute(ALoader: IHamlibLoader; ARig: Pointer);
var
  Ext:     IHamlibRigControl;
  RetCode: Integer;
begin
  Ext     := NeedRigControl(ALoader);
  RetCode := Ext.CallRigGetFunc(ARig,
                                TVfoCodec.ToHamlib(FVfo, ALoader.ApiMajor),
                                THamlibFuncCodec.ToHamlib(FFunc), FActive);
  CheckRig(RetCode, ALoader);
end;

procedure TGetFuncCommand.BuildFuncResult(out AResult: TRigFuncResult;
                                           AStatus: TRigCommandStatus;
                                           AError: TRigErrorKind;
                                           ANativeCode: Integer;
                                           const AErrorMsg: string);
begin
  AResult.Status     := AStatus;
  AResult.Func       := FFunc;
  AResult.Active     := FActive;
  AResult.Error      := AError;
  AResult.NativeCode := ANativeCode;
  AResult.ErrorMsg   := AErrorMsg;
end;

{ ============= TSetFuncCommand ============= }

constructor TSetFuncCommand.Create(AFunc: TRigFunc; AActive: Boolean;
                                    AVfo: TRigVfo;
                                    AToken: ICancellationToken;
                                    ACallback: TRigInternalCallback);
begin
  Assert(AFunc <> rfnNone, 'AFunc must name a function');
  inherited Create(AToken, ACallback);
  FVfo    := AVfo;
  FFunc   := AFunc;
  FActive := AActive;
end;

procedure TSetFuncCommand.DoExecute(ALoader: IHamlibLoader; ARig: Pointer);
var
  Ext:     IHamlibRigControl;
  RetCode: Integer;
begin
  Ext     := NeedRigControl(ALoader);
  RetCode := Ext.CallRigSetFunc(ARig,
                                TVfoCodec.ToHamlib(FVfo, ALoader.ApiMajor),
                                THamlibFuncCodec.ToHamlib(FFunc), FActive);
  CheckRig(RetCode, ALoader);
end;

{ ============= TSetSplitCommand ============= }

constructor TSetSplitCommand.Create(AEnabled: Boolean; ATxVfo: TRigVfo;
                                     AToken: ICancellationToken;
                                     ACallback: TRigInternalCallback);
begin
  inherited Create(AToken, ACallback);
  FEnabled := AEnabled;
  FTxVfo   := ATxVfo;
end;

procedure TSetSplitCommand.DoExecute(ALoader: IHamlibLoader; ARig: Pointer);
var
  Ext:      IHamlibRigControl;
  RetCode:  Integer;
  TxVfoRaw: Integer;
  WasOn:    Boolean;
  Existing: Integer;
begin
  Ext := NeedRigControl(ALoader);

  TxVfoRaw := TVfoCodec.ToHamlib(FTxVfo, ALoader.ApiMajor);

  { Turning split OFF with no transmit VFO named.

    rig_set_split_vfo takes a tx_vfo even when it is being told to
    disable, and whatever is passed is what the rig records. Passing
    RIG_VFO_CURR therefore overwrites the rig's memory of which VFO
    transmits — measured by running the same sequence through Hamlib's
    own rigctld, which answers "VFOB" where this component answered
    "currVFO" (tools/differential.py, step 21).

    That matters because the next SetSplitAsync(True) would then be
    nominating a transmit VFO that no longer means anything. So the
    existing nomination is read first and handed straight back: turning
    split off stops transmitting elsewhere, and changes nothing else.

    The read is allowed to fail. Disabling split is a safety operation
    and must not be blocked by an inability to read the rig — if the
    query fails, the original behaviour stands.

    送信 VFO を指定せずにスプリットを「切る」場合。

    rig_set_split_vfo は、無効化を指示されるときでも tx_vfo を取り、
    渡されたものがそのままリグに記録されます。したがって RIG_VFO_CURR を
    渡すと、どの VFO が送信するかというリグの記憶を上書きします。これは
    同一の操作列を Hamlib 自身の rigctld に流して実測したものです。
    rigctld が "VFOB" と答える箇所で、本コンポーネントは "currVFO" と
    答えていました (tools/differential.py のステップ 21)。

    これが問題なのは、次の SetSplitAsync(True) が、もはや何も意味しない
    送信 VFO を指名することになるからです。そこで既存の指名を先に読み、
    そのまま返します。スプリットを切ることは、他所での送信を止めるだけで
    あり、それ以外は何も変えません。

    この読み取りは失敗してよいものです。スプリットの解除は安全のための
    操作であり、リグが読めないことで妨げられてはなりません。問い合わせが
    失敗した場合は従来の動作になります。 }
  if (not FEnabled) and (FTxVfo = rvfoCurr) then
  begin
    Existing := Ext.CallRigGetSplitVfo(
      ARig, TVfoCodec.ToHamlib(rvfoCurr, ALoader.ApiMajor),
      WasOn, TxVfoRaw);
    if (Existing < 0) or (TxVfoRaw = 0) then
      TxVfoRaw := TVfoCodec.ToHamlib(rvfoCurr, ALoader.ApiMajor);
  end;

  { The receive VFO is always the current one. Naming a specific RX VFO
    would mean selecting it as a side effect of turning split on, which
    is not what the caller asked for.
    受信 VFO は常に現在の VFO です。特定の RX VFO を指定すると、
    スプリットを入れる副作用としてそれを選択することになり、呼び出し側が
    依頼した内容ではなくなります。 }
  RetCode := Ext.CallRigSetSplitVfo(
    ARig,
    TVfoCodec.ToHamlib(rvfoCurr, ALoader.ApiMajor),
    FEnabled,
    TxVfoRaw);
  CheckRig(RetCode, ALoader);
end;

{ ============= TGetSplitCommand ============= }

constructor TGetSplitCommand.Create(AToken: ICancellationToken;
                                     ASplitCallback: TRigSplitInternalCallback);
begin
  inherited Create(AToken, nil);
  FSplitOn       := False;
  FTxVfoRaw      := 0;
  FTxFreq        := 0;
  FSplitCallback := ASplitCallback;
end;

procedure TGetSplitCommand.DoExecute(ALoader: IHamlibLoader; ARig: Pointer);
var
  Ext:     IHamlibRigControl;
  RetCode: Integer;
  CurrVfo: Integer;
begin
  Ext     := NeedRigControl(ALoader);
  CurrVfo := TVfoCodec.ToHamlib(rvfoCurr, ALoader.ApiMajor);

  RetCode := Ext.CallRigGetSplitVfo(ARig, CurrVfo, FSplitOn, FTxVfoRaw);
  CheckRig(RetCode, ALoader);

  if not FSplitOn then Exit;

  { A failure here is NOT fatal to the command: we already know the
    split state, which is what was asked for, and some rigs refuse to
    report a transmit frequency they are perfectly happy to use.
    Reporting 0 for "did not answer" keeps the useful half.

    ここでの失敗はコマンド全体の失敗ではありません。問われたスプリット
    状態は既に判明しており、使うことには何の問題もない送信周波数の報告を
    拒むリグもあります。「答えなかった」を 0 とすることで、有用な半分を
    残します。 }
  if Ext.CallRigGetSplitFreq(ARig, CurrVfo, FTxFreq) < 0 then
    FTxFreq := 0;
end;

procedure TGetSplitCommand.BuildSplitResult(out AResult: TRigSplitResult;
                                             AStatus: TRigCommandStatus;
                                             AError: TRigErrorKind;
                                             ANativeCode: Integer;
                                             const AErrorMsg: string;
                                             AApiMajor: Integer);
begin
  AResult.Status     := AStatus;
  AResult.SplitOn    := FSplitOn;
  AResult.TxVfo      := TVfoCodec.FromHamlib(FTxVfoRaw, AApiMajor);
  AResult.TxFreq     := FTxFreq;
  AResult.Error      := AError;
  AResult.NativeCode := ANativeCode;
  AResult.ErrorMsg   := AErrorMsg;
end;

{ ============= TSetSplitFreqCommand ============= }

constructor TSetSplitFreqCommand.Create(AFreq: Double;
                                         AToken: ICancellationToken;
                                         ACallback: TRigInternalCallback);
begin
  inherited Create(AToken, ACallback);
  FFreq := AFreq;
end;

procedure TSetSplitFreqCommand.DoExecute(ALoader: IHamlibLoader; ARig: Pointer);
var
  Ext:     IHamlibRigControl;
  RetCode: Integer;
begin
  Ext     := NeedRigControl(ALoader);
  RetCode := Ext.CallRigSetSplitFreq(
    ARig, TVfoCodec.ToHamlib(rvfoCurr, ALoader.ApiMajor), FFreq);
  CheckRig(RetCode, ALoader);
end;

{ ============= TSetVfoCommand ============= }

constructor TSetVfoCommand.Create(AVfo: TRigVfo; AToken: ICancellationToken;
                                   ACallback: TRigInternalCallback);
begin
  inherited Create(AToken, ACallback);
  FVfo := AVfo;
end;

procedure TSetVfoCommand.DoExecute(ALoader: IHamlibLoader; ARig: Pointer);
var
  Ext:     IHamlibRigControl;
  RetCode: Integer;
begin
  Ext     := NeedRigControl(ALoader);
  RetCode := Ext.CallRigSetVfo(ARig,
                               TVfoCodec.ToHamlib(FVfo, ALoader.ApiMajor));
  CheckRig(RetCode, ALoader);
end;

{ ============= TGetVfoCommand ============= }

constructor TGetVfoCommand.Create(AToken: ICancellationToken;
                                   AVfoCallback: TRigVfoInternalCallback);
begin
  inherited Create(AToken, nil);
  FVfoRaw      := 0;
  FVfoCallback := AVfoCallback;
end;

procedure TGetVfoCommand.DoExecute(ALoader: IHamlibLoader; ARig: Pointer);
var
  Ext:     IHamlibRigControl;
  RetCode: Integer;
begin
  Ext     := NeedRigControl(ALoader);
  RetCode := Ext.CallRigGetVfo(ARig, FVfoRaw);
  CheckRig(RetCode, ALoader);
end;

procedure TGetVfoCommand.BuildVfoResult(out AResult: TRigVfoResult;
                                         AStatus: TRigCommandStatus;
                                         AError: TRigErrorKind;
                                         ANativeCode: Integer;
                                         const AErrorMsg: string;
                                         AApiMajor: Integer);
begin
  AResult.Status     := AStatus;
  AResult.Vfo        := TVfoCodec.FromHamlib(FVfoRaw, AApiMajor);
  AResult.RawVfo     := FVfoRaw;
  AResult.Error      := AError;
  AResult.NativeCode := ANativeCode;
  AResult.ErrorMsg   := AErrorMsg;
end;

{ ============= TVfoOpCommand ============= }

constructor TVfoOpCommand.Create(AOp: TRigVfoOp; AVfo: TRigVfo;
                                  AToken: ICancellationToken;
                                  ACallback: TRigInternalCallback);
begin
  Assert(AOp <> rvoNone, 'AOp must name an operation');
  inherited Create(AToken, ACallback);
  FVfo := AVfo;
  FOp  := AOp;
end;

procedure TVfoOpCommand.DoExecute(ALoader: IHamlibLoader; ARig: Pointer);
var
  Ext:     IHamlibRigControl;
  RetCode: Integer;
begin
  Ext     := NeedRigControl(ALoader);
  RetCode := Ext.CallRigVfoOp(ARig,
                              TVfoCodec.ToHamlib(FVfo, ALoader.ApiMajor),
                              RigVfoOpToHamlib(FOp));
  CheckRig(RetCode, ALoader);
end;

end.
