program ZLogUnitTests;

{$mode objfpc}{$H+}
{$codepage utf8}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, DateUtils, Math, ZLog.Domain.Types, ZLog.Domain.Qso,
  ZLog.Application.Ports, ZLog.Application.LogQso, ZLog.Application.QueryQsos,
  ZLog.Application.Diagnostics,
  ZLog.Application.Rig,
  ZLog.Application.Audio,
  ZLog.Application.Rtty,
  ZLog.Infrastructure.Memory,
  ZLog.Infrastructure.Deterministic, ZLog.Infrastructure.Journal,
  ZLog.Infrastructure.Runtime, ZLog.Application.Submission,
  ZLog.Infrastructure.SubmissionQueue, ZLog.Infrastructure.CompletionQueue,
  ZLog.Infrastructure.SubmissionWorker, ZLog.Infrastructure.Health,
  ZLog.Infrastructure.Rigctld,
  ZLog.Infrastructure.RigctldProcess,
  ZLog.Infrastructure.RigWorker,
  ZLog.Infrastructure.AudioRing,
  ZLog.Infrastructure.RttyReference,
  ZLog.Presentation.QsoEntry,
  ZLog.Presentation.RecentQsos;

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
    function TryDispatch(const AObserver: IQsoSubmissionObserver;
      const AResult: TLogQsoResult): Boolean;
    function HasCapacity: Boolean;
  end;

  TCapacityRaceDispatcher = class(TInterfacedObject,
    IQsoCompletionDispatcher)
  private
    FDispatchCount: Integer;
  public
    function TryDispatch(const AObserver: IQsoSubmissionObserver;
      const AResult: TLogQsoResult): Boolean;
    function HasCapacity: Boolean;
    property DispatchCount: Integer read FDispatchCount;
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
    FResult: TLogQsoResult;
  public
    procedure SubmissionCompleted(const AResult: TLogQsoResult);
    property Count: Integer read FCount;
    property LastResult: TLogQsoResult read FResult;
  end;

  TFailingLogQsoUseCase = class(TInterfacedObject, ILogQsoUseCase)
  public
    function Execute(const ADraft: TQsoDraft): TLogQsoResult;
  end;

  TTransientFailingSubmissionPump = class(TInterfacedObject,
    ISubmissionWorkPump)
  private
    FCallCount: LongInt;
  public
    function ProcessNext: Boolean;
    procedure CancelPending;
    function PendingCount: Integer;
    function CallCount: LongInt;
  end;

  TFakeRigctldTransport = class(TInterfacedObject, IRigctldTransport)
  private
    FCallCount: Integer;
    FLastCommand: string;
    FLastTimeoutMs: Integer;
    FNextResult: TRigctldTransportResult;
    FNextResponse: string;
  public
    function Execute(const ACommand: string; const ATimeoutMs: Integer;
      out AResponse: string): TRigctldTransportResult;
    procedure Configure(const AResult: TRigctldTransportResult;
      const AResponse: string);
    property CallCount: Integer read FCallCount;
    property LastCommand: string read FLastCommand;
    property LastTimeoutMs: Integer read FLastTimeoutMs;
  end;

  TFakeRigctldProcessSession = class(TInterfacedObject,
    IRigctldProcessSession)
  private
    FRunning: Boolean;
    FStartAllowed: Boolean;
    FStartCount: Integer;
    FStopCount: Integer;
    FExchangeCount: Integer;
    FNextResult: TRigctldTransportResult;
  public
    constructor Create;
    function Start: Boolean;
    procedure Stop;
    function IsRunning: Boolean;
    function Exchange(const ACommand: string; const ATimeoutMs: Integer;
      out AResponse: string): TRigctldTransportResult;
    property StartAllowed: Boolean read FStartAllowed write FStartAllowed;
    property NextResult: TRigctldTransportResult read FNextResult
      write FNextResult;
    property StartCount: Integer read FStartCount;
    property StopCount: Integer read FStopCount;
    property ExchangeCount: Integer read FExchangeCount;
  end;

  TRecordingRecentQsosView = class(TInterfacedObject, IRecentQsosView)
  private
    FRenderCount: Integer;
    FState: TRecentQsosState;
  public
    procedure RenderRecentQsos(const AState: TRecentQsosState);
    property RenderCount: Integer read FRenderCount;
    property State: TRecentQsosState read FState;
  end;

  TStageFaultInjector = class(TInterfacedObject, IJournalFaultInjector)
  private
    FFailureStage: TJournalAppendStage;
  public
    constructor Create(const AFailureStage: TJournalAppendStage);
    procedure BeforeStage(const AStage: TJournalAppendStage);
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

function TInlineDispatcher.TryDispatch(const AObserver: IQsoSubmissionObserver;
  const AResult: TLogQsoResult): Boolean;
begin
  AObserver.SubmissionCompleted(AResult);
  Result := True;
end;

function TInlineDispatcher.HasCapacity: Boolean;
begin
  Result := True;
end;

function TCapacityRaceDispatcher.TryDispatch(
  const AObserver: IQsoSubmissionObserver;
  const AResult: TLogQsoResult): Boolean;
begin
  Inc(FDispatchCount);
  Result := FDispatchCount > 1;
  if Result then
    AObserver.SubmissionCompleted(AResult);
end;

function TCapacityRaceDispatcher.HasCapacity: Boolean;
begin
  Result := True;
end;

procedure TCountingCompletionNotifier.NotifyCompletionAvailable;
begin
  Inc(FCount);
end;

function TFailingLogQsoUseCase.Execute(
  const ADraft: TQsoDraft): TLogQsoResult;
