unit ZLog.Infrastructure.SubmissionQueue;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, SyncObjs, ZLog.Domain.Qso, ZLog.Application.LogQso,
  ZLog.Application.Submission, ZLog.Application.Diagnostics;

type
  TQueuedQsoSubmission = class(TInterfacedObject, IQsoSubmissionPort,
    ISubmissionWorkPump)
  private type
    TWorkItem = class
    public
      Draft: TQsoDraft;
      Observer: IQsoSubmissionObserver;
      constructor Create(const ADraft: TQsoDraft;
        const AObserver: IQsoSubmissionObserver);
    end;
  private
    FUseCase: ILogQsoUseCase;
    FDispatcher: IQsoCompletionDispatcher;
    FDiagnostics: IDiagnosticSink;
    FCapacity: Integer;
    FQueue: TList;
    FLock: TCriticalSection;
    class function Failure(const AError: TLogQsoError): TLogQsoResult; static;
    class function RetryableFailure(
      const AError: TLogQsoError): TLogQsoResult; static;
    function ExtractFirst: TWorkItem;
  public
    constructor Create(const AUseCase: ILogQsoUseCase;
      const ADispatcher: IQsoCompletionDispatcher; const ACapacity: Integer;
      const ADiagnostics: IDiagnosticSink = nil);
    destructor Destroy; override;
    procedure Submit(const ADraft: TQsoDraft;
      const AObserver: IQsoSubmissionObserver);
    function ProcessNext: Boolean;
    procedure CancelPending;
    function PendingCount: Integer;
  end;

implementation

constructor TQueuedQsoSubmission.TWorkItem.Create(const ADraft: TQsoDraft;
  const AObserver: IQsoSubmissionObserver);
begin
  inherited Create;
  Draft := ADraft;
  Observer := AObserver;
end;

constructor TQueuedQsoSubmission.Create(const AUseCase: ILogQsoUseCase;
  const ADispatcher: IQsoCompletionDispatcher; const ACapacity: Integer;
  const ADiagnostics: IDiagnosticSink);
begin
  inherited Create;
  if not Assigned(AUseCase) then
    raise EArgumentNilException.Create('AUseCase');
  if not Assigned(ADispatcher) then
    raise EArgumentNilException.Create('ADispatcher');
  if ACapacity <= 0 then
    raise EArgumentOutOfRangeException.Create('ACapacity must be positive');
  FUseCase := AUseCase;
  FDispatcher := ADispatcher;
  FDiagnostics := ADiagnostics;
  FCapacity := ACapacity;
  FQueue := TList.Create;
  FLock := TCriticalSection.Create;
end;

destructor TQueuedQsoSubmission.Destroy;
begin
  CancelPending;
  FLock.Free;
  FQueue.Free;
  FDispatcher := nil;
  FDiagnostics := nil;
  FUseCase := nil;
  inherited Destroy;
end;

class function TQueuedQsoSubmission.Failure(
  const AError: TLogQsoError): TLogQsoResult;
begin
  Result.Success := False;
  Result.QsoId := '';
  Result.Error := AError;
  Result.Retryable := False;
end;

class function TQueuedQsoSubmission.RetryableFailure(
  const AError: TLogQsoError): TLogQsoResult;
begin
  Result := Failure(AError);
  Result.Retryable := True;
end;

procedure TQueuedQsoSubmission.Submit(const ADraft: TQsoDraft;
  const AObserver: IQsoSubmissionObserver);
var
  Item: TWorkItem;
  Accepted: Boolean;
begin
  if not Assigned(AObserver) then
    raise EArgumentNilException.Create('AObserver');
  Item := nil;
  FLock.Acquire;
  try
    Accepted := FQueue.Count < FCapacity;
    if Accepted then
    begin
      Item := TWorkItem.Create(ADraft, AObserver);
      FQueue.Add(Item);
    end;
  finally
    FLock.Release;
  end;
  if not Accepted then
    { Submit is a UI-thread port; avoid consuming worker completion capacity. }
    AObserver.SubmissionCompleted(RetryableFailure(lqeQueueFull));
end;

function TQueuedQsoSubmission.ExtractFirst: TWorkItem;
begin
  Result := nil;
  FLock.Acquire;
  try
    if FQueue.Count > 0 then
    begin
      Result := TWorkItem(FQueue[0]);
      FQueue.Delete(0);
    end;
  finally
    FLock.Release;
  end;
end;

function TQueuedQsoSubmission.ProcessNext: Boolean;
var
  Item: TWorkItem;
  LogResult: TLogQsoResult;
begin
  if not FDispatcher.HasCapacity then
    Exit(False);
  Item := ExtractFirst;
  Result := Assigned(Item);
  if not Result then
    Exit;
  try
    try
      LogResult := FUseCase.Execute(Item.Draft);
      if LogResult.Success and Assigned(FDiagnostics) then
        FDiagnostics.ReportHealthy('qso-persistence');
    except
      on E: Exception do
      begin
        if Assigned(FDiagnostics) then
          FDiagnostics.Report(dcQsoPersistenceFailed, dsError,
            'qso-persistence', E.ClassName);
        LogResult := RetryableFailure(lqePersistenceUnavailable);
      end;
    end;
    if not FDispatcher.TryDispatch(Item.Observer, LogResult) then
    begin
      if Assigned(FDiagnostics) then
        FDiagnostics.Report(dcCompletionDispatchFailed, dsCritical,
          'completion-dispatch', 'Completion queue capacity changed');
      raise EInvalidOperation.Create('Completion capacity changed unexpectedly');
    end;
  finally
    Item.Free;
  end;
end;

procedure TQueuedQsoSubmission.CancelPending;
var
  Item: TWorkItem;
begin
  repeat
    Item := ExtractFirst;
    if Assigned(Item) then
      try
        if not FDispatcher.TryDispatch(Item.Observer, Failure(lqeCancelled)) then
          Item.Observer.SubmissionCompleted(Failure(lqeCancelled));
      finally
        Item.Free;
      end;
  until not Assigned(Item);
end;

function TQueuedQsoSubmission.PendingCount: Integer;
begin
  FLock.Acquire;
  try
    Result := FQueue.Count;
  finally
    FLock.Release;
  end;
end;

end.
