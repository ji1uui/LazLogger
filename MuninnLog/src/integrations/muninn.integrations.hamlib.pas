unit Muninn.Integrations.Hamlib;

{ The radio port (Muninn.Core.Radio) on top of HamlibComponent (ADR 0008).
  The core sees only IRadioPort; this unit is the only one that uses the
  component's types.

  Threading: call the port from the main thread only. HamlibComponent runs
  every command on its worker thread and delivers results with TThread.Queue,
  so callbacks run on the main thread when it processes queued calls
  (CheckSynchronize). The component delivers every result exactly once, also
  when a command is cancelled; each call keeps a small request object until
  then. Destroying the adapter detaches the requests still waiting, so a late
  result is dropped instead of reaching a freed caller.

  Modes: MODE/SUBMODE are mapped to the radio's modes. Data modes (FT8, PSK,
  ...) are set as PKT-USB; reading PKT-USB back gives no ADIF mode, since the
  radio cannot tell which data mode is in use. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Muninn.Core.Frequency, Muninn.Core.Mode, Muninn.Core.Radio,
  HamlibInterfaces;

type
  THamlibRadio = class;

  { Makes a new service: from the process's TRigServiceFactory, or over a
    fake loader in tests. }
  TRigServiceCreator = function: IRigService of object;

  { One call waiting for its result. }
  TRadioRequest = class
  private
    FOwner: THamlibRadio;
  protected
    { Unregisters from the owner; the caller frees the request. }
    procedure Finish;
  public
    constructor Create(const AOwner: THamlibRadio);
    procedure Detach; virtual;
  end;

  THamlibRadio = class(TInterfacedObject, IRadioPort)
  private
    FCreateService: TRigServiceCreator;
    { The service of the current connection; nil while disconnected. }
    FService: IRigService;
    FPending: TList;
    FOnConnectionChanged: TRadioConnectionEvent;
    FOnFrequencyChanged: TRadioFrequencyEvent;
    FOnError: TRadioErrorEvent;
    procedure ServiceConnectionChanged(Sender: TObject; AConnected: Boolean);
    procedure ServiceFrequencyChanged(Sender: TObject; AFreq: Double);
    procedure ServiceError(Sender: TObject; AKind: TRigErrorKind;
      ANativeCode: Integer; const AMsg: string);
    procedure ReleaseService;
  public
    { Each Connect takes a new service from ACreateService, so no driver
      setting of an earlier connection carries over (a service keeps its
      conf tokens for good). Create one TRigServiceFactory per process. }
    constructor Create(const ACreateService: TRigServiceCreator);
    destructor Destroy; override;
    procedure Connect(const AConnection: TRadioConnection);
    procedure Disconnect;
    function IsConnected: Boolean;
    procedure SetFrequency(const AFrequency: TFrequencyHz;
      ACallback: TRadioCommandCallback);
    procedure GetFrequency(ACallback: TRadioFrequencyCallback);
    procedure SetMode(const AMode: TMode; ACallback: TRadioCommandCallback);
    procedure GetMode(ACallback: TRadioModeCallback);
    procedure SetTransmit(AOn: Boolean; ACallback: TRadioCommandCallback);
    procedure SetOnConnectionChanged(AHandler: TRadioConnectionEvent);
    procedure SetOnFrequencyChanged(AHandler: TRadioFrequencyEvent);
    procedure SetOnError(AHandler: TRadioErrorEvent);
  end;

{ The radio mode for an ADIF mode; False when the radio has none for it
  (e.g. SSB without USB or LSB). }
function TryRigModeFromMode(const AMode: TMode; out ARigMode: TRigMode;
  out AReason: string): Boolean;
function ModeReadingFromRigMode(const ARigMode: TRigMode): TRadioModeReading;
function RadioResultFromRig(const AStatus: TRigCommandStatus;
  const AKind: TRigErrorKind; const AMessage: string): TRadioResult;