begin
  raise EWriteError.Create('simulated storage detail');
end;

function TTransientFailingSubmissionPump.ProcessNext: Boolean;
begin
  if InterlockedIncrement(FCallCount) = 1 then
    raise EInvalidOperation.Create('simulated worker pump failure');
  Result := False;
end;

procedure TTransientFailingSubmissionPump.CancelPending;
begin
end;

function TTransientFailingSubmissionPump.PendingCount: Integer;
begin
  Result := 0;
end;

function TTransientFailingSubmissionPump.CallCount: LongInt;
begin
  Result := InterlockedCompareExchange(FCallCount, 0, 0);
end;

function TFakeRigctldTransport.Execute(const ACommand: string;
  const ATimeoutMs: Integer; out AResponse: string): TRigctldTransportResult;
begin
  Inc(FCallCount);
  FLastCommand := ACommand;
  FLastTimeoutMs := ATimeoutMs;
  AResponse := FNextResponse;
  Result := FNextResult;
end;

procedure TFakeRigctldTransport.Configure(
  const AResult: TRigctldTransportResult; const AResponse: string);
begin
  FNextResult := AResult;
  FNextResponse := AResponse;
end;

constructor TFakeRigctldProcessSession.Create;
begin
  inherited Create;
  FStartAllowed := True;
  FNextResult := rtrSuccess;
end;

function TFakeRigctldProcessSession.Start: Boolean;
begin
  Inc(FStartCount);
  Result := FStartAllowed;
  FRunning := Result;
end;

procedure TFakeRigctldProcessSession.Stop;
begin
  Inc(FStopCount);
  FRunning := False;
end;

function TFakeRigctldProcessSession.IsRunning: Boolean;
begin
  Result := FRunning;
end;

function TFakeRigctldProcessSession.Exchange(const ACommand: string;
  const ATimeoutMs: Integer; out AResponse: string): TRigctldTransportResult;
begin
  Inc(FExchangeCount);
  AResponse := 'RPRT 0';
  Result := FNextResult;
end;

procedure TRecordingSubmissionObserver.SubmissionCompleted(
  const AResult: TLogQsoResult);
begin
  Inc(FCount);
  FResult := AResult;
end;

procedure TRecordingRecentQsosView.RenderRecentQsos(
  const AState: TRecentQsosState);
begin
  Inc(FRenderCount);
  FState := AState;
end;

constructor TStageFaultInjector.Create(const AFailureStage: TJournalAppendStage);
begin
  inherited Create;
  FFailureStage := AFailureStage;
end;

procedure TStageFaultInjector.BeforeStage(const AStage: TJournalAppendStage);
begin
  if AStage = FFailureStage then
    raise EJournalError.CreateFmt('Injected journal failure at stage %d',
      [Ord(AStage)]);
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
  Recent: TQsoSnapshotArray;
  InvalidLimitRejected: Boolean;
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
  Recent := Repository.GetRecent(2);
  AssertTrue(Length(Recent) = 2, 'recent query honors its limit');
  AssertTrue(Recent[0].Id = 'qso-m', 'recent query returns newest first');
  AssertTrue(Recent[1].Id = 'qso-a', 'recent query preserves insertion order');
  Recent := Repository.GetRecent(0);
  AssertTrue(Length(Recent) = 0, 'zero recent limit returns an empty page');
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
  InvalidLimitRejected := False;
  try
    Recent := Repository.GetRecent(-1);
  except
    on E: EArgumentOutOfRangeException do InvalidLimitRejected := True;
  end;
  AssertTrue(InvalidLimitRejected, 'negative recent limit is rejected');
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

procedure TestRecentQsoQueryUseCase;
var
  Repository: IQsoRepository;
  LogUseCase: ILogQsoUseCase;
  QueryUseCase: IGetRecentQsosUseCase;
  Draft: TQsoDraft;
  LogResult: TLogQsoResult;
  QueryResult: TRecentQsoQueryResult;
begin
  Repository := TInMemoryQsoRepository.Create;
  LogUseCase := TLogQsoUseCase.Create(Repository, TFixedClock.Create(3),
    TSequentialIdGenerator.Create('query-'));
  Draft.Callsign := 'JA1ZLO';
  Draft.FrequencyHz := 7000000;
  Draft.Mode := emCW;
  Draft.SentExchange := '599 001';
  Draft.ReceivedExchange := '599 002';
  LogResult := LogUseCase.Execute(Draft);
  AssertTrue(LogResult.Success, 'query fixture QSO is logged');
  Draft.Callsign := 'JR8PPG';
  LogResult := LogUseCase.Execute(Draft);
  AssertTrue(LogResult.Success, 'second query fixture is logged');

  QueryUseCase := TGetRecentQsosUseCase.Create(Repository);
  QueryResult := QueryUseCase.Execute(1);
  AssertTrue(QueryResult.Success, 'recent QSO query succeeds');
  AssertTrue(Length(QueryResult.Items) = 1, 'query limit is applied');
  AssertTrue(QueryResult.Items[0].Callsign = 'JR8PPG', 'newest QSO is returned');
  QueryResult := QueryUseCase.Execute(501);
  AssertTrue(not QueryResult.Success, 'oversized query is rejected');
  AssertTrue(QueryResult.Error = rqeInvalidLimit, 'query validation is typed');
end;

procedure TestRecentQsosPresenter;
var
  Repository: IQsoRepository;
  LogUseCase: ILogQsoUseCase;
  QueryUseCase: IGetRecentQsosUseCase;
  ViewObject: TRecordingRecentQsosView;
  View: IRecentQsosView;
  Presenter: IRecentQsosPresenter;
  Draft: TQsoDraft;
