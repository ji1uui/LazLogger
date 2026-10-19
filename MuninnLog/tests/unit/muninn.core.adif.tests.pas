unit Muninn.Core.Adif.Tests;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  fpcunit, testregistry, Muninn.Core.Adif;

type
  TAdifTests = class(TTestCase)
  private
    FDocument: TAdifDocument;
    FIssues: TAdifIssues;
    procedure Read(const AText: string);
    procedure CheckIssue(const AIndex: Integer; const ASeverity: TAdifIssueSeverity;
      const AFieldName: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ReadsHeaderAndRecords;
    procedure ReadsFileWithoutHeader;
    procedure KeepsValuesExactly;
    procedure SkipsByteOrderMark;
    procedure ReadsUtf8ByteLengths;
    procedure DetectsCharacterLengths;
    procedure KeepsByteLengthsBeforeIgnoredText;
    procedure DetectsCharacterLengthsOfMixedText;
    procedure SkipsBlankLinesBeforeFirstTag;
    procedure ReadsWhitespaceOnlyHeader;
    procedure RejectsNonDecimalLengths;
    procedure WritesReadableHeaderText;
    procedure ReportsHugeLengths;
    procedure ReportsMalformedTags;
    procedure KeepsFirstOfRepeatedFields;
    procedure KeepsLastRecordWithoutEor;
    procedure ReportsMissingEoh;
    procedure ReportsInvalidUtf8;
    procedure WritesByteLengths;
    procedure RoundTripsDocument;
    procedure RejectsInvalidFieldNames;
    procedure EditsRecords;
  end;

implementation

uses
  SysUtils;

procedure TAdifTests.SetUp;
begin
  FDocument := TAdifDocument.Create;
  FIssues := TAdifIssues.Create;
end;

procedure TAdifTests.TearDown;
begin
  FIssues.Free;
  FDocument.Free;
end;

procedure TAdifTests.Read(const AText: string);
begin
  FIssues.Clear;
  ReadAdi(AText, FDocument, FIssues);
end;

procedure TAdifTests.CheckIssue(const AIndex: Integer;
  const ASeverity: TAdifIssueSeverity; const AFieldName: string);
begin
  AssertTrue('issue exists', AIndex < FIssues.Count);
  AssertTrue('severity of ' + FIssues[AIndex].Message,
    FIssues[AIndex].Severity = ASeverity);
  AssertEquals('field', AFieldName, FIssues[AIndex].FieldName);
end;

procedure TAdifTests.ReadsHeaderAndRecords;
begin
  Read('Exported by a test' + LineEnding +
    '<adif_ver:5>3.1.8 <USERDEF1:3:N>EPC <eoh>' + LineEnding +
    '<call:6>WN4AZY<band:3>20M<mode:4>RTTY<qso_date:8>19960513<time_on:4>1305<eor>' +
    LineEnding + '<CALL:5>VK9NS <BAND:3>20m <EOR>');
  AssertEquals('no issues', '', FIssues.ToText);
  AssertTrue(FDocument.HasHeader);
  AssertEquals('Exported by a test', FDocument.HeaderText);
  AssertEquals(2, FDocument.Header.Count);
  AssertEquals('3.1.8', FDocument.Header.Value('ADIF_VER'));
  AssertEquals('type indicator', 'N', FDocument.Header[1].DataType);
  AssertEquals(2, FDocument.RecordCount);
  AssertEquals('names are upper-cased', 'CALL', FDocument[0][0].Name);
  AssertEquals('WN4AZY', FDocument[0].Value('call'));
  AssertEquals('1305', FDocument[0].Value('TIME_ON'));
  AssertEquals('VK9NS', FDocument[1].Value('CALL'));
end;

procedure TAdifTests.ReadsFileWithoutHeader;
begin
  Read('<CALL:4>WF1B<EOR>');
  AssertEquals('', FIssues.ToText);
  AssertFalse(FDocument.HasHeader);
  AssertEquals(1, FDocument.RecordCount);
  AssertEquals('WF1B', FDocument[0].Value('CALL'));
end;

procedure TAdifTests.KeepsValuesExactly;
begin
  Read('<CNTY:4>0101 <STX:3>001 <NAME:0> <COMMENT:6>a  b  <EOR>');
  AssertEquals('leading zeros', '0101', FDocument[0].Value('CNTY'));
  AssertEquals('001', FDocument[0].Value('STX'));
  AssertTrue('empty value is a field', FDocument[0].Has('NAME'));
  AssertEquals('', FDocument[0].Value('NAME'));
  AssertEquals('spaces kept', 'a  b  ', FDocument[0].Value('COMMENT'));
end;

procedure TAdifTests.SkipsByteOrderMark;
begin
  Read(#$EF#$BB#$BF'<CALL:4>WF1B<EOR>');
  AssertFalse('BOM is not header text', FDocument.HasHeader);
  AssertEquals('WF1B', FDocument[0].Value('CALL'));
end;

procedure TAdifTests.ReadsUtf8ByteLengths;
begin
  Read('<NAME:6>山田 <QTH:9>札幌市<EOR>');
  AssertEquals('', FIssues.ToText);
  AssertEquals('山田', FDocument[0].Value('NAME'));
  AssertEquals('札幌市', FDocument[0].Value('QTH'));
end;

procedure TAdifTests.DetectsCharacterLengths;
begin
  { 2 and 3 characters, but 6 and 9 bytes. }
  Read('<NAME:2>山田 <QTH:3>札幌市 <CALL:6>JA1ZZZ<EOR>');
  AssertEquals('山田', FDocument[0].Value('NAME'));
  AssertEquals('札幌市', FDocument[0].Value('QTH'));
  AssertEquals('JA1ZZZ', FDocument[0].Value('CALL'));
  AssertEquals(2, FIssues.Count);
  CheckIssue(0, aisWarning, 'NAME');
  CheckIssue(1, aisWarning, 'QTH');
end;

procedure TAdifTests.KeepsByteLengthsBeforeIgnoredText;
begin
  { Text between data specifiers is ignored (ADIF IV.A.6). 3 bytes = 山; read
    as 3 characters the value would leave 'b' before the next tag. }
  Read('<NAME:3>山 ab <CALL:4>WF1B<EOR>');
  AssertEquals('山', FDocument[0].Value('NAME'));
  AssertEquals('WF1B', FDocument[0].Value('CALL'));
  AssertEquals('', FIssues.ToText);
end;

procedure TAdifTests.DetectsCharacterLengthsOfMixedText;
begin
  { 9 characters but 11 bytes; the byte count ends inside 'abcdefg'. }
  Read('<NAME:9>東 abcdefg <CALL:4>W1AW<EOR>');
  AssertEquals('東 abcdefg', FDocument[0].Value('NAME'));
  AssertEquals('W1AW', FDocument[0].Value('CALL'));
  CheckIssue(0, aisWarning, 'NAME');
end;

procedure TAdifTests.SkipsBlankLinesBeforeFirstTag;
begin
  Read(#13#10'  '#10'<CALL:4>W1AW<EOR>');
  AssertFalse('no header', FDocument.HasHeader);
  AssertEquals(1, FDocument.RecordCount);
  AssertEquals('', FIssues.ToText);
end;

procedure TAdifTests.ReadsWhitespaceOnlyHeader;
begin
  Read(#10'<USERDEF1:3:S>FOO <ADIF_VER:5>3.1.8 <EOH>'#10'<CALL:4>W1AW <FOO:1>x <EOR>');
  AssertEquals('', FIssues.ToText);
  AssertTrue(FDocument.HasHeader);
  AssertEquals('FOO', FDocument.Header.Value('USERDEF1'));
  AssertEquals(1, FDocument.RecordCount);
  AssertFalse('header fields not in the record', FDocument[0].Has('USERDEF1'));
end;

procedure TAdifTests.RejectsNonDecimalLengths;
begin
  Read('<CALL:$4>W1AW <NAME:0x2>Al <MODE:2>CW <EOR>');
  AssertEquals(2, FIssues.ErrorCount);
  AssertFalse(FDocument[0].Has('CALL'));
  AssertEquals('CW', FDocument[0].Value('MODE'));
end;

procedure TAdifTests.WritesReadableHeaderText;
var
  Text: string;
begin
  FDocument.HasHeader := True;
  FDocument.HeaderText := 'Exported by <MyLogger:v2>';
  FDocument.Header.Add('ADIF_VER', '3.1.8');
  FDocument.AddRecord.Add('CALL', 'W1AW');
  Text := WriteAdi(FDocument);
  Read(Text);
  AssertEquals('', FIssues.ToText);
  AssertEquals('3.1.8', FDocument.Header.Value('ADIF_VER'));
  AssertEquals('W1AW', FDocument[0].Value('CALL'));
end;

procedure TAdifTests.ReportsHugeLengths;
begin
  Read('<CALL:4>WF1B <NAME:2147483647>x<EOR>');
  AssertEquals(1, FIssues.ErrorCount);
  CheckIssue(0, aisError, 'NAME');
  AssertEquals('the rest of the file is the value', 'x<EOR>',
    FDocument[0].Value('NAME'));
  AssertEquals('WF1B', FDocument[0].Value('CALL'));
end;

procedure TAdifTests.ReportsMalformedTags;
begin
  Read('<CALL:x>WF1B <BAND:3>20m <A:B:C:D> <MODE:2>CW <EOR>');
  AssertEquals(2, FIssues.Count);
  CheckIssue(0, aisError, 'CALL');
  CheckIssue(1, aisError, '');
  AssertEquals('later fields still read', 'CW', FDocument[0].Value('MODE'));
  AssertEquals('20m', FDocument[0].Value('BAND'));
end;

procedure TAdifTests.KeepsFirstOfRepeatedFields;
begin
  Read('<CALL:4>WF1B <call:5>VK9NS <EOR>');
  AssertEquals('WF1B', FDocument[0].Value('CALL'));
  AssertEquals(1, FDocument[0].Count);
  CheckIssue(0, aisWarning, 'CALL');
end;

procedure TAdifTests.KeepsLastRecordWithoutEor;
begin
  Read('<CALL:4>WF1B <EOR> <CALL:5>VK9NS');
  AssertEquals(2, FDocument.RecordCount);
  AssertEquals('VK9NS', FDocument[1].Value('CALL'));
  CheckIssue(0, aisWarning, '');
end;

procedure TAdifTests.ReportsMissingEoh;
begin
  Read('header text <ADIF_VER:5>3.1.8 <CALL:4>WF1B <EOR>');
  AssertEquals(0, FDocument.RecordCount);
  AssertEquals(1, FIssues.ErrorCount);
end;

procedure TAdifTests.ReportsInvalidUtf8;
begin
  { "山田" in Shift_JIS. }
  Read('<NAME:4>'#$8E#$52#$93#$63'<EOR>');
  AssertEquals('bytes kept', 4, Length(FDocument[0].Value('NAME')));
  CheckIssue(0, aisWarning, 'NAME');
end;

procedure TAdifTests.WritesByteLengths;
var
  Fields: TAdifRecord;
begin
  Fields := FDocument.AddRecord;
  Fields.Add('NAME', '山田');
  Fields.Add('APP_TEST_SEQ', '17', 'n');
  Fields.Add('CNTY', '0101');
  AssertEquals('<NAME:6>山田 <APP_TEST_SEQ:2:N>17 <CNTY:4>0101 <EOR>' + #10,
    WriteAdi(FDocument));
end;

procedure TAdifTests.RoundTripsDocument;
var
  Text: string;
begin
  Read('Header' + #10 + '<ADIF_VER:5>3.1.8' + #10 + '<EOH>' + #10 +
    '<CALL:6>JA1ZZZ <NAME:6>山田 <EOR>' + #10);
  Text := WriteAdi(FDocument);
  AssertEquals('Header' + #10 + '<ADIF_VER:5>3.1.8' + #10 + '<EOH>' + #10 +
    '<CALL:6>JA1ZZZ <NAME:6>山田 <EOR>' + #10, Text);
  Read(Text);
  AssertEquals(Text, WriteAdi(FDocument));
end;

procedure TAdifTests.RejectsInvalidFieldNames;
var
  Fields: TAdifRecord;
begin
  AssertTrue(IsValidAdifFieldName('APP_MUNINNLOG_X'));
  AssertFalse(IsValidAdifFieldName('A:B'));
  AssertFalse(IsValidAdifFieldName('A<B'));
  AssertFalse(IsValidAdifFieldName(' A'));
  AssertFalse(IsValidAdifFieldName(''));
  Fields := FDocument.AddRecord;
  try
    Fields.Add('BAD,NAME', 'x');
    Fail('an invalid name must raise');
  except
    on EArgumentException do;
  end;
end;

procedure TAdifTests.EditsRecords;
var
  Fields: TAdifRecord;
begin
  Fields := FDocument.AddRecord;
  Fields.Add('CALL', 'WF1B');
  Fields.Add('BAND', '20m');
  Fields.SetValue('call', 'VK9NS');
  Fields.SetValue('MODE', 'CW');
  AssertEquals(3, Fields.Count);
  AssertEquals('VK9NS', Fields[0].Value);
  Fields.Remove('BAND');
  AssertEquals(2, Fields.Count);
  AssertEquals('MODE', Fields[1].Name);
  AssertEquals(-1, Fields.IndexOf('BAND'));
end;

initialization
  RegisterTest(TAdifTests);
end.
