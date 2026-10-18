unit Muninn.Core.AdifQso.Tests;

{ Conversion between ADIF records and QSOs, and the golden tests.
  Golden cases live in tests/golden/adif/<case>.adi with the expected export in
  <case>.expected.adi and the expected issues in <case>.issues.txt. Run the
  tests with MUNINN_UPDATE_GOLDEN=1 to rewrite the expected files, then review
  the diff before committing. MUNINN_GOLDEN_DIR overrides the directory. }

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Contnrs, fpcunit, testregistry, Muninn.Core.Adif, Muninn.Core.Qso;

type
  TAdifQsoTests = class(TTestCase)
  private
    FIssues: TAdifIssues;
    FRecord: TAdifRecord;
    function Convert(const AText: string): TQsoRecord;
    function IssueText: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ParsesScaledNumbers;
    procedure FormatsScaledNumbers;
    procedure ConvertsTypedFields;
    procedure KeepsOtherFieldsInOrder;
    procedure RequiresCallTimeAndMode;
    procedure RejectsDatesBefore1930;
    procedure EndTimeBeforeStartIsNextDay;
    procedure DerivesBandFromFrequency;
    procedure WarnsOnBandMismatch;
    procedure KeepsUninterpretableValues;
    procedure ConvertsImportOnlyModes;
    procedure ChecksJapaneseCodes;
    procedure ExportsTypedFieldsFirst;
  end;

  TAdifGoldenTests = class(TTestCase)
  private
    procedure CheckCase(const AName: string);
  published
    procedure WsjtxExport;
    procedure JapaneseDomesticLog;
    procedure CharacterLengths;
  end;

implementation

uses
  Classes, SysUtils, Muninn.Core.Time, Muninn.Core.AdifQso;

procedure TAdifQsoTests.SetUp;
begin
  FIssues := TAdifIssues.Create;
  FRecord := nil;
end;

procedure TAdifQsoTests.TearDown;
begin
  FRecord.Free;
  FIssues.Free;
end;

{ Reads one ADI record and converts it; nil when it is not a QSO. }
function TAdifQsoTests.Convert(const AText: string): TQsoRecord;
var
  Document: TAdifDocument;
begin
  Document := TAdifDocument.Create;
  try
    ReadAdi(AText, Document, FIssues);
    AssertEquals('one record', 1, Document.RecordCount);
    TryAdifRecordToQso(Document[0], 0, FIssues, Result);
  finally
    Document.Free;
  end;
end;

function TAdifQsoTests.IssueText: string;
begin
  Result := FIssues.ToText;
end;

procedure TAdifQsoTests.ParsesScaledNumbers;
var
  Value: Int64;
  Exact: Boolean;
begin
  AssertTrue(TryParseScaledNumber('14.074', 6, Value, Exact));
  AssertEquals(14074000, Value);
  AssertTrue(Exact);
  AssertTrue(TryParseScaledNumber('7', 6, Value, Exact));
  AssertEquals(7000000, Value);
  AssertTrue(TryParseScaledNumber('.5', 3, Value, Exact));
  AssertEquals(500, Value);
  AssertTrue(TryParseScaledNumber('0010.100', 3, Value, Exact));
  AssertEquals('leading zeros', 10100, Value);
  AssertTrue(TryParseScaledNumber('-1.5', 0, Value, Exact));
  AssertEquals('rounds half away from zero', -2, Value);
  AssertFalse(Exact);
  AssertTrue(TryParseScaledNumber('14.0740001', 6, Value, Exact));
  AssertEquals(14074000, Value);
  AssertFalse(Exact);
  AssertTrue(TryParseScaledNumber('14.07400000', 6, Value, Exact));
  AssertTrue('trailing zeros are exact', Exact);
  AssertTrue(TryParseScaledNumber('7500000', 6, Value, Exact));
  AssertEquals('7.5 THz', Int64(7500000000000), Value);
  AssertFalse('empty', TryParseScaledNumber('', 6, Value, Exact));
  AssertFalse('point only', TryParseScaledNumber('.', 6, Value, Exact));
  AssertFalse('comma', TryParseScaledNumber('14,074', 6, Value, Exact));
  AssertFalse('two points', TryParseScaledNumber('1.2.3', 6, Value, Exact));
  AssertFalse('exponent', TryParseScaledNumber('1e3', 6, Value, Exact));
  AssertFalse('too large', TryParseScaledNumber('99999999999999', 6, Value, Exact));
end;