begin
  Repository := TInMemoryQsoRepository.Create;
  LogUseCase := TLogQsoUseCase.Create(Repository,
    TFixedClock.Create(1777777777000), TSequentialIdGenerator.Create('recent-'));
  Draft.Callsign := 'JA1ZLO';
  Draft.FrequencyHz := 7030000;
  Draft.Mode := emCW;
  Draft.SentExchange := '599 001';
  Draft.ReceivedExchange := '599 002';
  AssertTrue(LogUseCase.Execute(Draft).Success, 'recent presenter fixture is logged');

  ViewObject := TRecordingRecentQsosView.Create;
  View := ViewObject;
  QueryUseCase := TGetRecentQsosUseCase.Create(Repository);
  Presenter := TRecentQsosPresenter.Create(View, QueryUseCase, 50);
  Presenter.Initialize;
  AssertTrue(ViewObject.RenderCount = 2,
    'recent presenter renders loading and loaded states');
  AssertTrue(ViewObject.State.Status = rqsLoaded, 'recent presenter reports loaded');
  AssertTrue(Length(ViewObject.State.Rows) = 1, 'recent presenter supplies one row');
  AssertTrue(ViewObject.State.Rows[0].Callsign = 'JA1ZLO',
    'recent row preserves normalized callsign');
  AssertTrue(ViewObject.State.Rows[0].Mode = 'CW', 'recent row formats mode');
  AssertTrue(ViewObject.State.Rows[0].Frequency = '7.030',
    'recent row formats frequency in MHz');
  AssertTrue(ViewObject.State.Rows[0].TimeUtc = '2026-05-03 03:09:37Z',
    'recent row formats a deterministic UTC timestamp');

  Presenter := nil;
  QueryUseCase := nil;
  View := nil;
  LogUseCase := nil;
  Repository := nil;
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

procedure CopyFilePrefix(const ASourceFileName, ADestinationFileName: string;
  const ALength: Int64);
var
  Source: TFileStream;
  Destination: TFileStream;
begin
  Source := TFileStream.Create(ASourceFileName, fmOpenRead or fmShareDenyNone);
  try
    if (ALength < 0) or (ALength > Source.Size) then
      raise EArgumentOutOfRangeException.Create('Invalid file prefix length');
    Destination := TFileStream.Create(ADestinationFileName, fmCreate);
    try
      { TStream.CopyFrom(..., 0) copies the entire source, not an empty prefix. }
      if ALength > 0 then
        Destination.CopyFrom(Source, ALength);
    finally
      Destination.Free;
    end;
  finally
    Source.Free;
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

procedure TestJournalRejectsOversizedRecordWithoutDamage;
var
  FileName: string;
  Repository: IQsoRepository;
  Callsign: TCallsign;
  Frequency: TFrequencyHz;
  Qso: TQso;
  Rejected: Boolean;
begin
  FileName := TemporaryJournalName('oversized-record');
  try
    Repository := TJournalQsoRepository.Create(FileName);
    AssertTrue(TCallsign.TryCreate('JA1ZLO', Callsign),
      'oversized fixture callsign is valid');
    AssertTrue(TFrequencyHz.TryCreate(7000000, Frequency),
      'oversized fixture frequency is valid');
    Qso := TQso.Create('oversized-1', Callsign, Frequency, emRTTY,
      UnicodeString(StringOfChar('A', 1024 * 1024)), '599 001', 1);
    try
      Rejected := False;
      try
        Repository.Add(Qso);
      except
        on E: EJournalError do Rejected := True;
      end;
      AssertTrue(Rejected, 'oversized journal record is rejected');
      AssertTrue(Repository.Count = 0,
        'rejected oversized record is not visible in memory');
      AssertTrue(SizeOfFile(FileName) = 0,
        'rejected oversized record writes no journal bytes');
    finally
      Qso.Free;
    end;
    Repository := nil;
    Repository := TJournalQsoRepository.Create(FileName);
    AssertTrue(Repository.Count = 0,
      'journal remains reopenable after oversized rejection');
    Repository := nil;
  finally
    DeleteFile(FileName);
  end;
end;

procedure TestJournalAppendFaultInjection;
var
  FileName: string;
  Repository: IQsoRepository;
  Injector: IJournalFaultInjector;
  Callsign: TCallsign;
  Frequency: TFrequencyHz;
  Qso: TQso;
  Stage: TJournalAppendStage;
  Rejected: Boolean;
begin
  AssertTrue(TCallsign.TryCreate('JA1ZLO', Callsign),
    'fault injection fixture callsign is valid');
  AssertTrue(TFrequencyHz.TryCreate(7000000, Frequency),
    'fault injection fixture frequency is valid');
  Qso := TQso.Create('fault-1', Callsign, Frequency, emCW,
    '599 001', '599 002', 1);
  try
    for Stage := Low(TJournalAppendStage) to High(TJournalAppendStage) do
    begin
      FileName := TemporaryJournalName('fault-' + IntToStr(Ord(Stage)));
      try
        Injector := TStageFaultInjector.Create(Stage);
        Repository := TJournalQsoRepository.Create(FileName, Injector);
        Rejected := False;
        try
          Repository.Add(Qso);
        except
          on E: EJournalError do Rejected := True;
        end;
        AssertTrue(Rejected, 'injected append failure is reported');
        AssertTrue(Repository.Count = 0,
          'failed append is not acknowledged in memory');
        AssertTrue(SizeOfFile(FileName) = 0,
          'failed append rolls the journal back to its original size');
        Repository := nil;
        Injector := nil;
        Repository := TJournalQsoRepository.Create(FileName);
        AssertTrue(Repository.Count = 0,
          'journal reopens after an injected append failure');
        Repository := nil;
      finally
        Repository := nil;
        Injector := nil;
        DeleteFile(FileName);
      end;
    end;
  finally
    Qso.Free;
  end;