implementation

uses
  Muninn.Core.AdifModes, HamlibModeCodec;

{ Mode mapping }

function TryRigModeFromMode(const AMode: TMode; out ARigMode: TRigMode;
  out AReason: string): Boolean;
var
  Name, Submode: string;
begin
  Result := True;
  AReason := '';
  ARigMode := rmUnknown;
  Name := AMode.Mode;
  Submode := AMode.Submode;
  if Name = 'SSB' then
  begin
    if Submode = 'USB' then
      ARigMode := rmUSB
    else if Submode = 'LSB' then
      ARigMode := rmLSB
    else
    begin
      AReason := 'SSB needs the submode USB or LSB';
      Exit(False);
    end;
  end
  else if Name = 'CW' then
    ARigMode := rmCW
  else if Name = 'AM' then
    ARigMode := rmAM
  else if Name = 'FM' then
    ARigMode := rmFM
  else if Name = 'RTTY' then
    ARigMode := rmRTTY
  else if (Name = 'DIGITALVOICE') and (Submode = 'C4FM') then
    ARigMode := rmC4FM
  else if (Name = 'DIGITALVOICE') and (Submode = 'DSTAR') then
    ARigMode := rmDStar
  else if (Name = 'DIGITALVOICE') and (Submode = 'FREEDV') then
    { FreeDV runs on a computer over the data variant of USB. }
    ARigMode := rmPktUSB
  else if IsAdifMode(Name) and (Name <> 'ATV') and (Name <> 'DIGITALVOICE') then
    { The remaining ADIF modes are sound-card data modes (FT8, PSK, SSTV, ...);
      they run over the data (PKT) variant of USB. }
    ARigMode := rmPktUSB
  else
  begin
    AReason := 'no radio mode for ' + AMode.DisplayName;
    Result := False;
  end;
end;

function ModeReadingFromRigMode(const ARigMode: TRigMode): TRadioModeReading;

  procedure Use(const AMode, ASubmode: string);
  begin
    Result.HasMode := TMode.TryCreate(AMode, ASubmode, Result.Mode);
  end;

begin
  Result.RadioText := THamlibModeCodec.ToDisplayString(ARigMode);
  Result.HasMode := False;
  Result.Mode := Default(TMode);
  case ARigMode of
    rmUSB: Use('SSB', 'USB');
    rmLSB: Use('SSB', 'LSB');
    rmCW, rmCWR, rmCWN: Use('CW', '');
    rmAM, rmAMS, rmAMN, rmSAM, rmSAL, rmSAH: Use('AM', '');
    rmFM, rmFMN: Use('FM', '');
    rmRTTY, rmRTTYR: Use('RTTY', '');
    rmC4FM: Use('DIGITALVOICE', 'C4FM');
    rmDStar: Use('DIGITALVOICE', 'DSTAR');
  end;
end;

function RadioResultFromRig(const AStatus: TRigCommandStatus;
  const AKind: TRigErrorKind; const AMessage: string): TRadioResult;
begin
  case AStatus of
    rcsSuccess: Exit(RadioResultOk);
    rcsCancelled: Exit(RadioResultError(reCancelled, AMessage));
    rcsTimeout: Exit(RadioResultError(reTimeout, AMessage));
    { Refused before reaching the radio: the kind says why (not connected,
      or the circuit breaker is open). }
    rcsRejected:
      if AKind = rekNone then
        Exit(RadioResultError(reTemporarilyUnavailable, AMessage));
  end;
  case AKind of
    rekNotConnected, rekPowerOff, rekInvalidHandle:
      Result := RadioResultError(reNotConnected, AMessage);
    rekConnectFailed:
      Result := RadioResultError(reConnectFailed, AMessage);
    rekAccessDenied, rekBusBusy:
      Result := RadioResultError(rePortBusy, AMessage);
    rekTimeout:
      Result := RadioResultError(reTimeout, AMessage);
    rekNotAvailable, rekNotImplemented, rekVfoNotTargetable, rekInvalidVfo:
      Result := RadioResultError(reNotSupported, AMessage);
    rekCircuitOpen:
      Result := RadioResultError(reTemporarilyUnavailable, AMessage);
  else
    Result := RadioResultError(reFailed, AMessage);
  end;
