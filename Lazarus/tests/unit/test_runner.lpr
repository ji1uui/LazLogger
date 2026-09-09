program ZLogUnitTests;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, DateUtils, ZLog.Domain.Types, ZLog.Domain.Qso,
  ZLog.Application.LogQso, ZLog.Infrastructure.Memory,
  ZLog.Infrastructure.Deterministic, ZLog.Infrastructure.Journal,
  ZLog.Infrastructure.Runtime, ZLog.Application.Submission,
  ZLog.Presentation.QsoEntry;

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
    Draft.ReceivedExchange := '599 002';
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

begin
  try
    TestCallsignNormalization;
    TestFrequencyValidation;
    TestLogQso;
    TestInvalidDraftDoesNotPersist;
    TestJournalRoundTripAndTailRecovery;
    TestRuntimeAdapters;
    TestQsoEntryPresenter;
    WriteLn('PASS: ', TestsRun, ' assertions');
  except
    on E: Exception do
    begin
      WriteLn(StdErr, E.Message);
      Halt(1);
    end;
  end;
end.
