unit Muninn.Core.AdifQso;

{ Converts between ADIF records and TQsoRecord (ADR 0004).
  Import keeps every field: values it cannot interpret stay in OtherFields under
  their ADIF name, with a warning. A record without CALL, QSO_DATE, TIME_ON or
  MODE cannot be a QSO and is reported as an error.
  Export writes the typed values first, in a fixed order, then OtherFields in
  their recorded order. Values are normalized: FREQ in MHz without trailing
  zeros, TIME_ON with seconds, band names in lower case, import-only modes as
  MODE + SUBMODE (ADIF policy II.B).
  Japanese STATE and CNTY codes (DXCC 339) are checked for their format only;
  checking them against the JCC / JCG / Ku lists needs the reference data of
  ADR 0005. }

{$mode objfpc}{$H+}

interface

uses
  Contnrs, Muninn.Core.Adif, Muninn.Core.Qso, Muninn.Core.Time;

const
  JapanDxcc = 339;
  MuninnProgramId = 'MuninnLog';

{ Parses an ADIF Number scaled by 10^AScale into an integer, e.g. '14.074' with
  scale 6 -> 14074000. Digits beyond the scale are rounded half away from zero
  and AExact is False. Returns False for text that is not an ADIF Number or a
  value that does not fit in Int64. }
function TryParseScaledNumber(const AText: string; const AScale: Integer;
  out AValue: Int64; out AExact: Boolean): Boolean;
{ The ADIF Number for AValue / 10^AScale without trailing zeros, e.g.
  14074000 with scale 6 -> '14.074'. }
function FormatScaledNumber(const AValue: Int64; const AScale: Integer): string;

{ Returns False, with an error in AIssues, when ARecord is not a QSO; AQso is
  then nil. On success the caller owns AQso. }
function TryAdifRecordToQso(const ARecord: TAdifRecord; const ARecordIndex: Integer;
  const AIssues: TAdifIssues; out AQso: TQsoRecord): Boolean;
{ The caller owns the result. }
function QsoToAdifRecord(const AQso: TQsoRecord): TAdifRecord;

{ Converts every record of ADocument; records that are not QSOs are skipped and
  reported. AQsos receives the TQsoRecord objects (make it own them). }
procedure ImportAdifDocument(const ADocument: TAdifDocument;
  const AIssues: TAdifIssues; const AQsos: TObjectList);
{ A document with a MuninnLog header and one record per QSO. USERDEFn fields
  of ASourceHeader (may be nil) are copied so user-defined fields stay valid.
  The caller owns the result. }
function ExportAdifDocument(const AQsos: TObjectList; const ACreated: TUtcInstant;
  const AProgramVersion: string; const ASourceHeader: TAdifRecord): TAdifDocument;

implementation

uses
  SysUtils, Muninn.Core.Callsign, Muninn.Core.Band, Muninn.Core.Frequency,
  Muninn.Core.Mode, Muninn.Core.AdifModes;

const
  MinimumAdifYear = 1930;
  FrequencyScale = 6;  { MHz -> Hz }
  PowerScale = 3;      { W -> mW }
  MsPerDay = Int64(86400000);
  MsPerMinute = 60000;
  { Fields that TQsoRecord holds as typed values. }
  TypedFields: array[0..11] of string = ('CALL', 'QSO_DATE', 'TIME_ON',
    'QSO_DATE_OFF', 'TIME_OFF', 'BAND', 'BAND_RX', 'FREQ', 'FREQ_RX', 'MODE',
    'SUBMODE', 'TX_PWR');

function IsTypedField(const AName: string): Boolean;
var
  Name: string;
begin
  for Name in TypedFields do
    if Name = AName then
      Exit(True);
  Result := False;
end;

function IsDigits(const AText: string): Boolean;
var
  Index: Integer;
begin
  Result := AText <> '';
  for Index := 1 to Length(AText) do
    if not (AText[Index] in ['0'..'9']) then
      Exit(False);
end;

