unit ZLog.Infrastructure.CompletionQueue;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, SyncObjs, ZLog.Application.LogQso,
  ZLog.Application.Submission;

type
  TQueuedCompletionDispatcher = class(TInterfacedObject,
    IQsoCompletionDispatcher, ICompletionPump)
  private type
    TCompletionItem = class
    public
      Observer: IQsoSubmissionObserver;
      LogResult: TLogQsoResult;
      constructor Create(const AObserver: IQsoSubmissionObserver;
        const AResult: TLogQsoResult);
    end;
  private
    FQueue: TList;
    FLock: TCriticalSection;
    FNotifier: ICompletionAvailableNotifier;
    FCapacity: Integer;
    FHighWaterMark: Integer;
    function ExtractFirst: TCompletionItem;
  public
    constructor Create(const ANotifier: ICompletionAvailableNotifier = nil;
      const ACapacity: Integer = 64);
    destructor Destroy; override;
    function TryDispatch(const AObserver: IQsoSubmissionObserver;
      const AResult: TLogQsoResult): Boolean;
    function HasCapacity: Boolean;
    function Drain(const AMaximumItems: Integer): Integer;
    function PendingCount: Integer;
    function Capacity: Integer;
    function HighWaterMark: Integer;
  end;

implementation

constructor TQueuedCompletionDispatcher.TCompletionItem.Create(
  const AObserver: IQsoSubmissionObserver; const AResult: TLogQsoResult);
begin
  inherited Create;
  Observer := AObserver;
  LogResult := AResult;
end;

constructor TQueuedCompletionDispatcher.Create(
  const ANotifier: ICompletionAvailableNotifier; const ACapacity: Integer);
begin
  inherited Create;
  if ACapacity <= 0 then
    raise EArgumentOutOfRangeException.Create('ACapacity must be positive');
  FQueue := TList.Create;
  FLock := TCriticalSection.Create;
  FNotifier := ANotifier;
  FCapacity := ACapacity;
end;

destructor TQueuedCompletionDispatcher.Destroy;
var
  Item: TCompletionItem;
begin
  repeat
    Item := ExtractFirst;
    Item.Free;
  until not Assigned(Item);
  FLock.Free;
  FQueue.Free;
  FNotifier := nil;
  inherited Destroy;
end;

function TQueuedCompletionDispatcher.TryDispatch(
  const AObserver: IQsoSubmissionObserver; const AResult: TLogQsoResult): Boolean;
var
  Item: TCompletionItem;
  MustNotify: Boolean;
begin
  if not Assigned(AObserver) then
    raise EArgumentNilException.Create('AObserver');
  Item := nil;
  MustNotify := False;
  FLock.Acquire;
  try
    Result := FQueue.Count < FCapacity;
    if Result then
    begin
      MustNotify := FQueue.Count = 0;
      Item := TCompletionItem.Create(AObserver, AResult);
      try
        FQueue.Add(Item);
      except
        Item.Free;
        raise;
      end;
      if FQueue.Count > FHighWaterMark then
        FHighWaterMark := FQueue.Count;
    end;
  finally
    FLock.Release;
  end;
  if Result and MustNotify and Assigned(FNotifier) then
    FNotifier.NotifyCompletionAvailable;
end;

function TQueuedCompletionDispatcher.HasCapacity: Boolean;
begin
  FLock.Acquire;
  try
    Result := FQueue.Count < FCapacity;
  finally
    FLock.Release;
  end;
end;

function TQueuedCompletionDispatcher.ExtractFirst: TCompletionItem;
begin
  Result := nil;
  FLock.Acquire;
  try
    if FQueue.Count > 0 then
    begin
      Result := TCompletionItem(FQueue[0]);
      FQueue.Delete(0);
    end;
  finally
    FLock.Release;
  end;
end;

function TQueuedCompletionDispatcher.Drain(const AMaximumItems: Integer): Integer;
var
  Item: TCompletionItem;
begin
  if AMaximumItems <= 0 then
    raise EArgumentOutOfRangeException.Create('AMaximumItems must be positive');
  Result := 0;
  while Result < AMaximumItems do
  begin
    Item := ExtractFirst;
    if not Assigned(Item) then
      Exit;
    try
      Item.Observer.SubmissionCompleted(Item.LogResult);
    finally
      Item.Free;
    end;
    Inc(Result);
  end;
end;

function TQueuedCompletionDispatcher.PendingCount: Integer;
begin
  FLock.Acquire;
  try
    Result := FQueue.Count;
  finally
    FLock.Release;
  end;
end;

function TQueuedCompletionDispatcher.Capacity: Integer;
begin
  Result := FCapacity;
end;

function TQueuedCompletionDispatcher.HighWaterMark: Integer;
begin
  FLock.Acquire;
  try
    Result := FHighWaterMark;
  finally
    FLock.Release;
  end;
end;

end.
