unit Muninn.UI.QsoEntry.Tests;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Muninn.Core.Frequency, Muninn.Core.Mode,
  Muninn.Core.Qso, Muninn.Core.QsoWriter, Muninn.Core.Logbook, Muninn.UI.QsoEntry;

type
  { Records what the presenter shows. }
  TFakeEntryView = class(TInterfacedObject, IQsoEntryView)
  public
    Normalized: string;
    Problem: string;
    Matches: TCallList;
    Total: Integer;
    Duplicate: Boolean;
    LoggedCalls: TStringList;
    LoggedStates: array of TQsoSaveState;
    Clears: Integer;
    StateTicket: Int64;
    State: TQsoSaveState;
    StateMessage: string;
    Pending: Integer;
    LastSaved: Int64;
    LastError: string;
    constructor Create;
    destructor Destroy; override;
    procedure ShowCallsignState(const ANormalized, AProblem: string);
    procedure ShowPartialMatches(const AMatches: TCallList; const ATotal: Integer);
    procedure ShowDuplicate(const AIsDuplicate: Boolean);
    procedure ShowLogged(const AQso: TLoggedQso);
    procedure ClearEntry;
    procedure ShowSaveState(const ATicket: Int64; const AState: TQsoSaveState;
      const AMessage: string);
    procedure ShowSaveStatus(const APending: Integer; const ALastSavedUtcMs: Int64;
      const ALastError: string);
  end;

  { Keeps the submitted QSOs; the test reports results. }
  TFakeWriter = class(TInterfacedObject, IQsoWriter)
  public
    Submitted: TList;
    Tickets: array of Int64;
    Full: Boolean;
    OnSaved: TQsoSavedEvent;
    OnFailed: TQsoSaveFailedEvent;
    Flushed: Boolean;
    constructor Create;
    destructor Destroy; override;
    function Submit(const AQso: TQsoRecord): Int64;
    function PendingCount: Integer;
    procedure SetOnSaved(AHandler: TQsoSavedEvent);
    procedure SetOnFailed(AHandler: TQsoSaveFailedEvent);
    function Flush(const ATimeoutMs: Cardinal): Boolean;
    function Qso(const AIndex: Integer): TQsoRecord;
    procedure Save(const AIndex: Integer);
  end;

  TQsoEntryPresenterTests = class(TTestCase)
  private
    FViewObject: TFakeEntryView;
    FView: IQsoEntryView;
    FPresenter: TQsoEntryPresenter;
    function Clock: Int64;
    procedure Tune(const AHz: Int64);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure NormalizesFullWidthInput;
    procedure ReportsOnlyProblemsTypingCannotFix;
    procedure FindsPartialMatches;
    procedure LimitsPartialMatches;
    procedure LogsAndClears;
    procedure RefusesInvalidCallsign;
    procedure RefusesWithoutFrequency;
    procedure FlagsDuplicateOnSameBandAndMode;
    procedure HandsTheQsoToTheWriter;
    procedure ShowsSavedAndFailed;
    procedure KeepsTheEntryWhenTheQueueIsFull;
    procedure UsesTheLogForDuplicatesAndPartials;
    procedure DetachingForgetsTheLog;
    procedure ParsesFrequencyText;
    procedure TellsWorkedForAnyFrequency;
  end;

implementation

constructor TFakeEntryView.Create;
begin
  inherited Create;
  LoggedCalls := TStringList.Create;
end;

destructor TFakeEntryView.Destroy;
begin
  LoggedCalls.Free;
  inherited Destroy;
end;

procedure TFakeEntryView.ShowCallsignState(const ANormalized, AProblem: string);
begin
  Normalized := ANormalized;
  Problem := AProblem;
end;

procedure TFakeEntryView.ShowPartialMatches(const AMatches: TCallList;
  const ATotal: Integer);
begin
  Matches := AMatches;
  Total := ATotal;
end;

procedure TFakeEntryView.ShowDuplicate(const AIsDuplicate: Boolean);
begin
  Duplicate := AIsDuplicate;
end;

procedure TFakeEntryView.ShowLogged(const AQso: TLoggedQso);
begin
  LoggedCalls.Add(AQso.Call.ToString);
end;

procedure TFakeEntryView.ClearEntry;
begin
  Inc(Clears);
end;

procedure TFakeEntryView.ShowSaveState(const ATicket: Int64;
  const AState: TQsoSaveState; const AMessage: string);
begin
  StateTicket := ATicket;
  State := AState;
  StateMessage := AMessage;
end;

procedure TFakeEntryView.ShowSaveStatus(const APending: Integer;
  const ALastSavedUtcMs: Int64; const ALastError: string);
begin
  Pending := APending;
  LastSaved := ALastSavedUtcMs;
  LastError := ALastError;
