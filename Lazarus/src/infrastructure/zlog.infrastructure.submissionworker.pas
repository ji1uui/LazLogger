unit ZLog.Infrastructure.SubmissionWorker;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, SyncObjs, ZLog.Domain.Qso, ZLog.Application.Submission,
  ZLog.Application.Diagnostics;

type
  TSubmissionWorkerService = class(TInterfacedObject,
    IManagedQsoSubmissionPort)
  private type
    TWorkerThread = class(TThread)
    private
      FPump: ISubmissionWorkPump;
      FDiagnostics: IDiagnosticSink;
      FWakeEvent: TEvent;
      procedure ReportFailure(const AException: Exception);
    protected
      procedure Execute; override;
    public
      constructor Create(const APump: ISubmissionWorkPump;
        const ADiagnostics: IDiagnosticSink);
      destructor Destroy; override;
      procedure Wake;
      procedure StopAndJoin;
    end;
  private
    FSubmission: IQsoSubmissionPort;
    FPump: ISubmissionWorkPump;
    FDiagnostics: IDiagnosticSink;
    FWorker: TWorkerThread;
    FShutdown: Boolean;
  public
    constructor Create(const ASubmission: IQsoSubmissionPort;
      const APump: ISubmissionWorkPump;
      const ADiagnostics: IDiagnosticSink = nil);
    destructor Destroy; override;
    procedure Submit(const ADraft: TQsoDraft;
      const AObserver: IQsoSubmissionObserver);
    procedure Shutdown;
  end;

implementation

constructor TSubmissionWorkerService.TWorkerThread.Create(
  const APump: ISubmissionWorkPump; const ADiagnostics: IDiagnosticSink);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FPump := APump;
  FDiagnostics := ADiagnostics;
  FWakeEvent := TEvent.Create(nil, False, False, '');
  Start;
end;

destructor TSubmissionWorkerService.TWorkerThread.Destroy;
begin
  FWakeEvent.Free;
  FDiagnostics := nil;
  FPump := nil;
  inherited Destroy;
end;

procedure TSubmissionWorkerService.TWorkerThread.ReportFailure(
  const AException: Exception);
begin
  if not Assigned(FDiagnostics) then
    Exit;
  try
    FDiagnostics.Report(dcSubmissionWorkerFailed, dsCritical,
      'qso-submission-worker', AException.ClassName);
  except
    { A diagnostic adapter must not be able to terminate the worker. }
  end;
end;

procedure TSubmissionWorkerService.TWorkerThread.Execute;
begin
  while not Terminated do
  begin
    try
      if FPump.ProcessNext then
        Continue;
      if FPump.PendingCount > 0 then
        FWakeEvent.WaitFor(16)
      else
        FWakeEvent.WaitFor(1000);
    except
      on E: Exception do
      begin
        ReportFailure(E);
        { Avoid a hot failure loop while preserving the worker for recovery. }
        FWakeEvent.WaitFor(1000);
        Continue;
      end;
    end;
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
  const ASubmission: IQsoSubmissionPort; const APump: ISubmissionWorkPump;
  const ADiagnostics: IDiagnosticSink);
begin
  inherited Create;
  if not Assigned(ASubmission) then
    raise EArgumentNilException.Create('ASubmission');
  if not Assigned(APump) then
    raise EArgumentNilException.Create('APump');
  FSubmission := ASubmission;
  FPump := APump;
  FDiagnostics := ADiagnostics;
  FWorker := TWorkerThread.Create(FPump, FDiagnostics);
end;

destructor TSubmissionWorkerService.Destroy;
begin
  Shutdown;
  FWorker.Free;
  FPump := nil;
  FSubmission := nil;
  FDiagnostics := nil;
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
  if Assigned(FWorker) then
    FWorker.StopAndJoin;
  if Assigned(FPump) then
    FPump.CancelPending;
end;

end.
