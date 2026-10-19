{
  HamlibFreqCommands.pas

  Frequency-related commands: TSetFreqCommand and TGetFreqCommand.
  Application code does NOT use these classes directly; they are
  internal to the Service implementation.

  周波数関連コマンド: TSetFreqCommand と TGetFreqCommand。
  アプリケーションコードはこれらのクラスを直接使いません。
  Service 実装の内部で使われます。

  Layer:    L3
  Depends:  HamlibInterfaces, HamlibErrors, HamlibVfoCodec, HamlibCommandBase
}
unit HamlibFreqCommands;

{$mode objfpc}{$H+}

interface

uses
  HamlibInterfaces, HamlibErrors, HamlibVfoCodec, HamlibCommandBase;

type
  { Internal callback for GetFreq — Service uses this to wrap user
    callbacks and event handlers.
    GetFreq 用の内部コールバック — Service がこれで利用者コールバックと
    イベントハンドラをラップします。 }
  TRigFreqInternalCallback = procedure(const AResult: TRigFreqResult) of object;

  { ====================================================================
    TSetFreqCommand — set the frequency on a specific VFO
    TSetFreqCommand - 特定 VFO の周波数を設定するコマンド
    ==================================================================== }
  TSetFreqCommand = class(TRigCommand)
  private
    FVfo:  TRigVfo;
    FFreq: Double;
  protected
    procedure DoExecute(ALoader: IHamlibLoader; ARig: Pointer); override;
  public
    constructor Create(AVfo: TRigVfo; AFreq: Double;
                       AToken: ICancellationToken;
                       ACallback: TRigInternalCallback);
    property Vfo:  TRigVfo read FVfo;
    property Freq: Double  read FFreq;
  end;

  { ====================================================================
    TGetFreqCommand — read the frequency from a specific VFO
    TGetFreqCommand - 特定 VFO から周波数を読み取るコマンド
    ====================================================================
    Uses a custom callback type because the result includes a Freq field.
    The Worker calls FreqCallback after DoExecute completes.

    結果に Freq フィールドが含まれるため独自のコールバック型を使います。
    Worker は DoExecute 完了後に FreqCallback を呼びます。 }
  TGetFreqCommand = class(TRigCommand)
  private
    FVfo:           TRigVfo;
    FFreq:          Double;
    FFreqCallback:  TRigFreqInternalCallback;
  protected
    procedure DoExecute(ALoader: IHamlibLoader; ARig: Pointer); override;
  public
    constructor Create(AVfo: TRigVfo;
                       AToken: ICancellationToken;
                       AFreqCallback: TRigFreqInternalCallback);

    { Build a TRigFreqResult from the executed command's state.
      Called by Worker after Execute returns successfully.
      実行済みコマンドの状態から TRigFreqResult を構築します。
      Execute が成功して戻った後 Worker が呼びます。 }
    procedure BuildFreqResult(out AResult: TRigFreqResult;
                               AStatus: TRigCommandStatus;
                               AError: TRigErrorKind;
                               ANativeCode: Integer;
                               const AErrorMsg: string);

    property Vfo:          TRigVfo                  read FVfo;
    property Freq:         Double                   read FFreq;
    property FreqCallback: TRigFreqInternalCallback read FFreqCallback;
  end;

implementation

{ ============= TSetFreqCommand ============= }

constructor TSetFreqCommand.Create(AVfo: TRigVfo; AFreq: Double;
                                    AToken: ICancellationToken;
                                    ACallback: TRigInternalCallback);
begin
  inherited Create(AToken, ACallback);
  FVfo  := AVfo;
  FFreq := AFreq;
end;

procedure TSetFreqCommand.DoExecute(ALoader: IHamlibLoader; ARig: Pointer);
var
  RetCode: Integer;
  HlVfo:   Integer;
begin
  HlVfo   := TVfoCodec.ToHamlib(FVfo, ALoader.ApiMajor);
  RetCode := ALoader.CallRigSetFreq(ARig, HlVfo, FFreq);
  CheckRig(RetCode, ALoader);
end;

{ ============= TGetFreqCommand ============= }

constructor TGetFreqCommand.Create(AVfo: TRigVfo;
                                    AToken: ICancellationToken;
                                    AFreqCallback: TRigFreqInternalCallback);
begin
  { Pass nil for the base TRigCommand callback because GetFreq uses its
    own typed callback (FFreqCallback) for result delivery.
    GetFreq は独自の型付きコールバック (FFreqCallback) で結果を配送するため、
    基底 TRigCommand のコールバックには nil を渡します。 }
  inherited Create(AToken, nil);
  FVfo          := AVfo;
  FFreq         := 0;
  FFreqCallback := AFreqCallback;
end;

procedure TGetFreqCommand.DoExecute(ALoader: IHamlibLoader; ARig: Pointer);
var
  RetCode: Integer;
  HlVfo:   Integer;
begin
  HlVfo   := TVfoCodec.ToHamlib(FVfo, ALoader.ApiMajor);
  RetCode := ALoader.CallRigGetFreq(ARig, HlVfo, FFreq);
  CheckRig(RetCode, ALoader);
end;

procedure TGetFreqCommand.BuildFreqResult(out AResult: TRigFreqResult;
                                           AStatus: TRigCommandStatus;
                                           AError: TRigErrorKind;
                                           ANativeCode: Integer;
                                           const AErrorMsg: string);
begin
  AResult.Status     := AStatus;
  AResult.Freq       := FFreq;
  AResult.Error      := AError;
  AResult.NativeCode := ANativeCode;
  AResult.ErrorMsg   := AErrorMsg;
end;

end.