end;

{ TFakeWriter }

constructor TFakeWriter.Create;
begin
  inherited Create;
  Submitted := TList.Create;
end;

destructor TFakeWriter.Destroy;
var
  Index: Integer;
begin
  for Index := 0 to Submitted.Count - 1 do
    TQsoRecord(Submitted[Index]).Free;
  Submitted.Free;
  inherited Destroy;
end;

function TFakeWriter.Submit(const AQso: TQsoRecord): Int64;
begin
  if Full then
  begin
    AQso.Free;
    raise EQsoQueueFull.Create('1000 QSOs are waiting to be saved');
  end;
  Submitted.Add(AQso);
  Result := 100 + Submitted.Count;
  SetLength(Tickets, Submitted.Count);
  Tickets[High(Tickets)] := Result;
end;

function TFakeWriter.PendingCount: Integer;
begin
  Result := Submitted.Count;
end;

procedure TFakeWriter.SetOnSaved(AHandler: TQsoSavedEvent);
begin
  OnSaved := AHandler;
end;

procedure TFakeWriter.SetOnFailed(AHandler: TQsoSaveFailedEvent);
begin
  OnFailed := AHandler;
end;

function TFakeWriter.Flush(const ATimeoutMs: Cardinal): Boolean;
begin
  Flushed := True;
  Result := Submitted.Count = 0;
end;

function TFakeWriter.Qso(const AIndex: Integer): TQsoRecord;
begin
  Result := TQsoRecord(Submitted[AIndex]);
end;

procedure TFakeWriter.Save(const AIndex: Integer);
var
  Ticket: Int64;
begin
  Ticket := Tickets[AIndex];
  TQsoRecord(Submitted[AIndex]).Free;
  Submitted.Delete(AIndex);
  Delete(Tickets, AIndex, 1);
  OnSaved(Ticket, 'id');
end;

function TQsoEntryPresenterTests.Clock: Int64;
begin
  Result := 1700000000000;
end;

procedure TQsoEntryPresenterTests.SetUp;
var
  Known: TStringList;
begin
  FViewObject := TFakeEntryView.Create;
  FView := FViewObject;
  FPresenter := TQsoEntryPresenter.Create(FView, @Clock);
  Known := TStringList.Create;
  try
    Known.CommaText := 'JA1ABC,ja1abd,JH1XYZ,7K1ABC,JA1ABC';
    FPresenter.SetKnownCalls(Known);
  finally
    Known.Free;
  end;
end;

procedure TQsoEntryPresenterTests.TearDown;
begin
  FPresenter.Free;
  FView := nil;
end;

procedure TQsoEntryPresenterTests.Tune(const AHz: Int64);
var
  Frequency: TFrequencyHz;
begin
  AssertTrue(TFrequencyHz.TryFromHz(AHz, Frequency));
  FPresenter.SetFrequency(Frequency);
end;

procedure TQsoEntryPresenterTests.NormalizesFullWidthInput;
begin
  FPresenter.CallsignChanged('ｊａ１ａｂｃ');
  AssertEquals('JA1ABC', FViewObject.Normalized);
  AssertEquals('', FViewObject.Problem);
end;

procedure TQsoEntryPresenterTests.ReportsOnlyProblemsTypingCannotFix;
begin
  FPresenter.CallsignChanged('JA');
  AssertEquals('no digit yet', '', FViewObject.Problem);
  FPresenter.CallsignChanged('JA1/');
  AssertEquals('separator not finished', '', FViewObject.Problem);
  FPresenter.CallsignChanged('JA1#B');
  AssertEquals('invalid character', FViewObject.Problem);
end;

procedure TQsoEntryPresenterTests.FindsPartialMatches;
begin
  FPresenter.CallsignChanged('1AB');
  AssertEquals(3, FViewObject.Total);
  AssertEquals('7K1ABC', FViewObject.Matches[0]);
  AssertEquals('JA1ABC', FViewObject.Matches[1]);
  AssertEquals('JA1ABD', FViewObject.Matches[2]);
  FPresenter.CallsignChanged('J');
  AssertEquals('one character matches nothing', 0, FViewObject.Total);
end;

procedure TQsoEntryPresenterTests.LimitsPartialMatches;
var
  Known: TStringList;
  Index: Integer;
begin
  Known := TStringList.Create;
  try
    for Index := 0 to 99 do
      Known.Add(Format('JA1A%.2d', [Index]));
    FPresenter.SetKnownCalls(Known);
  finally
    Known.Free;
  end;
  FPresenter.CallsignChanged('JA1A');
  AssertEquals(100, FViewObject.Total);
  AssertEquals(TQsoEntryPresenter.MaxPartialMatches, Length(FViewObject.Matches));
end;

