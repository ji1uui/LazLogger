unit Muninn.Core.Adif;

{ ADIF documents and the ADI file format (ADIF 3.1.8 section IV.A), without
  any file I/O: the reader takes the file contents and the writer returns them.
  Strings hold UTF-8. Field names are upper-cased; values are kept exactly as
  found, including leading zeros (e.g. CNTY 0101), so nothing is lost on import.

  Data lengths are byte counts, as ADI defines them. Some programs count
  characters instead when a value holds non-ASCII text; the reader detects that
  case (see ReadAdi) and reports a warning. The writer always writes byte
  counts. Non-ASCII text is not valid in ADI String fields, but Japanese logs
  use it (NAME, QTH); it is read and written as UTF-8 (ADR 0004). }

{$mode objfpc}{$H+}

interface

uses
  Classes, Contnrs;

const
  AdifVersion = '3.1.8';

type
  TAdifField = record
    { Upper case, e.g. 'CALL'. }
    Name: string;
    { The optional data type indicator, upper case, e.g. 'N'; usually empty. }
    DataType: string;
    Value: string;
  end;

  { An ordered list of fields: the fields of one QSO, or the header fields. }
  TAdifRecord = class
  private
    FFields: array of TAdifField;
    FCount: Integer;
    function GetField(const AIndex: Integer): TAdifField;
  public
    function IndexOf(const AName: string): Integer;
    function Has(const AName: string): Boolean;
    { The value, or '' when the field is absent. }
    function Value(const AName: string): string;
    { Appends a field. Raises EArgumentException for a name that ADI cannot carry. }
    procedure Add(const AName, AValue: string; const ADataType: string = '');
    { Replaces the value of an existing field (keeping its position) or appends it. }
    procedure SetValue(const AName, AValue: string);
    procedure Remove(const AName: string);
    procedure Clear;
    procedure Assign(const ASource: TAdifRecord);
    property Count: Integer read FCount;
    property Fields[const AIndex: Integer]: TAdifField read GetField; default;
  end;

  TAdifDocument = class
  private
    FHasHeader: Boolean;
    FHeaderText: string;
    FHeader: TAdifRecord;
    FRecords: TObjectList;
    function GetRecord(const AIndex: Integer): TAdifRecord;
    function GetRecordCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    { Appends a new, empty record that the document owns. }
    function AddRecord: TAdifRecord;
    { Takes ownership of ARecord. }
    procedure AppendRecord(const ARecord: TAdifRecord);
    property HasHeader: Boolean read FHasHeader write FHasHeader;
    { Free text at the start of the header, before the first header field. }
    property HeaderText: string read FHeaderText write FHeaderText;
    property Header: TAdifRecord read FHeader;
    property RecordCount: Integer read GetRecordCount;
    property Records[const AIndex: Integer]: TAdifRecord read GetRecord; default;
  end;

  TAdifIssueSeverity = (aisWarning, aisError);

  TAdifIssue = record
    Severity: TAdifIssueSeverity;
    { 0-based index of the QSO record; -1 for the header or the file as a whole. }
    RecordIndex: Integer;
    FieldName: string;
    Message: string;
  end;

  TAdifIssues = class
  private
    FItems: array of TAdifIssue;
    FCount: Integer;
    function GetItem(const AIndex: Integer): TAdifIssue;
  public
    procedure Add(const ASeverity: TAdifIssueSeverity; const ARecordIndex: Integer;
      const AFieldName, AMessage: string);
    procedure Clear;
    function ErrorCount: Integer;
    { One issue per line, e.g. 'record 3, FREQ: warning: ...'. }
    function ToText: string;
    property Count: Integer read FCount;
    property Items[const AIndex: Integer]: TAdifIssue read GetItem; default;
  end;

{ True when AName can be written as an ADI field name. }
function IsValidAdifFieldName(const AName: string): Boolean;
{ Parses ADI text into ADocument (cleared first). Problems are added to AIssues;
  the reader never raises on bad input and keeps every field it can read. }
procedure ReadAdi(const AText: string; const ADocument: TAdifDocument;
  const AIssues: TAdifIssues);
{ ADI text for ADocument: header (when HasHeader), then one record per line. }
function WriteAdi(const ADocument: TAdifDocument): string;

implementation

uses
  SysUtils;

const
  LineBreak = #10;

function IsValidAdifFieldName(const AName: string): Boolean;
var
  Index: Integer;
