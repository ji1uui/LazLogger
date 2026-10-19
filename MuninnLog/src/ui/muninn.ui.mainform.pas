unit Muninn.UI.MainForm;

{ The prototype's window (T10, ADR 0009): the QSO entry line, the partial
  check list, the log, and the band map. The form only lays out controls and
  forwards events; TQsoEntryPresenter decides what to show.

  Keys: Enter logs the entry, Esc clears it. A click on the band map tunes. }

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Graphics,
  Muninn.Core.Frequency, Muninn.Core.Mode, Muninn.UI.Bandmap,
  Muninn.UI.BandmapView, Muninn.UI.QsoEntry, Muninn.UI.Theme;

type
  TMainForm = class(TForm, IQsoEntryView)
  private
    FTheme: TUiTheme;
    FBandmapModel: TBandmapModel;
    FPresenter: TQsoEntryPresenter;
    FEntryPanel: TPanel;
    FCallEdit: TEdit;
    FRstSentEdit: TEdit;
    FRstReceivedEdit: TEdit;
    FModeCombo: TComboBox;
    FFrequencyLabel: TLabel;
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
    procedure Tune(const AHz: Int64);
    { IQsoEntryView }
    procedure ShowCallsignState(const ANormalized, AProblem: string);
    procedure ShowPartialMatches(const AMatches: TCallList; const ATotal: Integer);
    procedure ShowDuplicate(const AIsDuplicate: Boolean);
    procedure ShowLogged(const AQso: TLoggedQso);
    procedure ClearEntry;

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
  Caption := 'MuninnLog — UI prototype';
  Position := poScreenCenter;
  Width := Scale96ToScreen(960);
  Height := Scale96ToScreen(600);
  KeyPreview := True;
  FBandmapModel := TBandmapModel.Create(7000000, 7040000);
  BuildControls;
  FPresenter := TQsoEntryPresenter.Create(Self, @UtcNowMs);
  FModeCombo.ItemIndex := 0;
  ModeChanged(nil);
end;

destructor TMainForm.Destroy;
begin
  { The presenter holds this form as its view. }
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

procedure TMainForm.PlaceNext(const AControl: TControl);
begin
  { Left-aligned controls line up by Left: give each a larger one. }
  Inc(FNextLeft, 1000);
  AControl.Left := FNextLeft;
end;

procedure TMainForm.BuildControls;
var
  Body: TPanel;
  Splitter: TSplitter;
  ModeLabel: TLabel;
begin
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

  FFrequencyLabel := TLabel.Create(Self);
  FFrequencyLabel.Parent := FEntryPanel;
  FFrequencyLabel.Align := alLeft;
  FFrequencyLabel.Layout := tlCenter;
  FFrequencyLabel.BorderSpacing.Left := Scale96ToFont(12);
  FFrequencyLabel.Font.Size := 14;
  FFrequencyLabel.Caption := '— kHz';
  PlaceNext(FFrequencyLabel);

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
  FFrequencyLabel.Caption := FormatFloat('0.0', AHz / 1000) + ' kHz';
  FBandmap.Invalidate;
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

procedure TMainForm.ShowLogged(const AQso: TLoggedQso);
var
  Instant: TUtcInstant;
begin
  RefreshWorked;
  Instant := TUtcInstant.FromUnixMs(AQso.TimeOnUtcMs);
  FLogList.Items.Insert(0, Format('%s  %-12s %10s  %-8s %s %s',
    [Instant.ToIso8601, AQso.Call.ToString,
     FormatFloat('0.0', AQso.Frequency.Hz / 1000), AQso.Mode.DisplayName,
     AQso.RstSent, AQso.RstReceived]));
end;

procedure TMainForm.ClearEntry;
begin
  FCallEdit.Text := '';
  FocusCall;
end;

end.
