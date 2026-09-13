unit ZLog.Gui.MainForm;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, SyncObjs,
  ZLog.Domain.Types, ZLog.Application.Ports, ZLog.Application.LogQso,
  ZLog.Application.Submission, ZLog.Infrastructure.Runtime,
  ZLog.Infrastructure.Journal, ZLog.Infrastructure.SubmissionQueue,
  ZLog.Infrastructure.SubmissionWorker, ZLog.Infrastructure.CompletionQueue,
  ZLog.Presentation.QsoEntry;

type
  TMainForm = class;

  TLclCompletionNotifier = class(TInterfacedObject,
    ICompletionAvailableNotifier)
  private
    FForm: TMainForm;
    FLock: TCriticalSection;
    FQueued: Boolean;
    procedure Deliver(Data: PtrInt);
  public
    constructor Create(const AForm: TMainForm);
    destructor Destroy; override;
    procedure Disable;
    procedure NotifyCompletionAvailable;
  end;

  TQsoEntryViewAdapter = class(TInterfacedObject, IQsoEntryView)
  private
    FForm: TMainForm;
  public
    constructor Create(const AForm: TMainForm);
    procedure Detach;
    procedure Render(const AState: TQsoEntryState);
  end;

  TMainForm = class(TForm)
  private
    FCallsignEdit: TEdit;
    FFrequencyEdit: TEdit;
    FModeCombo: TComboBox;
    FSentEdit: TEdit;
    FReceivedEdit: TEdit;
    FLogButton: TButton;
    FStatusLabel: TLabel;
    FRepository: IQsoRepository;
    FManagedSubmission: IManagedQsoSubmissionPort;
    FCompletionPump: ICompletionPump;
    FPresenter: IQsoEntryPresenter;
    FViewAdapter: TQsoEntryViewAdapter;
    FView: IQsoEntryView;
    FCompletionNotifier: TLclCompletionNotifier;
    FNotifier: ICompletionAvailableNotifier;
    procedure BuildControls;
    procedure ComposeApplication;
    procedure LogButtonClick(Sender: TObject);
    procedure DrainCompletions;
    procedure UpdateFromState(const AState: TQsoEntryState);
    function SelectedMode: TEmissionMode;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  MainForm: TMainForm;

implementation

const
  Margin = 20;
  RowHeight = 34;

function NewLabel(const AOwner: TComponent; const AParent: TWinControl;
  const ACaption: string; const ATop: Integer): TLabel;
begin
  Result := TLabel.Create(AOwner);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := Margin;
  Result.Top := ATop + 7;
  Result.AutoSize := True;
end;

function NewEdit(const AOwner: TComponent; const AParent: TWinControl;
  const ATop: Integer): TEdit;
begin
  Result := TEdit.Create(AOwner);
  Result.Parent := AParent;
  Result.Left := 150;
  Result.Top := ATop;
  Result.Width := 310;
  Result.Anchors := [akLeft, akTop, akRight];
end;

constructor TQsoEntryViewAdapter.Create(const AForm: TMainForm);
begin
  inherited Create;
  FForm := AForm;
end;

constructor TLclCompletionNotifier.Create(const AForm: TMainForm);
begin
  inherited Create;
  FForm := AForm;
  FLock := TCriticalSection.Create;
end;

destructor TLclCompletionNotifier.Destroy;
begin
  Application.RemoveAsyncCalls(Self);
  FLock.Free;
  inherited Destroy;
end;

procedure TLclCompletionNotifier.Disable;
begin
  FLock.Acquire;
  try
    FForm := nil;
  finally
    FLock.Release;
  end;
  Application.RemoveAsyncCalls(Self);
end;

procedure TLclCompletionNotifier.NotifyCompletionAvailable;
var
  ShouldQueue: Boolean;
