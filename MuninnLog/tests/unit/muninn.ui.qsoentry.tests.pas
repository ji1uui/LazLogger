unit Muninn.UI.QsoEntry.Tests;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, fpcunit, testregistry, Muninn.Core.Frequency, Muninn.Core.Mode,
  Muninn.UI.QsoEntry;

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
    Clears: Integer;
    constructor Create;
    destructor Destroy; override;
    procedure ShowCallsignState(const ANormalized, AProblem: string);
    procedure ShowPartialMatches(const AMatches: TCallList; const ATotal: Integer);
    procedure ShowDuplicate(const AIsDuplicate: Boolean);
    procedure ShowLogged(const AQso: TLoggedQso);
    procedure ClearEntry;
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
    procedure TellsWorkedForAnyFrequency;
  end;

implementation

uses
  SysUtils;

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

initialization
  RegisterTest(TQsoEntryPresenterTests);

end.
