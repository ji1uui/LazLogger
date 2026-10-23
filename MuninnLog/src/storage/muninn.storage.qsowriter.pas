unit Muninn.Storage.QsoWriter;

{ The QSO writer port (Muninn.Core.QsoWriter) on SQLite: one worker thread
  with its own connection saves queued QSOs in order, one transaction each
  (ADR 0011). A failed save stays at the head of the queue and is tried again
  after a delay, so later QSOs keep their order; the failure is reported once
  per QSO.

  Results reach the main thread through TThread.Queue. Each queued notice
  holds a reference to a shared target whose handlers the writer clears when
  it is destroyed, so a notice still queued then is dropped. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Muninn.Core.Qso, Muninn.Core.QsoWriter,
  Muninn.Storage.Sqlite;

type
  TQsoClock = function: Int64 of object;

  { The handlers, shared with the queued notices. }
  TQsoWriterTarget = class(TInterfacedObject)
  public
    OnSaved: TQsoSavedEvent;
    OnFailed: TQsoSaveFailedEvent;
  end;

  TSqliteQsoWriter = class;

  TQsoWriterThread = class(TThread)
  private
    FOwner: TSqliteQsoWriter;
  protected
    procedure Execute; override;
  public
    constructor Create(const AOwner: TSqliteQsoWriter);
  end;

  TSqliteQsoWriter = class(TInterfacedObject, IQsoWriter)
  private
    FDatabase: TSqliteDatabase;
    FSource: string;
    FRetryDelayMs: Cardinal;
    FLock: TRTLCriticalSection;
    FWake: PRTLEvent;
    { TQsoRecord objects; FTickets holds their tickets at the same index. }
    FQueue: TList;
    FTickets: array of Int64;
    FNextTicket: Int64;
    FTarget: TQsoWriterTarget;
    FTargetRef: IUnknown;
    FThread: TQsoWriterThread;
    function TakeHead(out ATicket: Int64; out AQso: TQsoRecord): Boolean;
    procedure RemoveHead;
    function SaveOne(const AQso: TQsoRecord; out AQsoId, AError: string): Boolean;
  public
    const
      MaxPending = 1000;
      DefaultRetryDelayMs = 2000;
    { Takes ownership of ADatabase, an open logbook connection that only this
      writer will use from now on. ASource goes to qso.source. }
    constructor Create(const ADatabase: TSqliteDatabase; const ASource: string;
      const ARetryDelayMs: Cardinal = DefaultRetryDelayMs);
    { Waits up to 5 s for the queue to empty; QSOs still queued then are lost
      (call Flush first and tell the user). }
    destructor Destroy; override;
    function Submit(const AQso: TQsoRecord): Int64;
    function PendingCount: Integer;
    procedure SetOnSaved(AHandler: TQsoSavedEvent);
    procedure SetOnFailed(AHandler: TQsoSaveFailedEvent);
    function Flush(const ATimeoutMs: Cardinal): Boolean;
  end;

implementation

uses
  DateUtils, Muninn.Storage.QsoRepository;

type
  { One result on its way to the main thread. }
  TQsoNotice = class
  private
    FTarget: IUnknown;
    FSaved: Boolean;
    FTicket: Int64;
    FText: string;
  public
    constructor Create(const ATarget: TQsoWriterTarget; const ASaved: Boolean;
      const ATicket: Int64; const AText: string);
    procedure Deliver;
  end;

constructor TQsoNotice.Create(const ATarget: TQsoWriterTarget;
  const ASaved: Boolean; const ATicket: Int64; const AText: string);
begin
  inherited Create;
  FTarget := ATarget;
  FSaved := ASaved;
  FTicket := ATicket;
  FText := AText;
end;

procedure TQsoNotice.Deliver;
var
  Target: TQsoWriterTarget;
begin
  try
    Target := FTarget as TQsoWriterTarget;
    if FSaved then
    begin
      if Assigned(Target.OnSaved) then
        Target.OnSaved(FTicket, FText);
    end
    else if Assigned(Target.OnFailed) then
      Target.OnFailed(FTicket, FText);
  finally
    Free;
  end;
end;

function UtcNowMs: Int64;
begin
  Result := DateTimeToUnix(LocalTimeToUniversal(Now), True) * 1000 +
    MilliSecondOf(Now);
end;

{ TQsoWriterThread }

constructor TQsoWriterThread.Create(const AOwner: TSqliteQsoWriter);
begin
  FOwner := AOwner;
  inherited Create(False);
end;

procedure TQsoWriterThread.Execute;
var
  Ticket: Int64;
  Qso: TQsoRecord;
  QsoId, Error, ReportedError: string;
  ReportedTicket: Int64;
  Notice: TQsoNotice;
begin
  ReportedTicket := -1;
  ReportedError := '';
  while not Terminated do
  begin
    if not FOwner.TakeHead(Ticket, Qso) then
    begin
      RTLEventWaitFor(FOwner.FWake);
      Continue;
    end;
    if FOwner.SaveOne(Qso, QsoId, Error) then
    begin
      FOwner.RemoveHead;
      Notice := TQsoNotice.Create(FOwner.FTarget, True, Ticket, QsoId);
      TThread.Queue(nil, @Notice.Deliver);
    end
    else
    begin
      if (Ticket <> ReportedTicket) or (Error <> ReportedError) then
      begin
        ReportedTicket := Ticket;
        ReportedError := Error;
        Notice := TQsoNotice.Create(FOwner.FTarget, False, Ticket, Error);
        TThread.Queue(nil, @Notice.Deliver);
      end;
      { Woken early by Submit or Destroy; then the head is tried again. }
      RTLEventWaitFor(FOwner.FWake, FOwner.FRetryDelayMs);
    end;
  end;
end;

{ TSqliteQsoWriter }

constructor TSqliteQsoWriter.Create(const ADatabase: TSqliteDatabase;
  const ASource: string; const ARetryDelayMs: Cardinal);
begin
  inherited Create;
  if ADatabase = nil then
    raise EArgumentNilException.Create('TSqliteQsoWriter needs a database');
  FDatabase := ADatabase;
  FSource := ASource;
  FRetryDelayMs := ARetryDelayMs;
  InitCriticalSection(FLock);
  FWake := RTLEventCreate;
  FQueue := TList.Create;
  FNextTicket := 1;
  FTarget := TQsoWriterTarget.Create;
  FTargetRef := FTarget;
  FThread := TQsoWriterThread.Create(Self);
end;

destructor TSqliteQsoWriter.Destroy;
var
  Index: Integer;
begin
  if FThread <> nil then
  begin
    Flush(5000);
    FThread.Terminate;
    RTLEventSetEvent(FWake);
    FThread.WaitFor;
    FThread.Free;
  end;
  { Notices still queued for the main thread are dropped. }
  if FTarget <> nil then
  begin
    FTarget.OnSaved := nil;
    FTarget.OnFailed := nil;
  end;
  FTargetRef := nil;
  if FQueue <> nil then
    for Index := 0 to FQueue.Count - 1 do
      TQsoRecord(FQueue[Index]).Free;
  FQueue.Free;
  if FWake <> nil then
    RTLEventDestroy(FWake);
  DoneCriticalSection(FLock);
  FDatabase.Free;
  inherited Destroy;
end;

function TSqliteQsoWriter.Submit(const AQso: TQsoRecord): Int64;
begin
  if AQso = nil then
    raise EArgumentNilException.Create('Submit needs a QSO');
  EnterCriticalSection(FLock);
  try
    if FQueue.Count >= MaxPending then
    begin
      AQso.Free;
      raise EQsoQueueFull.CreateFmt('%d QSOs are waiting to be saved', [FQueue.Count]);
    end;
    Result := FNextTicket;
    Inc(FNextTicket);
    FQueue.Add(AQso);
    SetLength(FTickets, FQueue.Count);
    FTickets[FQueue.Count - 1] := Result;
  finally
    LeaveCriticalSection(FLock);
  end;
  RTLEventSetEvent(FWake);
end;

function TSqliteQsoWriter.TakeHead(out ATicket: Int64; out AQso: TQsoRecord): Boolean;
begin
  EnterCriticalSection(FLock);
  try
    Result := FQueue.Count > 0;
    if Result then
    begin
      AQso := TQsoRecord(FQueue[0]);
      ATicket := FTickets[0];
    end
    else
    begin
      AQso := nil;
      ATicket := 0;
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TSqliteQsoWriter.RemoveHead;
var
  Qso: TQsoRecord;
begin
  EnterCriticalSection(FLock);
  try
    Qso := TQsoRecord(FQueue[0]);
    FQueue.Delete(0);
    if Length(FTickets) > 1 then
      Move(FTickets[1], FTickets[0], (Length(FTickets) - 1) * SizeOf(Int64));
    SetLength(FTickets, Length(FTickets) - 1);
  finally
    LeaveCriticalSection(FLock);
  end;
  Qso.Free;
end;

{ On the worker thread; the only user of FDatabase. }
function TSqliteQsoWriter.SaveOne(const AQso: TQsoRecord;
  out AQsoId, AError: string): Boolean;
var
  Repository: TQsoRepository;
begin
  AQsoId := '';
  AError := '';
  Repository := TQsoRepository.Create(FDatabase);
  try
    try
      FDatabase.BeginTransaction;
      try
        AQsoId := Repository.Insert(AQso, FSource, UtcNowMs);
        FDatabase.Commit;
      except
        FDatabase.Rollback;
        raise;
      end;
      Result := True;
    except
      on E: Exception do
      begin
        AError := E.Message;
        Result := False;
      end;
    end;
  finally
    Repository.Free;
  end;
end;

function TSqliteQsoWriter.PendingCount: Integer;
begin
  EnterCriticalSection(FLock);
  try
    Result := FQueue.Count;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TSqliteQsoWriter.SetOnSaved(AHandler: TQsoSavedEvent);
begin
  FTarget.OnSaved := AHandler;
end;

procedure TSqliteQsoWriter.SetOnFailed(AHandler: TQsoSaveFailedEvent);
begin
  FTarget.OnFailed := AHandler;
end;

function TSqliteQsoWriter.Flush(const ATimeoutMs: Cardinal): Boolean;
var
  Deadline: QWord;
begin
  Deadline := GetTickCount64 + ATimeoutMs;
  repeat
    if PendingCount = 0 then
      Exit(True);
    RTLEventSetEvent(FWake);
    Sleep(5);
  until GetTickCount64 >= Deadline;
  Result := PendingCount = 0;
end;

end.
