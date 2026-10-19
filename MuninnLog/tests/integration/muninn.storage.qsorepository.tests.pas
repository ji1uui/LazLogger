unit Muninn.Storage.QsoRepository.Tests;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Contnrs, fpcunit, testregistry, Muninn.Core.Adif, Muninn.Core.Qso,
  Muninn.Storage.Sqlite, Muninn.Storage.QsoRepository;

type
  TQsoRepositoryTests = class(TTestCase)
  private
    FPath: string;
    FDatabase: TSqliteDatabase;
    FRepository: TQsoRepository;
    FLoaded: TObjectList;
    function ParseQso(const AText: string): TQsoRecord;
    function LoadOnly: TQsoRecord;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure RoundTripsTypedValues;
    procedure KeepsEveryOtherField;
    procedure KeepsNonCanonicalIntegersAsWritten;
    procedure LoadsInInsertOrder;
    procedure KeepsEmptyStationCallsign;
    procedure KeepsRepeatedFieldNames;
    procedure KeepsUserFieldDefinitions;
  end;

implementation

uses
  SysUtils, Muninn.Core.AdifQso, Muninn.Storage.Schema;

procedure TQsoRepositoryTests.SetUp;
begin
  FPath := IncludeTrailingPathDelimiter(GetTempDir(False)) +
    Format('muninn-repo-%d-%d.sqlite', [GetProcessID, Random(MaxInt)]);
  FDatabase := OpenLogDatabase(FPath);
  FRepository := TQsoRepository.Create(FDatabase);
  FLoaded := TObjectList.Create(True);
end;

procedure TQsoRepositoryTests.TearDown;
begin
  FLoaded.Free;
  FRepository.Free;
  FDatabase.Free;
  DeleteFile(FPath);
  DeleteFile(FPath + '-wal');
  DeleteFile(FPath + '-shm');
end;

function TQsoRepositoryTests.ParseQso(const AText: string): TQsoRecord;
var
  Document: TAdifDocument;
  Issues: TAdifIssues;
begin
  Document := TAdifDocument.Create;
  Issues := TAdifIssues.Create;
  try
    ReadAdi(AText, Document, Issues);
    AssertTrue(Issues.ToText, TryAdifRecordToQso(Document[0], 0, Issues, Result));
  finally
    Issues.Free;
    Document.Free;
  end;
end;

function TQsoRepositoryTests.LoadOnly: TQsoRecord;
begin
  FLoaded.Clear;
  FRepository.LoadAll(FLoaded);
  AssertEquals('one QSO', 1, FLoaded.Count);
  Result := TQsoRecord(FLoaded[0]);
end;

procedure TQsoRepositoryTests.RoundTripsTypedValues;
var
  Qso, Loaded: TQsoRecord;
begin
  Qso := ParseQso('<CALL:5>W1ZZZ <QSO_DATE:8>20240512 <TIME_ON:6>235930 ' +
    '<QSO_DATE_OFF:8>20240513 <TIME_OFF:4>0001 <FREQ:9>14.075123 <FREQ_RX:6>14.076 ' +
    '<BAND_RX:3>20m <MODE:4>MFSK <SUBMODE:3>FT4 <TX_PWR:3>0.5 <EOR>');
  try
    FRepository.Insert(Qso, 'test', 1000);
  finally
    Qso.Free;
  end;
  Loaded := LoadOnly;
  AssertEquals('W1ZZZ', Loaded.Call);
  AssertEquals('2024-05-12T23:59:30Z', Loaded.TimeOn.ToIso8601);
  AssertTrue(Loaded.HasTimeOff);
  AssertEquals('2024-05-13T00:01:00Z', Loaded.TimeOff.ToIso8601);
  AssertEquals(14075123, Loaded.FrequencyHz);
  AssertEquals(14076000, Loaded.FrequencyRxHz);
  AssertEquals('20m', Loaded.Band);
  AssertEquals('20m', Loaded.BandRx);
  AssertEquals('MFSK', Loaded.Mode.Mode);
  AssertEquals('FT4', Loaded.Mode.Submode);
  AssertEquals(500, Loaded.TxPowerMw);
  AssertEquals('no station callsign recorded', 0, Loaded.OtherFields.Count);
  AssertEquals('test', FDatabase.QueryText('SELECT source FROM qso'));
end;

procedure TQsoRepositoryTests.KeepsEveryOtherField;
var
  Qso, Loaded: TQsoRecord;
begin
  Qso := ParseQso('<CALL:6>JA1ZZZ <QSO_DATE:8>20231103 <TIME_ON:4>1200 <MODE:2>CW ' +
    '<APP_X_B:1>b <NAME:6>山田 <DXCC:3>339 <CNTY:4>0101 <APP_X_A:2:N>17 ' +
    '<STATION_CALLSIGN:6>JA9XXX <NAME_INTL:6>山田 <EOR>');
  try
    FRepository.Insert(Qso, 'test', 1000);
  finally
    Qso.Free;
  end;
  AssertEquals('columns used', '0101',
    FDatabase.QueryText('SELECT cnty FROM qso'));
  AssertEquals(339, FDatabase.QueryInt64('SELECT dxcc FROM qso'));
  AssertEquals('fields without a column', 3,
    FDatabase.QueryInt64('SELECT count(*) FROM qso_field'));
  Loaded := LoadOnly;
  AssertEquals(7, Loaded.OtherFields.Count);
  AssertEquals('山田', Loaded.OtherFields.Value('NAME'));
  AssertEquals('0101', Loaded.OtherFields.Value('CNTY'));
  AssertEquals('339', Loaded.OtherFields.Value('DXCC'));
  AssertEquals('JA9XXX', Loaded.OtherFields.Value('STATION_CALLSIGN'));
  { Fields without a column come last, in their recorded order. }
  AssertEquals('APP_X_B', Loaded.OtherFields[4].Name);
  AssertEquals('APP_X_A', Loaded.OtherFields[5].Name);
  AssertEquals('type indicator kept', 'N', Loaded.OtherFields[5].DataType);
  AssertEquals('NAME_INTL', Loaded.OtherFields[6].Name);
