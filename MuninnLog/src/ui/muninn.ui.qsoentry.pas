unit Muninn.UI.QsoEntry;

{ The QSO entry line, without the LCL (ADR 0009). The view forwards each
  keystroke's text; the presenter normalizes the callsign, checks it, finds
  partial matches and duplicates, and logs the QSO on Enter.

  Everything here runs on the UI thread and must stay fast: it runs on every
  keystroke (the measured budget is in ADR 0009). }

{$mode objfpc}{$H+}

interface

uses
  Classes, Muninn.Core.Callsign, Muninn.Core.Frequency, Muninn.Core.Mode;

type
  TLoggedQso = record
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
    function WorkedKey(const ACall: string; const AFrequency: TFrequencyHz;
      const AHasFrequency: Boolean): string;
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
    property LoggedCount: Integer read FLoggedCount;
    property Logged[AIndex: Integer]: TLoggedQso read GetLogged;
  end;

implementation

uses
  SysUtils, Muninn.Core.Band;

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
  FWorked := TStringList.Create;
  FWorked.Sorted := True;
  FWorked.Duplicates := dupIgnore;
  FWorked.CaseSensitive := True;
  FLoggedCalls := TStringList.Create;
  FLoggedCalls.Sorted := True;
  FLoggedCalls.Duplicates := dupIgnore;
  FLoggedCalls.CaseSensitive := True;
  if not TMode.TryCreate('CW', '', FMode) then
    raise EInvalidOperation.Create('CW is not a mode');
end;

destructor TQsoEntryPresenter.Destroy;
begin
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

procedure TQsoEntryPresenter.SetMode(const AMode: TMode);
begin
  FMode := AMode;
  Refresh;
end;

function TQsoEntryPresenter.WorkedKey(const ACall: string;
  const AFrequency: TFrequencyHz; const AHasFrequency: Boolean): string;
var
  Band: TBand;
  BandName: string;
begin
  { A duplicate is the same call on the same band and mode. }
  if AHasFrequency and TryBandOfFrequency(AFrequency, Band) then
    BandName := BandAdifName(Band)
  else
    BandName := '?';
  Result := ACall + #9 + BandName + #9 + FMode.Mode;
end;

function TQsoEntryPresenter.IsDuplicate(const ACall: string): Boolean;
var
  Index: Integer;
begin
  Result := (ACall <> '') and
    FWorked.Find(WorkedKey(ACall, FFrequency, FHasFrequency), Index);
end;

function TQsoEntryPresenter.IsWorked(const ACall: string;
  const AFrequency: TFrequencyHz): Boolean;
var
  Index: Integer;
begin
  Result := (ACall <> '') and FLoggedCalls.Find(ACall, Index) and
    FWorked.Find(WorkedKey(ACall, AFrequency, True), Index);
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
  if FLoggedCount = Length(FLogged) then
    SetLength(FLogged, FLoggedCount * 2 + 16);
  FLogged[FLoggedCount] := Qso;
  Inc(FLoggedCount);
  FWorked.Add(WorkedKey(Qso.Call.ToString, FFrequency, FHasFrequency));
  FLoggedCalls.Add(Qso.Call.ToString);
  FKnownCalls.Add(Qso.Call.ToString);
  FView.ShowLogged(Qso);
  FText := '';
  FView.ClearEntry;
  Refresh;
  Result := True;
end;

end.
