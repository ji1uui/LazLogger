program ZLogUnitTests;

{$mode objfpc}{$H+}
{$codepage utf8}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, DateUtils, ZLog.Domain.Types, ZLog.Domain.Qso,
  ZLog.Application.LogQso, ZLog.Infrastructure.Memory,
  ZLog.Infrastructure.Deterministic, ZLog.Infrastructure.Journal,
  ZLog.Infrastructure.Runtime, ZLog.Application.Submission,
  ZLog.Infrastructure.SubmissionQueue, ZLog.Infrastructure.CompletionQueue,
  ZLog.Infrastructure.SubmissionWorker, ZLog.Presentation.QsoEntry;

var
  TestsRun: Integer = 0;

type
  TRecordingView = class(TInterfacedObject, IQsoEntryView)
  private
    FRenderCount: Integer;
    FState: TQsoEntryState;
  public
    procedure Render(const AState: TQsoEntryState);
    property RenderCount: Integer read FRenderCount;
    property State: TQsoEntryState read FState;
  end;

  TControlledSubmission = class(TInterfacedObject, IQsoSubmissionPort)
  private
    FSubmitCount: Integer;
    FDraft: TQsoDraft;
    FObserver: IQsoSubmissionObserver;
  public
    procedure Submit(const ADraft: TQsoDraft;
      const AObserver: IQsoSubmissionObserver);
    procedure Complete(const AResult: TLogQsoResult);
    property SubmitCount: Integer read FSubmitCount;
    property Draft: TQsoDraft read FDraft;
  end;

  TInlineDispatcher = class(TInterfacedObject, IQsoCompletionDispatcher)
  public
    procedure Dispatch(const AObserver: IQsoSubmissionObserver;
      const AResult: TLogQsoResult);
  end;

  TCountingCompletionNotifier = class(TInterfacedObject,
    ICompletionAvailableNotifier)
  private
    FCount: Integer;
  public
    procedure NotifyCompletionAvailable;
    property Count: Integer read FCount;
  end;

  TRecordingSubmissionObserver = class(TInterfacedObject,
    IQsoSubmissionObserver)
  private
    FCount: Integer;
  public
    procedure SubmissionCompleted(const AResult: TLogQsoResult);
    property Count: Integer read FCount;
  end;

procedure TRecordingView.Render(const AState: TQsoEntryState);
begin
  Inc(FRenderCount);
  FState := AState;
end;

procedure TControlledSubmission.Submit(const ADraft: TQsoDraft;
  const AObserver: IQsoSubmissionObserver);
begin
  Inc(FSubmitCount);
  FDraft := ADraft;
  FObserver := AObserver;
end;

procedure TControlledSubmission.Complete(const AResult: TLogQsoResult);
var
  Observer: IQsoSubmissionObserver;
begin
  Observer := FObserver;
  FObserver := nil;
  if Assigned(Observer) then
    Observer.SubmissionCompleted(AResult);
end;

procedure TInlineDispatcher.Dispatch(const AObserver: IQsoSubmissionObserver;
  const AResult: TLogQsoResult);
begin
  AObserver.SubmissionCompleted(AResult);
end;

procedure TCountingCompletionNotifier.NotifyCompletionAvailable;
begin
  Inc(FCount);
end;

procedure TRecordingSubmissionObserver.SubmissionCompleted(
  const AResult: TLogQsoResult);
begin
  Inc(FCount);
end;

procedure AssertTrue(const ACondition: Boolean; const AMessage: string);
begin
  Inc(TestsRun);
  if not ACondition then
    raise Exception.Create('Assertion failed: ' + AMessage);
end;

procedure TestCallsignNormalization;
var
  Callsign: TCallsign;
begin
  AssertTrue(TCallsign.TryCreate(' ja1zlo/p ', Callsign), 'portable callsign is valid');
  AssertTrue(Callsign.ToString = 'JA1ZLO/P', 'callsign is normalized');
  AssertTrue(not TCallsign.TryCreate('INVALID', Callsign), 'a callsign needs a digit');
  AssertTrue(not TCallsign.TryCreate('JA1//ABC', Callsign), 'double slash is invalid');
