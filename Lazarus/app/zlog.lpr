program ZLogLazarus;

{$mode objfpc}{$H+}

uses
  SysUtils, ZLog.Domain.Types, ZLog.Domain.Qso, ZLog.Application.Ports,
  ZLog.Application.LogQso, ZLog.Infrastructure.Memory,
  ZLog.Infrastructure.Deterministic;

var
  Repository: IQsoRepository;
  UseCase: ILogQsoUseCase;
  Draft: TQsoDraft;
  LogResult: TLogQsoResult;
begin
  Repository := TInMemoryQsoRepository.Create;
  UseCase := TLogQsoUseCase.Create(Repository, TFixedClock.Create(0),
    TSequentialIdGenerator.Create('demo-'));

  Draft.Callsign := 'JA1ZLO';
  Draft.FrequencyHz := 7000000;
  Draft.Mode := emCW;
  Draft.SentExchange := '599 001';
  Draft.ReceivedExchange := '599 002';
  LogResult := UseCase.Execute(Draft);

  if not LogResult.Success then
    Halt(1);
  WriteLn('Logged QSO ', LogResult.QsoId, '; count=', Repository.Count);
end.
