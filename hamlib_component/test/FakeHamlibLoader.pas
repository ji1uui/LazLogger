{
  FakeHamlibLoader.pas

  In-memory fake of IHamlibLoader for unit tests. Does NOT load any
  real DLL — all rig operations return simulated values. Use this in
  fpcunit test cases to verify the component stack without hardware.

  ユニットテスト用の IHamlibLoader インメモリフェイク。実 DLL は
  ロードせず、すべてのリグ操作はシミュレート値を返します。fpcunit
  テストケースで、ハードウェア不要のコンポーネントスタック検証に使用。

  Note: This unit lives under test/ — production builds should NOT
  link it.

  注: 本ユニットは test/ 配下にあります。本番ビルドでリンクしないでください。
}
unit FakeHamlibLoader;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes,
  HamlibInterfaces;

type
  { ====================================================================
    TFakeHamlibLoader — pure stub implementation of IHamlibLoader.
    TFakeHamlibLoader - IHamlibLoader の純粋スタブ実装。
    ==================================================================== }
  TFakeHamlibLoader = class(TInterfacedObject, IHamlibLoader)
  private
    FSimFreq:   Double;
    FSimMode:   Int64;
    FSimWidth:  Int64;
    FSimPtt:    Integer;
    FFailNext:  Boolean;
    FFailCode:  Integer;
    FOpenCount: Integer;
    FConf:      TStringList;
    function  GetConfValue(const AName: string): string;
  public
    constructor Create;
    destructor  Destroy; override;

    { ----------------- IHamlibLoader implementation ----------------- }
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
    function  CallRigSetMode(ARig: Pointer; AVfo: Integer;
                             AMode: Int64; AWidth: Int64): Integer;
    function  CallRigGetMode(ARig: Pointer; AVfo: Integer;
                             out AMode: Int64; out AWidth: Int64): Integer;
    function  CallRigSetPtt(ARig: Pointer; AVfo: Integer; APtt: Integer): Integer;
    function  CallRigGetPtt(ARig: Pointer; AVfo: Integer; out APtt: Integer): Integer;
    function  CallRigError(ACode: Integer): string;
    function  SetConf(ARig: Pointer; const AName, AValue: string): Integer;
    function  SetSerialPort(ARig: Pointer; const APort: string): Integer;
    function  SetSerialBaud(ARig: Pointer; ABaud: Integer): Integer;

    { ----------------- Test control ----------------- }

    { Cause the next call to return ACode (a negative Hamlib error).
      次の呼び出しで ACode (負の Hamlib エラー) を返させます。 }
    procedure SimulateFailure(ACode: Integer);

    { Reset all simulated state to defaults.
      シミュレート状態をすべてデフォルトに戻します。 }
    procedure ResetSimulation;

    property SimFreq:    Double  read FSimFreq    write FSimFreq;
    property SimMode:    Int64   read FSimMode    write FSimMode;
    property SimWidth:   Int64   read FSimWidth   write FSimWidth;
    property SimPtt:     Integer read FSimPtt     write FSimPtt;
    property OpenCount:  Integer read FOpenCount;

    { Configuration values pushed in via SetConf (including the tier-1
      timeout/retry pair the Worker applies on connect). Read it to
      assert what the component configured.

      SetConf 経由で設定された値 (Worker が接続時に適用する第 1 段の
      timeout/retry を含む)。コンポーネントが何を設定したかの検証に
      使ってください。 }
    property ConfValue[const AName: string]: string read GetConfValue;
  end;

implementation

const
  RIG_OK = 0;
  FAKE_RIG_HANDLE = Pointer($DEADBEEF);

constructor TFakeHamlibLoader.Create;
begin
  inherited Create;
  FConf := TStringList.Create;
  ResetSimulation;
end;

destructor TFakeHamlibLoader.Destroy;
begin
  { try...finally is unnecessary here because FreeAndNil cannot raise,
    but the order matters: free owned objects before the inherited
    destructor releases the instance.

    FreeAndNil は例外を投げないため try...finally は不要ですが、順序は
    重要です。継承先のデストラクタがインスタンスを解放する前に所有
    オブジェクトを解放します。 }
  FreeAndNil(FConf);
  inherited Destroy;
end;

function TFakeHamlibLoader.GetConfValue(const AName: string): string;
begin
  Result := FConf.Values[AName];
end;

procedure TFakeHamlibLoader.ResetSimulation;
begin
  FSimFreq   := 14074000.0;     { Default to 20m FT8 / デフォルトは 20m FT8 }
  FSimMode   := Int64(1) shl 2; { USB }
  FSimWidth  := 2700;
  FSimPtt    := 0;
  FFailNext  := False;
  FFailCode  := 0;
  FOpenCount := 0;
  if Assigned(FConf) then FConf.Clear;
end;

procedure TFakeHamlibLoader.SimulateFailure(ACode: Integer);
begin
  FFailNext := True;
  FFailCode := ACode;