end;

{ Requests }

type
  TCommandRequest = class(TRadioRequest)
  private
    FCallback: TRadioCommandCallback;
  public
    procedure Delivered(const AResult: TRigResult);
    procedure Detach; override;
  end;

  TFrequencyRequest = class(TRadioRequest)
  private
    FCallback: TRadioFrequencyCallback;
  public
    procedure Delivered(const AResult: TRigFreqResult);
    procedure Detach; override;
  end;

  TModeRequest = class(TRadioRequest)
  private
    FCallback: TRadioModeCallback;
  public
    procedure Delivered(const AResult: TRigModeResult);
    procedure Detach; override;
  end;

constructor TRadioRequest.Create(const AOwner: THamlibRadio);
begin
  inherited Create;
  FOwner := AOwner;
  FOwner.FPending.Add(Self);
end;

procedure TRadioRequest.Finish;
begin
  if FOwner <> nil then
    FOwner.FPending.Remove(Self);
  FOwner := nil;
end;

procedure TRadioRequest.Detach;
begin
  FOwner := nil;
end;

procedure TCommandRequest.Delivered(const AResult: TRigResult);
var
  Callback: TRadioCommandCallback;
begin
  Callback := FCallback;
  Finish;
  Free;
  if Assigned(Callback) then
    Callback(RadioResultFromRig(AResult.Status, AResult.Error, AResult.ErrorMsg));
end;

procedure TCommandRequest.Detach;
begin
  inherited Detach;
  FCallback := nil;
end;

procedure TFrequencyRequest.Delivered(const AResult: TRigFreqResult);
var
  Callback: TRadioFrequencyCallback;
  RadioResult: TRadioResult;
  Frequency: TFrequencyHz;
begin
  Callback := FCallback;
  Finish;
  Free;
  if not Assigned(Callback) then
    Exit;
  RadioResult := RadioResultFromRig(AResult.Status, AResult.Error, AResult.ErrorMsg);
  Frequency := Default(TFrequencyHz);
  if (RadioResult.Error = reNone) and
    not TFrequencyHz.TryFromHz(Round(AResult.Freq), Frequency) then
    RadioResult := RadioResultError(reFailed,
      Format('the radio reported %.0f Hz', [AResult.Freq]));
  Callback(RadioResult, Frequency);
end;

procedure TFrequencyRequest.Detach;
begin
  inherited Detach;
  FCallback := nil;
end;

procedure TModeRequest.Delivered(const AResult: TRigModeResult);
var
  Callback: TRadioModeCallback;
  Reading: TRadioModeReading;
begin
  Callback := FCallback;
  Finish;
  Free;
  if not Assigned(Callback) then
    Exit;
  if AResult.Status = rcsSuccess then
    Reading := ModeReadingFromRigMode(AResult.Mode)
  else
    Reading := Default(TRadioModeReading);
  Callback(RadioResultFromRig(AResult.Status, AResult.Error, AResult.ErrorMsg),
    Reading);
end;

procedure TModeRequest.Detach;
begin
  inherited Detach;
  FCallback := nil;
end;

{ THamlibRadio }

constructor THamlibRadio.Create(const ACreateService: TRigServiceCreator);
begin
  inherited Create;
  if not Assigned(ACreateService) then
    raise EArgumentNilException.Create('THamlibRadio needs a service creator');
  FCreateService := ACreateService;
  FPending := TList.Create;
end;

destructor THamlibRadio.Destroy;
var
  Index: Integer;