end;

procedure TestJournalRecoveryAtEveryTailPosition;
var
  BaselineFileName: string;
  TruncatedFileName: string;
  Repository: IQsoRepository;
  UseCase: ILogQsoUseCase;
  Draft: TQsoDraft;
  FirstRecordSize: Int64;
  CompleteSize: Int64;
  CutPosition: Int64;
  ExpectedCount: Integer;
  ExpectedSize: Int64;
begin
  BaselineFileName := TemporaryJournalName('all-tail-source');
  TruncatedFileName := TemporaryJournalName('all-tail-cut');
  try
    Repository := TJournalQsoRepository.Create(BaselineFileName);
    UseCase := TLogQsoUseCase.Create(Repository, TFixedClock.Create(10),
      TSequentialIdGenerator.Create('tail-'));
    Draft.Callsign := 'JA1ZLO';
    Draft.FrequencyHz := 7000000;
    Draft.Mode := emCW;
    Draft.SentExchange := '599 001';
    Draft.ReceivedExchange := '599 002';
    AssertTrue(UseCase.Execute(Draft).Success, 'first tail fixture is logged');
    FirstRecordSize := SizeOfFile(BaselineFileName);
    Draft.Callsign := 'JR8PPG';
    AssertTrue(UseCase.Execute(Draft).Success, 'second tail fixture is logged');
    Repository := nil;
    UseCase := nil;
    CompleteSize := SizeOfFile(BaselineFileName);

    for CutPosition := 0 to CompleteSize - 1 do
    begin
      CopyFilePrefix(BaselineFileName, TruncatedFileName, CutPosition);
      AssertTrue(SizeOfFile(TruncatedFileName) = CutPosition,
        'tail fixture contains exactly the requested prefix');
      Repository := TJournalQsoRepository.Create(TruncatedFileName);
      if CutPosition >= FirstRecordSize then
      begin
        ExpectedCount := 1;
        ExpectedSize := FirstRecordSize;
      end
      else
      begin
        ExpectedCount := 0;
        ExpectedSize := 0;
      end;
      AssertTrue(Repository.Count = ExpectedCount,
        'tail recovery preserves only complete records');
      Repository := nil;
      AssertTrue(SizeOfFile(TruncatedFileName) = ExpectedSize,
        'tail recovery truncates to the last complete boundary');
    end;
  finally
    Repository := nil;
    UseCase := nil;
    DeleteFile(BaselineFileName);
    DeleteFile(TruncatedFileName);
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
    Completion.Retryable := False;
    SubmissionObject.Complete(Completion);
    AssertTrue(ViewObject.State.Status = qesRejected, 'failure is rendered');
    AssertTrue(ViewObject.State.ErrorField = 'callsign', 'invalid field gets focus hint');

    Presenter.UpdateDraft('JA1ZLO', 7000000, emCW, '599 001', '599 002');
    Presenter.Submit;
    Completion.Success := True;
    Completion.QsoId := 'accepted-1';
    Completion.Error := lqeNone;
    Completion.Retryable := False;
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
  AssertTrue(SecondViewObject.State.Retryable, 'queue pressure is retryable');
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

procedure TestCompletionCapacityRaceDoesNotDuplicateQso;
var
  Repository: IQsoRepository;
  UseCase: ILogQsoUseCase;
  Dispatcher: IQsoCompletionDispatcher;
  DispatcherObject: TCapacityRaceDispatcher;
  Submission: IQsoSubmissionPort;
  Pump: ISubmissionWorkPump;
  QueueObject: TQueuedQsoSubmission;
  Observer: IQsoSubmissionObserver;
  ObserverObject: TRecordingSubmissionObserver;
  RejectedObserver: IQsoSubmissionObserver;
  RejectedObserverObject: TRecordingSubmissionObserver;
  Draft: TQsoDraft;
begin
  Repository := TInMemoryQsoRepository.Create;
  UseCase := TLogQsoUseCase.Create(Repository, TFixedClock.Create(1),
    TSequentialIdGenerator.Create('race-'));
  DispatcherObject := TCapacityRaceDispatcher.Create;
  Dispatcher := DispatcherObject;
  QueueObject := TQueuedQsoSubmission.Create(UseCase, Dispatcher, 1);
  Submission := QueueObject;
  Pump := QueueObject;
  ObserverObject := TRecordingSubmissionObserver.Create;
  Observer := ObserverObject;
  Draft.Callsign := 'JA1ZLO';
  Draft.FrequencyHz := 7000000;
  Draft.Mode := emCW;
  Draft.SentExchange := '599 001';
  Draft.ReceivedExchange := '599 002';

  Submission.Submit(Draft, Observer);
  AssertTrue(Pump.ProcessNext,
    'capacity race retains a completion after persistence');
  AssertTrue(Repository.Count = 1,
    'capacity race persists the QSO exactly once');
  AssertTrue(Pump.PendingCount = 1,
    'undelivered completion remains visible as pending work');
  AssertTrue(ObserverObject.Count = 0,
    'observer is not called until dispatch succeeds');
  RejectedObserverObject := TRecordingSubmissionObserver.Create;
  RejectedObserver := RejectedObserverObject;
  Submission.Submit(Draft, RejectedObserver);
  AssertTrue(RejectedObserverObject.Count = 1,
    'retained completion continues to consume bounded capacity');
  AssertTrue(RejectedObserverObject.LastResult.Error = lqeQueueFull,
    'capacity reservation rejects new work explicitly');

  AssertTrue(Pump.ProcessNext, 'retained completion is retried');
  AssertTrue(Repository.Count = 1,
    'completion retry never repeats the durable use case');
  AssertTrue(Pump.PendingCount = 0,
    'successful retry removes retained completion');
  AssertTrue(ObserverObject.Count = 1,
    'observer receives exactly one completion');
  AssertTrue(ObserverObject.LastResult.Success,
    'retained successful result is preserved');
  AssertTrue(DispatcherObject.DispatchCount = 2,
    'dispatcher observes the failed and successful attempts');

  Observer := nil;
  RejectedObserver := nil;
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