end;

procedure TQsoRepositoryTests.KeepsNonCanonicalIntegersAsWritten;
var
  Qso, Loaded: TQsoRecord;
begin
  Qso := ParseQso('<CALL:6>JA1ZZZ <QSO_DATE:8>20231103 <TIME_ON:4>1200 <MODE:2>CW ' +
    '<STX:3>001 <SRX:2>42 <MY_DXCC:4>0339 <EOR>');
  try
    FRepository.Insert(Qso, 'test', 1000);
  finally
    Qso.Free;
  end;
  AssertEquals('canonical integer in its column', 42,
    FDatabase.QueryInt64('SELECT srx FROM qso'));
  AssertEquals('leading zeros are not in the column', 1, FDatabase.QueryInt64(
    'SELECT count(*) FROM qso WHERE stx IS NULL AND my_dxcc IS NULL'));
  Loaded := LoadOnly;
  AssertEquals('001', Loaded.OtherFields.Value('STX'));
  AssertEquals('42', Loaded.OtherFields.Value('SRX'));
  AssertEquals('0339', Loaded.OtherFields.Value('MY_DXCC'));
end;

procedure TQsoRepositoryTests.KeepsEmptyStationCallsign;
var
  Qso, Loaded: TQsoRecord;
begin
  Qso := ParseQso('<CALL:5>W1ZZZ <QSO_DATE:8>20240512 <TIME_ON:4>1200 <MODE:2>CW ' +
    '<STATION_CALLSIGN:0> <EOR>');
  try
    FRepository.Insert(Qso, 'test', 1000);
  finally
    Qso.Free;
  end;
  Loaded := LoadOnly;
  AssertTrue('recorded as empty', Loaded.OtherFields.Has('STATION_CALLSIGN'));
  AssertEquals('', Loaded.OtherFields.Value('STATION_CALLSIGN'));
end;

procedure TQsoRepositoryTests.KeepsRepeatedFieldNames;
var
  Qso, Loaded: TQsoRecord;
begin
  { The ADIF reader never repeats a name, but the API allows it. }
  Qso := ParseQso('<CALL:5>W1ZZZ <QSO_DATE:8>20240512 <TIME_ON:4>1200 <MODE:2>CW <EOR>');
  try
    Qso.OtherFields.Add('NAME', 'first', 'S');
    Qso.OtherFields.Add('NAME', 'second');
    FRepository.Insert(Qso, 'test', 1000);
  finally
    Qso.Free;
  end;
  Loaded := LoadOnly;
  AssertEquals(2, Loaded.OtherFields.Count);
  AssertEquals('column value', 'second', Loaded.OtherFields[0].Value);
  AssertEquals('kept in qso_field', 'first', Loaded.OtherFields[1].Value);
  AssertEquals('S', Loaded.OtherFields[1].DataType);
end;

procedure TQsoRepositoryTests.LoadsInInsertOrder;
var
  Qso: TQsoRecord;
begin
  Qso := ParseQso('<CALL:5>W2ZZZ <QSO_DATE:8>20240512 <TIME_ON:4>1300 <MODE:2>CW <EOR>');
  try
    FRepository.Insert(Qso, 'test', 1000);
  finally
    Qso.Free;
  end;
  Qso := ParseQso('<CALL:5>W1ZZZ <QSO_DATE:8>20240512 <TIME_ON:4>1200 <MODE:2>CW <EOR>');
  try
    FRepository.Insert(Qso, 'test', 1000);
  finally
    Qso.Free;
  end;
  FRepository.LoadAll(FLoaded);
  AssertEquals(2, FRepository.Count);
  AssertEquals('W2ZZZ', TQsoRecord(FLoaded[0]).Call);
  AssertEquals('W1ZZZ', TQsoRecord(FLoaded[1]).Call);
end;

procedure TQsoRepositoryTests.KeepsUserFieldDefinitions;
var
  Header, Loaded: TAdifRecord;
  Issues: TAdifIssues;
begin
  Header := TAdifRecord.Create;
  Issues := TAdifIssues.Create;
  try
    Header.Add('ADIF_VER', '3.1.8');
    Header.Add('USERDEF1', 'SweaterSize,{S,M,L}', 'E');
    Header.Add('USERDEF2', 'EPC', 'N');
    FRepository.SaveUserFields(Header, Issues);
    AssertEquals('', Issues.ToText);
    Header.Clear;
    Header.Add('USERDEF1', 'EPC', 'S');
    FRepository.SaveUserFields(Header, Issues);
    AssertEquals('redefinition reported', 1, Issues.Count);
    Loaded := FRepository.LoadUserFieldHeader;
    try
      AssertEquals(2, Loaded.Count);
      AssertEquals('USERDEF1', Loaded[0].Name);
      AssertEquals('EPC', Loaded[0].Value);
      AssertEquals('first definition kept', 'N', Loaded[0].DataType);
      AssertEquals('SweaterSize,{S,M,L}', Loaded[1].Value);
      AssertEquals('E', Loaded[1].DataType);
    finally
      Loaded.Free;
    end;
  finally
    Issues.Free;
    Header.Free;
  end;
end;

initialization
  RegisterTest(TQsoRepositoryTests);
end.
