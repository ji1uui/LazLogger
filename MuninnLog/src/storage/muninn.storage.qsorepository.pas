unit Muninn.Storage.QsoRepository;

{ Stores TQsoRecord in the qso and qso_field tables (ADR 0006).
  Typed values go to their columns. An ADIF field in OtherFields goes to the
  column of the same name when one exists, it carries no data type indicator,
  and (for INTEGER columns) its text is the canonical integer, so '001' or
  '+5' stay as written. A recorded empty STATION_CALLSIGN also stays out of its
  column, where '' means not recorded. Every other field goes to qso_field with its data
  type and recorded position, so loading gives back every field and value.
  Loading orders the column fields in a fixed order and the qso_field fields
  in their recorded order. }

{$mode objfpc}{$H+}

interface

uses
  Contnrs, Muninn.Core.Adif, Muninn.Core.Qso, Muninn.Storage.Sqlite;

type
  TQsoRepository = class
  private
    FDatabase: TSqliteDatabase;
  public
    constructor Create(const ADatabase: TSqliteDatabase);
    { Inserts AQso with a new id and returns the id. ASource is stored in
      qso.source, e.g. 'adif'. Runs inside the caller's transaction, if any. }
    function Insert(const AQso: TQsoRecord; const ASource: string;
      const ANowUtcMs: Int64): string;
    { Appends every QSO, in the order they were inserted. }
    procedure LoadAll(const AQsos: TObjectList);
    function Count: Int64;
    { Stores the USERDEFn fields of an ADIF header. A name that is already
      defined differently keeps its definition and is reported in AIssues. }
    procedure SaveUserFields(const AHeader: TAdifRecord; const AIssues: TAdifIssues);
    { USERDEF1..n header fields for every stored user-defined field. The caller
      owns the result. }
    function LoadUserFieldHeader: TAdifRecord;
  end;

{ The name part of a USERDEFn value, e.g. 'SweaterSize' for a definition that
  lists its values after a comma. }
function UserFieldName(const ADefinition: string): string;

implementation

uses
  SysUtils, Muninn.Core.Time, Muninn.Core.Mode;

type
  TColumnKind = (ckText, ckInteger);

  TFieldColumn = record
    Name: string;
    Kind: TColumnKind;
  end;

const
  { qso columns named after ADIF fields, in the order they are loaded. }
  FieldColumns: array[0..30] of TFieldColumn = (
    (Name: 'RST_SENT'; Kind: ckText),
    (Name: 'RST_RCVD'; Kind: ckText),
    (Name: 'STX'; Kind: ckInteger),
    (Name: 'STX_STRING'; Kind: ckText),
    (Name: 'SRX'; Kind: ckInteger),
    (Name: 'SRX_STRING'; Kind: ckText),
    (Name: 'CONTEST_ID'; Kind: ckText),
    (Name: 'NAME'; Kind: ckText),
    (Name: 'QTH'; Kind: ckText),
    (Name: 'GRIDSQUARE'; Kind: ckText),
    (Name: 'DXCC'; Kind: ckInteger),
    (Name: 'STATE'; Kind: ckText),
    (Name: 'CNTY'; Kind: ckText),
    (Name: 'POTA_REF'; Kind: ckText),
    (Name: 'SOTA_REF'; Kind: ckText),
    (Name: 'STATION_CALLSIGN'; Kind: ckText),
    (Name: 'OPERATOR'; Kind: ckText),
    (Name: 'OWNER_CALLSIGN'; Kind: ckText),
    (Name: 'MY_GRIDSQUARE'; Kind: ckText),
    (Name: 'MY_DXCC'; Kind: ckInteger),
    (Name: 'MY_CQ_ZONE'; Kind: ckInteger),
    (Name: 'MY_ITU_ZONE'; Kind: ckInteger),
    (Name: 'MY_STATE'; Kind: ckText),
    (Name: 'MY_CNTY'; Kind: ckText),
    (Name: 'MY_POTA_REF'; Kind: ckText),
    (Name: 'MY_SOTA_REF'; Kind: ckText),
    (Name: 'MY_SIG'; Kind: ckText),
    (Name: 'MY_SIG_INFO'; Kind: ckText),
    (Name: 'MY_RIG'; Kind: ckText),
    (Name: 'MY_ANTENNA'; Kind: ckText),
    (Name: 'COMMENT'; Kind: ckText));

  { Parameters 1..11 and columns 0..10 are the typed values. }
  TypedColumns = 'call, time_on_ms, time_off_ms, freq_hz, freq_rx_hz, band, ' +
    'band_rx, mode, submode, tx_pwr_mw, id';
  TypedColumnCount = 11;

function FindColumn(const AName: string; out AIndex: Integer): Boolean;
var
  Index: Integer;
begin
  for Index := Low(FieldColumns) to High(FieldColumns) do
    if FieldColumns[Index].Name = AName then
    begin
      AIndex := Index;
      Exit(True);
    end;
  AIndex := -1;
  Result := False;
end;

{ True when AText is an integer that reads back the same, e.g. '339' but not
  '0339', '001' or '+5'. }
function IsCanonicalInteger(const AText: string; out AValue: Int64): Boolean;
begin
  Result := TryStrToInt64(AText, AValue) and (IntToStr(AValue) = AText);
end;

function UserFieldName(const ADefinition: string): string;
var
  Comma: Integer;
begin
  Comma := Pos(',', ADefinition);
  if Comma > 0 then
    Result := Copy(ADefinition, 1, Comma - 1)
  else
    Result := ADefinition;
  Result := UpperCase(Trim(Result));
end;

function NewQsoId: string;
var
  Guid: TGUID;
begin
  if CreateGUID(Guid) <> 0 then
    raise ESqliteError.CreateCode(0, 'Cannot create a QSO id');
  Result := LowerCase(Copy(GUIDToString(Guid), 2, 36));
end;

function ColumnList: string;
var
  Index: Integer;
begin
  Result := TypedColumns;
  for Index := Low(FieldColumns) to High(FieldColumns) do
    Result := Result + ', ' + LowerCase(FieldColumns[Index].Name);
end;

{ TQsoRepository }

constructor TQsoRepository.Create(const ADatabase: TSqliteDatabase);
begin
  inherited Create;
  FDatabase := ADatabase;
end;

function TQsoRepository.Insert(const AQso: TQsoRecord; const ASource: string;
  const ANowUtcMs: Int64): string;
var
  Statement, FieldStatement: TSqliteStatement;
  Placeholders: string;
  Index, ColumnIndex, Position: Integer;
  { The OtherFields index whose value fills each column; -1 for none. }
  ColumnSource: array[Low(FieldColumns)..High(FieldColumns)] of Integer;
  Field: TAdifField;
  Value: Int64;
begin
  Result := NewQsoId;
  Placeholders := '?';
  for Index := 2 to TypedColumnCount + Length(FieldColumns) + 3 do
    Placeholders := Placeholders + ', ?';
  FieldStatement := nil;
  Statement := TSqliteStatement.Create(FDatabase, 'INSERT INTO qso (' + ColumnList +
    ', source, created_at_ms, updated_at_ms) VALUES (' + Placeholders + ')');
  try
    FieldStatement := TSqliteStatement.Create(FDatabase,
      'INSERT INTO qso_field (qso_id, name, value, data_type, position) ' +
      'VALUES (?1, ?2, ?3, ?4, ?5)');
    Statement.BindText(1, AQso.Call);
    Statement.BindInt64(2, AQso.TimeOn.UnixMs);
    if AQso.HasTimeOff then
      Statement.BindInt64(3, AQso.TimeOff.UnixMs)
    else
      Statement.BindNull(3);
    if AQso.FrequencyHz <> NoFrequency then
      Statement.BindInt64(4, AQso.FrequencyHz)
    else
      Statement.BindNull(4);
    if AQso.FrequencyRxHz <> NoFrequency then
      Statement.BindInt64(5, AQso.FrequencyRxHz)
    else
      Statement.BindNull(5);
    if AQso.Band <> '' then
      Statement.BindText(6, AQso.Band)
    else
      Statement.BindNull(6);
    if AQso.BandRx <> '' then
      Statement.BindText(7, AQso.BandRx)
    else
      Statement.BindNull(7);
    Statement.BindText(8, AQso.Mode.Mode);
    if AQso.Mode.Submode <> '' then
      Statement.BindText(9, AQso.Mode.Submode)
    else
      Statement.BindNull(9);
    if AQso.TxPowerMw <> NoPower then
      Statement.BindInt64(10, AQso.TxPowerMw)
    else
      Statement.BindNull(10);
    Statement.BindText(11, Result);

    for Index := Low(FieldColumns) to High(FieldColumns) do
    begin
      ColumnSource[Index] := -1;
      Statement.BindNull(TypedColumnCount + 1 + Index);
    end;
    { station_callsign is NOT NULL; '' in the column means not recorded. A
      recorded empty STATION_CALLSIGN goes to qso_field so it is exported. }
    FindColumn('STATION_CALLSIGN', ColumnIndex);
    Statement.BindText(TypedColumnCount + 1 + ColumnIndex, '');

    Position := 0;
    for Index := 0 to AQso.OtherFields.Count - 1 do
    begin
      Field := AQso.OtherFields[Index];
      if FindColumn(Field.Name, ColumnIndex) and (Field.DataType = '') and
        (ColumnSource[ColumnIndex] < 0) then
      begin
        case FieldColumns[ColumnIndex].Kind of
          ckText:
            if (Field.Value <> '') or (Field.Name <> 'STATION_CALLSIGN') then
            begin
              Statement.BindText(TypedColumnCount + 1 + ColumnIndex, Field.Value);
              ColumnSource[ColumnIndex] := Index;
              Continue;
            end;
          ckInteger:
            if IsCanonicalInteger(Field.Value, Value) then
            begin
              Statement.BindInt64(TypedColumnCount + 1 + ColumnIndex, Value);
              ColumnSource[ColumnIndex] := Index;
              Continue;
            end;
        end;
      end;
      { Kept for qso_field below, after the qso row exists. }
    end;

    Index := TypedColumnCount + Length(FieldColumns);
    Statement.BindText(Index + 1, ASource);
    Statement.BindInt64(Index + 2, ANowUtcMs);
    Statement.BindInt64(Index + 3, ANowUtcMs);
    Statement.Step;

    for Index := 0 to AQso.OtherFields.Count - 1 do
    begin
      Field := AQso.OtherFields[Index];
      { Only the field that filled a column is skipped. }
      if FindColumn(Field.Name, ColumnIndex) and (ColumnSource[ColumnIndex] = Index) then
        Continue;
      FieldStatement.Reset;
      FieldStatement.BindText(1, Result);
      FieldStatement.BindText(2, Field.Name);
      FieldStatement.BindText(3, Field.Value);
      FieldStatement.BindText(4, Field.DataType);
      FieldStatement.BindInt64(5, Position);
      FieldStatement.Step;
      Inc(Position);
    end;
  finally
    FieldStatement.Free;
    Statement.Free;
  end;
end;

procedure TQsoRepository.LoadAll(const AQsos: TObjectList);
var
  Statement, FieldStatement: TSqliteStatement;
  Qso: TQsoRecord;
  Mode: TMode;
  Index, Column: Integer;
begin
  FieldStatement := nil;
  Statement := TSqliteStatement.Create(FDatabase,
    'SELECT ' + ColumnList + ' FROM qso ORDER BY rowid');
  try
    FieldStatement := TSqliteStatement.Create(FDatabase,
      'SELECT name, value, data_type FROM qso_field WHERE qso_id = ?1 ' +
      'ORDER BY position, name');
    while Statement.Step do
    begin
      Qso := TQsoRecord.Create;
      AQsos.Add(Qso);
      Qso.Call := Statement.ColumnText(0);
      Qso.TimeOn := TUtcInstant.FromUnixMs(Statement.ColumnInt64(1));
      Qso.HasTimeOff := not Statement.ColumnIsNull(2);
      if Qso.HasTimeOff then
        Qso.TimeOff := TUtcInstant.FromUnixMs(Statement.ColumnInt64(2));
      if not Statement.ColumnIsNull(3) then
        Qso.FrequencyHz := Statement.ColumnInt64(3);
      if not Statement.ColumnIsNull(4) then
        Qso.FrequencyRxHz := Statement.ColumnInt64(4);
      Qso.Band := Statement.ColumnText(5);
      Qso.BandRx := Statement.ColumnText(6);
      if not TMode.TryCreate(Statement.ColumnText(7), Statement.ColumnText(8), Mode) then
        raise ESqliteError.CreateCode(0, Format('QSO %s has an invalid mode "%s"',
          [Statement.ColumnText(10), Statement.ColumnText(7)]));
      Qso.Mode := Mode;
      if not Statement.ColumnIsNull(9) then
        Qso.TxPowerMw := Statement.ColumnInt64(9);
      for Index := Low(FieldColumns) to High(FieldColumns) do
      begin
        Column := TypedColumnCount + Index;
        if Statement.ColumnIsNull(Column) then
          Continue;
        if (FieldColumns[Index].Name = 'STATION_CALLSIGN') and
          (Statement.ColumnText(Column) = '') then
          Continue;
        Qso.OtherFields.Add(FieldColumns[Index].Name, Statement.ColumnText(Column));
      end;
      FieldStatement.Reset;
      FieldStatement.BindText(1, Statement.ColumnText(10));
      while FieldStatement.Step do
        Qso.OtherFields.Add(FieldStatement.ColumnText(0),
          FieldStatement.ColumnText(1), FieldStatement.ColumnText(2));
    end;
  finally
    FieldStatement.Free;
    Statement.Free;
  end;
end;

function TQsoRepository.Count: Int64;
begin
  Result := FDatabase.QueryInt64('SELECT count(*) FROM qso');
end;

procedure TQsoRepository.SaveUserFields(const AHeader: TAdifRecord;
  const AIssues: TAdifIssues);
var
  Lookup, Inserter: TSqliteStatement;
  Index: Integer;
  Field: TAdifField;
  Name: string;
begin
  Inserter := nil;
  Lookup := TSqliteStatement.Create(FDatabase,
    'SELECT data_type, definition FROM adif_user_field WHERE name = ?1');
  try
    Inserter := TSqliteStatement.Create(FDatabase,
      'INSERT INTO adif_user_field (name, data_type, definition) VALUES (?1, ?2, ?3)');
    for Index := 0 to AHeader.Count - 1 do
    begin
      Field := AHeader[Index];
      if Copy(Field.Name, 1, 7) <> 'USERDEF' then
        Continue;
      Name := UserFieldName(Field.Value);
      if Name = '' then
        Continue;
      Lookup.Reset;
      Lookup.BindText(1, Name);
      if Lookup.Step then
      begin
        if (Lookup.ColumnText(0) <> Field.DataType) or
          (Lookup.ColumnText(1) <> Field.Value) then
          AIssues.Add(aisWarning, -1, Field.Name, Format(
            'user-defined field %s is already defined as "%s"; kept',
            [Name, Lookup.ColumnText(1)]));
        Continue;
      end;
      Inserter.Reset;
      Inserter.BindText(1, Name);
      Inserter.BindText(2, Field.DataType);
      Inserter.BindText(3, Field.Value);
      Inserter.Step;
    end;
  finally
    Inserter.Free;
    Lookup.Free;
  end;
end;

function TQsoRepository.LoadUserFieldHeader: TAdifRecord;
var
  Statement: TSqliteStatement;
  Number: Integer;
begin
  Result := TAdifRecord.Create;
  Statement := nil;
  try
    Statement := TSqliteStatement.Create(FDatabase,
      'SELECT data_type, definition FROM adif_user_field ORDER BY name');
    Number := 0;
    while Statement.Step do
    begin
      Inc(Number);
      Result.Add('USERDEF' + IntToStr(Number), Statement.ColumnText(1),
        Statement.ColumnText(0));
    end;
  except
    Statement.Free;
    Result.Free;
    raise;
  end;
  Statement.Free;
end;

end.