procedure TQsoEntryPresenterTests.LogsAndClears;
begin
  Tune(7010000);
  FPresenter.CallsignChanged('jh1xyz');
  AssertTrue(FPresenter.LogRequested('599', '599'));
  AssertEquals(1, FPresenter.LoggedCount);
  AssertEquals('JH1XYZ', FViewObject.LoggedCalls[0]);
  AssertEquals(1, FViewObject.Clears);
  AssertEquals(7010000, FPresenter.Logged[0].Frequency.Hz);
  AssertEquals('CW', FPresenter.Logged[0].Mode.Mode);
  AssertEquals(1700000000000, FPresenter.Logged[0].TimeOnUtcMs);
  AssertEquals('entry cleared', '', FPresenter.NormalizedCall);
end;

procedure TQsoEntryPresenterTests.RefusesInvalidCallsign;
begin
  Tune(7010000);
  FPresenter.CallsignChanged('JA');
  AssertFalse(FPresenter.LogRequested('599', '599'));
  AssertEquals(0, FPresenter.LoggedCount);
  AssertTrue('problem shown', FViewObject.Problem <> '');
  FPresenter.CallsignChanged('');
  AssertFalse(FPresenter.LogRequested('599', '599'));
  AssertEquals('no callsign', FViewObject.Problem);
end;

procedure TQsoEntryPresenterTests.RefusesWithoutFrequency;
begin
  FPresenter.CallsignChanged('JA1ABC');
  AssertFalse(FPresenter.LogRequested('599', '599'));
  AssertEquals('no frequency', FViewObject.Problem);
end;

procedure TQsoEntryPresenterTests.FlagsDuplicateOnSameBandAndMode;
var
  Ssb: TMode;
begin
  Tune(7010000);
  FPresenter.CallsignChanged('JA1ABC');
  AssertFalse(FViewObject.Duplicate);
  AssertTrue(FPresenter.LogRequested('599', '599'));
  FPresenter.CallsignChanged('JA1ABC');
  AssertTrue('same band and mode', FViewObject.Duplicate);
  Tune(14010000);
  AssertFalse('other band', FViewObject.Duplicate);
  Tune(7020000);
  AssertTrue(TMode.TryCreate('SSB', 'LSB', Ssb));
  FPresenter.SetMode(Ssb);
  AssertFalse('other mode', FViewObject.Duplicate);
end;

procedure TQsoEntryPresenterTests.TellsWorkedForAnyFrequency;
var
  Other, Same: TFrequencyHz;
  Ssb: TMode;
begin
  Tune(7010000);
  FPresenter.CallsignChanged('JA1ABC');
  AssertTrue(FPresenter.LogRequested('599', '599'));
  AssertTrue(TFrequencyHz.TryFromHz(7025000, Same));
  AssertTrue(TFrequencyHz.TryFromHz(14025000, Other));
  AssertTrue('same band', FPresenter.IsWorked('JA1ABC', Same));
  AssertFalse('other band', FPresenter.IsWorked('JA1ABC', Other));
  AssertTrue(TMode.TryCreate('SSB', 'LSB', Ssb));
  FPresenter.SetMode(Ssb);
  AssertFalse('other mode', FPresenter.IsWorked('JA1ABC', Same));
end;

procedure TQsoEntryPresenterTests.HandsTheQsoToTheWriter;
var
  Writer: TFakeWriter;
  WriterRef: IQsoWriter;
  Qso: TQsoRecord;
begin
  Writer := TFakeWriter.Create;
  WriterRef := Writer;
  FPresenter.AttachLog(WriterRef, nil);
  Tune(7010000);
  FPresenter.CallsignChanged('jh1xyz');
  AssertTrue(FPresenter.LogRequested('599', '579'));
  AssertEquals(1, Writer.Submitted.Count);
  Qso := Writer.Qso(0);
  AssertEquals('JH1XYZ', Qso.Call);
  AssertEquals(7010000, Qso.FrequencyHz);
  AssertEquals('40m', Qso.Band);
  AssertEquals('CW', Qso.Mode.Mode);
  AssertEquals(1700000000000, Qso.TimeOn.UnixMs);
  AssertEquals('599', Qso.OtherFields.Value('RST_SENT'));
  AssertEquals('579', Qso.OtherFields.Value('RST_RCVD'));
  AssertTrue('shown as pending', FPresenter.Logged[0].SaveState = qssPending);
  AssertEquals(101, FPresenter.Logged[0].Ticket);
  AssertEquals('pending count shown', 1, FViewObject.Pending);
  AssertEquals('entry cleared at once', 1, FViewObject.Clears);
end;

procedure TQsoEntryPresenterTests.ShowsSavedAndFailed;
var
  Writer: TFakeWriter;
  WriterRef: IQsoWriter;
