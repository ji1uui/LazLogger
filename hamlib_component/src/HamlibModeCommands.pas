{
  HamlibModeCommands.pas

  Mode-related commands: TSetModeCommand and TGetModeCommand.
  Internal to the Service implementation.

  モード関連コマンド: TSetModeCommand と TGetModeCommand。
  Service 実装の内部用です。

  Layer:    L3
  Depends:  HamlibInterfaces, HamlibErrors, HamlibVfoCodec, HamlibModeCodec,
            HamlibCommandBase
}
unit HamlibModeCommands;

{$mode objfpc}{$H+}

interface

uses
  HamlibInterfaces, HamlibErrors, HamlibVfoCodec, HamlibModeCodec,
  HamlibCommandBase;

type
  { Internal callback for GetMode result delivery.
    GetMode 結果配送用の内部コールバック。 }
  TRigModeInternalCallback = procedure(const AResult: TRigModeResult) of object;

  { ====================================================================
    TSetModeCommand — set operating mode on a specific VFO
    TSetModeCommand - 特定 VFO の動作モードを設定するコマンド
    ====================================================================
    APassbandHz=0 lets Hamlib pick the rig's default passband for the
    requested mode (recommended for normal use).

    The command holds the mode as a TRigMode and translates it to
    rmode_t at the moment of the call, so the raw bitmask exists only
    inside DoExecute.

    APassbandHz=0 にすると Hamlib が要求モードに対するリグ既定の通過
    帯域幅を選びます (通常の使用には推奨)。

    コマンドはモードを TRigMode として保持し、呼び出しの瞬間に rmode_t
    へ変換します。生のビットマスクは DoExecute の中にしか存在しません。 }
  TSetModeCommand = class(TRigCommand)
  private
    FVfo:        TRigVfo;
    FMode:       TRigMode;
    FPassbandHz: Integer;
  protected
    procedure DoExecute(ALoader: IHamlibLoader; ARig: Pointer); override;
  public
    constructor Create(AMode: TRigMode; APassbandHz: Integer; AVfo: TRigVfo;
                       AToken: ICancellationToken;
                       ACallback: TRigInternalCallback);

    property Vfo:        TRigVfo  read FVfo;
    property Mode:       TRigMode read FMode;
    property PassbandHz: Integer  read FPassbandHz;
  end;

  { ====================================================================
    TGetModeCommand — read operating mode from a specific VFO
    TGetModeCommand - 特定 VFO から動作モードを読み取るコマンド
    ==================================================================== }
  TGetModeCommand = class(TRigCommand)
  private
    { Raw out-parameters for the C call. They stay Int64 because that is
      what rig_get_mode writes into; translation happens in
      BuildModeResult, at the boundary where the value leaves L3.

      C 呼び出し用の生 out パラメータ。rig_get_mode が書き込む型である
      ため Int64 のままにします。変換は値が L3 を出る境界、すなわち
      BuildModeResult で行います。 }
    FVfo:          TRigVfo;
    FRawMode:      Int64;
    FRawPassband:  Int64;
    FModeCallback: TRigModeInternalCallback;
  protected
    procedure DoExecute(ALoader: IHamlibLoader; ARig: Pointer); override;
  public
    constructor Create(AVfo: TRigVfo;
                       AToken: ICancellationToken;
                       AModeCallback: TRigModeInternalCallback);

    procedure BuildModeResult(out AResult: TRigModeResult;
                               AStatus: TRigCommandStatus;
                               AError: TRigErrorKind;
                               ANativeCode: Integer;
                               const AErrorMsg: string);

    property Vfo:          TRigVfo                  read FVfo;
    property RawMode:      Int64                    read FRawMode;
    property RawPassband:  Int64                    read FRawPassband;
    property ModeCallback: TRigModeInternalCallback read FModeCallback;
  end;

implementation

{ ============= TSetModeCommand ============= }

constructor TSetModeCommand.Create(AMode: TRigMode; APassbandHz: Integer;
                                    AVfo: TRigVfo;
                                    AToken: ICancellationToken;
                                    ACallback: TRigInternalCallback);
begin
  Assert(AMode <> rmUnknown, 'AMode must be a concrete mode, not rmUnknown');
  Assert(APassbandHz >= 0, 'APassbandHz must be >= 0 (0 = rig default)');
  inherited Create(AToken, ACallback);
  FVfo        := AVfo;
  FMode       := AMode;
  FPassbandHz := APassbandHz;
end;

procedure TSetModeCommand.DoExecute(ALoader: IHamlibLoader; ARig: Pointer);
var
  RetCode: Integer;
  HlVfo:   Integer;
  HlMode:  Int64;
begin
  HlVfo   := TVfoCodec.ToHamlib(FVfo, ALoader.ApiMajor);
  HlMode  := THamlibModeCodec.ToHamlib(FMode);
  RetCode := ALoader.CallRigSetMode(ARig, HlVfo, HlMode, FPassbandHz);
  CheckRig(RetCode, ALoader);
end;

{ ============= TGetModeCommand ============= }

constructor TGetModeCommand.Create(AVfo: TRigVfo;
                                    AToken: ICancellationToken;
                                    AModeCallback: TRigModeInternalCallback);
begin
  inherited Create(AToken, nil);
  FVfo          := AVfo;
  FRawMode      := 0;
  FRawPassband  := 0;
  FModeCallback := AModeCallback;
end;

procedure TGetModeCommand.DoExecute(ALoader: IHamlibLoader; ARig: Pointer);
var
  RetCode: Integer;
  HlVfo:   Integer;
begin
  HlVfo   := TVfoCodec.ToHamlib(FVfo, ALoader.ApiMajor);
  RetCode := ALoader.CallRigGetMode(ARig, HlVfo, FRawMode, FRawPassband);
  CheckRig(RetCode, ALoader);
end;

procedure TGetModeCommand.BuildModeResult(out AResult: TRigModeResult;
                                           AStatus: TRigCommandStatus;
                                           AError: TRigErrorKind;
                                           ANativeCode: Integer;
                                           const AErrorMsg: string);
begin
  AResult.Status     := AStatus;
  AResult.Error      := AError;
  AResult.NativeCode := ANativeCode;
  AResult.Mode     := THamlibModeCodec.FromHamlib(FRawMode);
  AResult.RawMode  := FRawMode;
  { pbwidth_t is a C long, so on LP64 it is wider than Integer. A
    passband is a few kHz at most, so a value that does not fit cannot
    be a real width — report "rig default" rather than truncate it into
    a plausible-looking wrong number.

    pbwidth_t は C の long であり、LP64 では Integer より広いです。通過
    帯域幅は高々数 kHz なので、収まらない値は実在の幅ではありません。
    もっともらしい誤った数値に切り詰めるのではなく「リグ既定」として
    報告します。 }
  if (FRawPassband < Low(Integer)) or (FRawPassband > High(Integer)) then
    AResult.Passband := 0
  else
    AResult.Passband := Integer(FRawPassband);
  AResult.ErrorMsg := AErrorMsg;
end;

end.
