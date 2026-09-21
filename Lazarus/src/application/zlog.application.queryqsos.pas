unit ZLog.Application.QueryQsos;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, ZLog.Domain.Qso, ZLog.Application.Ports;

type
  TRecentQsoQueryError = (rqeNone, rqeInvalidLimit);

  TRecentQsoQueryResult = record
    Success: Boolean;
    Items: TQsoSnapshotArray;
    Error: TRecentQsoQueryError;
  end;

  IGetRecentQsosUseCase = interface
    ['{7805C13D-6B4B-4287-BBB9-E3CE1FC3728C}']
    function Execute(const AMaximumCount: Integer): TRecentQsoQueryResult;
  end;

  TGetRecentQsosUseCase = class(TInterfacedObject, IGetRecentQsosUseCase)
  private
    FRepository: IQsoReadRepository;
  public
    constructor Create(const ARepository: IQsoReadRepository);
    function Execute(const AMaximumCount: Integer): TRecentQsoQueryResult;
  end;

implementation

const
  MaximumPageSize = 500;

constructor TGetRecentQsosUseCase.Create(const ARepository: IQsoReadRepository);
begin
  inherited Create;
  if not Assigned(ARepository) then
    raise EArgumentNilException.Create('ARepository');
  FRepository := ARepository;
end;

function TGetRecentQsosUseCase.Execute(
  const AMaximumCount: Integer): TRecentQsoQueryResult;
begin
  Result.Success := False;
  Result.Error := rqeInvalidLimit;
  SetLength(Result.Items, 0);
  if (AMaximumCount < 0) or (AMaximumCount > MaximumPageSize) then
    Exit;
  Result.Items := FRepository.GetRecent(AMaximumCount);
  Result.Error := rqeNone;
  Result.Success := True;
end;

end.
