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
      HasResult: Boolean;
      LogResult: TLogQsoResult;
      constructor Create(const ADraft: TQsoDraft;
        const AObserver: IQsoSubmissionObserver);
    end;
  private
    FUseCase: ILogQsoUseCase;
    FDispatcher: IQsoCompletionDispatcher;
    FDiagnostics: IDiagnosticSink;
    FCapacity: Integer;
    FQueue: TList;
    FPendingCompletion: TWorkItem;
    FInFlight: Integer;
    FLock: TCriticalSection;
    class function Failure(const AError: TLogQsoError): TLogQsoResult; static;
    class function RetryableFailure(
      const AError: TLogQsoError): TLogQsoResult; static;
    function ExtractFirst: TWorkItem;
    function ExtractForProcessing: TWorkItem;
    procedure FinishProcessing;
    procedure ReportDiagnostic(const ACode: TDiagnosticCode;
      const ASeverity: TDiagnosticSeverity; const AComponent,
      ADetail: string);
    procedure ReportHealthy(const AComponent: string);
    procedure StorePendingCompletion(const AItem: TWorkItem);
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
  HasResult := False;
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
  if Assigned(FLock) and Assigned(FQueue) then
    CancelPending;
  FreeAndNil(FLock);
  FreeAndNil(FQueue);
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
    Accepted := FQueue.Count + Ord(Assigned(FPendingCompletion)) + FInFlight <
      FCapacity;
    if Accepted then
    begin
      Item := TWorkItem.Create(ADraft, AObserver);
      try
        FQueue.Add(Item);
      except
        Item.Free;
        raise;
      end;
    end;
  finally
    FLock.Release;
  end;
  if not Accepted then
    { Submit is a UI-thread port; avoid consuming worker completion capacity. }
    AObserver.SubmissionCompleted(RetryableFailure(lqeQueueFull));
end;

function TQueuedQsoSubmission.ExtractForProcessing: TWorkItem;
begin
  Result := nil;
  FLock.Acquire;
  try
    if Assigned(FPendingCompletion) then
    begin
      Result := FPendingCompletion;
      FPendingCompletion := nil;
    end
    else if FQueue.Count > 0 then
    begin
      Result := TWorkItem(FQueue[0]);
      FQueue.Delete(0);
    end;
    if Assigned(Result) then
      Inc(FInFlight);
  finally
    FLock.Release;
  end;
end;

procedure TQueuedQsoSubmission.FinishProcessing;
begin
  FLock.Acquire;
  try
    if FInFlight <= 0 then
      raise EInvalidOperation.Create('No submission is being processed');
    Dec(FInFlight);
  finally
    FLock.Release;
  end;
end;

procedure TQueuedQsoSubmission.ReportDiagnostic(
  const ACode: TDiagnosticCode; const ASeverity: TDiagnosticSeverity;
  const AComponent, ADetail: string);
begin
  if not Assigned(FDiagnostics) then
    Exit;
  try
    FDiagnostics.Report(ACode, ASeverity, AComponent, ADetail);
  except
    { Diagnostics must never change persistence or completion semantics. }
  end;
end;

procedure TQueuedQsoSubmission.ReportHealthy(const AComponent: string);
begin
  if not Assigned(FDiagnostics) then
    Exit;
  try
    FDiagnostics.ReportHealthy(AComponent);
  except
    { Diagnostics must never change persistence or completion semantics. }
  end;
end;

function TQueuedQsoSubmission.ExtractFirst: TWorkItem;
begin
  Result := nil;
  FLock.Acquire;
  try
    if Assigned(FPendingCompletion) then
    begin
      Result := FPendingCompletion;
      FPendingCompletion := nil;
    end
    else if FQueue.Count > 0 then
    begin
      Result := TWorkItem(FQueue[0]);
      FQueue.Delete(0);
    end;
  finally
    FLock.Release;
  end;
end;

procedure TQueuedQsoSubmission.StorePendingCompletion(const AItem: TWorkItem);
begin
  FLock.Acquire;
  try
    if Assigned(FPendingCompletion) then
      raise EInvalidOperation.Create('Only one completion may be pending');
    if FInFlight <= 0 then
      raise EInvalidOperation.Create('No submission is being processed');
    FPendingCompletion := AItem;
    Dec(FInFlight);
  finally
    FLock.Release;
  end;
end;

function TQueuedQsoSubmission.ProcessNext: Boolean;
var
  Item: TWorkItem;
  LogResult: TLogQsoResult;
  Dispatched: Boolean;
begin
  if not FDispatcher.HasCapacity then
    Exit(False);
  Item := ExtractForProcessing;
  Result := Assigned(Item);
  if not Result then
    Exit;
  try
    try
      if not Item.HasResult then
      begin
        LogResult := FUseCase.Execute(Item.Draft);
        Item.LogResult := LogResult;
        Item.HasResult := True;
        if LogResult.Success then
          ReportHealthy('qso-persistence');
      end
      else
        LogResult := Item.LogResult;
    except
      on E: Exception do
      begin
        ReportDiagnostic(dcQsoPersistenceFailed, dsError,
          'qso-persistence', E.ClassName);
        LogResult := RetryableFailure(lqePersistenceUnavailable);
        Item.LogResult := LogResult;
        Item.HasResult := True;
      end;
    end;
    try
      Dispatched := FDispatcher.TryDispatch(Item.Observer, LogResult);
    except
      on E: Exception do
      begin
        Dispatched := False;
        ReportDiagnostic(dcCompletionDispatchFailed, dsCritical,
          'completion-dispatch', E.ClassName);
      end;
    end;
    if not Dispatched then
    begin
      ReportDiagnostic(dcCompletionDispatchFailed, dsCritical,
        'completion-dispatch', 'Completion queue capacity changed');
      { Capacity can change between HasCapacity and TryDispatch. Retain the
        completed item so a durable operation is never executed twice. }
      StorePendingCompletion(Item);
      Item := nil;
    end;
  finally
    if Assigned(Item) then
    begin
      FinishProcessing;
      Item.Free;
    end;
  end;
end;

procedure TQueuedQsoSubmission.CancelPending;
var
  Item: TWorkItem;
  LogResult: TLogQsoResult;
begin
  repeat
    Item := ExtractFirst;
    if Assigned(Item) then
      try
        if Item.HasResult then
          LogResult := Item.LogResult
        else
          LogResult := Failure(lqeCancelled);
        if not FDispatcher.TryDispatch(Item.Observer, LogResult) then
          Item.Observer.SubmissionCompleted(LogResult);
      finally
        Item.Free;
      end;
  until not Assigned(Item);
end;

function TQueuedQsoSubmission.PendingCount: Integer;
begin
  FLock.Acquire;
  try
    Result := FQueue.Count + Ord(Assigned(FPendingCompletion)) + FInFlight;
  finally
    FLock.Release;
  end;
end;

end.