procedure TAdifQsoTests.FormatsScaledNumbers;
begin
  AssertEquals('14.074', FormatScaledNumber(14074000, 6));
  AssertEquals('7', FormatScaledNumber(7000000, 6));
  AssertEquals('0.0005', FormatScaledNumber(500, 6));
  AssertEquals('0', FormatScaledNumber(0, 3));
  AssertEquals('-1.5', FormatScaledNumber(-1500, 3));
  AssertEquals('42', FormatScaledNumber(42, 0));
end;

procedure TAdifQsoTests.ConvertsTypedFields;
var
  Qso: TQsoRecord;
begin
  Qso := Convert('<CALL:6>ja1zzz <QSO_DATE:8>20240512 <TIME_ON:4>0915 ' +
    '<QSO_DATE_OFF:8>20240512 <TIME_OFF:6>091615 <BAND:3>20M <FREQ:9>14.075123 ' +
    '<FREQ_RX:6>14.076 <BAND_RX:3>20m <MODE:4>mfsk <SUBMODE:3>ft4 <TX_PWR:3>0.5 <EOR>');
  try
    AssertEquals('', IssueText);
    AssertEquals('JA1ZZZ', Qso.Call);
    AssertEquals('2024-05-12T09:15:00Z', Qso.TimeOn.ToIso8601);
    AssertTrue(Qso.HasTimeOff);
    AssertEquals('2024-05-12T09:16:15Z', Qso.TimeOff.ToIso8601);
    AssertEquals('20m', Qso.Band);
    AssertEquals('20m', Qso.BandRx);
    AssertEquals(14075123, Qso.FrequencyHz);
    AssertEquals(14076000, Qso.FrequencyRxHz);
    AssertEquals('MFSK', Qso.Mode.Mode);
    AssertEquals('FT4', Qso.Mode.Submode);
    AssertEquals(500, Qso.TxPowerMw);
    AssertEquals('no other fields', 0, Qso.OtherFields.Count);
  finally
    Qso.Free;
  end;
end;

procedure TAdifQsoTests.KeepsOtherFieldsInOrder;
var
  Qso: TQsoRecord;
begin
  Qso := Convert('<NAME:6>山田 <CALL:6>JA1ZZZ <CNTY:4>0101 <QSO_DATE:8>20240512 ' +
    '<TIME_ON:4>0915 <APP_X_SEQ:2:N>17 <MODE:2>CW <EOR>');
  try
    AssertEquals(3, Qso.OtherFields.Count);
    AssertEquals('NAME', Qso.OtherFields[0].Name);
    AssertEquals('山田', Qso.OtherFields[0].Value);
    AssertEquals('leading zero kept', '0101', Qso.OtherFields.Value('CNTY'));
    AssertEquals('APP_X_SEQ', Qso.OtherFields[2].Name);
    AssertEquals('type indicator kept', 'N', Qso.OtherFields[2].DataType);
  finally
    Qso.Free;
  end;
end;

procedure TAdifQsoTests.RequiresCallTimeAndMode;
begin
  AssertNull(Convert('<QSO_DATE:8>20240512 <BAND:3>20m <EOR>'));
  AssertEquals('CALL, time and MODE are all reported', 3, FIssues.ErrorCount);
end;

procedure TAdifQsoTests.RejectsDatesBefore1930;
begin
  AssertNull(Convert('<CALL:5>W1ZZZ <QSO_DATE:8>19291231 <TIME_ON:4>2359 ' +
    '<MODE:2>CW <EOR>'));
  AssertEquals(1, FIssues.ErrorCount);
  AssertEquals('QSO_DATE', FIssues[0].FieldName);
end;

procedure TAdifQsoTests.EndTimeBeforeStartIsNextDay;
var
  Qso: TQsoRecord;
begin
  Qso := Convert('<CALL:5>W1ZZZ <QSO_DATE:8>20240512 <TIME_ON:6>235930 ' +
    '<TIME_OFF:4>0001 <MODE:2>CW <BAND:3>20m <EOR>');
  try
    AssertEquals('2024-05-13T00:01:00Z', Qso.TimeOff.ToIso8601);
  finally
    Qso.Free;
  end;
end;

procedure TAdifQsoTests.DerivesBandFromFrequency;
var
  Qso: TQsoRecord;
begin
  Qso := Convert('<CALL:5>W1ZZZ <QSO_DATE:8>20240512 <TIME_ON:4>1200 ' +
    '<FREQ:5>7.074 <MODE:3>FT8 <EOR>');
  try
    AssertEquals('', IssueText);
    AssertEquals('40m', Qso.Band);
  finally
    Qso.Free;
  end;