function TryParseScaledNumber(const AText: string; const AScale: Integer;
  out AValue: Int64; out AExact: Boolean): Boolean;
const
  MaxDigits = 18;
var
  Text, IntegerPart, FractionPart, Digits: string;
  Negative: Boolean;
  Point: Integer;
  RoundUp: Boolean;
begin
  AValue := 0;
  AExact := True;
  Text := Trim(AText);
  Negative := (Text <> '') and (Text[1] = '-');
  if Negative then
    Delete(Text, 1, 1);
  Point := Pos('.', Text);
  if Point > 0 then
  begin
    IntegerPart := Copy(Text, 1, Point - 1);
    FractionPart := Copy(Text, Point + 1, MaxInt);
  end
  else
  begin
    IntegerPart := Text;
    FractionPart := '';
  end;
  if ((IntegerPart = '') and (FractionPart = '')) or
    ((IntegerPart <> '') and not IsDigits(IntegerPart)) or
    ((FractionPart <> '') and not IsDigits(FractionPart)) then
    Exit(False);
  RoundUp := False;
  if Length(FractionPart) > AScale then
  begin
    RoundUp := FractionPart[AScale + 1] >= '5';
    AExact := StringOfChar('0', Length(FractionPart) - AScale) =
      Copy(FractionPart, AScale + 1, MaxInt);
    SetLength(FractionPart, AScale);
  end;
  Digits := IntegerPart + FractionPart + StringOfChar('0', AScale - Length(FractionPart));
  while (Length(Digits) > 1) and (Digits[1] = '0') do
    Delete(Digits, 1, 1);
  if Length(Digits) > MaxDigits then
    Exit(False);
  AValue := StrToInt64(Digits);
  if RoundUp then
    Inc(AValue);
  if Negative then
    AValue := -AValue;
  Result := True;
end;

function FormatScaledNumber(const AValue: Int64; const AScale: Integer): string;
var
  Magnitude, Divisor: QWord;
  Index: Integer;
  Fraction: string;
begin
  Divisor := 1;
  for Index := 1 to AScale do
    Divisor := Divisor * 10;
  if AValue < 0 then
    Magnitude := QWord(-(AValue + 1)) + 1
  else
    Magnitude := QWord(AValue);
  Result := IntToStr(Magnitude div Divisor);
  if AScale > 0 then
  begin
    Fraction := IntToStr(Magnitude mod Divisor);
    Fraction := StringOfChar('0', AScale - Length(Fraction)) + Fraction;
    while (Fraction <> '') and (Fraction[Length(Fraction)] = '0') do
      SetLength(Fraction, Length(Fraction) - 1);
    if Fraction <> '' then
      Result := Result + '.' + Fraction;
  end;
  if AValue < 0 then
    Result := '-' + Result;
end;

function TryParseAdifDate(const AText: string; out AComponents: TUtcComponents): Boolean;
begin
  AComponents := Default(TUtcComponents);
  Result := (Length(AText) = 8) and IsDigits(AText);
  if not Result then
    Exit;
  AComponents.Year := StrToInt(Copy(AText, 1, 4));
  AComponents.Month := StrToInt(Copy(AText, 5, 2));
  AComponents.Day := StrToInt(Copy(AText, 7, 2));
  Result := AComponents.Year >= MinimumAdifYear;
end;

function TryParseAdifTime(const AText: string; var AComponents: TUtcComponents): Boolean;
begin
  Result := ((Length(AText) = 4) or (Length(AText) = 6)) and IsDigits(AText);
  if not Result then
    Exit;
  AComponents.Hour := StrToInt(Copy(AText, 1, 2));
  AComponents.Minute := StrToInt(Copy(AText, 3, 2));
  if Length(AText) = 6 then
    AComponents.Second := StrToInt(Copy(AText, 5, 2))
  else
    AComponents.Second := 0;
end;

function TryParseAdifDateTime(const ADate, ATime: string;
  out AInstant: TUtcInstant): Boolean;
var
  Components: TUtcComponents;