begin
  Writer := TFakeWriter.Create;
  WriterRef := Writer;
  FPresenter.AttachLog(WriterRef, nil);
  Tune(7010000);
  FPresenter.CallsignChanged('JA1ABC');
  AssertTrue(FPresenter.LogRequested('599', '599'));
  Writer.OnFailed(101, 'disk full');
  AssertTrue(FViewObject.State = qssFailed);
  AssertEquals('disk full', FViewObject.StateMessage);
  AssertEquals('disk full', FViewObject.LastError);
  AssertTrue(FPresenter.Logged[0].SaveState = qssFailed);
  Writer.Save(0);
  AssertTrue('saved after the retry', FViewObject.State = qssSaved);
  AssertEquals(101, FViewObject.StateTicket);
  AssertTrue(FPresenter.Logged[0].SaveState = qssSaved);
  AssertEquals(0, FViewObject.Pending);
  AssertEquals(1700000000000, FViewObject.LastSaved);
  AssertEquals('error cleared', '', FViewObject.LastError);
end;

procedure TQsoEntryPresenterTests.KeepsTheEntryWhenTheQueueIsFull;
var
  Writer: TFakeWriter;
  WriterRef: IQsoWriter;
begin
  Writer := TFakeWriter.Create;
  WriterRef := Writer;
  Writer.Full := True;
  FPresenter.AttachLog(WriterRef, nil);
  Tune(7010000);
  FPresenter.CallsignChanged('JA1ABC');
  AssertFalse(FPresenter.LogRequested('599', '599'));
  AssertEquals('entry kept', 0, FViewObject.Clears);
  AssertEquals(0, FPresenter.LoggedCount);
  AssertTrue('problem shown', Pos('not logged', FViewObject.Problem) = 1);
end;

procedure TQsoEntryPresenterTests.UsesTheLogForDuplicatesAndPartials;
var
  Worked: TWorkedEntries;
  WriterRef: IQsoWriter;
begin
  SetLength(Worked, 2);
  Worked[0].Call := 'JR1QQQ';
  Worked[0].Band := '40m';
  Worked[0].Mode := 'CW';
  Worked[1].Call := 'JR1QQR';
  Worked[1].Band := '';
  Worked[1].Mode := 'CW';
  WriterRef := TFakeWriter.Create;
  FPresenter.AttachLog(WriterRef, Worked);
  Tune(7010000);
  FPresenter.CallsignChanged('JR1QQQ');
  AssertTrue('worked on 40 m CW', FViewObject.Duplicate);
  FPresenter.CallsignChanged('JR1QQR');
  AssertFalse('no band: not a duplicate', FViewObject.Duplicate);
  FPresenter.CallsignChanged('1QQ');
  AssertEquals('both in the partial check', 2, FViewObject.Total);
end;

procedure TQsoEntryPresenterTests.DetachingForgetsTheLog;
var
  Worked: TWorkedEntries;
  Writer: TFakeWriter;
  WriterRef: IQsoWriter;
begin
  SetLength(Worked, 1);
  Worked[0].Call := 'JR1QQQ';
  Worked[0].Band := '40m';
  Worked[0].Mode := 'CW';
  Writer := TFakeWriter.Create;
  WriterRef := Writer;
  FPresenter.AttachLog(WriterRef, Worked);
  AssertTrue(FPresenter.DetachLog(100));
  AssertTrue('flushed', Writer.Flushed);
  AssertTrue('handlers cleared', not Assigned(Writer.OnSaved));
  AssertTrue(FPresenter.Writer = nil);
  Tune(7010000);
  FPresenter.CallsignChanged('JR1QQQ');
  AssertFalse(FViewObject.Duplicate);
end;

procedure TQsoEntryPresenterTests.ParsesFrequencyText;

  procedure Refuse(const AText: string);
  begin
    AssertFalse(AText, FPresenter.FrequencyTextChanged(AText));
  end;

begin
  AssertTrue(FPresenter.FrequencyTextChanged('7010'));
  FPresenter.CallsignChanged('JA1ABC');
  AssertTrue(FPresenter.LogRequested('', ''));
  AssertEquals(7010000, FPresenter.Logged[0].Frequency.Hz);
  AssertTrue(FPresenter.FrequencyTextChanged(' 14074.5 '));
  FPresenter.CallsignChanged('JA1ABD');
  AssertTrue(FPresenter.LogRequested('', ''));
  AssertEquals(14074500, FPresenter.Logged[1].Frequency.Hz);
  AssertTrue('comma as decimal point', FPresenter.FrequencyTextChanged('3573,25'));
  Refuse('');
  Refuse('abc');
  Refuse('-7010');
  Refuse('$1F');
  Refuse('7010.1234');
  Refuse('0');
end;

initialization
  RegisterTest(TQsoEntryPresenterTests);

end.
