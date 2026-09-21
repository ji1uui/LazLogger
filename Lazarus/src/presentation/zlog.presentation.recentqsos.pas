unit ZLog.Presentation.RecentQsos;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, DateUtils, ZLog.Domain.Types, ZLog.Domain.Qso,
  ZLog.Application.QueryQsos;

type
  TRecentQsoStatus = (rqsLoading, rqsLoaded, rqsFailed);

  TRecentQsoRow = record
    Id: string;
    TimeUtc: string;
    Callsign: UnicodeString;
    Frequency: string;
    Mode: string;
    SentExchange: UnicodeString;
    ReceivedExchange: UnicodeString;
  end;

  TRecentQsoRowArray = array of TRecentQsoRow;

  TRecentQsosState = record
    Status: TRecentQsoStatus;
    Rows: TRecentQsoRowArray;
    ErrorMessage: string;
  end;

  IRecentQsosView = interface
    ['{A542901E-F0C3-4788-AB1A-6D6C3B3021EE}']
    procedure RenderRecentQsos(const AState: TRecentQsosState);
  end;

  IRecentQsosPresenter = interface
    ['{0DD191C7-2F2C-4BC5-859B-C8008830BC58}']
    procedure Initialize;
    procedure Refresh;
  end;

  TRecentQsosPresenter = class(TInterfacedObject, IRecentQsosPresenter)
  private
    FView: IRecentQsosView;
    FQuery: IGetRecentQsosUseCase;
    FMaximumCount: Integer;
    FState: TRecentQsosState;
    procedure Publish;
    class function ModeText(const AMode: TEmissionMode): string; static;
    class function ToRow(const AItem: TQsoSnapshot): TRecentQsoRow; static;
  public
    constructor Create(const AView: IRecentQsosView;
      const AQuery: IGetRecentQsosUseCase; const AMaximumCount: Integer = 50);
    procedure Initialize;
    procedure Refresh;
  end;

implementation

constructor TRecentQsosPresenter.Create(const AView: IRecentQsosView;
  const AQuery: IGetRecentQsosUseCase; const AMaximumCount: Integer);
begin
  inherited Create;
  if not Assigned(AView) then
    raise EArgumentNilException.Create('AView');
  if not Assigned(AQuery) then
    raise EArgumentNilException.Create('AQuery');
  if (AMaximumCount <= 0) or (AMaximumCount > 500) then
    raise EArgumentOutOfRangeException.Create('AMaximumCount must be between 1 and 500');
  FView := AView;
  FQuery := AQuery;
  FMaximumCount := AMaximumCount;
  FState.Status := rqsLoading;
end;

procedure TRecentQsosPresenter.Publish;
begin
  FView.RenderRecentQsos(FState);
end;

class function TRecentQsosPresenter.ModeText(
  const AMode: TEmissionMode): string;
begin
  case AMode of
    emCW: Result := 'CW';
    emRTTY: Result := 'RTTY';
    emSSB: Result := 'SSB';
  else
    Result := '?';
  end;
end;

class function TRecentQsosPresenter.ToRow(
  const AItem: TQsoSnapshot): TRecentQsoRow;
var
  Timestamp: TDateTime;
begin
  Result.Id := AItem.Id;
  Timestamp := UnixToDateTime(AItem.OccurredAtUtcMs div 1000, True);
  Result.TimeUtc := FormatDateTime('yyyy-mm-dd hh:nn:ss', Timestamp) + 'Z';
  Result.Callsign := AItem.Callsign;
  Result.Frequency := IntToStr(AItem.FrequencyHz div 1000000) + '.' +
    Format('%.3d', [(AItem.FrequencyHz mod 1000000) div 1000]);
  Result.Mode := ModeText(AItem.Mode);
  Result.SentExchange := AItem.SentExchange;
  Result.ReceivedExchange := AItem.ReceivedExchange;
end;

procedure TRecentQsosPresenter.Initialize;
begin
  Refresh;
end;

procedure TRecentQsosPresenter.Refresh;
var
  QueryResult: TRecentQsoQueryResult;
  Index: Integer;
begin
  FState.Status := rqsLoading;
  FState.ErrorMessage := '';
  Publish;
  try
    QueryResult := FQuery.Execute(FMaximumCount);
    if not QueryResult.Success then
      raise EInvalidOperation.Create('Recent QSO query rejected its configured limit');
    SetLength(FState.Rows, Length(QueryResult.Items));
    for Index := 0 to High(QueryResult.Items) do
      FState.Rows[Index] := ToRow(QueryResult.Items[Index]);
    FState.Status := rqsLoaded;
    Publish;
  except
    on E: Exception do
    begin
      SetLength(FState.Rows, 0);
      FState.Status := rqsFailed;
      FState.ErrorMessage := 'Unable to load recent QSOs';
      Publish;
    end;
  end;
end;

end.