begin
  AInstant := TUtcInstant.FromUnixMs(0);
  Result := TryParseAdifDate(ADate, Components) and
    TryParseAdifTime(ATime, Components) and
    TUtcInstant.TryFromComponents(Components, AInstant);
end;

{ Japanese prefecture codes of the ADIF Primary Administrative Subdivision
  enumeration for DXCC 339 are 01..47. }
function IsJapanesePrefectureCode(const ACode: string): Boolean;
begin
  Result := (Length(ACode) = 2) and IsDigits(ACode) and
    (StrToInt(ACode) >= 1) and (StrToInt(ACode) <= 47);
end;

type
  TQsoImporter = class
  private
    FRecord: TAdifRecord;
    FRecordIndex: Integer;
    FIssues: TAdifIssues;
    FQso: TQsoRecord;
    procedure Warn(const AFieldName, AMessage: string);
    procedure Fail(const AFieldName, AMessage: string);
    procedure KeepRaw(const AFieldName: string);
    function ReadCall: Boolean;
    function ReadTimes: Boolean;
    procedure ReadFrequency(const AFieldName: string; var AHz: Int64);
    procedure ReadBand(const AFieldName: string; var ABand: string);
    function ReadMode: Boolean;
    procedure ReadPower;
    procedure CheckJapaneseLocation(const ADxccField, AStateField, ACntyField: string);
    procedure CopyOtherFields;
  public
    function Convert(const ARecord: TAdifRecord; const ARecordIndex: Integer;
      const AIssues: TAdifIssues; out AQso: TQsoRecord): Boolean;
  end;

procedure TQsoImporter.Warn(const AFieldName, AMessage: string);
begin
  FIssues.Add(aisWarning, FRecordIndex, AFieldName, AMessage);
end;

procedure TQsoImporter.Fail(const AFieldName, AMessage: string);
begin
  FIssues.Add(aisError, FRecordIndex, AFieldName, AMessage);
end;

procedure TQsoImporter.KeepRaw(const AFieldName: string);
var
  Index: Integer;
begin
  Index := FRecord.IndexOf(AFieldName);
  if Index >= 0 then
    FQso.OtherFields.Add(FRecord[Index].Name, FRecord[Index].Value,
      FRecord[Index].DataType);
end;

function TQsoImporter.ReadCall: Boolean;
var
  Raw: string;
  Callsign: TCallsign;
begin
  Raw := FRecord.Value('CALL');
  if TCallsign.TryCreate(Raw, Callsign) then
    FQso.Call := Callsign.ToString
  else
  begin
    FQso.Call := UpperCase(Trim(Raw));
    if FQso.Call <> '' then
      Warn('CALL', 'not a valid callsign; kept as is');
  end;
  Result := FQso.Call <> '';
  if not Result then
    Fail('CALL', 'missing; the record is not a QSO');
end;

function TQsoImporter.ReadTimes: Boolean;
var
  OffDate: string;
  HasOffDate: Boolean;
  StartMs: Int64;
