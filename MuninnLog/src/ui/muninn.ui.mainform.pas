unit Muninn.UI.MainForm;

{ The main window (T10 prototype, T12): the menu, the QSO entry line, the
  partial check list, the log, the band map and the status bar. The form only
  lays out controls and forwards events; TQsoEntryPresenter and
  TLogbookPresenter decide what to show (ADR 0009, ADR 0010).

  Keys: Enter logs the entry, Esc clears it. A click on the band map tunes.
  The entry line works only while a logbook is open, or in the demo. }

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Menus,
  Dialogs, Graphics, Muninn.Core.Frequency, Muninn.Core.Mode,
  Muninn.Core.Logbook, Muninn.UI.Bandmap, Muninn.UI.BandmapView,
  Muninn.UI.QsoEntry, Muninn.UI.Logbook, Muninn.UI.Theme;

type
  TMainForm = class(TForm, IQsoEntryView, ILogbookView)
  private
    FLogbooks: TLogbookPresenter;
    FDemo: Boolean;
    FStatusBar: TStatusBar;
    FRecentMenu: TMenuItem;
    FCloseItem: TMenuItem;
    procedure BuildMenu;
    procedure NewLogbookClick(Sender: TObject);
    procedure OpenLogbookClick(Sender: TObject);
    procedure RecentLogbookClick(Sender: TObject);
    procedure CloseLogbookClick(Sender: TObject);
    procedure QuitClick(Sender: TObject);
    procedure UpdateEntryEnabled;
    procedure FrequencyChanged(Sender: TObject);
    procedure UpdateStatusBar;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure UseLogbook;
    procedure LeaveLogbook;
  private
    FTheme: TUiTheme;
    FBandmapModel: TBandmapModel;
    FPresenter: TQsoEntryPresenter;
    FEntryPanel: TPanel;
    FCallEdit: TEdit;
    FRstSentEdit: TEdit;
    FRstReceivedEdit: TEdit;
    FModeCombo: TComboBox;
    FFrequencyEdit: TEdit;
    FSettingFrequency: Boolean;
    FLogbookText: string;
    FLogbookPath: string;
    FQsoCount: Int64;
    FSaveText: string;
    FStatusLabel: TLabel;
    FPartialList: TListBox;
    FLogList: TListBox;
    FBandmap: TBandmapControl;
    FProblem: string;
    FDuplicate: Boolean;
    FNextLeft: Integer;
    procedure PlaceNext(const AControl: TControl);
    function UtcNowMs: Int64;
    { AWidth96 is the width at 96 dpi. }
    function AddEdit(const AParent: TWinControl; const ACaption: string;
      const AWidth96: Integer): TEdit;
    procedure BuildControls;
    procedure CallChanged(Sender: TObject);
    procedure ModeChanged(Sender: TObject);
    procedure EntryKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure BandmapTune(Sender: TObject; const AHz: Int64);
    procedure ShowStatus;
    procedure FocusCall;
    procedure RefreshWorked;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ApplyTheme(const ATheme: TUiTheme);
    { Logbooks from AStore; the recent list comes from ARecent and is saved
      with ASaveRecent. Without this call (or in the demo) there is no menu
      for logbooks. }
    procedure AttachLogbooks(const AStore: ILogbookStore; const ARecent: TStrings;
      const ASaveRecent: TRecentLogbooksSaver);
    { The prototype's demo: the entry line works without a logbook. }
    procedure EnableDemo;
    procedure Tune(const AHz: Int64);
    { IQsoEntryView }
    procedure ShowCallsignState(const ANormalized, AProblem: string);
    procedure ShowPartialMatches(const AMatches: TCallList; const ATotal: Integer);
    procedure ShowDuplicate(const AIsDuplicate: Boolean);
    procedure ShowLogged(const AQso: TLoggedQso);
    procedure ClearEntry;
    procedure ShowSaveState(const ATicket: Int64; const AState: TQsoSaveState;
      const AMessage: string);
    procedure ShowSaveStatus(const APending: Integer; const ALastSavedUtcMs: Int64;
      const ALastError: string);
    { ILogbookView }
    procedure ShowLogbook(const APath: string; const AQsoCount: Int64);
    procedure ShowNoLogbook;
    procedure ShowLogbookError(const AMessage: string);
    procedure ShowRecentLogbooks(const APaths: TStrings);

    property Logbooks: TLogbookPresenter read FLogbooks;
    property Presenter: TQsoEntryPresenter read FPresenter;
    property BandmapModel: TBandmapModel read FBandmapModel;
    property Bandmap: TBandmapControl read FBandmap;
    property CallEdit: TEdit read FCallEdit;
    property RstSentEdit: TEdit read FRstSentEdit;
    property RstReceivedEdit: TEdit read FRstReceivedEdit;
  end;

implementation

uses
  LCLType, DateUtils, Muninn.Core.Time;

const
  Modes: array[0..4] of string = ('CW', 'USB', 'LSB', 'FT8', 'RTTY');

constructor TMainForm.Create(AOwner: TComponent);
begin
  { Built in code: there is no form resource. }
  inherited CreateNew(AOwner);
  FTheme := DarkTheme;
  Caption := 'MuninnLog';
  Position := poScreenCenter;
  Width := Scale96ToScreen(960);
  Height := Scale96ToScreen(600);
  KeyPreview := True;
  OnCloseQuery := @FormCloseQuery;
  FBandmapModel := TBandmapModel.Create(7000000, 7040000);
  BuildMenu;
  BuildControls;
  FPresenter := TQsoEntryPresenter.Create(Self, @UtcNowMs);
  FModeCombo.ItemIndex := 0;
  ModeChanged(nil);
  ShowNoLogbook;
end;

destructor TMainForm.Destroy;
begin
  { The presenters hold this form as their view. }
  FreeAndNil(FLogbooks);
  FreeAndNil(FPresenter);
  inherited Destroy;
  FBandmapModel.Free;
end;

function TMainForm.UtcNowMs: Int64;
begin
  Result := DateTimeToUnix(LocalTimeToUniversal(Now), True) * 1000 +
    MilliSecondOf(Now);
end;

function TMainForm.AddEdit(const AParent: TWinControl; const ACaption: string;
  const AWidth96: Integer): TEdit;
var
  Title: TLabel;
begin
  Title := TLabel.Create(Self);
  Title.Parent := AParent;
  Title.Caption := ACaption;
  Title.Layout := tlCenter;
  Title.Align := alLeft;
  Title.BorderSpacing.Left := Scale96ToFont(8);
  Title.BorderSpacing.Right := Scale96ToFont(4);
  Result := TEdit.Create(Self);
  Result.Parent := AParent;
  Result.Align := alLeft;
  Result.Width := Scale96ToForm(AWidth96);
  Result.BorderSpacing.Around := Scale96ToFont(4);
  Result.OnKeyDown := @EntryKeyDown;
  PlaceNext(Title);
  PlaceNext(Result);
end;

procedure TMainForm.BuildMenu;
var
  MainMenu: TMainMenu;
  FileMenu: TMenuItem;

  function AddItem(const AParent: TMenuItem; const ACaption: string;
    const AKey: Word; const AHandler: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(Self);
    Result.Caption := ACaption;
    if AKey <> 0 then
      { ssModifier is Ctrl, or Command on macOS. }
      Result.ShortCut := ShortCut(AKey, [ssModifier]);
    Result.OnClick := AHandler;
    AParent.Add(Result);
  end;

begin
  MainMenu := TMainMenu.Create(Self);
  Menu := MainMenu;
  FileMenu := TMenuItem.Create(Self);
  FileMenu.Caption := '&File';
  MainMenu.Items.Add(FileMenu);
  AddItem(FileMenu, '&New logbook...', VK_N, @NewLogbookClick);
  AddItem(FileMenu, '&Open logbook...', VK_O, @OpenLogbookClick);
  FRecentMenu := AddItem(FileMenu, 'Open &recent', 0, nil);
  FCloseItem := AddItem(FileMenu, '&Close logbook', 0, @CloseLogbookClick);
  AddItem(FileMenu, '-', 0, nil);
  AddItem(FileMenu, '&Quit', VK_Q, @QuitClick);
end;

procedure TMainForm.AttachLogbooks(const AStore: ILogbookStore;
  const ARecent: TStrings; const ASaveRecent: TRecentLogbooksSaver);
begin
  FreeAndNil(FLogbooks);
  FLogbooks := TLogbookPresenter.Create(AStore, Self, ASaveRecent);
  FLogbooks.SetRecentLogbooks(ARecent);
end;

procedure TMainForm.EnableDemo;
begin
  FDemo := True;
  Caption := 'MuninnLog — demo';
  UpdateEntryEnabled;
end;

procedure TMainForm.UpdateEntryEnabled;
begin
  FEntryPanel.Enabled := FDemo or ((FLogbooks <> nil) and FLogbooks.HasLogbook);
  FCloseItem.Enabled := (FLogbooks <> nil) and FLogbooks.HasLogbook;
end;

function LogbookDialogFilter: string;
begin
  Result := 'MuninnLog logbook (*.muninnlog)|*.muninnlog|' +
    'SQLite file (*.sqlite)|*.sqlite|All files|*';
end;

procedure TMainForm.NewLogbookClick(Sender: TObject);
var
  Dialog: TSaveDialog;
begin
  if FLogbooks = nil then
    Exit;
  Dialog := TSaveDialog.Create(Self);
  try
    Dialog.Title := 'New logbook';
    Dialog.Filter := LogbookDialogFilter;
    Dialog.DefaultExt := 'muninnlog';
    Dialog.Options := Dialog.Options + [ofOverwritePrompt];
    if Dialog.Execute then
      FLogbooks.NewRequested(Dialog.FileName);
  finally
    Dialog.Free;
  end;
end;

procedure TMainForm.OpenLogbookClick(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  if FLogbooks = nil then
    Exit;
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Title := 'Open logbook';
    Dialog.Filter := LogbookDialogFilter;
    Dialog.Options := Dialog.Options + [ofFileMustExist];
    if Dialog.Execute then
      FLogbooks.OpenRequested(Dialog.FileName);
  finally
    Dialog.Free;
  end;
end;

procedure TMainForm.RecentLogbookClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := (Sender as TMenuItem).Tag;
  if (FLogbooks <> nil) and (Index < FLogbooks.Recent.Count) then
    FLogbooks.OpenRequested(FLogbooks.Recent[Index]);
end;

procedure TMainForm.CloseLogbookClick(Sender: TObject);
begin
  if FLogbooks <> nil then
    FLogbooks.CloseRequested;
end;

procedure TMainForm.QuitClick(Sender: TObject);
begin
  Close;
end;

procedure TMainForm.ShowLogbook(const APath: string; const AQsoCount: Int64);
begin
  LeaveLogbook;
  Caption := ExtractFileName(APath) + ' - MuninnLog';
  FLogbookPath := APath;
  FQsoCount := AQsoCount;
  FLogbookText := Format('%s   %d QSOs', [FLogbookPath, FQsoCount]);
  UseLogbook;
  UpdateStatusBar;
  UpdateEntryEnabled;
  FocusCall;
end;

procedure TMainForm.ShowNoLogbook;
begin
  LeaveLogbook;
  if not FDemo then
    Caption := 'MuninnLog';
  FLogbookText := 'No logbook open. Use File > New logbook or Open logbook.';
  FSaveText := '';
  UpdateStatusBar;
  UpdateEntryEnabled;
end;

procedure TMainForm.UseLogbook;
begin
  if (FLogbooks = nil) or not FLogbooks.HasLogbook then
    Exit;
  FLogList.Items.Clear;
  FPresenter.AttachLog(FLogbooks.Logbook.CreateWriter, FLogbooks.Logbook.LoadWorked);
  RefreshWorked;
end;

procedure TMainForm.LeaveLogbook;
var
  Pending: Integer;
begin
  if FPresenter.Writer = nil then
    Exit;
  Pending := FPresenter.PendingCount;
  if not FPresenter.DetachLog(5000) then
    MessageDlg('MuninnLog', Format('%d QSOs could not be saved before the ' +
      'logbook was closed. Check the disk and enter them again.', [Pending]),
      mtWarning, [mbOK], 0);
  FLogList.Items.Clear;
  RefreshWorked;
end;

procedure TMainForm.UpdateStatusBar;
begin
  if FSaveText = '' then
    FStatusBar.SimpleText := FLogbookText
  else
    FStatusBar.SimpleText := FLogbookText + '   |   ' + FSaveText;
end;

procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  Pending: Integer;
begin
  Pending := FPresenter.PendingCount;
  if (Pending = 0) or ((FPresenter.Writer <> nil) and
    FPresenter.Writer.Flush(5000)) then
    Exit;
  CanClose := MessageDlg('MuninnLog', Format('%d QSOs are still waiting to be ' +
    'saved. Quit anyway and lose them?', [FPresenter.PendingCount]),
    mtWarning, [mbYes, mbNo], 0) = mrYes;
end;

procedure TMainForm.ShowLogbookError(const AMessage: string);
begin
  MessageDlg('MuninnLog', AMessage, mtError, [mbOK], 0);
end;

procedure TMainForm.ShowRecentLogbooks(const APaths: TStrings);
var
  Index: Integer;
  Item: TMenuItem;
begin
  FRecentMenu.Clear;
  for Index := 0 to APaths.Count - 1 do
  begin
    Item := TMenuItem.Create(Self);
    Item.Caption := APaths[Index];
    Item.Tag := Index;
    Item.OnClick := @RecentLogbookClick;
    FRecentMenu.Add(Item);
  end;
  FRecentMenu.Enabled := APaths.Count > 0;
end;

procedure TMainForm.PlaceNext(const AControl: TControl);
begin
  { Left-aligned controls line up by Left: give each a larger one. }
  Inc(FNextLeft, 1000);
  AControl.Left := FNextLeft;
end;

procedure TMainForm.BuildControls;

  procedure AddStatusBar;
  begin
    FStatusBar := TStatusBar.Create(Self);
    FStatusBar.Parent := Self;
    FStatusBar.SimplePanel := True;
  end;

var
  Body: TPanel;
  Splitter: TSplitter;
  ModeLabel: TLabel;
begin
  AddStatusBar;
  FEntryPanel := TPanel.Create(Self);
  FEntryPanel.Parent := Self;
  FEntryPanel.Align := alTop;
  FEntryPanel.BevelOuter := bvNone;
  FEntryPanel.AutoSize := True;

  FCallEdit := AddEdit(FEntryPanel, 'Call', 200);
  FCallEdit.Font.Size := 16;
  FCallEdit.Font.Style := [fsBold];
  FCallEdit.CharCase := ecUppercase;
  FCallEdit.OnChange := @CallChanged;
  FRstSentEdit := AddEdit(FEntryPanel, 'Sent', 48);
  FRstSentEdit.Text := '599';
  FRstReceivedEdit := AddEdit(FEntryPanel, 'Rcvd', 48);
  FRstReceivedEdit.Text := '599';

  ModeLabel := TLabel.Create(Self);
  ModeLabel.Parent := FEntryPanel;
  ModeLabel.Caption := 'Mode';
  ModeLabel.Layout := tlCenter;
  ModeLabel.Align := alLeft;
  ModeLabel.BorderSpacing.Left := Scale96ToFont(8);
  PlaceNext(ModeLabel);
  FModeCombo := TComboBox.Create(Self);
  FModeCombo.Parent := FEntryPanel;
  FModeCombo.Style := csDropDownList;
  FModeCombo.Items.AddStrings(Modes);
  FModeCombo.Align := alLeft;
  FModeCombo.BorderSpacing.Around := Scale96ToFont(4);
  FModeCombo.OnChange := @ModeChanged;
  PlaceNext(FModeCombo);

  { Typed in kHz, or set by the band map and the radio. }
  FFrequencyEdit := AddEdit(FEntryPanel, 'kHz', 96);
  FFrequencyEdit.Font.Size := 12;
  FFrequencyEdit.OnChange := @FrequencyChanged;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.Align := alTop;
  FStatusLabel.BorderSpacing.Around := Scale96ToFont(6);
  FStatusLabel.Font.Style := [fsBold];
  FStatusLabel.Caption := ' ';
  { Below the entry line. }
  FStatusLabel.Top := FEntryPanel.Top + FEntryPanel.Height + 1;

  FBandmap := TBandmapControl.Create(Self, FBandmapModel);
  FBandmap.Parent := Self;
  FBandmap.Align := alRight;
  FBandmap.Width := Scale96ToScreen(280);
  FBandmap.Theme := FTheme;
  FBandmap.OnTune := @BandmapTune;
  Splitter := TSplitter.Create(Self);
  Splitter.Parent := Self;
  Splitter.Align := alRight;
  Splitter.Left := FBandmap.Left - 1;

  Body := TPanel.Create(Self);
  Body.Parent := Self;
  Body.Align := alClient;
  Body.BevelOuter := bvNone;
  FPartialList := TListBox.Create(Self);
  FPartialList.Parent := Body;
  FPartialList.Align := alTop;
  FPartialList.Height := Scale96ToScreen(140);
  FPartialList.TabStop := False;
  FLogList := TListBox.Create(Self);
  FLogList.Parent := Body;
  FLogList.Align := alClient;
  FLogList.TabStop := False;
  FLogList.Font.Name := 'Monospace';
  {$IFDEF WINDOWS}FLogList.Font.Name := 'Consolas';{$ENDIF}
  {$IFDEF DARWIN}FLogList.Font.Name := 'Menlo';{$ENDIF}

  ActiveControl := FCallEdit;
end;

procedure TMainForm.CallChanged(Sender: TObject);
begin
  FPresenter.CallsignChanged(FCallEdit.Text);
  FBandmapModel.SetHighlight(FPresenter.NormalizedCall);
  FBandmap.Invalidate;
end;

procedure TMainForm.ModeChanged(Sender: TObject);
var
  Mode: TMode;
begin
  { USB and LSB are shown as on the radio; they stand for SSB/USB, SSB/LSB. }
  if (FModeCombo.ItemIndex >= 0) and
    TMode.TryParseDisplay(FModeCombo.Items[FModeCombo.ItemIndex], Mode) then
  begin
    FPresenter.SetMode(Mode);
    RefreshWorked;
  end;
end;

procedure TMainForm.RefreshWorked;
begin
  { Worked depends on the band and the mode, so ask the log again. }
  FBandmapModel.UpdateWorked(@FPresenter.IsWorked);
  FBandmap.Invalidate;
end;

procedure TMainForm.EntryKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        FPresenter.LogRequested(FRstSentEdit.Text, FRstReceivedEdit.Text);
        Key := 0;
      end;
    VK_ESCAPE:
      begin
        ClearEntry;
        Key := 0;
      end;
  end;
end;

procedure TMainForm.BandmapTune(Sender: TObject; const AHz: Int64);
begin
  Tune(AHz);
  FocusCall;
end;

procedure TMainForm.Tune(const AHz: Int64);
var
  Frequency: TFrequencyHz;
begin
  if not TFrequencyHz.TryFromHz(AHz, Frequency) then
    Exit;
  FPresenter.SetFrequency(Frequency);
  FBandmapModel.SetCurrentFrequency(Frequency);
  FSettingFrequency := True;
  try
    FFrequencyEdit.Text := FormatFloat('0.###', AHz / 1000);
  finally
    FSettingFrequency := False;
  end;
  RefreshWorked;
end;

procedure TMainForm.FrequencyChanged(Sender: TObject);
begin
  if FSettingFrequency then
    Exit;
  if FPresenter.FrequencyTextChanged(FFrequencyEdit.Text) then
  begin
    FBandmapModel.SetCurrentFrequency(FPresenter.Frequency);
    RefreshWorked;
  end;
end;

procedure TMainForm.FocusCall;
begin
  { Not before the window is shown (the LCL raises then). }
  if Showing and FCallEdit.CanFocus then
    FCallEdit.SetFocus;
end;

procedure TMainForm.ApplyTheme(const ATheme: TUiTheme);
begin
  FTheme := ATheme;
  FBandmap.Theme := ATheme;
  ShowStatus;
end;

procedure TMainForm.ShowStatus;
begin
  if FProblem <> '' then
  begin
    FStatusLabel.Caption := 'Check the call: ' + FProblem;
    FStatusLabel.Font.Color := FTheme.Warning;
  end
  else if FDuplicate then
  begin
    FStatusLabel.Caption := 'DUPE — already worked on this band and mode';
    FStatusLabel.Font.Color := FTheme.Warning;
  end
  else
  begin
    FStatusLabel.Caption := ' ';
    FStatusLabel.Font.Color := clDefault;
  end;
end;

procedure TMainForm.ShowCallsignState(const ANormalized, AProblem: string);
begin
  FProblem := AProblem;
  ShowStatus;
end;

procedure TMainForm.ShowPartialMatches(const AMatches: TCallList;
  const ATotal: Integer);
var
  Index: Integer;
begin
  FPartialList.Items.BeginUpdate;
  try
    FPartialList.Items.Clear;
    for Index := 0 to High(AMatches) do
      FPartialList.Items.Add(AMatches[Index]);
    if ATotal > Length(AMatches) then
      FPartialList.Items.Add(Format('… %d more', [ATotal - Length(AMatches)]));
  finally
    FPartialList.Items.EndUpdate;
  end;
end;

procedure TMainForm.ShowDuplicate(const AIsDuplicate: Boolean);
begin
  FDuplicate := AIsDuplicate;
  ShowStatus;
end;

function SaveStateText(const AState: TQsoSaveState): string;
begin
  { Words, not only colours (ADR 0009). }
  case AState of
    qssMemoryOnly: Result := '[demo]';
    qssPending: Result := '[saving]';
    qssSaved: Result := '[saved]';
  else
    Result := '[NOT SAVED - retrying]';
  end;
end;

procedure TMainForm.ShowLogged(const AQso: TLoggedQso);
var
  Instant: TUtcInstant;
begin
  RefreshWorked;
  Instant := TUtcInstant.FromUnixMs(AQso.TimeOnUtcMs);
  FLogList.Items.InsertObject(0, Format('%s  %-12s %10s  %-8s %-3s %-3s  %s',
    [Instant.ToIso8601, AQso.Call.ToString,
     FormatFloat('0.0', AQso.Frequency.Hz / 1000), AQso.Mode.DisplayName,
     AQso.RstSent, AQso.RstReceived, SaveStateText(AQso.SaveState)]),
    TObject(PtrInt(AQso.Ticket)));
end;

procedure TMainForm.ShowSaveState(const ATicket: Int64; const AState: TQsoSaveState;
  const AMessage: string);
var
  Index, Mark: Integer;
  Row: string;
begin
  for Index := 0 to FLogList.Items.Count - 1 do
    if PtrInt(FLogList.Items.Objects[Index]) = ATicket then
    begin
      Row := FLogList.Items[Index];
      Mark := LastDelimiter('[', Row);
      if Mark > 0 then
        FLogList.Items[Index] := Copy(Row, 1, Mark - 1) + SaveStateText(AState);
      Break;
    end;
  if AState = qssSaved then
  begin
    Inc(FQsoCount);
    FLogbookText := Format('%s   %d QSOs', [FLogbookPath, FQsoCount]);
    UpdateStatusBar;
  end;
end;

procedure TMainForm.ShowSaveStatus(const APending: Integer;
  const ALastSavedUtcMs: Int64; const ALastError: string);
begin
  if ALastError <> '' then
    FSaveText := Format('NOT SAVED: %s (%d waiting, retrying)', [ALastError, APending])
  else if APending > 0 then
    FSaveText := Format('saving %d', [APending])
  else if ALastSavedUtcMs > 0 then
    FSaveText := 'saved ' + Copy(TUtcInstant.FromUnixMs(ALastSavedUtcMs).ToIso8601, 12, 8) + ' UTC'
  else
    FSaveText := '';
  UpdateStatusBar;
end;

procedure TMainForm.ClearEntry;
begin
  FCallEdit.Text := '';
  FocusCall;
end;

end.