end;

procedure TestFrequencyValidation;
var
  Frequency: TFrequencyHz;
begin
  AssertTrue(TFrequencyHz.TryCreate(7000000, Frequency), '7 MHz is accepted');
  AssertTrue(Frequency.ToInt64 = 7000000, 'frequency is preserved in Hz');
  AssertTrue(not TFrequencyHz.TryCreate(0, Frequency), 'zero frequency is rejected');
end;

procedure TestIndexedRepository;
const
  Identifiers: array[0..2] of string = ('qso-z', 'qso-a', 'qso-m');
var
  Repository: IQsoRepository;
  Callsign: TCallsign;
  Frequency: TFrequencyHz;
  Qso, Stored: TQso;
  Index: Integer;
  DuplicateRejected: Boolean;
begin
  AssertTrue(TCallsign.TryCreate('JA1ZLO', Callsign), 'repository fixture callsign');
  AssertTrue(TFrequencyHz.TryCreate(7000000, Frequency), 'repository fixture frequency');
  Repository := TInMemoryQsoRepository.Create;
  for Index := Low(Identifiers) to High(Identifiers) do
  begin
    Qso := TQso.Create(Identifiers[Index], Callsign, Frequency, emCW,
      '599 001', '599 002', Index);
    try
      Repository.Add(Qso);
    finally
      Qso.Free;
    end;
  end;
  AssertTrue(Repository.Count = Length(Identifiers), 'out-of-order IDs are indexed');
  for Index := Low(Identifiers) to High(Identifiers) do
  begin
    Stored := Repository.FindById(Identifiers[Index]);
    try
      AssertTrue(Assigned(Stored), 'indexed ID can be found');
      AssertTrue(Stored.Id = Identifiers[Index], 'lookup returns requested snapshot');
    finally
      Stored.Free;
    end;
  end;

  DuplicateRejected := False;
  Qso := TQso.Create(Identifiers[0], Callsign, Frequency, emCW,
    '599 003', '599 004', 4);
  try
    try
      Repository.Add(Qso);
    except
      on E: EListError do DuplicateRejected := True;
    end;
  finally
    Qso.Free;
  end;
  AssertTrue(DuplicateRejected, 'duplicate indexed ID is rejected');
  AssertTrue(Repository.Count = Length(Identifiers), 'duplicate does not change count');
end;

procedure TestLogQso;
const
  ExpectedTime = Int64(1777777777000);
var
  Repository: IQsoRepository;
  UseCase: ILogQsoUseCase;
  Draft: TQsoDraft;
  LogResult: TLogQsoResult;
  Stored: TQso;
begin
  Repository := TInMemoryQsoRepository.Create;
  UseCase := TLogQsoUseCase.Create(Repository, TFixedClock.Create(ExpectedTime),
    TSequentialIdGenerator.Create('qso-', 42));
  Draft.Callsign := 'jr8ppg';
  Draft.FrequencyHz := 14074000;
  Draft.Mode := emRTTY;
  Draft.SentExchange := ' 599 001 ';
  Draft.ReceivedExchange := ' 599 002 ';

  LogResult := UseCase.Execute(Draft);
  AssertTrue(LogResult.Success, 'valid QSO is logged');
  AssertTrue(LogResult.QsoId = 'qso-42', 'ID generator is used');
  AssertTrue(Repository.Count = 1, 'repository contains one QSO');
  Stored := Repository.FindById(LogResult.QsoId);
  try
    AssertTrue(Assigned(Stored), 'stored QSO can be retrieved');
    AssertTrue(Stored.Callsign.ToString = 'JR8PPG', 'normalized callsign is stored');
    AssertTrue(Stored.OccurredAtUtcMs = ExpectedTime, 'injected clock is used');
    AssertTrue(Stored.SentExchange = '599 001', 'exchange is trimmed');
  finally
    Stored.Free;
  end;
