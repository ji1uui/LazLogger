program ZLogUnitTests;

{$mode objfpc}{$H+}

uses
  SysUtils, ZLog.Domain.Types, ZLog.Domain.Qso, ZLog.Application.Ports,
  ZLog.Application.LogQso, ZLog.Infrastructure.Memory,
  ZLog.Infrastructure.Deterministic;

var
  TestsRun: Integer = 0;

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

begin
  try
    TestCallsignNormalization;
    TestFrequencyValidation;
    TestLogQso;
    TestInvalidDraftDoesNotPersist;
    WriteLn('PASS: ', TestsRun, ' assertions');
  except
    on E: Exception do
    begin
      WriteLn(StdErr, E.Message);
      Halt(1);
    end;
  end;
end.
