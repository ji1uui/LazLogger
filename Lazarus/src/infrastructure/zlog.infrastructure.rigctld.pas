unit ZLog.Infrastructure.Rigctld;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, SyncObjs, ZLog.Application.Diagnostics, ZLog.Application.Rig;

type
  TRigctldTransportResult = (rtrSuccess, rtrTimeout, rtrDisconnected,
    rtrProtocolError);

  IRigctldTransport = interface
    ['{81D126E8-8047-40D2-AC12-A0929C72324B}']
    { Implemented by a child-process adapter; may block only its rig worker. }
    function Execute(const ACommand: string; const ATimeoutMs: Integer;
      out AResponse: string): TRigctldTransportResult;
  end;

  IRigctldProcessSession = interface
    ['{21717A04-B1E8-45B6-865A-E120C8E92966}']
    { OS adapter owns the child process and its stdin/stdout pipes. }
    function Start: Boolean;
    procedure Stop;
    function IsRunning: Boolean;
    function Exchange(const ACommand: string; const ATimeoutMs: Integer;
      out AResponse: string): TRigctldTransportResult;
  end;

  TRigctldProcessTransport = class(TInterfacedObject, IRigctldTransport)
  private
    FSession: IRigctldProcessSession;
  public
    constructor Create(const ASession: IRigctldProcessSession);
    destructor Destroy; override;
    function Execute(const ACommand: string; const ATimeoutMs: Integer;
      out AResponse: string): TRigctldTransportResult;
  end;

  TRigctldClient = class(TInterfacedObject, IRigCommandPort, IRigWorkPump)
  private
    FTransport: IRigctldTransport;
    FDiagnostics: IDiagnosticSink;
    FLock: TCriticalSection;
    FState: TRigConnectionState;
    FFrequencyHz: Int64;
    FPendingFrequencyHz: Int64;
    FHasPendingFrequency: Boolean;
    FRefreshPending: Boolean;
    FConsecutiveFailures: Integer;
    FNextRetryAtMs: Int64;
    FTimeoutMs: Integer;
    procedure RecordFailure(const AResult: TRigctldTransportResult;
      const ANowMs: Int64);
    procedure RecordSuccess;
    class function RetryDelayMs(const AFailureCount: Integer): Int64; static;
  public
    constructor Create(const ATransport: IRigctldTransport;
      const ADiagnostics: IDiagnosticSink = nil; const ATimeoutMs: Integer = 500);
    destructor Destroy; override;
    function RequestFrequency(const AFrequencyHz: Int64): Boolean;
    procedure RequestRefresh;
    function Snapshot: TRigSnapshot;
    function ProcessNext(const ANowMs: Int64): Boolean;
  end;

implementation

const
  MinimumFrequencyHz = 100000;
  MaximumFrequencyHz = Int64(300000000000);
  InitialRetryDelayMs = 250;
  MaximumRetryDelayMs = 8000;

constructor TRigctldProcessTransport.Create(
  const ASession: IRigctldProcessSession);
begin
  inherited Create;
  if not Assigned(ASession) then
    raise EArgumentNilException.Create('ASession');
  FSession := ASession;
end;

destructor TRigctldProcessTransport.Destroy;
begin
  if Assigned(FSession) and FSession.IsRunning then
    FSession.Stop;
  FSession := nil;
  inherited Destroy;
end;

function TRigctldProcessTransport.Execute(const ACommand: string;
  const ATimeoutMs: Integer; out AResponse: string): TRigctldTransportResult;
begin
  AResponse := '';
  if not FSession.IsRunning and not FSession.Start then
    Exit(rtrDisconnected);
  Result := FSession.Exchange(ACommand, ATimeoutMs, AResponse);
  if Result <> rtrSuccess then
    FSession.Stop;
end;

constructor TRigctldClient.Create(const ATransport: IRigctldTransport;
  const ADiagnostics: IDiagnosticSink; const ATimeoutMs: Integer);
begin
  inherited Create;
  if not Assigned(ATransport) then
    raise EArgumentNilException.Create('ATransport');
  if ATimeoutMs <= 0 then
    raise EArgumentOutOfRangeException.Create('ATimeoutMs must be positive');
  FTransport := ATransport;
  FDiagnostics := ADiagnostics;
  FTimeoutMs := ATimeoutMs;
  FLock := TCriticalSection.Create;
  FState := rcsDisconnected;
end;

destructor TRigctldClient.Destroy;
begin
  FLock.Free;
  FDiagnostics := nil;
  FTransport := nil;
  inherited Destroy;
end;

class function TRigctldClient.RetryDelayMs(
  const AFailureCount: Integer): Int64;
var
  Index: Integer;