end;

procedure TestInvalidDraftDoesNotPersist;
var
  Repository: IQsoRepository;
  UseCase: ILogQsoUseCase;
  Draft: TQsoDraft;
  LogResult: TLogQsoResult;
begin
  Repository := TInMemoryQsoRepository.Create;
  UseCase := TLogQsoUseCase.Create(Repository, TFixedClock.Create(0),
    TSequentialIdGenerator.Create('qso-'));
  Draft.Callsign := '???';
  Draft.FrequencyHz := 7000000;
  Draft.Mode := emCW;
  LogResult := UseCase.Execute(Draft);
  AssertTrue(not LogResult.Success, 'invalid draft is rejected');
  AssertTrue(LogResult.Error = lqeInvalidCallsign, 'validation error is specific');
  AssertTrue(Repository.Count = 0, 'invalid draft is not persisted');
end;

function TemporaryJournalName(const ASuffix: string): string;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir(False)) +
    'zlog-journal-test-' + ASuffix + '.bin';
  DeleteFile(Result);
end;

function SizeOfFile(const AFileName: string): Int64;
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    Result := Stream.Size;
  finally
    Stream.Free;
  end;
end;

procedure AppendIncompleteHeader(const AFileName: string);
var
  Stream: TFileStream;
  Bytes: array[0..2] of Byte;
begin
  Bytes[0] := $5A;
  Bytes[1] := $51;
  Bytes[2] := $53;
  Stream := TFileStream.Create(AFileName, fmOpenWrite or fmShareDenyWrite);
  try
    Stream.Position := Stream.Size;
    Stream.WriteBuffer(Bytes, SizeOf(Bytes));
  finally
    Stream.Free;
  end;
end;

procedure TestJournalRoundTripAndTailRecovery;
const
  ExpectedTime = Int64(1888888888000);
var
  FileName: string;
  Repository: IQsoRepository;
  UseCase: ILogQsoUseCase;
  Draft: TQsoDraft;
  LogResult: TLogQsoResult;
  Stored: TQso;
  CompleteSize: Int64;
begin
  FileName := TemporaryJournalName('round-trip');
  try
    Repository := TJournalQsoRepository.Create(FileName);
    UseCase := TLogQsoUseCase.Create(Repository, TFixedClock.Create(ExpectedTime),
      TSequentialIdGenerator.Create('journal-', 7));
    Draft.Callsign := 'ja1zlo/p';
    Draft.FrequencyHz := 7030000;
    Draft.Mode := emCW;
    Draft.SentExchange := '599 001';
    Draft.ReceivedExchange := '599 東京都';
    LogResult := UseCase.Execute(Draft);
    AssertTrue(LogResult.Success, 'journal accepts a valid QSO');
    UseCase := nil;
    Repository := nil;
    CompleteSize := SizeOfFile(FileName);

    AppendIncompleteHeader(FileName);
    Repository := TJournalQsoRepository.Create(FileName);
    AssertTrue(Repository.Count = 1, 'complete record survives an incomplete tail');
    AssertTrue(SizeOfFile(FileName) = CompleteSize, 'incomplete tail is truncated');
    Stored := Repository.FindById('journal-7');
    try
      AssertTrue(Assigned(Stored), 'journal record is loaded by ID');
      AssertTrue(Stored.Callsign.ToString = 'JA1ZLO/P', 'journal preserves callsign');
      AssertTrue(Stored.OccurredAtUtcMs = ExpectedTime, 'journal preserves timestamp');
      AssertTrue(Stored.ReceivedExchange = '599 東京都',
        'journal preserves a Unicode exchange as UTF-8');
    finally
      Stored.Free;
    end;
    Repository := nil;
  finally
    DeleteFile(FileName);
  end;
end;

procedure TestRuntimeAdapters;
var
  Clock: IClock;
  IdGenerator: IIdGenerator;
  FirstId: string;
  SecondId: string;
  BeforeMs: Int64;
  CurrentMs: Int64;
  AfterMs: Int64;
