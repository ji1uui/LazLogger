unit ZLog.Infrastructure.RigWorker;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, SyncObjs, ZLog.Application.Rig;

type
  TRigWorkerService = class(TInterfacedObject, IManagedRigCommandPort)
  private type
    TRigThread = class(TThread)
    private
      FCommands: IRigCommandPort;
      FPump: IRigWorkPump;
      FWakeEvent: TEvent;
      function WaitDurationMs(const ANowMs: Int64): Cardinal;
    protected
      procedure Execute; override;
    public
      constructor Create(const ACommands: IRigCommandPort;
        const APump: IRigWorkPump);
      destructor Destroy; override;
      procedure Wake;
      procedure StopAndJoin;
    end;
  private
    FCommands: IRigCommandPort;
    FPump: IRigWorkPump;
    FWorker: TRigThread;
    FShutdown: Boolean;
  public
    constructor Create(const ACommands: IRigCommandPort;
      const APump: IRigWorkPump);
    destructor Destroy; override;
    function RequestFrequency(const AFrequencyHz: Int64): Boolean;
    procedure RequestRefresh;
    function Snapshot: TRigSnapshot;
    procedure Shutdown;
  end;

implementation

const
  IdleWaitMs = 1000;
  MinimumBackoffWaitMs = 1;

constructor TRigWorkerService.TRigThread.Create(
  const ACommands: IRigCommandPort; const APump: IRigWorkPump);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FCommands := ACommands;
  FPump := APump;
  FWakeEvent := TEvent.Create(nil, False, False, '');
  Start;
end;

destructor TRigWorkerService.TRigThread.Destroy;
begin
  FWakeEvent.Free;
  FPump := nil;
  FCommands := nil;
  inherited Destroy;
end;

function TRigWorkerService.TRigThread.WaitDurationMs(
  const ANowMs: Int64): Cardinal;
var
  Rig: TRigSnapshot;
  Remaining: Int64;
begin
  Rig := FCommands.Snapshot;
  if not Rig.HasPendingFrequency and not Rig.HasPendingRefresh then
    Exit(IdleWaitMs);
  Remaining := Rig.NextRetryAtMs - ANowMs;
  if Remaining <= 0 then
    Exit(MinimumBackoffWaitMs);
  if Remaining > IdleWaitMs then
    Exit(IdleWaitMs);
  Result := Cardinal(Remaining);
end;

procedure TRigWorkerService.TRigThread.Execute;
var
  NowMs: Int64;
  DidWork: Boolean;
  PumpFailed: Boolean;
begin
  while not Terminated do
  begin
    NowMs := Int64(GetTickCount64);
    try
      PumpFailed := False;
      DidWork := FPump.ProcessNext(NowMs);
    except
      PumpFailed := True;
      DidWork := False;
    end;
    if DidWork then
      Continue;
    if PumpFailed then
      FWakeEvent.WaitFor(IdleWaitMs)
    else
      FWakeEvent.WaitFor(WaitDurationMs(NowMs));
  end;
end;

procedure TRigWorkerService.TRigThread.Wake;
begin
  FWakeEvent.SetEvent;
end;

procedure TRigWorkerService.TRigThread.StopAndJoin;
begin
  Terminate;
  Wake;
  WaitFor;
end;

constructor TRigWorkerService.Create(const ACommands: IRigCommandPort;
  const APump: IRigWorkPump);
begin
  inherited Create;
  if not Assigned(ACommands) then
    raise EArgumentNilException.Create('ACommands');
  if not Assigned(APump) then
    raise EArgumentNilException.Create('APump');
  FCommands := ACommands;
  FPump := APump;
  FWorker := TRigThread.Create(FCommands, FPump);
end;

destructor TRigWorkerService.Destroy;
begin
  Shutdown;
  FWorker.Free;
  FPump := nil;
  FCommands := nil;
  inherited Destroy;
end;

function TRigWorkerService.RequestFrequency(const AFrequencyHz: Int64): Boolean;
begin
  if FShutdown then
    raise EInvalidOperation.Create('Rig worker is shut down');
  Result := FCommands.RequestFrequency(AFrequencyHz);
  if Result then
    FWorker.Wake;
end;

procedure TRigWorkerService.RequestRefresh;
begin
  if FShutdown then
    raise EInvalidOperation.Create('Rig worker is shut down');
  FCommands.RequestRefresh;
  FWorker.Wake;
end;

function TRigWorkerService.Snapshot: TRigSnapshot;
begin
  Result := FCommands.Snapshot;
end;

procedure TRigWorkerService.Shutdown;
begin
  if FShutdown then
    Exit;
  FShutdown := True;
  if Assigned(FWorker) then
    FWorker.StopAndJoin;
end;

end.