begin
  Result := TryParseAdifDateTime(FRecord.Value('QSO_DATE'),
    FRecord.Value('TIME_ON'), FQso.TimeOn);
  if not Result then
  begin
    Fail('QSO_DATE', Format(
      'QSO_DATE "%s" / TIME_ON "%s" is not a valid UTC date and time',
      [FRecord.Value('QSO_DATE'), FRecord.Value('TIME_ON')]));
    Exit;
  end;
  if not FRecord.Has('TIME_OFF') then
  begin
    if FRecord.Has('QSO_DATE_OFF') then
    begin
      Warn('QSO_DATE_OFF', 'given without TIME_OFF; kept as is');
      KeepRaw('QSO_DATE_OFF');
    end;
    Exit;
  end;
  OffDate := Trim(FRecord.Value('QSO_DATE_OFF'));
  HasOffDate := OffDate <> '';
  if not HasOffDate then
    OffDate := FRecord.Value('QSO_DATE');
  if not TryParseAdifDateTime(OffDate, FRecord.Value('TIME_OFF'), FQso.TimeOff) then
  begin
    Warn('TIME_OFF', 'not a valid UTC date and time; kept as is');
    KeepRaw('QSO_DATE_OFF');
    KeepRaw('TIME_OFF');
    Exit;
  end;
  { Without QSO_DATE_OFF, an end time before the start time is on the next day.
    Compare at the precision of TIME_OFF: 1200 is not before 120030. }
  if not HasOffDate then
  begin
    StartMs := FQso.TimeOn.UnixMs;
    if Length(FRecord.Value('TIME_OFF')) = 4 then
      StartMs := StartMs - StartMs mod MsPerMinute;
    if FQso.TimeOff.UnixMs < StartMs then
    begin
      FQso.TimeOff := TUtcInstant.FromUnixMs(FQso.TimeOff.UnixMs + MsPerDay);
      if FQso.TimeOff.Components.Year > MaximumYear then
      begin
        Warn('TIME_OFF', 'the next day is after 9999-12-31; kept as is');
        KeepRaw('QSO_DATE_OFF');
        KeepRaw('TIME_OFF');
        Exit;
      end;
    end;
  end;
  FQso.HasTimeOff := True;
end;

procedure TQsoImporter.ReadFrequency(const AFieldName: string; var AHz: Int64);
var
  Hz: Int64;
  Exact: Boolean;
  Frequency: TFrequencyHz;
begin
  if not FRecord.Has(AFieldName) then
    Exit;
  if TryParseScaledNumber(FRecord.Value(AFieldName), FrequencyScale, Hz, Exact) and
    TFrequencyHz.TryFromHz(Hz, Frequency) then
  begin
    AHz := Hz;
    if not Exact then
      Warn(AFieldName, 'finer than 1 Hz; rounded to the nearest Hz');
  end
  else
  begin
    Warn(AFieldName, 'not a valid frequency in MHz; kept as is');
    KeepRaw(AFieldName);
  end;
end;

procedure TQsoImporter.ReadBand(const AFieldName: string; var ABand: string);
var
  Band: TBand;
begin
  if not FRecord.Has(AFieldName) then
    Exit;
  if TryParseBand(FRecord.Value(AFieldName), Band) then
    ABand := BandAdifName(Band)
  else
  begin
    Warn(AFieldName, 'not an ADIF band; kept as is');
    KeepRaw(AFieldName);
  end;
end;

function TQsoImporter.ReadMode: Boolean;
var
  ModeText, SubmodeText, Parent: string;
begin
  ModeText := UpperCase(Trim(FRecord.Value('MODE')));
  SubmodeText := UpperCase(Trim(FRecord.Value('SUBMODE')));
  if ModeText = '' then
  begin
    Fail('MODE', 'missing; the record is not a QSO');
    Exit(False);
  end;
  if TryConvertImportOnlyMode(ModeText, SubmodeText) then
    Warn('MODE', Format('import-only mode %s exported as MODE %s, SUBMODE %s',
      [FRecord.Value('MODE'), ModeText, SubmodeText]))
  else if not IsAdifMode(ModeText) then
    Warn('MODE', 'not an ADIF mode; kept as is')
  else if (SubmodeText <> '') and
    not (TryAdifParentMode(SubmodeText, Parent) and (Parent = ModeText)) then
    Warn('SUBMODE', 'not an ADIF submode of ' + ModeText + '; kept as is');
  Result := TMode.TryCreate(ModeText, SubmodeText, FQso.Mode);
  if not Result then
    Fail('MODE', Format('MODE "%s" / SUBMODE "%s" cannot be stored',
      [FRecord.Value('MODE'), FRecord.Value('SUBMODE')]));
end;

procedure TQsoImporter.ReadPower;
var
  Milliwatts: Int64;
  Exact: Boolean;
begin
  if not FRecord.Has('TX_PWR') then
    Exit;
  if TryParseScaledNumber(FRecord.Value('TX_PWR'), PowerScale, Milliwatts, Exact) and
    (Milliwatts >= 0) then
  begin
    FQso.TxPowerMw := Milliwatts;
    if not Exact then
      Warn('TX_PWR', 'finer than 1 mW; rounded');
  end
  else
  begin
    Warn('TX_PWR', 'not a valid power in watts; kept as is');
    KeepRaw('TX_PWR');
  end;