end;

procedure TAdifQsoTests.WarnsOnBandMismatch;
var
  Qso: TQsoRecord;
begin
  Qso := Convert('<CALL:5>W1ZZZ <QSO_DATE:8>20240512 <TIME_ON:4>1200 ' +
    '<BAND:3>20m <FREQ:5>7.074 <MODE:3>FT8 <EOR>');
  try
    AssertEquals('both kept', '20m', Qso.Band);
    AssertEquals(7074000, Qso.FrequencyHz);
    AssertEquals(1, FIssues.Count);
    AssertEquals('BAND', FIssues[0].FieldName);
  finally
    Qso.Free;
  end;
end;

procedure TAdifQsoTests.KeepsUninterpretableValues;
var
  Qso: TQsoRecord;
begin
  Qso := Convert('<CALL:5>W1ZZZ <QSO_DATE:8>20240512 <TIME_ON:4>1200 ' +
    '<BAND:4>11m! <FREQ:5>abcde <TX_PWR:4>high <MODE:2>CW <EOR>');
  try
    AssertEquals(3, FIssues.Count);
    AssertEquals(0, FIssues.ErrorCount);
    AssertEquals('11m!', Qso.OtherFields.Value('BAND'));
    AssertEquals('abcde', Qso.OtherFields.Value('FREQ'));
    AssertEquals('high', Qso.OtherFields.Value('TX_PWR'));
    AssertEquals('', Qso.Band);
    AssertEquals(NoFrequency, Qso.FrequencyHz);
    AssertEquals(NoPower, Qso.TxPowerMw);
  finally
    Qso.Free;
  end;
end;

procedure TAdifQsoTests.ConvertsImportOnlyModes;
var
  Qso: TQsoRecord;
begin
  Qso := Convert('<CALL:5>W1ZZZ <QSO_DATE:8>20240512 <TIME_ON:4>1200 ' +
    '<BAND:2>2m <MODE:5>DSTAR <EOR>');
  try
    AssertEquals('DIGITALVOICE', Qso.Mode.Mode);
    AssertEquals('DSTAR', Qso.Mode.Submode);
    AssertEquals(1, FIssues.Count);
    AssertTrue(FIssues[0].Severity = aisWarning);
  finally
    Qso.Free;
  end;
end;

procedure TAdifQsoTests.ChecksJapaneseCodes;
var
  Qso: TQsoRecord;
begin
  { Valid: Sapporo (JCC), Chuo Ku of Sapporo, Akan Gun, Chiyoda Ku of Tokyo. }
  Qso := Convert('<CALL:6>JA1ZZZ <QSO_DATE:8>20240512 <TIME_ON:4>1200 <BAND:3>40m ' +
    '<MODE:2>CW <DXCC:3>339 <STATE:2>01 <CNTY:6>010101 ' +
    '<MY_DXCC:3>339 <MY_STATE:2>10 <MY_CNTY:6>100101 <EOR>');
  Qso.Free;
  AssertEquals('', IssueText);
  FIssues.Clear;
  Qso := Convert('<CALL:6>JA1ZZZ <QSO_DATE:8>20240512 <TIME_ON:4>1200 <BAND:3>40m ' +
    '<MODE:2>CW <DXCC:3>339 <STATE:1>1 <CNTY:4>1001 ' +
    '<MY_DXCC:3>339 <MY_STATE:2>01 <MY_CNTY:7>JCC0101 <EOR>');
  try
    AssertEquals(3, FIssues.Count);
    AssertEquals('STATE', FIssues[0].FieldName);
    AssertEquals('CNTY', FIssues[1].FieldName);
    AssertEquals('MY_CNTY', FIssues[2].FieldName);
    AssertEquals('kept as is', 'JCC0101', Qso.OtherFields.Value('MY_CNTY'));
  finally
    Qso.Free;
  end;
  FIssues.Clear;
  { Other entities are not checked against the Japanese codes. }
  Convert('<CALL:5>W1ZZZ <QSO_DATE:8>20240512 <TIME_ON:4>1200 <BAND:3>40m ' +
    '<MODE:2>CW <DXCC:3>291 <STATE:2>MA <CNTY:12>MA,Middlesex <EOR>').Free;
  AssertEquals('', IssueText);
end;

procedure TAdifQsoTests.ExportsTypedFieldsFirst;
var
  Qso: TQsoRecord;
  Document: TAdifDocument;