begin
  BeforeMs := DateTimeToUnix(Now, False) * 1000 - 1000;
  Clock := TSystemClock.Create;
  CurrentMs := Clock.UtcNowMs;
  AfterMs := DateTimeToUnix(Now, False) * 1000 + 2000;
  AssertTrue((CurrentMs >= BeforeMs) and (CurrentMs <= AfterMs),
    'system clock returns a current Unix timestamp');

  IdGenerator := TGuidIdGenerator.Create;
  FirstId := IdGenerator.NextId;
  SecondId := IdGenerator.NextId;
  AssertTrue(Length(FirstId) = 36, 'GUID identifier has canonical length');
  AssertTrue(FirstId <> SecondId, 'runtime identifiers are unique');
end;

procedure TestQsoEntryPresenter;
var
  ViewObject: TRecordingView;
  SubmissionObject: TControlledSubmission;
  View: IQsoEntryView;
  Submission: IQsoSubmissionPort;
  Presenter: IQsoEntryPresenter;
  Completion: TLogQsoResult;
begin
  ViewObject := TRecordingView.Create;
  View := ViewObject;
  SubmissionObject := TControlledSubmission.Create;
  Submission := SubmissionObject;
  Presenter := TQsoEntryPresenter.Create(View, Submission);
  try
    Presenter.Initialize;
    AssertTrue(ViewObject.State.Status = qesReady, 'presenter initializes ready');
    Presenter.UpdateDraft('ja1zlo', 7000000, emCW, '599 001', '599 002');
    Presenter.Submit;
    AssertTrue(ViewObject.State.Status = qesSubmitting, 'submit is non-blocking state');
    AssertTrue(SubmissionObject.SubmitCount = 1, 'submission is enqueued once');
    AssertTrue(SubmissionObject.Draft.Callsign = 'ja1zlo', 'draft reaches submission port');
    Presenter.Submit;
    AssertTrue(SubmissionObject.SubmitCount = 1, 'double submit is suppressed');

    Completion.Success := False;
    Completion.QsoId := '';
    Completion.Error := lqeInvalidCallsign;
    SubmissionObject.Complete(Completion);
    AssertTrue(ViewObject.State.Status = qesRejected, 'failure is rendered');
    AssertTrue(ViewObject.State.ErrorField = 'callsign', 'invalid field gets focus hint');

    Presenter.UpdateDraft('JA1ZLO', 7000000, emCW, '599 001', '599 002');
    Presenter.Submit;
    Completion.Success := True;
    Completion.QsoId := 'accepted-1';
    Completion.Error := lqeNone;
    SubmissionObject.Complete(Completion);
    AssertTrue(ViewObject.State.Status = qesAccepted, 'success is rendered');
    AssertTrue(ViewObject.State.AcceptedQsoId = 'accepted-1', 'accepted ID is rendered');
    AssertTrue(ViewObject.State.Callsign = '', 'callsign clears after durable acceptance');
    AssertTrue(ViewObject.State.SentExchange = '599 001', 'sent exchange remains for next QSO');
  finally
    Presenter := nil;
    Submission := nil;
    View := nil;
  end;
end;

procedure TestBoundedSubmissionQueue;
var
  Repository: IQsoRepository;
  UseCase: ILogQsoUseCase;
  Dispatcher: IQsoCompletionDispatcher;
  Submission: IQsoSubmissionPort;
  Pump: ISubmissionWorkPump;
  QueueObject: TQueuedQsoSubmission;
  FirstViewObject, SecondViewObject: TRecordingView;
  FirstView, SecondView: IQsoEntryView;
  FirstPresenter, SecondPresenter: IQsoEntryPresenter;