end;

{ Format checks for Japan (ADIF III.B.12 and III.B.22): STATE is 01..47; CNTY
  is a JCC (4 or 6 digits), JCG (5 digits) or Ku (6 digits) code that starts
  with the prefecture code. The lists themselves are checked later (ADR 0005). }
procedure TQsoImporter.CheckJapaneseLocation(const ADxccField, AStateField,
  ACntyField: string);
var
  State, Cnty: string;
begin
  if StrToIntDef(Trim(FRecord.Value(ADxccField)), 0) <> JapanDxcc then
    Exit;
  State := FRecord.Value(AStateField);
  Cnty := FRecord.Value(ACntyField);
  if (State <> '') and not IsJapanesePrefectureCode(State) then
    Warn(AStateField, 'not a Japanese prefecture code (01..47)');
  if Cnty = '' then
    Exit;
  if not (IsDigits(Cnty) and (Length(Cnty) >= 4) and (Length(Cnty) <= 6) and
    IsJapanesePrefectureCode(Copy(Cnty, 1, 2))) then
    Warn(ACntyField, 'not a JCC, JCG or Ku code')
  else if (State <> '') and (Copy(Cnty, 1, 2) <> State) then
    Warn(ACntyField, Format('in prefecture %s, but %s is %s',
      [Copy(Cnty, 1, 2), AStateField, State]));
end;

procedure TQsoImporter.CopyOtherFields;
var
  Index: Integer;
begin
  for Index := 0 to FRecord.Count - 1 do
    if not IsTypedField(FRecord[Index].Name) then
      FQso.OtherFields.Add(FRecord[Index].Name, FRecord[Index].Value,
        FRecord[Index].DataType);
end;

function TQsoImporter.Convert(const ARecord: TAdifRecord;
  const ARecordIndex: Integer; const AIssues: TAdifIssues;
  out AQso: TQsoRecord): Boolean;
var
  Band: TBand;
  Frequency: TFrequencyHz;
begin
  FRecord := ARecord;
  FRecordIndex := ARecordIndex;
  FIssues := AIssues;
  FQso := TQsoRecord.Create;
  try
    { Evaluate all three so every problem of the record is reported. }
    Result := ReadCall;
    Result := ReadTimes and Result;
    Result := ReadMode and Result;
    if Result then
    begin
      ReadFrequency('FREQ', FQso.FrequencyHz);
      ReadFrequency('FREQ_RX', FQso.FrequencyRxHz);
      ReadBand('BAND', FQso.Band);
      ReadBand('BAND_RX', FQso.BandRx);
      ReadPower;
      if (FQso.FrequencyHz <> NoFrequency) and
        TFrequencyHz.TryFromHz(FQso.FrequencyHz, Frequency) then
      begin
        if not TryBandOfFrequency(Frequency, Band) then
          Warn('FREQ', 'outside every ADIF band')
        else if FQso.Band = '' then
        begin
          if not FRecord.Has('BAND') then
            FQso.Band := BandAdifName(Band);
        end
        else if FQso.Band <> BandAdifName(Band) then
          Warn('BAND', Format('%s does not contain FREQ %s MHz',
            [FQso.Band, FRecord.Value('FREQ')]));
      end;
      if (FQso.Band = '') and (FQso.FrequencyHz = NoFrequency) and
        not FRecord.Has('BAND') and not FRecord.Has('FREQ') then
        Warn('BAND', 'neither BAND nor FREQ is given');
      CheckJapaneseLocation('DXCC', 'STATE', 'CNTY');
      CheckJapaneseLocation('MY_DXCC', 'MY_STATE', 'MY_CNTY');
      CopyOtherFields;
    end;
  except
    FQso.Free;
    raise;
  end;
  if Result then
    AQso := FQso
  else
  begin
    FQso.Free;
    AQso := nil;
  end;
