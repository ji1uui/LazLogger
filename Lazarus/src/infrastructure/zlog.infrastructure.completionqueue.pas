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
    function ExtractFirst: TCompletionItem;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Dispatch(const AObserver: IQsoSubmissionObserver;
      const AResult: TLogQsoResult);
    function Drain(const AMaximumItems: Integer): Integer;
    function PendingCount: Integer;
  end;

implementation

constructor TQueuedCompletionDispatcher.TCompletionItem.Create(
  const AObserver: IQsoSubmissionObserver; const AResult: TLogQsoResult);
begin
  inherited Create;
  Observer := AObserver;
  LogResult := AResult;
end;

constructor TQueuedCompletionDispatcher.Create;
begin
  inherited Create;
  FQueue := TList.Create;
  FLock := TCriticalSection.Create;
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
  inherited Destroy;
end;

procedure TQueuedCompletionDispatcher.Dispatch(
  const AObserver: IQsoSubmissionObserver; const AResult: TLogQsoResult);
var
  Item: TCompletionItem;
begin
  if not Assigned(AObserver) then
    raise EArgumentNilException.Create('AObserver');
  Item := TCompletionItem.Create(AObserver, AResult);
  FLock.Acquire;
  try
    FQueue.Add(Item);
  except
    Item.Free;
    raise;
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

end.