begin
  Qso := Convert('<NAME:2>Al <MODE:3>USB <CALL:5>W1ZZZ <TIME_ON:4>1200 ' +
    '<QSO_DATE:8>20240512 <FREQ:10>14.2000000 <EOR>');
  FRecord := QsoToAdifRecord(Qso);
  Qso.Free;
  Document := TAdifDocument.Create;
  try
    Document.AppendRecord(FRecord);
    FRecord := nil;
    AssertEquals('<CALL:5>W1ZZZ <QSO_DATE:8>20240512 <TIME_ON:6>120000 ' +
      '<BAND:3>20m <FREQ:4>14.2 <MODE:3>SSB <SUBMODE:3>USB <NAME:2>Al <EOR>' + #10,
      WriteAdi(Document));
  finally
    Document.Free;
  end;
end;

{ Golden tests }

function GoldenDirectory: string;
begin
  Result := GetEnvironmentVariable('MUNINN_GOLDEN_DIR');
  if Result = '' then
    Result := 'tests/golden/adif';
  Result := IncludeTrailingPathDelimiter(Result);
end;

function ReadTextFile(const APath: string): string;
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    Result := '';
    SetLength(Result, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Result[1], Stream.Size);
  finally
    Stream.Free;
  end;
end;

procedure WriteTextFile(const APath, AText: string);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(APath, fmCreate);
  try
    if AText <> '' then
      Stream.WriteBuffer(AText[1], Length(AText));
  finally
    Stream.Free;
  end;
end;

{ Import <name>.adi, export it, and compare with <name>.expected.adi and the
  issues with <name>.issues.txt; then check that importing and exporting the
  expected file changes nothing. }
procedure TAdifGoldenTests.CheckCase(const AName: string);
var
  Base, Exported, Issued: string;
  Created: TUtcInstant;
  Components: TUtcComponents;

  procedure RoundTrip(const AText: string; out AExported, AIssued: string);
  var
    Document, Output: TAdifDocument;
    Issues: TAdifIssues;
    Qsos: TObjectList;
  begin
    Document := TAdifDocument.Create;
    Issues := TAdifIssues.Create;
    Qsos := TObjectList.Create(True);
    Output := nil;
    try
      ReadAdi(AText, Document, Issues);
      ImportAdifDocument(Document, Issues, Qsos);
      Output := ExportAdifDocument(Qsos, Created, 'golden', Document.Header);
      AExported := WriteAdi(Output);
      AIssued := Issues.ToText;
    finally
      Output.Free;
      Qsos.Free;
      Issues.Free;
      Document.Free;
    end;
  end;

var
  Again, AgainIssued: string;
begin
  Components := Default(TUtcComponents);
  Components.Year := 2024;
  Components.Month := 1;
  Components.Day := 1;
  AssertTrue(TUtcInstant.TryFromComponents(Components, Created));
  Base := GoldenDirectory + AName;
  RoundTrip(ReadTextFile(Base + '.adi'), Exported, Issued);
  if GetEnvironmentVariable('MUNINN_UPDATE_GOLDEN') = '1' then
  begin
    WriteTextFile(Base + '.expected.adi', Exported);
    WriteTextFile(Base + '.issues.txt', Issued);
  end;
  AssertEquals('export of ' + AName, ReadTextFile(Base + '.expected.adi'), Exported);
  AssertEquals('issues of ' + AName, ReadTextFile(Base + '.issues.txt'), Issued);
  { Normalizing warnings (e.g. a converted mode) must not come back; warnings
    about the content itself (e.g. CNTY outside STATE) do. }
  RoundTrip(Exported, Again, AgainIssued);
  AssertEquals('re-export of ' + AName + ' is unchanged', Exported, Again);
  AssertEquals('re-import of ' + AName + ' has no errors', 0,
    Pos(': error: ', AgainIssued));
  AssertTrue('re-import of ' + AName + ' has no new issues',
    Length(AgainIssued) <= Length(Issued));
end;

procedure TAdifGoldenTests.WsjtxExport;
begin
  CheckCase('wsjtx');
end;

procedure TAdifGoldenTests.JapaneseDomesticLog;
begin
  CheckCase('japan');
end;

procedure TAdifGoldenTests.CharacterLengths;
begin
  CheckCase('character-lengths');
end;

initialization
  RegisterTest(TAdifQsoTests);
  RegisterTest(TAdifGoldenTests);
end.