begin
  FLock.Acquire;
  try
    ShouldQueue := Assigned(FForm) and not FQueued;
    if ShouldQueue then
      FQueued := True;
  finally
    FLock.Release;
  end;
  if ShouldQueue then
    Application.QueueAsyncCall(@Deliver, 0);
end;

procedure TLclCompletionNotifier.Deliver(Data: PtrInt);
var
  Form: TMainForm;
begin
  FLock.Acquire;
  try
    FQueued := False;
    Form := FForm;
  finally
    FLock.Release;
  end;
  if Assigned(Form) then
    Form.DrainCompletions;
end;

procedure TQsoEntryViewAdapter.Detach;
begin
  FForm := nil;
end;

procedure TQsoEntryViewAdapter.Render(const AState: TQsoEntryState);
begin
  if Assigned(FForm) then
    FForm.UpdateFromState(AState);
end;

constructor TMainForm.Create(TheOwner: TComponent);
begin
  inherited CreateNew(TheOwner, 1);
  Caption := 'zLog Lazarus Edition';
  Width := 520;
  Height := 330;
  Position := poScreenCenter;
  Constraints.MinWidth := 500;
  Constraints.MinHeight := 300;
  BuildControls;
  ComposeApplication;
end;

destructor TMainForm.Destroy;
begin
  if Assigned(FViewAdapter) then
    FViewAdapter.Detach;
  if Assigned(FCompletionNotifier) then
    FCompletionNotifier.Disable;
  if Assigned(FManagedSubmission) then
    FManagedSubmission.Shutdown;
  if Assigned(FCompletionPump) then
    while FCompletionPump.PendingCount > 0 do
      FCompletionPump.Drain(16);
  FPresenter := nil;
  FView := nil;
  FManagedSubmission := nil;
  FCompletionPump := nil;
  FNotifier := nil;
  FRepository := nil;
  inherited Destroy;
end;

procedure TMainForm.BuildControls;
var
  TopPosition: Integer;
begin
  TopPosition := Margin;
  NewLabel(Self, Self, 'Callsign', TopPosition);
  FCallsignEdit := NewEdit(Self, Self, TopPosition);
  FCallsignEdit.CharCase := ecUppercase;

  Inc(TopPosition, RowHeight);
  NewLabel(Self, Self, 'Frequency (Hz)', TopPosition);
  FFrequencyEdit := NewEdit(Self, Self, TopPosition);
  FFrequencyEdit.Text := '7000000';

  Inc(TopPosition, RowHeight);
  NewLabel(Self, Self, 'Mode', TopPosition);
  FModeCombo := TComboBox.Create(Self);
  FModeCombo.Parent := Self;
  FModeCombo.Left := 150;
  FModeCombo.Top := TopPosition;
  FModeCombo.Width := 160;
  FModeCombo.Style := csDropDownList;
  FModeCombo.Items.Add('CW');
  FModeCombo.Items.Add('RTTY');
  FModeCombo.Items.Add('SSB');
  FModeCombo.ItemIndex := 0;

  Inc(TopPosition, RowHeight);
  NewLabel(Self, Self, 'Sent exchange', TopPosition);
  FSentEdit := NewEdit(Self, Self, TopPosition);
  FSentEdit.Text := '599 001';

  Inc(TopPosition, RowHeight);
  NewLabel(Self, Self, 'Received exchange', TopPosition);
  FReceivedEdit := NewEdit(Self, Self, TopPosition);

  Inc(TopPosition, RowHeight + 4);
  FLogButton := TButton.Create(Self);
  FLogButton.Parent := Self;
  FLogButton.Caption := 'Log QSO';
  FLogButton.Left := 150;
  FLogButton.Top := TopPosition;
  FLogButton.Width := 120;
  FLogButton.Default := True;
  FLogButton.OnClick := @LogButtonClick;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.Left := 290;
  FStatusLabel.Top := TopPosition + 7;
  FStatusLabel.Caption := 'Ready';
  FStatusLabel.AutoSize := True;
  FStatusLabel.ShowHint := True;

