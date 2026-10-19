type
  TFakeLoader = class(TInterfacedObject, IHamlibLoader)
  public
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
    function  CallRigSetMode(ARig: Pointer; AVfo: Integer; AMode: Int64; AWidth: Int64): Integer;
    function  CallRigGetMode(ARig: Pointer; AVfo: Integer; out AMode: Int64; out AWidth: Int64): Integer;
    function  CallRigSetPtt(ARig: Pointer; AVfo: Integer; APtt: Integer): Integer;
    function  CallRigGetPtt(ARig: Pointer; AVfo: Integer; out APtt: Integer): Integer;
    function  CallRigError(ACode: Integer): string;
    function  SetConf(ARig: Pointer; const AName, AValue: string): Integer;
    function  SetSerialPort(ARig: Pointer; const APort: string): Integer;
    function  SetSerialBaud(ARig: Pointer; ABaud: Integer): Integer;
  end;

function  TFakeLoader.Load(const APath: string): Boolean; begin Result := True; end;
procedure TFakeLoader.Unload; begin end;
function  TFakeLoader.GetIsLoaded: Boolean; begin Result := True; end;
function  TFakeLoader.GetApiMajor: Integer; begin Result := 4; end;
function  TFakeLoader.GetApiMinor: Integer; begin Result := 5; end;
function  TFakeLoader.GetLibPath: string; begin Result := '<fake>'; end;
function  TFakeLoader.HasSymbol(const AName: string): Boolean; begin Result := True; end;
function  TFakeLoader.CallRigInit(AModel: Integer): Pointer; begin Result := Pointer(1); end;
function  TFakeLoader.CallRigOpen(ARig: Pointer): Integer; begin Result := 0; end;
function  TFakeLoader.CallRigClose(ARig: Pointer): Integer; begin Result := 0; end;
function  TFakeLoader.CallRigCleanup(ARig: Pointer): Integer; begin Result := 0; end;
function  TFakeLoader.CallRigSetFreq(ARig: Pointer; AVfo: Integer; AFreq: Double): Integer;
begin Sleep(5); Result := 0; end;
function  TFakeLoader.CallRigGetFreq(ARig: Pointer; AVfo: Integer; out AFreq: Double): Integer;
begin Sleep(5); AFreq := 14074000.0; Result := 0; end;
function  TFakeLoader.CallRigSetMode(ARig: Pointer; AVfo: Integer; AMode: Int64; AWidth: Int64): Integer; begin Result := 0; end;
function  TFakeLoader.CallRigGetMode(ARig: Pointer; AVfo: Integer; out AMode: Int64; out AWidth: Int64): Integer;
begin AMode := 4; AWidth := 2700; Result := 0; end;
function  TFakeLoader.CallRigSetPtt(ARig: Pointer; AVfo: Integer; APtt: Integer): Integer; begin Result := 0; end;
function  TFakeLoader.CallRigGetPtt(ARig: Pointer; AVfo: Integer; out APtt: Integer): Integer;
begin APtt := 0; Result := 0; end;
function  TFakeLoader.CallRigError(ACode: Integer): string; begin Result := 'fake'; end;
function  TFakeLoader.SetConf(ARig: Pointer; const AName, AValue: string): Integer;
begin Result := 0; end;

function  TFakeLoader.SetSerialPort(ARig: Pointer; const APort: string): Integer; begin Result := 0; end;
function  TFakeLoader.SetSerialBaud(ARig: Pointer; ABaud: Integer): Integer; begin Result := 0; end;
