{
  HamlibPttCommands.pas

  PTT (Push-To-Talk) commands: TSetPttCommand and TGetPttCommand.
  Internal to the Service implementation.

  PTT (送信ボタン) コマンド: TSetPttCommand と TGetPttCommand。
  Service 実装の内部用です。

  Layer:    L3
  Depends:  HamlibInterfaces, HamlibErrors, HamlibVfoCodec, HamlibCommandBase
}
unit HamlibPttCommands;

{$mode objfpc}{$H+}

interface

uses
  HamlibInterfaces, HamlibErrors, HamlibVfoCodec, HamlibCommandBase;

type
  { Internal callback for GetPtt result delivery.
    GetPtt 結果配送用の内部コールバック。 }
  TRigPttInternalCallback = procedure(const AResult: TRigPttResult) of object;

  { ====================================================================
    TSetPttCommand — set transmission state
    TSetPttCommand - 送信状態を設定するコマンド
    ====================================================================
    Note: Setting PTT to On while a CW or DATA mode is active may have
    different behavior depending on the rig. Always check rig manual.

    注: CW や DATA モード時の PTT On は機種により動作が異なります。
    必ず機種マニュアルを確認してください。 }
  TSetPttCommand = class(TRigCommand)
  private
    FState: TRigPttState;
  protected
    procedure DoExecute(ALoader: IHamlibLoader; ARig: Pointer); override;
  public
    constructor Create(AState: TRigPttState;
                       AToken: ICancellationToken;
                       ACallback: TRigInternalCallback);

    property State: TRigPttState read FState;
  end;

  { ====================================================================
    TGetPttCommand — read current transmission state
    TGetPttCommand - 現在の送信状態を読み取るコマンド
    ==================================================================== }
  TGetPttCommand = class(TRigCommand)
  private
    FActive:      Boolean;
    FPttCallback: TRigPttInternalCallback;
  protected
    procedure DoExecute(ALoader: IHamlibLoader; ARig: Pointer); override;
  public
    constructor Create(AToken: ICancellationToken;
                       APttCallback: TRigPttInternalCallback);

    procedure BuildPttResult(out AResult: TRigPttResult;
                              AStatus: TRigCommandStatus);

    property Active:      Boolean                 read FActive;
    property PttCallback: TRigPttInternalCallback read FPttCallback;
  end;

implementation

const
  { Hamlib RIG_PTT_OFF = 0, _ON = 1, _ON_MIC = 2, _ON_DATA = 3.
    Hamlib の PTT 状態定数。 }
  HL_PTT_OFF      = 0;
  HL_PTT_ON       = 1;
  HL_PTT_ON_MIC   = 2;
  HL_PTT_ON_DATA  = 3;

{ ============= TSetPttCommand ============= }

constructor TSetPttCommand.Create(AState: TRigPttState;
                                   AToken: ICancellationToken;
                                   ACallback: TRigInternalCallback);
begin
  inherited Create(AToken, ACallback);
  FState := AState;
end;

procedure TSetPttCommand.DoExecute(ALoader: IHamlibLoader; ARig: Pointer);
var
  RetCode: Integer;
  HlPtt:   Integer;
  HlVfo:   Integer;
begin
  case FState of
    rpttOff:      HlPtt := HL_PTT_OFF;
    rpttOn:       HlPtt := HL_PTT_ON;
    rpttOnMic:    HlPtt := HL_PTT_ON_MIC;
    rpttOnData:   HlPtt := HL_PTT_ON_DATA;
  else
    HlPtt := HL_PTT_OFF;
  end;

  HlVfo   := TVfoCodec.ToHamlib(rvfoCurr, ALoader.ApiMajor);
  RetCode := ALoader.CallRigSetPtt(ARig, HlVfo, HlPtt);
  CheckRig(RetCode, ALoader);
end;

{ ============= TGetPttCommand ============= }

constructor TGetPttCommand.Create(AToken: ICancellationToken;
                                   APttCallback: TRigPttInternalCallback);
begin
  inherited Create(AToken, nil);
  FActive       := False;
  FPttCallback  := APttCallback;
end;

procedure TGetPttCommand.DoExecute(ALoader: IHamlibLoader; ARig: Pointer);
var
  RetCode:  Integer;
  HlPtt:    Integer;
  HlVfo:    Integer;
begin
  HlVfo   := TVfoCodec.ToHamlib(rvfoCurr, ALoader.ApiMajor);
  RetCode := ALoader.CallRigGetPtt(ARig, HlVfo, HlPtt);
  CheckRig(RetCode, ALoader);
  FActive := HlPtt <> HL_PTT_OFF;
end;

procedure TGetPttCommand.BuildPttResult(out AResult: TRigPttResult;
                                         AStatus: TRigCommandStatus);
begin
  AResult.Status := AStatus;
  AResult.Active := FActive;
end;

end.
