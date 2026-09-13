unit ZLog.Infrastructure.SubmissionWorker;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, SyncObjs, ZLog.Domain.Qso, ZLog.Application.Submission;

type
  TSubmissionWorkerService = class(TInterfacedObject,
    IManagedQsoSubmissionPort)
  private type
    TWorkerThread = class(TThread)
    private
      FPump: ISubmissionWorkPump;
      FWakeEvent: TEvent;
    protected
      procedure Execute; override;
    public
      constructor Create(const APump: ISubmissionWorkPump);
      destructor Destroy; override;
      procedure Wake;
      procedure StopAndJoin;
    end;
  private
    FSubmission: IQsoSubmissionPort;
    FPump: ISubmissionWorkPump;
    FWorker: TWorkerThread;
    FShutdown: Boolean;
  public
    constructor Create(const ASubmission: IQsoSubmissionPort;
      const APump: ISubmissionWorkPump);
    destructor Destroy; override;
    procedure Submit(const ADraft: TQsoDraft;
      const AObserver: IQsoSubmissionObserver);
    procedure Shutdown;
  end;

implementation

constructor TSubmissionWorkerService.TWorkerThread.Create(
  const APump: ISubmissionWorkPump);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FPump := APump;
  FWakeEvent := TEvent.Create(nil, False, False, '');
  Start;
end;

destructor TSubmissionWorkerService.TWorkerThread.Destroy;
begin
  FWakeEvent.Free;
  FPump := nil;
  inherited Destroy;
end;

procedure TSubmissionWorkerService.TWorkerThread.Execute;
begin
  while not Terminated do
  begin
    if FPump.ProcessNext then
      Continue;
    if FPump.PendingCount > 0 then
      FWakeEvent.WaitFor(16)
    else
      FWakeEvent.WaitFor(1000);
  end;
end;

procedure TSubmissionWorkerService.TWorkerThread.Wake;
begin
  FWakeEvent.SetEvent;
end;

procedure TSubmissionWorkerService.TWorkerThread.StopAndJoin;
begin
  Terminate;
  Wake;
  WaitFor;
end;

constructor TSubmissionWorkerService.Create(
  const ASubmission: IQsoSubmissionPort; const APump: ISubmissionWorkPump);
begin
  inherited Create;
  if not Assigned(ASubmission) then
    raise EArgumentNilException.Create('ASubmission');
  if not Assigned(APump) then
    raise EArgumentNilException.Create('APump');
  FSubmission := ASubmission;
  FPump := APump;
  FWorker := TWorkerThread.Create(FPump);
end;

destructor TSubmissionWorkerService.Destroy;
begin
  Shutdown;
  FWorker.Free;
  FPump := nil;
  FSubmission := nil;
  inherited Destroy;
end;

procedure TSubmissionWorkerService.Submit(const ADraft: TQsoDraft;
  const AObserver: IQsoSubmissionObserver);
begin
  if FShutdown then
    raise EInvalidOperation.Create('Submission worker is shut down');
  FSubmission.Submit(ADraft, AObserver);
  FWorker.Wake;
end;

procedure TSubmissionWorkerService.Shutdown;
begin
  if FShutdown then
    Exit;
  FShutdown := True;
  FWorker.StopAndJoin;
  FPump.CancelPending;
end;

end.