begin
  Result := InitialRetryDelayMs;
  for Index := 2 to AFailureCount do
  begin
    Result := Result * 2;
    if Result >= MaximumRetryDelayMs then
      Exit(MaximumRetryDelayMs);
  end;
end;

procedure TRigctldClient.RecordFailure(
  const AResult: TRigctldTransportResult; const ANowMs: Int64);
begin
  FLock.Acquire;
  try
    Inc(FConsecutiveFailures);
    FState := rcsDegraded;
    FNextRetryAtMs := ANowMs + RetryDelayMs(FConsecutiveFailures);
  finally
    FLock.Release;
  end;
  if Assigned(FDiagnostics) then
    FDiagnostics.Report(dcRigTransportFailed, dsWarning, 'hamlib-rigctld',
      IntToStr(Ord(AResult)));
end;

procedure TRigctldClient.RecordSuccess;
begin
  FLock.Acquire;
  try
    FConsecutiveFailures := 0;
    FNextRetryAtMs := 0;
    FState := rcsReady;
  finally
    FLock.Release;
  end;
  if Assigned(FDiagnostics) then
    FDiagnostics.ReportHealthy('hamlib-rigctld');
end;

function TRigctldClient.RequestFrequency(const AFrequencyHz: Int64): Boolean;
begin
  Result := (AFrequencyHz >= MinimumFrequencyHz) and
    (AFrequencyHz <= MaximumFrequencyHz);
  if not Result then
    Exit;
  FLock.Acquire;
  try
    FPendingFrequencyHz := AFrequencyHz;
    FHasPendingFrequency := True;
  finally
    FLock.Release;
  end;
end;

procedure TRigctldClient.RequestRefresh;
begin
  FLock.Acquire;
  try
    FRefreshPending := True;
  finally
    FLock.Release;
  end;
end;

function TRigctldClient.Snapshot: TRigSnapshot;
begin
  FLock.Acquire;
  try
    Result.State := FState;
    Result.FrequencyHz := FFrequencyHz;
    Result.PendingFrequencyHz := FPendingFrequencyHz;
    Result.HasPendingFrequency := FHasPendingFrequency;
    Result.HasPendingRefresh := FRefreshPending;
    Result.ConsecutiveFailures := FConsecutiveFailures;
    Result.NextRetryAtMs := FNextRetryAtMs;
  finally
    FLock.Release;
  end;
end;

function TRigctldClient.ProcessNext(const ANowMs: Int64): Boolean;
var
  Command: string;
  Response: string;
  DesiredFrequency: Int64;
  IsSetCommand: Boolean;
  TransportResult: TRigctldTransportResult;
  ParsedFrequency: Int64;
begin
  Command := '';
  DesiredFrequency := 0;
  IsSetCommand := False;
  FLock.Acquire;
  try
    if ANowMs < FNextRetryAtMs then
      Exit(False);
    if FHasPendingFrequency then
    begin
      DesiredFrequency := FPendingFrequencyHz;
      Command := 'F ' + IntToStr(DesiredFrequency);
      IsSetCommand := True;
    end
    else if FRefreshPending then
      Command := 'f'
    else
      Exit(False);
    FState := rcsConnecting;
  finally
    FLock.Release;
  end;

  try
    TransportResult := FTransport.Execute(Command, FTimeoutMs, Response);
  except
    on E: Exception do
      TransportResult := rtrDisconnected;
  end;
  TransportResult := FTransport.Execute(Command, FTimeoutMs, Response);
  Result := True;
  if TransportResult <> rtrSuccess then
  begin
    RecordFailure(TransportResult, ANowMs);
    Exit;
  end;

  if IsSetCommand then
  begin
    if Trim(Response) <> 'RPRT 0' then
    begin
      RecordFailure(rtrProtocolError, ANowMs);
      Exit;
    end;
    FLock.Acquire;
    try
      { Clear only the value that was sent; a newer UI request remains queued. }
      if FHasPendingFrequency and (FPendingFrequencyHz = DesiredFrequency) then
        FHasPendingFrequency := False;
      FFrequencyHz := DesiredFrequency;
    finally
      FLock.Release;
    end;
  end
  else
  begin
    if not TryStrToInt64(Trim(Response), ParsedFrequency) or
      (ParsedFrequency < MinimumFrequencyHz) or
      (ParsedFrequency > MaximumFrequencyHz) then
    begin
      RecordFailure(rtrProtocolError, ANowMs);
      Exit;
    end;
    FLock.Acquire;
    try
      FFrequencyHz := ParsedFrequency;
      FRefreshPending := False;
    finally
      FLock.Release;
    end;
  end;
  RecordSuccess;
end;

end.