begin
  Repository := TInMemoryQsoRepository.Create;
  UseCase := TLogQsoUseCase.Create(Repository, TFixedClock.Create(1),
    TSequentialIdGenerator.Create('queued-'));
  Dispatcher := TInlineDispatcher.Create;
  QueueObject := TQueuedQsoSubmission.Create(UseCase, Dispatcher, 1);
  Submission := QueueObject;
  Pump := QueueObject;
  FirstViewObject := TRecordingView.Create;
  FirstView := FirstViewObject;
  SecondViewObject := TRecordingView.Create;
  SecondView := SecondViewObject;
  FirstPresenter := TQsoEntryPresenter.Create(FirstView, Submission);
  SecondPresenter := TQsoEntryPresenter.Create(SecondView, Submission);

  FirstPresenter.UpdateDraft('JA1ZLO', 7000000, emCW, '599 001', '599 002');
  FirstPresenter.Submit;
  AssertTrue(Pump.PendingCount = 1, 'submission is queued');
  AssertTrue(Repository.Count = 0, 'submit performs no repository I/O');

  SecondPresenter.UpdateDraft('JR8PPG', 14074000, emRTTY, '599 003', '599 004');
  SecondPresenter.Submit;
  AssertTrue(SecondViewObject.State.Status = qesRejected, 'full queue rejects work');
  AssertTrue(SecondViewObject.State.ErrorCode = lqeQueueFull, 'queue pressure is explicit');
  AssertTrue(Pump.PendingCount = 1, 'rejected work does not grow queue');

  AssertTrue(Pump.ProcessNext, 'worker processes queued submission');
  AssertTrue(Repository.Count = 1, 'worker performs durable use case');
  AssertTrue(FirstViewObject.State.Status = qesAccepted, 'completion reaches presenter');
  AssertTrue(Pump.PendingCount = 0, 'processed work leaves queue');
  AssertTrue(not Pump.ProcessNext, 'empty queue reports no work');

  FirstPresenter.UpdateDraft('JA1ZLO', 21000000, emSSB, '59 001', '59 002');
  FirstPresenter.Submit;
  Pump.CancelPending;
  AssertTrue(Pump.PendingCount = 0, 'cancel drains pending work');
  AssertTrue(Repository.Count = 1, 'cancelled work is not persisted');
  AssertTrue(FirstViewObject.State.Status = qesRejected, 'cancel reaches presenter');
  AssertTrue(FirstViewObject.State.ErrorCode = lqeCancelled, 'cancel is explicit');

  FirstPresenter := nil;
  SecondPresenter := nil;
  FirstView := nil;
  SecondView := nil;
  Pump := nil;
  Submission := nil;
  Dispatcher := nil;
  UseCase := nil;
  Repository := nil;
end;

procedure TestSubmissionWorkerAndMainThreadCompletion;
const
  CompletionTimeoutMs = 2000;
var
  Repository: IQsoRepository;
  UseCase: ILogQsoUseCase;
  Dispatcher: IQsoCompletionDispatcher;
  CompletionPump: ICompletionPump;
  QueueSubmission: IQsoSubmissionPort;
  WorkPump: ISubmissionWorkPump;
  ManagedSubmission: IManagedQsoSubmissionPort;
  Submission: IQsoSubmissionPort;
  View: IQsoEntryView;
  Presenter: IQsoEntryPresenter;
  QueueObject: TQueuedQsoSubmission;
  DispatcherObject: TQueuedCompletionDispatcher;
  ViewObject: TRecordingView;
  Deadline: QWord;