procedure TestSubmissionWorkerSurvivesUnexpectedPumpFailure;
const
  WorkerTimeoutMs = 3000;
var
  SubmissionObject: TControlledSubmission;
  Submission: IQsoSubmissionPort;
  PumpObject: TTransientFailingSubmissionPump;
  Pump: ISubmissionWorkPump;
  Managed: IManagedQsoSubmissionPort;
  Observer: IQsoSubmissionObserver;
  MonitorObject: TInMemoryHealthMonitor;
  Diagnostics: IDiagnosticSink;
  HealthQuery: IHealthQuery;
  Deadline: QWord;
  Draft: TQsoDraft;
begin
  SubmissionObject := TControlledSubmission.Create;
  Submission := SubmissionObject;
  PumpObject := TTransientFailingSubmissionPump.Create;
  Pump := PumpObject;
  MonitorObject := TInMemoryHealthMonitor.Create;
  Diagnostics := MonitorObject;
  HealthQuery := MonitorObject;
  Managed := TSubmissionWorkerService.Create(Submission, Pump, Diagnostics);

  Deadline := GetTickCount64 + WorkerTimeoutMs;
  while (HealthQuery.Snapshot.LastCode <> dcSubmissionWorkerFailed) and
    (GetTickCount64 < Deadline) do
    Sleep(1);
  AssertTrue(PumpObject.CallCount >= 1,
    'submission worker invokes its pump');
  AssertTrue(HealthQuery.Snapshot.LastCode = dcSubmissionWorkerFailed,
    'unexpected pump failure is observable through diagnostics');

  Observer := TRecordingSubmissionObserver.Create;
  Managed.Submit(Draft, Observer);
  Deadline := GetTickCount64 + WorkerTimeoutMs;
  while (PumpObject.CallCount < 2) and (GetTickCount64 < Deadline) do
    Sleep(1);
  AssertTrue(PumpObject.CallCount >= 2,
    'submission worker remains alive after an unexpected exception');

  Managed.Shutdown;
  Managed := nil;
  Observer := nil;
  HealthQuery := nil;
  Diagnostics := nil;
  Pump := nil;
  Submission := nil;
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
  DispatcherObject := TQueuedCompletionDispatcher.Create(Notifier, 2);
  Dispatcher := DispatcherObject;
  Pump := DispatcherObject;
  Completion.Success := True;
  Completion.QsoId := 'notification-test';
  Completion.Error := lqeNone;
  Completion.Retryable := False;

  AssertTrue(Dispatcher.TryDispatch(Observer, Completion), 'first completion fits');
  AssertTrue(Dispatcher.TryDispatch(Observer, Completion), 'second completion fits');
  AssertTrue(NotifierObject.Count = 1, 'empty-to-nonempty transition notifies once');
  AssertTrue(not Dispatcher.HasCapacity, 'completion capacity is observable');
  AssertTrue(not Dispatcher.TryDispatch(Observer, Completion),
    'full completion queue applies backpressure');
  AssertTrue(Pump.Capacity = 2, 'configured completion capacity is reported');
  AssertTrue(Pump.HighWaterMark = 2, 'completion high-water mark is recorded');
  AssertTrue(Pump.Drain(1) = 1, 'bounded drain handles one completion');
  AssertTrue(Dispatcher.TryDispatch(Observer, Completion), 'third completion fits');
  AssertTrue(NotifierObject.Count = 1, 'nonempty queue does not notify again');
  AssertTrue(Pump.Drain(16) = 2, 'remaining completions are drained');
  AssertTrue(Dispatcher.TryDispatch(Observer, Completion), 'fourth completion fits');
  AssertTrue(NotifierObject.Count = 2, 'next empty transition notifies again');
  AssertTrue(Pump.Drain(16) = 1, 'final completion is delivered');
  AssertTrue(ObserverObject.Count = 4, 'every completion is delivered exactly once');

  Pump := nil;
  Dispatcher := nil;
  Observer := nil;
  Notifier := nil;
end;

procedure TestStructuredDiagnosticsAndHealth;
var
  MonitorObject: TInMemoryHealthMonitor;
  Diagnostics: IDiagnosticSink;
  HealthQuery: IHealthQuery;
  Health: THealthSnapshot;
  UseCase: ILogQsoUseCase;
  Dispatcher: IQsoCompletionDispatcher;
  Submission: IQsoSubmissionPort;
  Pump: ISubmissionWorkPump;
  QueueObject: TQueuedQsoSubmission;
  ObserverObject: TRecordingSubmissionObserver;
  Observer: IQsoSubmissionObserver;
  Draft: TQsoDraft;
