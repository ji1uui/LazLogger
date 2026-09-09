unit ZLog.Application.LogQso;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, ZLog.Domain.Types, ZLog.Domain.Qso, ZLog.Application.Ports;

type
  TLogQsoError = (lqeNone, lqeInvalidCallsign, lqeInvalidFrequency,
    lqeUnknownMode, lqeMissingIdentifier);

  TLogQsoResult = record
    Success: Boolean;
    QsoId: string;
    Error: TLogQsoError;
  end;

  ILogQsoUseCase = interface
    ['{57628105-E7C4-4E37-8F16-E86DEDE4B0FE}']
    function Execute(const ADraft: TQsoDraft): TLogQsoResult;
  end;

  TLogQsoUseCase = class(TInterfacedObject, ILogQsoUseCase)
  private
    FRepository: IQsoRepository;
    FClock: IClock;
    FIdGenerator: IIdGenerator;
    class function Failure(const AError: TLogQsoError): TLogQsoResult; static;
  public
    constructor Create(const ARepository: IQsoRepository; const AClock: IClock;
      const AIdGenerator: IIdGenerator);
    function Execute(const ADraft: TQsoDraft): TLogQsoResult;
  end;

implementation

constructor TLogQsoUseCase.Create(const ARepository: IQsoRepository;
  const AClock: IClock; const AIdGenerator: IIdGenerator);
begin
  inherited Create;
  if not Assigned(ARepository) then
    raise EArgumentNilException.Create('ARepository');
  if not Assigned(AClock) then
    raise EArgumentNilException.Create('AClock');
  if not Assigned(AIdGenerator) then
    raise EArgumentNilException.Create('AIdGenerator');
  FRepository := ARepository;
  FClock := AClock;
  FIdGenerator := AIdGenerator;
end;

class function TLogQsoUseCase.Failure(const AError: TLogQsoError): TLogQsoResult;
begin
  Result.Success := False;
  Result.QsoId := '';
  Result.Error := AError;
end;

function TLogQsoUseCase.Execute(const ADraft: TQsoDraft): TLogQsoResult;
var
  Callsign: TCallsign;
  Frequency: TFrequencyHz;
  Qso: TQso;
begin
  if not TCallsign.TryCreate(ADraft.Callsign, Callsign) then
    Exit(Failure(lqeInvalidCallsign));
  if not TFrequencyHz.TryCreate(ADraft.FrequencyHz, Frequency) then
    Exit(Failure(lqeInvalidFrequency));
  if ADraft.Mode = emUnknown then
    Exit(Failure(lqeUnknownMode));

  Result.QsoId := FIdGenerator.NextId;
  if Result.QsoId = '' then
    Exit(Failure(lqeMissingIdentifier));

  Qso := TQso.Create(Result.QsoId, Callsign, Frequency, ADraft.Mode,
    Trim(ADraft.SentExchange), Trim(ADraft.ReceivedExchange), FClock.UtcNowMs);
  try
    FRepository.Add(Qso);
  finally
    Qso.Free;
  end;

  Result.Success := True;
  Result.Error := lqeNone;
end;

end.