begin
  { Detach first: Close cancels the pending commands, and a cancellation
    queued from the main thread is delivered at once, inside Close. Results
    still queued free their requests when they arrive. }
  if FPending <> nil then
    for Index := 0 to FPending.Count - 1 do
      TRadioRequest(FPending[Index]).Detach;
  FreeAndNil(FPending);
  ReleaseService;
  inherited Destroy;
end;

procedure THamlibRadio.ReleaseService;
var
  Service: IRigService;
begin
  Service := FService;
  FService := nil;
  if Service = nil then
    Exit;
  Service.SetOnConnectionChanged(nil);
  Service.SetOnFrequencyChanged(nil);
  Service.SetOnError(nil);
  if Service.IsOpen then
    Service.Close;
end;

procedure THamlibRadio.ServiceConnectionChanged(Sender: TObject; AConnected: Boolean);
var
  Handler: TRadioConnectionEvent;
begin
  Handler := FOnConnectionChanged;
  if Assigned(Handler) then
    Handler(Self, AConnected);
end;

procedure THamlibRadio.ServiceFrequencyChanged(Sender: TObject; AFreq: Double);
var
  Handler: TRadioFrequencyEvent;
  Frequency: TFrequencyHz;
begin
  Handler := FOnFrequencyChanged;
  if Assigned(Handler) and TFrequencyHz.TryFromHz(Round(AFreq), Frequency) then
    Handler(Self, Frequency);
end;

procedure THamlibRadio.ServiceError(Sender: TObject; AKind: TRigErrorKind;
  ANativeCode: Integer; const AMsg: string);
var
  Handler: TRadioErrorEvent;
begin
  Handler := FOnError;
  if Assigned(Handler) then
    Handler(Self, RadioResultFromRig(rcsError, AKind, AMsg));
end;

procedure THamlibRadio.Connect(const AConnection: TRadioConnection);
var
  Setting: TRadioSetting;
  Service: IRigService;
begin
  if FService <> nil then
    raise EInvalidOperation.Create('the radio is already connected');
  if AConnection.ModelId < 1 then
    raise SysUtils.EArgumentException.CreateFmt('invalid radio model %d',
      [AConnection.ModelId]);
  Service := FCreateService();
  for Setting in AConnection.Settings do
    Service.AddConfToken(Setting.Name, Setting.Value);
  Service.SetOnConnectionChanged(@ServiceConnectionChanged);
  Service.SetOnFrequencyChanged(@ServiceFrequencyChanged);
  Service.SetOnError(@ServiceError);
  FService := Service;
  try
    Service.Open(AConnection.ModelId, AConnection.Port);
    if AConnection.PollIntervalMs > 0 then
      Service.EnablePolling(AConnection.PollIntervalMs);
  except
    { E.g. an unknown model or a too short poll interval: leave nothing
      open, so the caller can correct the settings and connect again. }
    ReleaseService;
    raise;
  end;
end;

procedure THamlibRadio.Disconnect;
begin
  ReleaseService;
end;

function THamlibRadio.IsConnected: Boolean;
begin
  Result := (FService <> nil) and FService.IsOpen;
end;

{ A call the service refused before queuing it reports to its callback now. }

procedure THamlibRadio.SetFrequency(const AFrequency: TFrequencyHz;
  ACallback: TRadioCommandCallback);
var
  Request: TCommandRequest;
begin
  if not IsConnected then
  begin
    if Assigned(ACallback) then
      ACallback(RadioResultError(reNotConnected, 'the radio is not connected'));
    Exit;
  end;
  Request := TCommandRequest.Create(Self);
  Request.FCallback := ACallback;
  try
    FService.SetFrequencyAsync(AFrequency.Hz, rvfoCurr, @Request.Delivered);
  except
    on E: Exception do
    begin
      Request.Finish;
      Request.Free;
      if Assigned(ACallback) then
        ACallback(RadioResultError(reFailed, E.Message));
    end;
  end;