begin
  MonitorObject := TInMemoryHealthMonitor.Create;
  Diagnostics := MonitorObject;
  HealthQuery := MonitorObject;
  Health := HealthQuery.Snapshot;
  AssertTrue(Health.Status = hsHealthy, 'health starts healthy');

  UseCase := TFailingLogQsoUseCase.Create;
  Dispatcher := TInlineDispatcher.Create;
  QueueObject := TQueuedQsoSubmission.Create(UseCase, Dispatcher, 2,
    Diagnostics);
  Submission := QueueObject;
  Pump := QueueObject;
  ObserverObject := TRecordingSubmissionObserver.Create;
  Observer := ObserverObject;
  Draft.Callsign := 'JA1ZLO';
  Submission.Submit(Draft, Observer);
  AssertTrue(Pump.ProcessNext, 'failing persistence work is processed');
  AssertTrue(ObserverObject.Count = 1, 'failure completes exactly once');
  AssertTrue(ObserverObject.LastResult.Error = lqePersistenceUnavailable,
    'storage exception is mapped to a user-facing category');
  AssertTrue(ObserverObject.LastResult.Retryable,
    'persistence unavailability is explicitly retryable');
  Health := HealthQuery.Snapshot;
  AssertTrue(Health.Status = hsDegraded, 'storage failure degrades health');
  AssertTrue(Health.ErrorCount = 1, 'health counts the storage error');
  AssertTrue(Health.LastCode = dcQsoPersistenceFailed,
    'health exposes a structured diagnostic code');
  AssertTrue(Health.LastComponent = 'qso-persistence',
    'health identifies the failing component');
  AssertTrue(Health.LastMessage = 'EWriteError',
    'diagnostics retain the exception class without sensitive details');

  Diagnostics.ReportHealthy('qso-persistence');
  Health := HealthQuery.Snapshot;
  AssertTrue(Health.Status = hsHealthy, 'successful recovery restores health');
  AssertTrue(Health.ErrorCount = 1, 'recovery preserves cumulative counters');

  Diagnostics.Report(dcRigTransportFailed, dsCritical, 'hamlib-rigctld',
    'offline');
  Diagnostics.Report(dcQsoPersistenceFailed, dsError, 'qso-persistence',
    'disk');
  Diagnostics.ReportHealthy('qso-persistence');
  Health := HealthQuery.Snapshot;
  AssertTrue(Health.Status = hsFailed,
    'recovering one component does not hide another failure');
  AssertTrue(Health.LastComponent = 'hamlib-rigctld',
    'health retains the remaining failed component');

  Pump := nil;
  Submission := nil;
  Dispatcher := nil;
  UseCase := nil;
  Observer := nil;
  Diagnostics := nil;
  HealthQuery := nil;
end;

procedure TestRigctldProcessLifecycle;
var
  SessionObject: TFakeRigctldProcessSession;
  Session: IRigctldProcessSession;
  Transport: IRigctldTransport;
  Response: string;
begin
  SessionObject := TFakeRigctldProcessSession.Create;
  Session := SessionObject;
  Transport := TRigctldProcessTransport.Create(Session);
  AssertTrue(Transport.Execute('f', 100, Response) = rtrSuccess,
    'process transport starts and exchanges a command');
  AssertTrue(SessionObject.StartCount = 1, 'child process starts lazily');
  AssertTrue(SessionObject.ExchangeCount = 1, 'command is exchanged once');
  AssertTrue(Transport.Execute('f', 100, Response) = rtrSuccess,
    'running child process is reused');
  AssertTrue(SessionObject.StartCount = 1, 'healthy process is not restarted');

  SessionObject.NextResult := rtrTimeout;
  AssertTrue(Transport.Execute('f', 100, Response) = rtrTimeout,
    'process timeout reaches the protocol client');
  AssertTrue(SessionObject.StopCount = 1, 'timed-out child is stopped');
  SessionObject.NextResult := rtrSuccess;
  AssertTrue(Transport.Execute('f', 100, Response) = rtrSuccess,
    'next command restarts the stopped child');
  AssertTrue(SessionObject.StartCount = 2, 'child restart is observable');

  SessionObject.Stop;
  SessionObject.StartAllowed := False;
  AssertTrue(Transport.Execute('f', 100, Response) = rtrDisconnected,
    'start failure is reported as disconnected');
  AssertTrue(SessionObject.ExchangeCount = 4,
    'start failure performs no pipe exchange');
  Transport := nil;
  Session := nil;
end;

function FakeRigctldExecutable: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
    'fake-rigctld';
  {$IFDEF WINDOWS}
  Result := Result + '.exe';
  {$ENDIF}
end;

procedure TestRealRigctldProcessSession;
var
  Session: IRigctldProcessSession;
  Transport: IRigctldTransport;
  Response: string;
begin
  AssertTrue(FileExists(FakeRigctldExecutable),
    'fake rigctld executable is built beside the test runner');
  Session := TRigctldProcessSession.Create(FakeRigctldExecutable);
  Transport := TRigctldProcessTransport.Create(Session);
  AssertTrue(Transport.Execute('f', 1000, Response) = rtrSuccess,
    'real pipe session reads a rigctld response');
  AssertTrue(Response = '7100000', 'real pipe session preserves one response line');
  AssertTrue(Transport.Execute('F 14000000', 1000, Response) = rtrSuccess,
    'real pipe session writes a set-frequency command');
  AssertTrue(Response = 'RPRT 0', 'set-frequency acknowledgement is read');

  AssertTrue(Transport.Execute('delay', 20, Response) = rtrTimeout,
    'real pipe session enforces its response timeout');
  AssertTrue(Transport.Execute('f', 1000, Response) = rtrSuccess,
    'transport restarts the child after timeout');
  AssertTrue(Response = '7100000', 'restarted child has a clean response buffer');
  Transport := nil;
  Session := nil;
