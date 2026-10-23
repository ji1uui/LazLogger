unit Muninn.UI.QsoEntry;

{ The QSO entry line, without the LCL (ADR 0009, ADR 0011). The view forwards
  each keystroke's text; the presenter normalizes the callsign, checks it,
  finds partial matches and duplicates, and logs the QSO on Enter.

  With a writer attached (an open logbook), Enter hands the QSO to the
  writer and returns at once; the QSO is shown as pending until the writer
  reports it saved. Without one (the demo), QSOs stay in memory.

  Everything here runs on the UI thread and must stay fast: it runs on every
  keystroke (the measured budget is in ADR 0009). }

{$mode objfpc}{$H+}

interface

uses
  Classes, Muninn.Core.Callsign, Muninn.Core.Frequency, Muninn.Core.Mode,
  Muninn.Core.Logbook, Muninn.Core.QsoWriter;

type
  TQsoSaveState = (
    { The demo: not saved anywhere. }
    qssMemoryOnly,
    qssPending,
    qssSaved,
    { The writer reported an error; it keeps trying. }
    qssFailed);

  TLoggedQso = record
    { The writer's ticket; 0 without a writer. }
    Ticket: Int64;
    SaveState: TQsoSaveState;
    Call: TCallsign;
    Frequency: TFrequencyHz;
    Mode: TMode;
    RstSent: string;
    RstReceived: string;
    TimeOnUtcMs: Int64;
  end;

  TCallList = array of string;

  IQsoEntryView = interface
    ['{5C3F0B6E-2D7A-4E19-9A4B-7F1E8C2D6A53}']
    { AProblem is '' when the callsign is valid (or still empty). }
    procedure ShowCallsignState(const ANormalized, AProblem: string);
    { The first matches, and how many there are in all. }
    procedure ShowPartialMatches(const AMatches: TCallList; const ATotal: Integer);
    procedure ShowDuplicate(const AIsDuplicate: Boolean);
    procedure ShowLogged(const AQso: TLoggedQso);
    procedure ClearEntry;
    { A QSO shown by ShowLogged changed state; AMessage explains a failure. }
    procedure ShowSaveState(const ATicket: Int64; const AState: TQsoSaveState;
      const AMessage: string);
    { How many QSOs wait to be saved, when the last one was saved (UTC Unix
      ms, 0 for none yet), and the last error ('' after a success). }
    procedure ShowSaveStatus(const APending: Integer; const ALastSavedUtcMs: Int64;
      const ALastError: string);
  end;

  { Returns the current time as UTC Unix milliseconds. }
  TUtcClock = function: Int64 of object;

  TQsoEntryPresenter = class
  private
    FView: IQsoEntryView;
    FClock: TUtcClock;
    FKnownCalls: TStringList;
    FWorked: TStringList;
    { The calls in the log, to rule out most spots without building a key. }
    FLoggedCalls: TStringList;
    FLogged: array of TLoggedQso;
    FLoggedCount: Integer;
    FText: string;
    FNormalized: string;
    FFrequency: TFrequencyHz;
    FHasFrequency: Boolean;
    FMode: TMode;
    FWriter: IQsoWriter;
    FLastSavedUtcMs: Int64;
    FLastError: string;
    function BandName(const AFrequency: TFrequencyHz;
      const AHasFrequency: Boolean): string;
    function WorkedKey(const ACall, ABand, AMode: string): string;
    procedure AddWorked(const ACall, ABand, AMode: string);
    function IndexOfTicket(const ATicket: Int64): Integer;
    procedure WriterSaved(const ATicket: Int64; const AQsoId: string);
    procedure WriterFailed(const ATicket: Int64; const AMessage: string);
    procedure ShowStatus;
    function Submit(const AQso: TLoggedQso; out ATicket: Int64): Boolean;
    function CallsignProblem(const AError: TCallsignError): string;
    procedure Refresh;
    function GetLogged(AIndex: Integer): TLoggedQso;
  public
    const
      MaxPartialMatches = 20;
    constructor Create(const AView: IQsoEntryView; const AClock: TUtcClock);
    destructor Destroy; override;
    { The call history for the partial check (any case; duplicates are
      dropped). }
    procedure SetKnownCalls(const ACalls: TStrings);
    procedure SetFrequency(const AFrequency: TFrequencyHz);
    { The frequency field changed: kHz with an optional decimal point
      ('7010', '14074.5'). False, and the frequency unchanged, when it is not
      a frequency. }
    function FrequencyTextChanged(const AText: string): Boolean;
    { Logs into AWriter from now on; AWorked is the logbook's QSOs, for the
      duplicate and partial check. }
    procedure AttachLog(const AWriter: IQsoWriter; const AWorked: TWorkedEntries);
    { Stops using the writer after waiting up to ATimeoutMs for it to save
      what it has; False when QSOs were still waiting. Forgets the log's
      QSOs. }
    function DetachLog(const ATimeoutMs: Cardinal): Boolean;
    function PendingCount: Integer;
    procedure SetMode(const AMode: TMode);
    { The callsign field changed. }
    procedure CallsignChanged(const AText: string);
    { Logs the entry. Returns False and shows the problem when the callsign
      is not valid or no frequency is set. }
    function LogRequested(const ARstSent, ARstReceived: string): Boolean;
    { ACall is in the log on the current frequency's band and mode. }
    function IsDuplicate(const ACall: string): Boolean;
    { ACall is in the log on AFrequency's band and the current mode. }
    function IsWorked(const ACall: string; const AFrequency: TFrequencyHz): Boolean;
    property NormalizedCall: string read FNormalized;
    property Writer: IQsoWriter read FWriter;
    { Valid once a frequency was set. }
    property Frequency: TFrequencyHz read FFrequency;
    property LoggedCount: Integer read FLoggedCount;
    property Logged[AIndex: Integer]: TLoggedQso read GetLogged;
  end;

implementation

uses
  SysUtils, Muninn.Core.Band, Muninn.Core.Qso, Muninn.Core.Time;

function IsDigits(const AText: string): Boolean;
var
  Index: Integer;
begin
  Result := AText <> '';
  for Index := 1 to Length(AText) do
    if not (AText[Index] in ['0'..'9']) then
      Exit(False);
end;

{ kHz to Hz without floating point: '14074.5' -> 14074500. Digits only (no
  sign, no hex), at most Hz resolution. }
function TryParseKilohertz(const AText: string; out AHz: Int64): Boolean;
var
  Text, Whole, Fraction: string;
  Dot: Integer;
begin
  Result := False;
  AHz := 0;
  Text := Trim(AText);
  Dot := Pos('.', Text);
  if Dot = 0 then
    Dot := Pos(',', Text);
  if Dot > 0 then
  begin
    Whole := Copy(Text, 1, Dot - 1);
    Fraction := Copy(Text, Dot + 1, MaxInt);
    if not IsDigits(Fraction) or (Length(Fraction) > 3) then
      Exit;
  end
  else
  begin
    Whole := Text;
    Fraction := '';
  end;
  if not IsDigits(Whole) or (Length(Whole) > 9) then
    Exit;
  while Length(Fraction) < 3 do
    Fraction := Fraction + '0';
  AHz := StrToInt64(Whole) * 1000 + StrToInt64(Fraction);
  Result := AHz > 0;
end;

{ Sorts AList and drops repeated strings, then keeps it sorted. The lists
  compare bytes (UseLocale is False): calls and keys are ASCII, and the
  locale's collation is many times slower. }
procedure SortUnique(const AList: TStringList);
var
  Index: Integer;
begin
  AList.Sort;
  for Index := AList.Count - 1 downto 1 do
    if AList[Index] = AList[Index - 1] then
      AList.Delete(Index);
  AList.Sorted := True;
end;

constructor TQsoEntryPresenter.Create(const AView: IQsoEntryView;
  const AClock: TUtcClock);
begin
  inherited Create;
  if AView = nil then
    raise EArgumentNilException.Create('TQsoEntryPresenter needs a view');
  if not Assigned(AClock) then
    raise EArgumentNilException.Create('TQsoEntryPresenter needs a clock');
  FView := AView;
  FClock := AClock;
  FKnownCalls := TStringList.Create;
  FKnownCalls.Sorted := True;
  FKnownCalls.Duplicates := dupIgnore;
  FKnownCalls.CaseSensitive := True;
  FKnownCalls.UseLocale := False;
  FWorked := TStringList.Create;
  FWorked.Sorted := True;
  FWorked.Duplicates := dupIgnore;
  FWorked.CaseSensitive := True;
  FWorked.UseLocale := False;
  FLoggedCalls := TStringList.Create;
  FLoggedCalls.Sorted := True;
  FLoggedCalls.Duplicates := dupIgnore;
  FLoggedCalls.CaseSensitive := True;
  FLoggedCalls.UseLocale := False;
  if not TMode.TryCreate('CW', '', FMode) then
    raise EInvalidOperation.Create('CW is not a mode');
end;

destructor TQsoEntryPresenter.Destroy;
begin
  if FWriter <> nil then
  begin
    FWriter.SetOnSaved(nil);
    FWriter.SetOnFailed(nil);
    FWriter := nil;
  end;
  FLoggedCalls.Free;
  FWorked.Free;
  FKnownCalls.Free;
  FView := nil;
  inherited Destroy;
end;

function TQsoEntryPresenter.GetLogged(AIndex: Integer): TLoggedQso;
begin
  if (AIndex < 0) or (AIndex >= FLoggedCount) then
    raise EArgumentOutOfRangeException.CreateFmt('QSO %d of %d',
      [AIndex, FLoggedCount]);
  Result := FLogged[AIndex];
end;

procedure TQsoEntryPresenter.SetKnownCalls(const ACalls: TStrings);
var
  Index: Integer;
  Call: string;
begin
  FKnownCalls.BeginUpdate;
  try
    FKnownCalls.Clear;
    for Index := 0 to ACalls.Count - 1 do
    begin
      Call := NormalizeCallsignInput(ACalls[Index]);
      if Call <> '' then
        FKnownCalls.Add(Call);
    end;
  finally
    FKnownCalls.EndUpdate;
  end;
  Refresh;
end;

procedure TQsoEntryPresenter.SetFrequency(const AFrequency: TFrequencyHz);
begin
  FFrequency := AFrequency;
  FHasFrequency := True;
  Refresh;
end;

function TQsoEntryPresenter.FrequencyTextChanged(const AText: string): Boolean;
var
  Hz: Int64;
  Typed: TFrequencyHz;
begin
  Result := TryParseKilohertz(AText, Hz) and TFrequencyHz.TryFromHz(Hz, Typed);
  if Result then
    SetFrequency(Typed);
end;

procedure TQsoEntryPresenter.AddWorked(const ACall, ABand, AMode: string);
begin
  FWorked.Add(WorkedKey(ACall, ABand, AMode));
  FLoggedCalls.Add(ACall);
  FKnownCalls.Add(ACall);
end;

procedure TQsoEntryPresenter.AttachLog(const AWriter: IQsoWriter;
  const AWorked: TWorkedEntries);
var
  Index: Integer;
begin
  if FWriter <> nil then
    raise EInvalidOperation.Create('a log is already attached');
  FWriter := AWriter;
  FLastSavedUtcMs := 0;
  FLastError := '';
  { Appending to a sorted list moves its tail each time; for a large log,
    append unsorted and sort once. }
  FWorked.Sorted := False;
  FLoggedCalls.Sorted := False;
  FKnownCalls.Sorted := False;
  try
    for Index := 0 to High(AWorked) do
    begin
      FWorked.Add(WorkedKey(AWorked[Index].Call, AWorked[Index].Band,
        AWorked[Index].Mode));
      FLoggedCalls.Add(AWorked[Index].Call);
      FKnownCalls.Add(AWorked[Index].Call);
    end;
  finally
    SortUnique(FWorked);
    SortUnique(FLoggedCalls);
    SortUnique(FKnownCalls);
  end;
  if FWriter <> nil then
  begin
    FWriter.SetOnSaved(@WriterSaved);
    FWriter.SetOnFailed(@WriterFailed);
  end;
  ShowStatus;
  Refresh;
end;

function TQsoEntryPresenter.DetachLog(const ATimeoutMs: Cardinal): Boolean;
begin
  Result := True;
  if FWriter <> nil then
  begin
    Result := FWriter.Flush(ATimeoutMs);
    FWriter.SetOnSaved(nil);
    FWriter.SetOnFailed(nil);
    FWriter := nil;
  end;
  FWorked.Clear;
  FLoggedCalls.Clear;
  FKnownCalls.Clear;
  FLoggedCount := 0;
  FLogged := nil;
  Refresh;
end;

function TQsoEntryPresenter.PendingCount: Integer;
begin
  if FWriter = nil then
    Result := 0
  else
    Result := FWriter.PendingCount;
end;

function TQsoEntryPresenter.IndexOfTicket(const ATicket: Int64): Integer;
begin
  { Recent QSOs are at the end, and results come in order. }
  for Result := FLoggedCount - 1 downto 0 do
    if FLogged[Result].Ticket = ATicket then
      Exit;
  Result := -1;
end;

procedure TQsoEntryPresenter.ShowStatus;
begin
  FView.ShowSaveStatus(PendingCount, FLastSavedUtcMs, FLastError);
end;

procedure TQsoEntryPresenter.WriterSaved(const ATicket: Int64; const AQsoId: string);
var
  Index: Integer;
begin
  Index := IndexOfTicket(ATicket);
  if Index >= 0 then
    FLogged[Index].SaveState := qssSaved;
  FLastSavedUtcMs := FClock();
  FLastError := '';
  FView.ShowSaveState(ATicket, qssSaved, '');
  ShowStatus;
end;

procedure TQsoEntryPresenter.WriterFailed(const ATicket: Int64; const AMessage: string);
var
  Index: Integer;
begin
  Index := IndexOfTicket(ATicket);
  if Index >= 0 then
    FLogged[Index].SaveState := qssFailed;
  FLastError := AMessage;
  FView.ShowSaveState(ATicket, qssFailed, AMessage);
  ShowStatus;
end;

procedure TQsoEntryPresenter.SetMode(const AMode: TMode);
begin
  FMode := AMode;
  Refresh;
end;

function TQsoEntryPresenter.BandName(const AFrequency: TFrequencyHz;
  const AHasFrequency: Boolean): string;
var
  Band: TBand;
begin
  if AHasFrequency and TryBandOfFrequency(AFrequency, Band) then
    Result := BandAdifName(Band)
  else
    Result := '';
end;

function TQsoEntryPresenter.WorkedKey(const ACall, ABand, AMode: string): string;
begin
  { A duplicate is the same call on the same band and mode. A QSO without a
    band matches no band. }
  if ABand = '' then
    Result := ACall + #9 + '?' + #9 + AMode
  else
    Result := ACall + #9 + ABand + #9 + AMode;
end;

function TQsoEntryPresenter.IsDuplicate(const ACall: string): Boolean;
var
  Index: Integer;
begin
  Result := (ACall <> '') and FHasFrequency and
    FWorked.Find(WorkedKey(ACall, BandName(FFrequency, True), FMode.Mode), Index);
end;

function TQsoEntryPresenter.IsWorked(const ACall: string;
  const AFrequency: TFrequencyHz): Boolean;
var
  Index: Integer;
begin
  Result := (ACall <> '') and FLoggedCalls.Find(ACall, Index) and
    FWorked.Find(WorkedKey(ACall, BandName(AFrequency, True), FMode.Mode), Index);
end;

function TQsoEntryPresenter.CallsignProblem(const AError: TCallsignError): string;
begin
  case AError of
    ceNone, ceEmpty: Result := '';
    ceTooShort: Result := 'too short';
    ceTooLong: Result := 'too long';
    ceInvalidCharacter: Result := 'invalid character';
    ceMissingDigit: Result := 'no digit';
    ceMissingLetter: Result := 'no letter';
    ceInvalidSeparator: Result := 'misplaced /';
  else
    Result := 'invalid';
  end;
end;

procedure TQsoEntryPresenter.CallsignChanged(const AText: string);
begin
  FText := AText;
  Refresh;
end;

procedure TQsoEntryPresenter.Refresh;
var
  Call: TCallsign;
  Error: TCallsignError;
  Problem: string;
  Matches: TCallList;
  Index, Total: Integer;
begin
  FNormalized := NormalizeCallsignInput(FText);
  Problem := '';
  { While typing, show only what more typing cannot fix: 'JA' (no digit)
    and 'JA1/' (separator) are calls not finished yet. }
  if (FNormalized <> '') and not TCallsign.TryCreate(FNormalized, Call, Error) and
    (Error in [ceInvalidCharacter, ceTooLong]) then
    Problem := CallsignProblem(Error);
  FView.ShowCallsignState(FNormalized, Problem);

  Matches := nil;
  Total := 0;
  { One character matches most of the list; start from two. }
  if Length(FNormalized) >= 2 then
  begin
    SetLength(Matches, MaxPartialMatches);
    for Index := 0 to FKnownCalls.Count - 1 do
      if Pos(FNormalized, FKnownCalls[Index]) > 0 then
      begin
        if Total < MaxPartialMatches then
          Matches[Total] := FKnownCalls[Index];
        Inc(Total);
      end;
    if Total < MaxPartialMatches then
      SetLength(Matches, Total);
  end;
  FView.ShowPartialMatches(Matches, Total);
  FView.ShowDuplicate(IsDuplicate(FNormalized));
end;

function TQsoEntryPresenter.Submit(const AQso: TLoggedQso; out ATicket: Int64): Boolean;
var
  Record_: TQsoRecord;
  Band: string;
begin
  Record_ := TQsoRecord.Create;
  Record_.Call := AQso.Call.ToString;
  Record_.TimeOn := TUtcInstant.FromUnixMs(AQso.TimeOnUtcMs);
  Record_.FrequencyHz := AQso.Frequency.Hz;
  Band := BandName(AQso.Frequency, True);
  Record_.Band := Band;
  Record_.Mode := AQso.Mode;
  if AQso.RstSent <> '' then
    Record_.OtherFields.Add('RST_SENT', AQso.RstSent);
  if AQso.RstReceived <> '' then
    Record_.OtherFields.Add('RST_RCVD', AQso.RstReceived);
  try
    { Submit owns the record from here on, also when it raises. }
    ATicket := FWriter.Submit(Record_);
    Result := True;
  except
    on E: EQsoQueueFull do
    begin
      FView.ShowCallsignState(FNormalized, 'not logged: ' + E.Message);
      Result := False;
    end;
  end;
end;

function TQsoEntryPresenter.LogRequested(const ARstSent, ARstReceived: string): Boolean;
var
  Qso: TLoggedQso;
  Error: TCallsignError;
begin
  Result := False;
  if not TCallsign.TryCreate(FNormalized, Qso.Call, Error) then
  begin
    if Error = ceEmpty then
      FView.ShowCallsignState(FNormalized, 'no callsign')
    else
      FView.ShowCallsignState(FNormalized, CallsignProblem(Error));
    Exit;
  end;
  if not FHasFrequency then
  begin
    FView.ShowCallsignState(FNormalized, 'no frequency');
    Exit;
  end;
  Qso.Frequency := FFrequency;
  Qso.Mode := FMode;
  Qso.RstSent := Trim(ARstSent);
  Qso.RstReceived := Trim(ARstReceived);
  Qso.TimeOnUtcMs := FClock();
  Qso.Ticket := 0;
  Qso.SaveState := qssMemoryOnly;
  if FWriter <> nil then
  begin
    if not Submit(Qso, Qso.Ticket) then
      Exit;
    Qso.SaveState := qssPending;
  end;
  if FLoggedCount = Length(FLogged) then
    SetLength(FLogged, FLoggedCount * 2 + 16);
  FLogged[FLoggedCount] := Qso;
  Inc(FLoggedCount);
  AddWorked(Qso.Call.ToString, BandName(FFrequency, True), FMode.Mode);
  FView.ShowLogged(Qso);
  if FWriter <> nil then
    ShowStatus;
  FText := '';
  FView.ClearEntry;
  Refresh;
  Result := True;
end;

end.