begin
  Repository := TInMemoryQsoRepository.Create;
  UseCase := TLogQsoUseCase.Create(Repository, TFixedClock.Create(2),
    TSequentialIdGenerator.Create('worker-'));
  DispatcherObject := TQueuedCompletionDispatcher.Create;
  Dispatcher := DispatcherObject;
  CompletionPump := DispatcherObject;
  QueueObject := TQueuedQsoSubmission.Create(UseCase, Dispatcher, 4);
  QueueSubmission := QueueObject;
  WorkPump := QueueObject;
  ManagedSubmission := TSubmissionWorkerService.Create(QueueSubmission, WorkPump);
  Submission := ManagedSubmission;
  ViewObject := TRecordingView.Create;
  View := ViewObject;
  Presenter := TQsoEntryPresenter.Create(View, Submission);

  Presenter.UpdateDraft('JA1ZLO', 7000000, emCW, '599 001', '599 002');
  Presenter.Submit;
  AssertTrue(ViewObject.State.Status = qesSubmitting,
    'worker submission returns before completion is rendered');
  Deadline := GetTickCount64 + CompletionTimeoutMs;
  while (CompletionPump.PendingCount = 0) and (GetTickCount64 < Deadline) do
    Sleep(1);
  AssertTrue(CompletionPump.PendingCount = 1, 'worker produces one completion');
  AssertTrue(ViewObject.State.Status = qesSubmitting,
    'worker never renders view from its thread');
  AssertTrue(CompletionPump.Drain(16) = 1, 'main thread drains completion');
  AssertTrue(ViewObject.State.Status = qesAccepted,
    'main-thread completion accepts QSO');
  AssertTrue(Repository.Count = 1, 'worker persists one QSO');

  ManagedSubmission.Shutdown;
  Presenter := nil;
  View := nil;
  Submission := nil;
  ManagedSubmission := nil;
  WorkPump := nil;
  QueueSubmission := nil;
  CompletionPump := nil;
  Dispatcher := nil;
  UseCase := nil;
  Repository := nil;
end;

procedure TestCompletionNotificationCoalescing;
var
  NotifierObject: TCountingCompletionNotifier;
  ObserverObject: TRecordingSubmissionObserver;
  Notifier: ICompletionAvailableNotifier;
  Observer: IQsoSubmissionObserver;
  Dispatcher: IQsoCompletionDispatcher;
  Pump: ICompletionPump;
  DispatcherObject: TQueuedCompletionDispatcher;
  Completion: TLogQsoResult;
begin
  NotifierObject := TCountingCompletionNotifier.Create;
  Notifier := NotifierObject;
  ObserverObject := TRecordingSubmissionObserver.Create;
  Observer := ObserverObject;
  DispatcherObject := TQueuedCompletionDispatcher.Create(Notifier);
  Dispatcher := DispatcherObject;
  Pump := DispatcherObject;
  Completion.Success := True;
  Completion.QsoId := 'notification-test';
  Completion.Error := lqeNone;

  Dispatcher.Dispatch(Observer, Completion);
  Dispatcher.Dispatch(Observer, Completion);
  AssertTrue(NotifierObject.Count = 1, 'empty-to-nonempty transition notifies once');
  AssertTrue(Pump.Drain(1) = 1, 'bounded drain handles one completion');
  Dispatcher.Dispatch(Observer, Completion);
  AssertTrue(NotifierObject.Count = 1, 'nonempty queue does not notify again');
  AssertTrue(Pump.Drain(16) = 2, 'remaining completions are drained');
  Dispatcher.Dispatch(Observer, Completion);
  AssertTrue(NotifierObject.Count = 2, 'next empty transition notifies again');
  AssertTrue(Pump.Drain(16) = 1, 'final completion is delivered');
  AssertTrue(ObserverObject.Count = 4, 'every completion is delivered exactly once');

  Pump := nil;
  Dispatcher := nil;
  Observer := nil;
  Notifier := nil;
end;

begin
  try
    TestCallsignNormalization;
    TestFrequencyValidation;
    TestIndexedRepository;
    TestLogQso;
    TestInvalidDraftDoesNotPersist;
    TestJournalRoundTripAndTailRecovery;
    TestRuntimeAdapters;
    TestQsoEntryPresenter;
    TestBoundedSubmissionQueue;
    TestSubmissionWorkerAndMainThreadCompletion;
    TestCompletionNotificationCoalescing;
    WriteLn('PASS: ', TestsRun, ' assertions');
  except
    on E: Exception do
    begin
      WriteLn(StdErr, E.Message);
      Halt(1);
    end;
  end;
end.