end;

procedure TMainForm.ComposeApplication;
var
  JournalPath: string;
  UseCase: ILogQsoUseCase;
  Dispatcher: IQsoCompletionDispatcher;
  QueueSubmission: IQsoSubmissionPort;
  WorkPump: ISubmissionWorkPump;
  QueueObject: TQueuedQsoSubmission;
  DispatcherObject: TQueuedCompletionDispatcher;
begin
  JournalPath := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) +
    'qso.journal';
  FRepository := TJournalQsoRepository.Create(JournalPath);
  UseCase := TLogQsoUseCase.Create(FRepository, TSystemClock.Create,
    TGuidIdGenerator.Create);
  FCompletionNotifier := TLclCompletionNotifier.Create(Self);
  FNotifier := FCompletionNotifier;
  DispatcherObject := TQueuedCompletionDispatcher.Create(FNotifier);
  Dispatcher := DispatcherObject;
  FCompletionPump := DispatcherObject;
  QueueObject := TQueuedQsoSubmission.Create(UseCase, Dispatcher, 32);
  QueueSubmission := QueueObject;
  WorkPump := QueueObject;
  FManagedSubmission := TSubmissionWorkerService.Create(QueueSubmission, WorkPump);
  FViewAdapter := TQsoEntryViewAdapter.Create(Self);
  FView := FViewAdapter;
  FPresenter := TQsoEntryPresenter.Create(FView, FManagedSubmission);
  FPresenter.Initialize;
end;

function TMainForm.SelectedMode: TEmissionMode;
begin
  case FModeCombo.ItemIndex of
    0: Result := emCW;
    1: Result := emRTTY;
    2: Result := emSSB;
  else
    Result := emUnknown;
  end;
end;

procedure TMainForm.LogButtonClick(Sender: TObject);
begin
  FPresenter.UpdateDraft(FCallsignEdit.Text,
    StrToInt64Def(FFrequencyEdit.Text, 0), SelectedMode, FSentEdit.Text,
    FReceivedEdit.Text);
  FPresenter.Submit;
end;

procedure TMainForm.DrainCompletions;
begin
  FCompletionPump.Drain(16);
  if FCompletionPump.PendingCount > 0 then
    FCompletionNotifier.NotifyCompletionAvailable;
end;

procedure TMainForm.UpdateFromState(const AState: TQsoEntryState);
begin
  FLogButton.Enabled := AState.Status <> qesSubmitting;
  case AState.Status of
    qesReady: FStatusLabel.Caption := 'Ready';
    qesSubmitting: FStatusLabel.Caption := 'Saving...';
    qesAccepted: FStatusLabel.Caption := 'Saved: ' + AState.AcceptedQsoId;
    qesRejected:
      case AState.ErrorCode of
        lqeInvalidCallsign: FStatusLabel.Caption := 'Check the callsign';
        lqeInvalidFrequency: FStatusLabel.Caption := 'Check the frequency';
        lqeUnknownMode: FStatusLabel.Caption := 'Select a mode';
        lqeQueueFull: FStatusLabel.Caption := 'Save queue is full; retry';
        lqeCancelled: FStatusLabel.Caption := 'Save cancelled';
      else
        FStatusLabel.Caption := 'QSO was not saved';
      end;
  end;
  if AState.Status = qesAccepted then
  begin
    FCallsignEdit.Text := UTF8Encode(AState.Callsign);
    FReceivedEdit.Text := UTF8Encode(AState.ReceivedExchange);
    FCallsignEdit.SetFocus;
  end
  else if AState.Status = qesRejected then
  begin
    if AState.ErrorField = 'callsign' then FCallsignEdit.SetFocus
    else if AState.ErrorField = 'frequency' then FFrequencyEdit.SetFocus
    else if AState.ErrorField = 'mode' then FModeCombo.SetFocus;
  end;
end;

end.