end;

procedure TestRigWorkerKeepsIoOffCaller;
const
  CompletionTimeoutMs = 2000;
var
  TransportObject: TFakeRigctldTransport;
  Transport: IRigctldTransport;
  ClientObject: TRigctldClient;
  Commands: IRigCommandPort;
  Pump: IRigWorkPump;
  Managed: IManagedRigCommandPort;
  Rig: TRigSnapshot;
  Deadline: QWord;
  RejectedAfterShutdown: Boolean;
begin
  TransportObject := TFakeRigctldTransport.Create;
  TransportObject.Configure(rtrSuccess, 'RPRT 0');
  Transport := TransportObject;
  ClientObject := TRigctldClient.Create(Transport, nil, 500);
  Commands := ClientObject;
  Pump := ClientObject;
  Managed := TRigWorkerService.Create(Commands, Pump);

  AssertTrue(Managed.RequestFrequency(28000000),
    'managed rig accepts work without caller-side transport I/O');
  Deadline := GetTickCount64 + CompletionTimeoutMs;
  repeat
    Rig := Managed.Snapshot;
    if (Rig.State = rcsReady) and not Rig.HasPendingFrequency then
      Break;
    Sleep(1);
  until GetTickCount64 >= Deadline;
  AssertTrue(Rig.State = rcsReady, 'dedicated rig worker processes the command');
  AssertTrue(Rig.FrequencyHz = 28000000, 'worker publishes rig read model');
  AssertTrue(TransportObject.CallCount = 1, 'worker performs one transport call');

  Managed.Shutdown;
  RejectedAfterShutdown := False;
  try
    Managed.RequestRefresh;
  except
    on E: EInvalidOperation do RejectedAfterShutdown := True;
  end;
  AssertTrue(RejectedAfterShutdown, 'shutdown rejects new rig work');
  Managed := nil;
  Pump := nil;
  Commands := nil;
  Transport := nil;
end;

procedure TestBoundedAudioRing;
const
  FirstBlock: array[0..4] of Single = (1, 2, 3, 4, 5);
  SecondBlock: array[0..3] of Single = (6, 7, 8, 9);
var
  Queue: IAudioSampleQueue;
  Output: array[0..5] of Single;
  Snapshot: TAudioQueueSnapshot;
  Count: Integer;
begin
  Queue := TLockFreeSpscAudioRing.Create(8);
  AssertTrue(Queue.TryPush(FirstBlock), 'audio ring accepts the first block');
  Count := Queue.Pop(Slice(Output, 3));
  AssertTrue(Count = 3, 'audio ring returns the requested sample count');
  AssertTrue((Output[0] = 1) and (Output[1] = 2) and (Output[2] = 3),
    'audio ring preserves FIFO sample order');
  AssertTrue(Queue.TryPush(SecondBlock), 'audio ring accepts a wrapped block');
  Count := Queue.Pop(Output);
  AssertTrue(Count = 6, 'audio ring reads across its wrap boundary');
  AssertTrue((Output[0] = 4) and (Output[1] = 5) and
    (Output[2] = 6) and (Output[5] = 9),
    'wrapped audio remains in FIFO order');

  AssertTrue(Queue.TryPush(FirstBlock), 'audio ring can be reused');
  AssertTrue(not Queue.TryPush(SecondBlock),
    'audio ring rejects a block that would exceed capacity');
  Snapshot := Queue.Snapshot;
  AssertTrue(Snapshot.Capacity = 8, 'audio capacity is explicit');
  AssertTrue(Snapshot.Available = 5, 'rejected block changes no queue data');
  AssertTrue(Snapshot.HighWaterMark = 6, 'audio high-water mark is retained');
  AssertTrue(Snapshot.OverrunCount = 1, 'audio overrun is observable');
  Queue := nil;
end;

procedure TestScalarRttyReference;
const
  SourceBits: array[0..15] of Byte =
    (1, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 1, 1, 1, 0, 1);
var
  Profile: TRttyProfile;
  Generator: IRttyWaveformGenerator;
  Demodulator: IRttyBitDemodulator;
  Samples: TSingleArray;
  Decoded: TByteArray;
  Confidence: TSingleArray;
  Index: Integer;
begin
  AssertTrue(TRttyProfile.TryCreate(8000, 45.45, 2125, 2295, False,
    Profile), 'standard fractional-baud RTTY profile is valid');
  Generator := TScalarRttyWaveformGenerator.Create(Profile);
  Demodulator := TScalarRttyBitDemodulator.Create(Profile);
  Samples := Generator.Generate(SourceBits);
  AssertTrue(Length(Samples) = Ceil(Length(SourceBits) * 8000 / 45.45),
    'RTTY generator uses a fractional symbol accumulator');
  AssertTrue(Demodulator.Decode(Samples, Length(SourceBits), Decoded,
    Confidence), 'scalar RTTY detector accepts the generated waveform');
  AssertTrue(Length(Decoded) = Length(SourceBits),
    'RTTY detector returns every expected bit');
  for Index := Low(SourceBits) to High(SourceBits) do
  begin
    AssertTrue(Decoded[Index] = SourceBits[Index],
      'clean RTTY waveform decodes without bit errors');
    AssertTrue(Confidence[Index] > 0.5,
      'clean RTTY bit has useful normalized confidence');
  end;
  AssertTrue(not Demodulator.Decode(Slice(Samples, Length(Samples) - 1),
    Length(SourceBits), Decoded, Confidence),
    'RTTY detector rejects a truncated waveform');
  AssertTrue(not TRttyProfile.TryCreate(8000, 45.45, 5000, 5170, False,
    Profile), 'RTTY profile rejects tones above Nyquist');