end;

procedure THamlibRadio.GetFrequency(ACallback: TRadioFrequencyCallback);
var
  Request: TFrequencyRequest;
begin
  if not IsConnected then
  begin
    if Assigned(ACallback) then
      ACallback(RadioResultError(reNotConnected, 'the radio is not connected'),
        Default(TFrequencyHz));
    Exit;
  end;
  Request := TFrequencyRequest.Create(Self);
  Request.FCallback := ACallback;
  try
    FService.GetFrequencyAsync(rvfoCurr, @Request.Delivered);
  except
    on E: Exception do
    begin
      Request.Finish;
      Request.Free;
      if Assigned(ACallback) then
        ACallback(RadioResultError(reFailed, E.Message), Default(TFrequencyHz));
    end;
  end;
end;

procedure THamlibRadio.SetMode(const AMode: TMode; ACallback: TRadioCommandCallback);
var
  Request: TCommandRequest;
  RigMode: TRigMode;
  Reason: string;
begin
  if not TryRigModeFromMode(AMode, RigMode, Reason) then
  begin
    if Assigned(ACallback) then
      ACallback(RadioResultError(reNotSupported, Reason));
    Exit;
  end;
  if not IsConnected then
  begin
    if Assigned(ACallback) then
      ACallback(RadioResultError(reNotConnected, 'the radio is not connected'));
    Exit;
  end;
  Request := TCommandRequest.Create(Self);
  Request.FCallback := ACallback;
  try
    { Passband 0: the radio's default width for the mode. }
    FService.SetModeAsync(RigMode, 0, rvfoCurr, @Request.Delivered);
  except
    on E: Exception do
    begin
      Request.Finish;
      Request.Free;
      if Assigned(ACallback) then
        ACallback(RadioResultError(reFailed, E.Message));
    end;
  end;
end;

procedure THamlibRadio.GetMode(ACallback: TRadioModeCallback);
var
  Request: TModeRequest;
begin
  if not IsConnected then
  begin
    if Assigned(ACallback) then
      ACallback(RadioResultError(reNotConnected, 'the radio is not connected'),
        Default(TRadioModeReading));
    Exit;
  end;
  Request := TModeRequest.Create(Self);
  Request.FCallback := ACallback;
  try
    FService.GetModeAsync(rvfoCurr, @Request.Delivered);
  except
    on E: Exception do
    begin
      Request.Finish;
      Request.Free;
      if Assigned(ACallback) then
        ACallback(RadioResultError(reFailed, E.Message), Default(TRadioModeReading));
    end;
  end;
end;

procedure THamlibRadio.SetTransmit(AOn: Boolean; ACallback: TRadioCommandCallback);
var
  Request: TCommandRequest;
  State: TRigPttState;
begin
  if not IsConnected then
  begin
    if Assigned(ACallback) then
      ACallback(RadioResultError(reNotConnected, 'the radio is not connected'));
    Exit;
  end;
  if AOn then
    State := rpttOn
  else
    State := rpttOff;
  Request := TCommandRequest.Create(Self);
  Request.FCallback := ACallback;
  try
    FService.SetPttAsync(State, @Request.Delivered);
  except
    on E: Exception do
    begin
      Request.Finish;
      Request.Free;
      if Assigned(ACallback) then
        ACallback(RadioResultError(reFailed, E.Message));
    end;
  end;
end;

procedure THamlibRadio.SetOnConnectionChanged(AHandler: TRadioConnectionEvent);
begin
  FOnConnectionChanged := AHandler;
end;

procedure THamlibRadio.SetOnFrequencyChanged(AHandler: TRadioFrequencyEvent);
begin
  FOnFrequencyChanged := AHandler;
end;

procedure THamlibRadio.SetOnError(AHandler: TRadioErrorEvent);
begin
  FOnError := AHandler;
end;

end.