begin
  Result := (AName <> '') and (AName[1] <> ' ') and (AName[Length(AName)] <> ' ');
  if Result then
    for Index := 1 to Length(AName) do
      if AName[Index] in [',', ':', '<', '>', '{', '}', #0..#31, #127..#255] then
        Exit(False);
end;

{ TAdifRecord }

function TAdifRecord.GetField(const AIndex: Integer): TAdifField;
begin
  if (AIndex < 0) or (AIndex >= FCount) then
    raise EArgumentOutOfRangeException.CreateFmt('Field index %d out of range', [AIndex]);
  Result := FFields[AIndex];
end;

function TAdifRecord.IndexOf(const AName: string): Integer;
var
  Name: string;
begin
  Name := UpperCase(AName);
  for Result := 0 to FCount - 1 do
    if FFields[Result].Name = Name then
      Exit;
  Result := -1;
end;

function TAdifRecord.Has(const AName: string): Boolean;
begin
  Result := IndexOf(AName) >= 0;
end;

function TAdifRecord.Value(const AName: string): string;
var
  Index: Integer;
begin
  Index := IndexOf(AName);
  if Index >= 0 then
    Result := FFields[Index].Value
  else
    Result := '';
end;

procedure TAdifRecord.Add(const AName, AValue: string; const ADataType: string);
begin
  if not IsValidAdifFieldName(AName) then
    raise EArgumentException.CreateFmt('Invalid ADIF field name: "%s"', [AName]);
  if FCount = Length(FFields) then
    SetLength(FFields, FCount * 2 + 8);
  FFields[FCount].Name := UpperCase(AName);
  FFields[FCount].DataType := UpperCase(ADataType);
  FFields[FCount].Value := AValue;
  Inc(FCount);
end;

procedure TAdifRecord.SetValue(const AName, AValue: string);
var
  Index: Integer;
begin
  Index := IndexOf(AName);
  if Index >= 0 then
    FFields[Index].Value := AValue
  else
    Add(AName, AValue);
end;

procedure TAdifRecord.Remove(const AName: string);
var
  Index: Integer;
begin
  Index := IndexOf(AName);
  if Index < 0 then
    Exit;
  Dec(FCount);
  for Index := Index to FCount - 1 do
    FFields[Index] := FFields[Index + 1];
  FFields[FCount] := Default(TAdifField);
end;

procedure TAdifRecord.Clear;
begin
  FFields := nil;
  FCount := 0;
end;

procedure TAdifRecord.Assign(const ASource: TAdifRecord);
var
  Index: Integer;
begin
  FCount := 0;
  for Index := 0 to ASource.Count - 1 do
    Add(ASource[Index].Name, ASource[Index].Value, ASource[Index].DataType);
end;

{ TAdifDocument }

constructor TAdifDocument.Create;
begin
  inherited Create;
  FHeader := TAdifRecord.Create;
  FRecords := TObjectList.Create(True);
end;

destructor TAdifDocument.Destroy;
begin
  FRecords.Free;
  FHeader.Free;
  inherited Destroy;
end;

procedure TAdifDocument.Clear;
begin
  FHasHeader := False;
  FHeaderText := '';
  FHeader.Free;
  FHeader := TAdifRecord.Create;
  FRecords.Clear;
end;

function TAdifDocument.AddRecord: TAdifRecord;
begin
  Result := TAdifRecord.Create;
  FRecords.Add(Result);
end;

procedure TAdifDocument.AppendRecord(const ARecord: TAdifRecord);
begin
  FRecords.Add(ARecord);
end;

function TAdifDocument.GetRecord(const AIndex: Integer): TAdifRecord;
begin
  Result := TAdifRecord(FRecords[AIndex]);
end;

function TAdifDocument.GetRecordCount: Integer;
begin
  Result := FRecords.Count;
end;

{ TAdifIssues }

function TAdifIssues.GetItem(const AIndex: Integer): TAdifIssue;
begin
  if (AIndex < 0) or (AIndex >= FCount) then
    raise EArgumentOutOfRangeException.CreateFmt('Issue index %d out of range', [AIndex]);
  Result := FItems[AIndex];
end;

procedure TAdifIssues.Add(const ASeverity: TAdifIssueSeverity;
  const ARecordIndex: Integer; const AFieldName, AMessage: string);
begin
  if FCount = Length(FItems) then
    SetLength(FItems, FCount * 2 + 8);
  FItems[FCount].Severity := ASeverity;
  FItems[FCount].RecordIndex := ARecordIndex;
  FItems[FCount].FieldName := AFieldName;
  FItems[FCount].Message := AMessage;
  Inc(FCount);
end;

procedure TAdifIssues.Clear;
begin
  FItems := nil;
  FCount := 0;
end;

function TAdifIssues.ErrorCount: Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index := 0 to FCount - 1 do
    if FItems[Index].Severity = aisError then
      Inc(Result);
end;

function TAdifIssues.ToText: string;
const
  SeverityNames: array[TAdifIssueSeverity] of string = ('warning', 'error');
var
  Index: Integer;
  Where: string;
begin
  Result := '';
  for Index := 0 to FCount - 1 do
  begin
    if FItems[Index].RecordIndex >= 0 then
      Where := Format('record %d', [FItems[Index].RecordIndex + 1])
    else
      Where := 'file';
    if FItems[Index].FieldName <> '' then
      Where := Where + ', ' + FItems[Index].FieldName;
    Result := Result + Format('%s: %s: %s', [Where,
      SeverityNames[FItems[Index].Severity], FItems[Index].Message]) + LineBreak;
  end;
end;

{ Reader }

function IsContinuationByte(const AChar: Char): Boolean; inline;
begin
  Result := (Ord(AChar) and $C0) = $80;
end;

{ The byte position just after ACount UTF-8 characters starting at AStart. }
function SkipUtf8Characters(const AText: string; const AStart, ACount: Integer): Integer;
var
  Remaining: Integer;
begin
  Result := AStart;
  Remaining := ACount;
  while (Remaining > 0) and (Result <= Length(AText)) do
  begin
    Inc(Result);
    while (Result <= Length(AText)) and IsContinuationByte(AText[Result]) do
      Inc(Result);
    Dec(Remaining);
  end;
end;

{ True when the text from AStart to the next '<' (or the end) is only blanks,
  i.e. a value that ends at AStart leaves nothing unread before the next tag. }
function OnlyBlanksBeforeTag(const AText: string; const AStart: Integer): Boolean;
var
  Index: Integer;
begin
  Index := AStart;
  while (Index <= Length(AText)) and (AText[Index] <> '<') do
  begin
    if not (AText[Index] in [' ', #9, #10, #13]) then
      Exit(False);
    Inc(Index);
  end;
  Result := True;
end;

function IsDecimalDigits(const AText: string): Boolean;
var
  Index: Integer;
begin
  Result := AText <> '';
  for Index := 1 to Length(AText) do
    if not (AText[Index] in ['0'..'9']) then
      Exit(False);
end;

function HasNonAscii(const AText: string): Boolean;
var
  Index: Integer;
begin
  for Index := 1 to Length(AText) do
    if Ord(AText[Index]) > 127 then
      Exit(True);
  Result := False;
end;

function IsValidUtf8(const AText: string): Boolean;
var
  Index, Following, Code: Integer;
begin
  Index := 1;
  while Index <= Length(AText) do
  begin
    Code := Ord(AText[Index]);
    if Code < $80 then
      Following := 0
    else if (Code and $E0) = $C0 then
      Following := 1
    else if (Code and $F0) = $E0 then
      Following := 2
    else if (Code and $F8) = $F0 then
      Following := 3
    else
      Exit(False);
    if Index + Following > Length(AText) then
      Exit(False);
    while Following > 0 do
    begin
      Inc(Index);
      if not IsContinuationByte(AText[Index]) then
        Exit(False);
      Dec(Following);
    end;
    Inc(Index);
  end;
  Result := True;
end;

type
  TAdiReader = class
  private
    FText: string;
    FPosition: Integer;
    FDocument: TAdifDocument;
    FIssues: TAdifIssues;
    FRecord: TAdifRecord;
    FInHeader: Boolean;
    function CurrentRecordIndex: Integer;
    procedure Issue(const ASeverity: TAdifIssueSeverity; const AFieldName,
      AMessage: string);
    function ReadValue(const AFieldName: string; const ALength: Integer): string;
    procedure ReadTag;
    procedure FinishRecord;
  public
    procedure Read(const AText: string; const ADocument: TAdifDocument;
      const AIssues: TAdifIssues);
  end;

function TAdiReader.CurrentRecordIndex: Integer;
begin
  if FInHeader then
    Result := -1
  else
    Result := FDocument.RecordCount;
end;

procedure TAdiReader.Issue(const ASeverity: TAdifIssueSeverity;
  const AFieldName, AMessage: string);
begin
  FIssues.Add(ASeverity, CurrentRecordIndex, AFieldName, AMessage);
end;

{ Reads ALength bytes of data at FPosition. The byte count wins when it ends on
  a character boundary and leaves only blanks before the next tag. Otherwise,
  for a value with non-ASCII text, a writer that counted characters is assumed
  when the same count in characters does end right before the next tag: the
  value is read as characters and a warning is reported. Text between data
  specifiers is allowed (ADIF IV.A.6), so this is ambiguous when such text
  follows a non-ASCII value without a blank; ADR 0004 prefers not losing the
  end of the value. }
function TAdiReader.ReadValue(const AFieldName: string;
  const ALength: Integer): string;
var
  ByteEnd, CharacterEnd: Integer;
  SplitsCharacter: Boolean;
begin
  { Compare with the remaining size first so a huge length cannot overflow. }
  if ALength > Length(FText) - FPosition + 1 then
  begin
    Issue(aisError, AFieldName, Format(
      'data length %d runs past the end of the file', [ALength]));
    ByteEnd := Length(FText) + 1;
  end
  else
    ByteEnd := FPosition + ALength;
  Result := Copy(FText, FPosition, ByteEnd - FPosition);
  SplitsCharacter := (ByteEnd <= Length(FText)) and IsContinuationByte(FText[ByteEnd]);
  if SplitsCharacter or HasNonAscii(Result) then
  begin
    if SplitsCharacter or not OnlyBlanksBeforeTag(FText, ByteEnd) then
    begin
      CharacterEnd := SkipUtf8Characters(FText, FPosition, ALength);
      if OnlyBlanksBeforeTag(FText, CharacterEnd) then
      begin
        Result := Copy(FText, FPosition, CharacterEnd - FPosition);
        ByteEnd := CharacterEnd;
        Issue(aisWarning, AFieldName,
          'data length counts characters, not bytes; read as characters');
      end;
    end;
    if not IsValidUtf8(Result) then
      Issue(aisWarning, AFieldName, 'value is not valid UTF-8; kept as is');
  end;
  FPosition := ByteEnd;
end;

procedure TAdiReader.FinishRecord;
begin
  if FRecord.Count > 0 then
    FDocument.AppendRecord(FRecord)
  else
    FRecord.Free;
  FRecord := TAdifRecord.Create;
end;

procedure TAdiReader.ReadTag;
var
  Closing: Integer;
  Tag, Name, LengthText, DataType, Value: string;
  Parts: TStringArray;
  DataLength: Integer;
begin
  Closing := Pos('>', FText, FPosition);
  if Closing = 0 then
  begin
    Issue(aisError, '', 'unterminated tag at the end of the file');
    FPosition := Length(FText) + 1;
    Exit;
  end;
  Tag := Copy(FText, FPosition + 1, Closing - FPosition - 1);
  FPosition := Closing + 1;
  Name := UpperCase(Trim(Tag));
  if Name = 'EOH' then
  begin
    if FInHeader then
    begin
      FDocument.Header.Assign(FRecord);
      FRecord.Free;
      FRecord := TAdifRecord.Create;
      FInHeader := False;
    end
    else
      Issue(aisWarning, '', '<EOH> after the first record; ignored');
    Exit;
  end;
  if Name = 'EOR' then
  begin
    if FInHeader then
      Issue(aisWarning, '', '<EOR> inside the header; ignored')
    else
      FinishRecord;
    Exit;
  end;

  Parts := Tag.Split(':');
  if (Length(Parts) < 2) or (Length(Parts) > 3) then
  begin
    Issue(aisError, '', Format('malformed tag <%s>; skipped', [Tag]));
    Exit;
  end;
  Name := UpperCase(Parts[0]);
  LengthText := Trim(Parts[1]);
  if Length(Parts) = 3 then
    DataType := UpperCase(Trim(Parts[2]))
  else
    DataType := '';
  { Decimal digits only: TryStrToInt would also accept '$4', '0x4' or '-4'. }
  if not IsDecimalDigits(LengthText) or not TryStrToInt(LengthText, DataLength) then
  begin
    Issue(aisError, Name, Format('invalid data length in <%s>; skipped', [Tag]));
    Exit;
  end;
  Value := ReadValue(Name, DataLength);
  if not IsValidAdifFieldName(Name) then
  begin
    Issue(aisError, Name, 'invalid field name; skipped');
    Exit;
  end;
  if FRecord.Has(Name) then
  begin
    Issue(aisWarning, Name, 'field repeated; the first value is kept');
    Exit;
  end;
  FRecord.Add(Name, Value, DataType);
end;

procedure TAdiReader.Read(const AText: string; const ADocument: TAdifDocument;
  const AIssues: TAdifIssues);
var
  NextTag: Integer;
begin
  FText := AText;
  FDocument := ADocument;
  FIssues := AIssues;
  FDocument.Clear;
  FPosition := 1;
  { A UTF-8 byte order mark is not text of the header. }
  if Copy(FText, 1, 3) = #$EF#$BB#$BF then
    FPosition := 4;
  { IV.A.3 decides on the first character. When only blanks come before the
    first tag, the file is read as headerless unless it has an <EOH> tag, so
    neither its QSOs nor a whitespace-only header are lost. }
  NextTag := FPosition;
  while (NextTag <= Length(FText)) and (FText[NextTag] in [' ', #9, #10, #13]) do
    Inc(NextTag);
  if (NextTag <= Length(FText)) and (FText[NextTag] <> '<') then
    FInHeader := True
  else
    FInHeader := (NextTag > FPosition) and (Pos('<EOH>', UpperCase(FText)) > 0);
  FDocument.HasHeader := FInHeader;
  if FInHeader then
  begin
    NextTag := Pos('<', FText, FPosition);
    if NextTag = 0 then
      NextTag := Length(FText) + 1;
    FDocument.HeaderText := TrimRight(Copy(FText, FPosition, NextTag - FPosition));
    FPosition := NextTag;
  end;
  FRecord := TAdifRecord.Create;
  try
    while FPosition <= Length(FText) do
    begin
      NextTag := Pos('<', FText, FPosition);
      if NextTag = 0 then
        Break;
      FPosition := NextTag;
      ReadTag;
    end;
    if FInHeader then
    begin
      Issue(aisError, '', 'the header has no <EOH>; no records read');
      FDocument.Header.Assign(FRecord);
    end
    else if FRecord.Count > 0 then
    begin
      Issue(aisWarning, '', 'the last record has no <EOR>; kept');
      FinishRecord;
    end;
  finally
    FRecord.Free;
    FRecord := nil;
  end;
end;

procedure ReadAdi(const AText: string; const ADocument: TAdifDocument;
  const AIssues: TAdifIssues);
var
  Reader: TAdiReader;
begin
  Reader := TAdiReader.Create;
  try
    Reader.Read(AText, ADocument, AIssues);
  finally
    Reader.Free;
  end;
end;

{ Writer }

function DataSpecifier(const AField: TAdifField): string;
begin
  Result := '<' + AField.Name + ':' + IntToStr(Length(AField.Value));
  if AField.DataType <> '' then
    Result := Result + ':' + AField.DataType;
  Result := Result + '>' + AField.Value;
end;

function WriteAdi(const ADocument: TAdifDocument): string;
var
  Builder: TStringList;
  Line: string;
  RecordIndex, FieldIndex: Integer;
  Fields: TAdifRecord;
begin
  Builder := TStringList.Create;
  try
    Builder.LineBreak := LineBreak;
    if ADocument.HasHeader then
    begin
      { A header must not start with '<'. }
      { The header text must not contain '<' (it would start a tag) and must
        not be blank (a reader could not tell it from no header). }
      if (Trim(ADocument.HeaderText) = '') or (Pos('<', ADocument.HeaderText) > 0) then
        Builder.Add('ADIF export')
      else
        Builder.Add(ADocument.HeaderText);
      for FieldIndex := 0 to ADocument.Header.Count - 1 do
        Builder.Add(DataSpecifier(ADocument.Header[FieldIndex]));
      Builder.Add('<EOH>');
    end;
    for RecordIndex := 0 to ADocument.RecordCount - 1 do
    begin
      Fields := ADocument[RecordIndex];
      Line := '';
      for FieldIndex := 0 to Fields.Count - 1 do
        Line := Line + DataSpecifier(Fields[FieldIndex]) + ' ';
      Builder.Add(Line + '<EOR>');
    end;
    Result := Builder.Text;
  finally
    Builder.Free;
  end;
end;

end.