end;

procedure TestRigctldContractAndBackoff;
var
  TransportObject: TFakeRigctldTransport;
  Transport: IRigctldTransport;
  MonitorObject: TInMemoryHealthMonitor;
  Diagnostics: IDiagnosticSink;
  HealthQuery: IHealthQuery;
  CommandPort: IRigCommandPort;
  WorkPump: IRigWorkPump;
  ClientObject: TRigctldClient;
  Rig: TRigSnapshot;
  Health: THealthSnapshot;
begin
  TransportObject := TFakeRigctldTransport.Create;
  Transport := TransportObject;
  MonitorObject := TInMemoryHealthMonitor.Create;
  Diagnostics := MonitorObject;
  HealthQuery := MonitorObject;
  ClientObject := TRigctldClient.Create(Transport, Diagnostics, 321);
  CommandPort := ClientObject;
  WorkPump := ClientObject;

  AssertTrue(not CommandPort.RequestFrequency(0),
    'rig rejects an invalid frequency without transport I/O');
  AssertTrue(CommandPort.RequestFrequency(7000000),
    'rig accepts a valid frequency');
  AssertTrue(CommandPort.RequestFrequency(14000000),
    'newer frequency replaces pending work');
  TransportObject.Configure(rtrTimeout, '');
  AssertTrue(WorkPump.ProcessNext(0), 'rig worker attempts pending command');
  AssertTrue(TransportObject.LastCommand = 'F 14000000',
    'latest frequency wins before transport I/O');
  AssertTrue(TransportObject.LastTimeoutMs = 321,
    'rig transport receives the configured timeout');
  Rig := CommandPort.Snapshot;
  AssertTrue(Rig.State = rcsDegraded, 'timeout degrades rig state');
  AssertTrue(Rig.HasPendingFrequency, 'failed command remains pending');
  AssertTrue(Rig.NextRetryAtMs = 250, 'first retry uses bounded backoff');
  AssertTrue(not WorkPump.ProcessNext(249), 'backoff prevents an early retry');
  AssertTrue(TransportObject.CallCount = 1, 'early retry performs no I/O');
  Health := HealthQuery.Snapshot;
  AssertTrue(Health.LastCode = dcRigTransportFailed,
    'rig timeout emits a structured diagnostic');

  TransportObject.Configure(rtrDisconnected, '');
  AssertTrue(WorkPump.ProcessNext(250), 'rig retries at the first deadline');
  Rig := CommandPort.Snapshot;
  AssertTrue(Rig.ConsecutiveFailures = 2, 'repeated failures are counted');
  AssertTrue(Rig.NextRetryAtMs = 750, 'retry delay grows exponentially');
  AssertTrue(not WorkPump.ProcessNext(749), 'second backoff prevents early I/O');

  TransportObject.Configure(rtrSuccess, 'RPRT 0');
  AssertTrue(WorkPump.ProcessNext(750), 'rig retries at the second deadline');
  Rig := CommandPort.Snapshot;
  AssertTrue(Rig.State = rcsReady, 'successful retry restores rig state');
  AssertTrue(Rig.FrequencyHz = 14000000, 'successful set updates snapshot');
  AssertTrue(not Rig.HasPendingFrequency, 'acknowledged command is removed');
  AssertTrue(Rig.ConsecutiveFailures = 0, 'success resets backoff');
  AssertTrue(HealthQuery.Snapshot.Status = hsHealthy,
    'successful rig command restores component health');

  CommandPort.RequestRefresh;
  TransportObject.Configure(rtrSuccess, '21000000');
  AssertTrue(WorkPump.ProcessNext(751), 'frequency refresh is processed');
  AssertTrue(TransportObject.LastCommand = 'f',
    'refresh uses the rigctld frequency command');
  Rig := CommandPort.Snapshot;
  AssertTrue(Rig.FrequencyHz = 21000000,
    'rigctld response updates the read model');

  WorkPump := nil;
  CommandPort := nil;
  Transport := nil;
  Diagnostics := nil;
  HealthQuery := nil;
end;

begin
  try
    TestCallsignNormalization;
    TestFrequencyValidation;
    TestIndexedRepository;
    TestLogQso;
    TestRecentQsoQueryUseCase;
    TestRecentQsosPresenter;
    TestInvalidDraftDoesNotPersist;
    TestJournalRoundTripAndTailRecovery;
    TestJournalRejectsOversizedRecordWithoutDamage;
    TestJournalAppendFaultInjection;
    TestJournalRecoveryAtEveryTailPosition;
    TestRuntimeAdapters;
    TestQsoEntryPresenter;
    TestBoundedSubmissionQueue;
    TestCompletionCapacityRaceDoesNotDuplicateQso;
    TestSubmissionWorkerAndMainThreadCompletion;
    TestSubmissionWorkerSurvivesUnexpectedPumpFailure;
    TestCompletionNotificationCoalescing;
    TestStructuredDiagnosticsAndHealth;
    TestRigctldContractAndBackoff;
    TestRigctldProcessLifecycle;
    TestRealRigctldProcessSession;
    TestRigWorkerKeepsIoOffCaller;
    TestBoundedAudioRing;
    TestScalarRttyReference;
    WriteLn('PASS: ', TestsRun, ' assertions');
  except
    on E: Exception do
    begin
      WriteLn(StdErr, E.Message);
      Halt(1);
    end;
  end;
end.
