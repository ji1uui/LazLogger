unit ZLog.Presentation.QsoEntry;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, ZLog.Domain.Types, ZLog.Domain.Qso, ZLog.Application.LogQso,
  ZLog.Application.Submission;

type
  TQsoEntryStatus = (qesReady, qesSubmitting, qesAccepted, qesRejected);

  TQsoEntryState = record
    Callsign: string;
    FrequencyHz: Int64;
    Mode: TEmissionMode;
    SentExchange: string;
    ReceivedExchange: string;
    Status: TQsoEntryStatus;
    ErrorField: string;
    ErrorCode: TLogQsoError;
    AcceptedQsoId: string;
  end;

  IQsoEntryView = interface
    ['{5BDDE310-24B3-493E-AE05-7062D5F7FB2D}']
    procedure Render(const AState: TQsoEntryState);
  end;

  IQsoEntryPresenter = interface
    ['{33D6EC02-9F50-4533-AD4D-BC45BC10CA07}']
    procedure Initialize;
    procedure UpdateDraft(const ACallsign: string; const AFrequencyHz: Int64;
      const AMode: TEmissionMode; const ASentExchange,
      AReceivedExchange: string);
    procedure Submit;
  end;

  TQsoEntryPresenter = class(TInterfacedObject, IQsoEntryPresenter,
    IQsoSubmissionObserver)
  private
    FView: IQsoEntryView;
    FSubmission: IQsoSubmissionPort;
    FState: TQsoEntryState;
    procedure Publish;
    class function ErrorFieldFor(const AError: TLogQsoError): string; static;
  public
    constructor Create(const AView: IQsoEntryView;
      const ASubmission: IQsoSubmissionPort);
    procedure Initialize;
    procedure UpdateDraft(const ACallsign: string; const AFrequencyHz: Int64;
      const AMode: TEmissionMode; const ASentExchange,
      AReceivedExchange: string);
    procedure Submit;
    procedure SubmissionCompleted(const AResult: TLogQsoResult);
  end;

implementation

constructor TQsoEntryPresenter.Create(const AView: IQsoEntryView;
  const ASubmission: IQsoSubmissionPort);
begin
  inherited Create;
  if not Assigned(AView) then
    raise EArgumentNilException.Create('AView');
  if not Assigned(ASubmission) then
    raise EArgumentNilException.Create('ASubmission');
  FView := AView;
  FSubmission := ASubmission;
  FState.Mode := emCW;
  FState.Status := qesReady;
  FState.ErrorCode := lqeNone;
end;

procedure TQsoEntryPresenter.Publish;
begin
  FView.Render(FState);
end;

class function TQsoEntryPresenter.ErrorFieldFor(
  const AError: TLogQsoError): string;
begin
  case AError of
    lqeInvalidCallsign: Result := 'callsign';
    lqeInvalidFrequency: Result := 'frequency';
    lqeUnknownMode: Result := 'mode';
  else
    Result := '';
  end;
end;

procedure TQsoEntryPresenter.Initialize;
begin
  Publish;
end;

procedure TQsoEntryPresenter.UpdateDraft(const ACallsign: string;
  const AFrequencyHz: Int64; const AMode: TEmissionMode;
  const ASentExchange, AReceivedExchange: string);
begin
  if FState.Status = qesSubmitting then
    Exit;
  FState.Callsign := ACallsign;
  FState.FrequencyHz := AFrequencyHz;
  FState.Mode := AMode;
  FState.SentExchange := ASentExchange;
  FState.ReceivedExchange := AReceivedExchange;
  FState.Status := qesReady;
  FState.ErrorField := '';
  FState.ErrorCode := lqeNone;
  FState.AcceptedQsoId := '';
  Publish;
end;

procedure TQsoEntryPresenter.Submit;
var
  Draft: TQsoDraft;
begin
  if FState.Status = qesSubmitting then
    Exit;
  Draft.Callsign := FState.Callsign;
  Draft.FrequencyHz := FState.FrequencyHz;
  Draft.Mode := FState.Mode;
  Draft.SentExchange := FState.SentExchange;
  Draft.ReceivedExchange := FState.ReceivedExchange;
  FState.Status := qesSubmitting;
  FState.ErrorField := '';
  FState.ErrorCode := lqeNone;
  Publish;
  FSubmission.Submit(Draft, Self);
end;

procedure TQsoEntryPresenter.SubmissionCompleted(
  const AResult: TLogQsoResult);
begin
  if FState.Status <> qesSubmitting then
    Exit;
  FState.ErrorCode := AResult.Error;
  if AResult.Success then
  begin
    FState.Status := qesAccepted;
    FState.AcceptedQsoId := AResult.QsoId;
    FState.Callsign := '';
    FState.ReceivedExchange := '';
  end
  else
  begin
    FState.Status := qesRejected;
    FState.ErrorField := ErrorFieldFor(AResult.Error);
  end;
  Publish;
end;

end.