end;

function TFakeHamlibLoader.Load(const APath: string): Boolean;
begin
  Result := True;
end;

procedure TFakeHamlibLoader.Unload;
begin
  { No-op for fake / フェイクなのでノーオペレーション }
end;

function TFakeHamlibLoader.GetIsLoaded: Boolean;
begin
  Result := True;
end;

function TFakeHamlibLoader.GetApiMajor: Integer;
begin
  Result := 4;
end;

function TFakeHamlibLoader.GetApiMinor: Integer;
begin
  Result := 5;
end;

function TFakeHamlibLoader.GetLibPath: string;
begin
  Result := '<fake>';
end;

function TFakeHamlibLoader.HasSymbol(const AName: string): Boolean;
begin
  { Fake reports all symbols as available.
    フェイクはすべてのシンボルを利用可能と報告します。 }
  Result := True;
end;

function TFakeHamlibLoader.CallRigInit(AModel: Integer): Pointer;
begin
  Result := FAKE_RIG_HANDLE;
end;

function TFakeHamlibLoader.CallRigOpen(ARig: Pointer): Integer;
begin
  Inc(FOpenCount);
  if FFailNext then
  begin
    FFailNext := False;
    Result := FFailCode;
  end
  else
    Result := RIG_OK;
end;

function TFakeHamlibLoader.CallRigClose(ARig: Pointer): Integer;
begin
  Result := RIG_OK;
end;

function TFakeHamlibLoader.CallRigCleanup(ARig: Pointer): Integer;
begin
  Result := RIG_OK;
end;

function TFakeHamlibLoader.CallRigSetFreq(ARig: Pointer; AVfo: Integer;
                                           AFreq: Double): Integer;
begin
  if FFailNext then
  begin
    FFailNext := False;
    Result := FFailCode;
    Exit;
  end;
  FSimFreq := AFreq;
  Result   := RIG_OK;
end;

function TFakeHamlibLoader.CallRigGetFreq(ARig: Pointer; AVfo: Integer;
                                           out AFreq: Double): Integer;
begin
  if FFailNext then
  begin
    FFailNext := False;
    AFreq  := 0;
    Result := FFailCode;
    Exit;
  end;
  AFreq  := FSimFreq;
  Result := RIG_OK;
end;

function TFakeHamlibLoader.CallRigSetMode(ARig: Pointer; AVfo: Integer;
                                           AMode: Int64; AWidth: Int64): Integer;
begin
  if FFailNext then
  begin
    FFailNext := False;
    Result := FFailCode;
    Exit;
  end;
  FSimMode  := AMode;
  FSimWidth := AWidth;
  Result    := RIG_OK;
end;

function TFakeHamlibLoader.CallRigGetMode(ARig: Pointer; AVfo: Integer;
                                           out AMode: Int64;
                                           out AWidth: Int64): Integer;
begin
  if FFailNext then
  begin
    FFailNext := False;
    AMode  := 0;
    AWidth := 0;
    Result := FFailCode;
    Exit;
  end;
  AMode  := FSimMode;
  AWidth := FSimWidth;
  Result := RIG_OK;
end;

function TFakeHamlibLoader.CallRigSetPtt(ARig: Pointer; AVfo: Integer;
                                          APtt: Integer): Integer;
begin
  if FFailNext then
  begin
    FFailNext := False;
    Result := FFailCode;
    Exit;
  end;
  FSimPtt := APtt;
  Result  := RIG_OK;
end;

function TFakeHamlibLoader.CallRigGetPtt(ARig: Pointer; AVfo: Integer;
                                          out APtt: Integer): Integer;
begin
  if FFailNext then
  begin
    FFailNext := False;
    APtt   := 0;
    Result := FFailCode;
    Exit;
  end;
  APtt   := FSimPtt;
  Result := RIG_OK;
end;

function TFakeHamlibLoader.CallRigError(ACode: Integer): string;
begin
  Result := Format('FakeHamlib error %d', [ACode]);
end;

{ Record a Hamlib configuration token so tests can assert what the
  component pushed into the library (e.g. the tier-1 timeout/retry).
  Hamlib の設定トークンを記録し、コンポーネントがライブラリへ何を設定
  したか (例: 第 1 段の timeout/retry) をテストで検証できるようにします。 }
function TFakeHamlibLoader.SetConf(ARig: Pointer;
                                   const AName, AValue: string): Integer;
begin
  FConf.Values[AName] := AValue;
  Result := RIG_OK;
end;

function TFakeHamlibLoader.SetSerialPort(ARig: Pointer; const APort: string): Integer;
begin
  Result := SetConf(ARig, 'rig_pathname', APort);
end;

function TFakeHamlibLoader.SetSerialBaud(ARig: Pointer; ABaud: Integer): Integer;
begin
  Result := SetConf(ARig, 'serial_speed', IntToStr(ABaud));
end;

end.
