{
  HamlibCommandBase.pas

  Base class for all rig commands and the adaptive Circuit Breaker
  result window. Application code does NOT use these types directly;
  they are implementation details of the L3 worker.

  すべてのリグコマンドの基底クラスと、適応的 Circuit Breaker のための
  結果ウィンドウ。アプリケーションコードはこれらの型を直接使いません。
  L3 worker の実装詳細です。

  Layer:    L3
  Depends:  HamlibInterfaces, HamlibCancellation
}
unit HamlibCommandBase;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  HamlibInterfaces, HamlibCancellation;

type
  { Internal callback type used between Worker and Service. The Service
    constructs an internal callback that closes over the user-supplied
    callback and the OnError snapshot, so that the command does not need
    to know about user code structures.

    Worker と Service 間で使われる内部コールバック型。Service は利用者
    提供のコールバックと OnError スナップショットを捕捉した内部コールバックを
    構築するため、コマンドは利用者コード構造を知る必要がありません。 }
  TRigInternalCallback = procedure(const AResult: TRigResult) of object;

  { ====================================================================
    TRigCommand — base class for all async commands
    TRigCommand - すべての非同期コマンドの基底クラス
    ====================================================================
    Subclasses override DoExecute to perform the actual Hamlib call.
    Errors are raised as ERigError; the Worker catches them and converts
    to TRigResult.

    サブクラスは DoExecute を override して実際の Hamlib 呼び出しを
    実行します。エラーは ERigError として発生され、Worker がそれを
    捕まえて TRigResult に変換します。 }
  TRigCommand = class
  private
    FToken:    ICancellationToken;
    FCallback: TRigInternalCallback;
  protected
    { Subclasses implement this. Called only on the Worker thread.
      ALoader provides Hamlib API access. ARig is the PRIG handle.
      May raise ERigError to signal failure.

      サブクラスがこれを実装します。Worker スレッド上でのみ呼び出されます。
      ALoader は Hamlib API アクセスを提供。ARig は PRIG ハンドル。
      失敗を示すために ERigError を発生してもよい。 }
    procedure DoExecute(ALoader: IHamlibLoader; ARig: Pointer); virtual; abstract;

    { Subclasses fill in result-specific fields after DoExecute succeeds.
      Default implementation is empty.
      DoExecute 成功後にサブクラスが結果固有フィールドを埋めます。
      デフォルト実装は空。 }
    procedure FillResult(var AResult: TRigResult); virtual;
  public
    constructor Create(AToken: ICancellationToken;
                       ACallback: TRigInternalCallback);
    destructor  Destroy; override;

    { Returns True if the cancellation token has been signalled.
      Worker checks this before executing each command.
      キャンセルトークンがシグナルされていれば True を返します。
      Worker は各コマンド実行前にこれを確認します。 }
    function IsCancelRequested: Boolean;

    { Public access for the Worker to invoke DoExecute.
      Worker が DoExecute を呼び出せるようにするための公開メソッド。 }
    procedure Execute(ALoader: IHamlibLoader; ARig: Pointer);

    { Public access for the Worker to fill result fields.
      Worker が結果フィールドを埋められるようにするための公開メソッド。 }
    procedure ApplyResultFields(var AResult: TRigResult);

    property Callback: TRigInternalCallback read FCallback;
    property Token:    ICancellationToken   read FToken;
  end;

  { ====================================================================
    TCommandResultWindow — sliding window for adaptive CB
    TCommandResultWindow - 適応的 CB 用のスライディングウィンドウ
    ====================================================================
    Tracks the last N command outcomes (success/failure) and computes
    the failure rate. Used by Worker when CbStrategy = cbsAdaptive.

    直近 N 個のコマンド結果 (成功/失敗) を追跡し、失敗率を計算します。
    CbStrategy = cbsAdaptive のとき Worker が使用します。 }
  TCommandResultWindow = class
  private
    FResults:   array of Boolean;     { True = success / 成功 }
    FSize:      Integer;
    FHead:      Integer;
    FFilled:    Boolean;
  public
    { Construct with a fixed window size (must be >= 3).
      固定ウィンドウサイズで生成します (3 以上必須)。 }
    constructor Create(AWindowSize: Integer);

    { Record one command outcome.
      コマンド結果を 1 件記録します。 }
    procedure RecordResult(ASuccess: Boolean);

    { Reset all counters. Called when CB closes (recovery successful).
      すべてのカウンタをリセットします。CB が閉じたとき (回復成功時) に呼ばれます。 }
    procedure Reset;

    { Compute failure rate over recorded results. Returns 0 if empty.
      記録された結果の失敗率を計算します。空の場合 0。 }
    function FailureRate: Double;

    { Returns True once the window is fully populated. Adaptive CB
      should not trigger before this returns True.
      ウィンドウが満たされた後 True を返します。Adaptive CB は
      これが True を返すまでトリガしないでください。 }
    function IsFilled: Boolean;
  end;

implementation

{ ============= TRigCommand ============= }

constructor TRigCommand.Create(AToken: ICancellationToken;
                                ACallback: TRigInternalCallback);
begin
  inherited Create;
  FToken    := AToken;
  FCallback := ACallback;
end;

destructor TRigCommand.Destroy;
begin
  FToken := nil;   { Release reference to the token / トークンへの参照を解放 }
  inherited;
end;

function TRigCommand.IsCancelRequested: Boolean;
begin
  Result := Assigned(FToken) and FToken.IsCancelled;
end;

procedure TRigCommand.Execute(ALoader: IHamlibLoader; ARig: Pointer);
begin
  Assert(Assigned(ALoader), 'Loader required for execute');
  DoExecute(ALoader, ARig);
end;

procedure TRigCommand.FillResult(var AResult: TRigResult);
begin
  { Default: nothing to fill. Subclasses with result-specific records
    do not use this; they have their own result types.
    デフォルト: 何も埋めない。結果固有レコードを持つサブクラスは
    これを使わず、独自の結果型を持ちます。 }
end;

procedure TRigCommand.ApplyResultFields(var AResult: TRigResult);
begin
  FillResult(AResult);
end;

{ ============= TCommandResultWindow ============= }

constructor TCommandResultWindow.Create(AWindowSize: Integer);
begin
  Assert(AWindowSize >= 3, 'Window size must be at least 3');
  inherited Create;
  SetLength(FResults, AWindowSize);
  FSize   := AWindowSize;
  FHead   := 0;
  FFilled := False;
end;

procedure TCommandResultWindow.RecordResult(ASuccess: Boolean);
begin
  FResults[FHead] := ASuccess;
  FHead := (FHead + 1) mod FSize;
  if FHead = 0 then
    FFilled := True;
end;

procedure TCommandResultWindow.Reset;
begin
  FHead   := 0;
  FFilled := False;
end;

function TCommandResultWindow.FailureRate: Double;
var
  i, Total, Failures: Integer;
begin
  if FFilled then Total := FSize else Total := FHead;
  if Total = 0 then Exit(0);
  Failures := 0;
  for i := 0 to Total - 1 do
    if not FResults[i] then Inc(Failures);
  Result := Failures / Total;
end;

function TCommandResultWindow.IsFilled: Boolean;
begin
  Result := FFilled;
end;

end.