end;

function TryAdifRecordToQso(const ARecord: TAdifRecord; const ARecordIndex: Integer;
  const AIssues: TAdifIssues; out AQso: TQsoRecord): Boolean;
var
  Importer: TQsoImporter;
begin
  Importer := TQsoImporter.Create;
  try
    Result := Importer.Convert(ARecord, ARecordIndex, AIssues, AQso);
  finally
    Importer.Free;
  end;
end;

function QsoToAdifRecord(const AQso: TQsoRecord): TAdifRecord;
var
  Index: Integer;
begin
  Result := TAdifRecord.Create;
  try
    Result.Add('CALL', AQso.Call);
    Result.Add('QSO_DATE', AQso.TimeOn.ToAdifDate);
    Result.Add('TIME_ON', AQso.TimeOn.ToAdifTime);
    if AQso.HasTimeOff then
    begin
      Result.Add('QSO_DATE_OFF', AQso.TimeOff.ToAdifDate);
      Result.Add('TIME_OFF', AQso.TimeOff.ToAdifTime);
    end;
    if AQso.Band <> '' then
      Result.Add('BAND', AQso.Band);
    if AQso.BandRx <> '' then
      Result.Add('BAND_RX', AQso.BandRx);
    if AQso.FrequencyHz <> NoFrequency then
      Result.Add('FREQ', FormatScaledNumber(AQso.FrequencyHz, FrequencyScale));
    if AQso.FrequencyRxHz <> NoFrequency then
      Result.Add('FREQ_RX', FormatScaledNumber(AQso.FrequencyRxHz, FrequencyScale));
    Result.Add('MODE', AQso.Mode.Mode);
    if AQso.Mode.Submode <> '' then
      Result.Add('SUBMODE', AQso.Mode.Submode);
    if AQso.TxPowerMw <> NoPower then
      Result.Add('TX_PWR', FormatScaledNumber(AQso.TxPowerMw, PowerScale));
    for Index := 0 to AQso.OtherFields.Count - 1 do
      if not Result.Has(AQso.OtherFields[Index].Name) then
        Result.Add(AQso.OtherFields[Index].Name, AQso.OtherFields[Index].Value,
          AQso.OtherFields[Index].DataType);
  except
    Result.Free;
    raise;
  end;
end;

procedure ImportAdifDocument(const ADocument: TAdifDocument;
  const AIssues: TAdifIssues; const AQsos: TObjectList);
var
  Index: Integer;
  Qso: TQsoRecord;
begin
  for Index := 0 to ADocument.RecordCount - 1 do
    if TryAdifRecordToQso(ADocument[Index], Index, AIssues, Qso) then
      AQsos.Add(Qso);
end;

function ExportAdifDocument(const AQsos: TObjectList; const ACreated: TUtcInstant;
  const AProgramVersion: string; const ASourceHeader: TAdifRecord): TAdifDocument;
var
  Index: Integer;
begin
  Result := TAdifDocument.Create;
  try
    Result.HasHeader := True;
    Result.HeaderText := 'MuninnLog ADIF export';
    Result.Header.Add('ADIF_VER', AdifVersion);
    Result.Header.Add('CREATED_TIMESTAMP',
      ACreated.ToAdifDate + ' ' + ACreated.ToAdifTime);
    Result.Header.Add('PROGRAMID', MuninnProgramId);
    Result.Header.Add('PROGRAMVERSION', AProgramVersion);
    if ASourceHeader <> nil then
      for Index := 0 to ASourceHeader.Count - 1 do
        if Copy(ASourceHeader[Index].Name, 1, 7) = 'USERDEF' then
          Result.Header.Add(ASourceHeader[Index].Name, ASourceHeader[Index].Value,
            ASourceHeader[Index].DataType);
    for Index := 0 to AQsos.Count - 1 do
      Result.AppendRecord(QsoToAdifRecord(TQsoRecord(AQsos[Index])));
  except
    Result.Free;
    raise;
  end;
end;

end.
