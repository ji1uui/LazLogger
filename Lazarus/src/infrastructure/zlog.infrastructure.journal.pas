unit ZLog.Infrastructure.Journal;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, ZLog.Domain.Types, ZLog.Domain.Qso,
  ZLog.Application.Ports, ZLog.Infrastructure.Memory;

type
  EJournalError = class(Exception);
  EJournalCorrupt = class(EJournalError);

  { Add returns only after the append-only record has been flushed. }
  TJournalQsoRepository = class(TInterfacedObject, IQsoRepository)
  private
    FFileName: string;
    FMemory: IQsoRepository;
    FStream: TFileStream;
    procedure LoadAndRecover;
    procedure AppendRecord(const AQso: TQso);
  public
    constructor Create(const AFileName: string);
    destructor Destroy; override;
    procedure Add(const AQso: TQso);
    function Count: Integer;
    function FindById(const AId: string): TQso;
    property FileName: string read FFileName;
  end;

implementation

const
  RecordMagic: array[0..3] of Byte = ($5A, $51, $53, $4F); { ZQSO }
  PayloadVersion = 1;
  HeaderSize = 12;
  MaximumPayloadSize = 1024 * 1024;

procedure WriteUInt32LE(const AStream: TStream; const AValue: LongWord);
var
  Buffer: array[0..3] of Byte;
begin
  Buffer[0] := AValue and $FF;
  Buffer[1] := (AValue shr 8) and $FF;
  Buffer[2] := (AValue shr 16) and $FF;
  Buffer[3] := (AValue shr 24) and $FF;
  AStream.WriteBuffer(Buffer, SizeOf(Buffer));
end;

function ReadUInt32LE(const AStream: TStream): LongWord;
var
  Buffer: array[0..3] of Byte;
begin
  AStream.ReadBuffer(Buffer, SizeOf(Buffer));
  Result := LongWord(Buffer[0]) or (LongWord(Buffer[1]) shl 8) or
    (LongWord(Buffer[2]) shl 16) or (LongWord(Buffer[3]) shl 24);
end;

procedure WriteInt64LE(const AStream: TStream; const AValue: Int64);
var
  Index: Integer;
  Value: QWord;
  Octet: Byte;
begin
  Value := QWord(AValue);
  for Index := 0 to 7 do
  begin
    Octet := (Value shr (Index * 8)) and $FF;
    AStream.WriteBuffer(Octet, SizeOf(Octet));
  end;
end;

function ReadInt64LE(const AStream: TStream): Int64;
var
  Index: Integer;
  Octet: Byte;
  Value: QWord;
begin
  Value := 0;
  for Index := 0 to 7 do
  begin
    AStream.ReadBuffer(Octet, SizeOf(Octet));
    Value := Value or (QWord(Octet) shl (Index * 8));
  end;
  Result := Int64(Value);
end;

procedure WriteText(const AStream: TStream; const AValue: UnicodeString);
var
  ByteLength: LongWord;
  Encoded: UTF8String;
begin
  Encoded := UTF8Encode(AValue);
  ByteLength := Length(Encoded);
  WriteUInt32LE(AStream, ByteLength);
  if ByteLength > 0 then
    AStream.WriteBuffer(Encoded[1], ByteLength);
end;

function ReadText(const AStream: TStream): UnicodeString;
var
  ByteLength: LongWord;
  Encoded: UTF8String;
begin
  ByteLength := ReadUInt32LE(AStream);
  if ByteLength > MaximumPayloadSize then
    raise EJournalCorrupt.Create('Journal string exceeds the safety limit');
  SetLength(Encoded, ByteLength);
  if ByteLength > 0 then
    AStream.ReadBuffer(Encoded[1], ByteLength);
  Result := UTF8Decode(Encoded);
end;

function CalculateCrc32(const ABuffer; const ALength: LongWord): LongWord;
const
  Polynomial = LongWord($EDB88320);
var
  Bytes: PByte;
  Index: LongWord;
  BitIndex: Integer;
begin
  Result := $FFFFFFFF;
  Bytes := @ABuffer;
  if ALength > 0 then
    for Index := 0 to ALength - 1 do
    begin
      Result := Result xor Bytes[Index];
      for BitIndex := 0 to 7 do
        if (Result and 1) <> 0 then
          Result := (Result shr 1) xor Polynomial
        else
          Result := Result shr 1;
    end;
  Result := not Result;
end;

function PayloadCrc(const APayload: TMemoryStream): LongWord;
begin
  if APayload.Size = 0 then
    Result := 0
  else
    Result := CalculateCrc32(APayload.Memory^, APayload.Size);
end;

function SerializeQso(const AQso: TQso): TMemoryStream;
var
  Version: Byte;
  ModeValue: Byte;
begin
  Result := TMemoryStream.Create;
  Version := PayloadVersion;
  Result.WriteBuffer(Version, SizeOf(Version));
  WriteText(Result, UnicodeString(AQso.Id));
  WriteText(Result, AQso.Callsign.ToString);
  WriteInt64LE(Result, AQso.Frequency.ToInt64);
  ModeValue := Ord(AQso.Mode);
  Result.WriteBuffer(ModeValue, SizeOf(ModeValue));
  WriteText(Result, AQso.SentExchange);
  WriteText(Result, AQso.ReceivedExchange);
  WriteInt64LE(Result, AQso.OccurredAtUtcMs);
  Result.Position := 0;
end;

function DeserializeQso(const APayload: TMemoryStream): TQso;
var
  Version: Byte;
  Id: string;
  CallsignText, SentExchange, ReceivedExchange: UnicodeString;
  Callsign: TCallsign;
  Frequency: TFrequencyHz;
  FrequencyValue, OccurredAtUtcMs: Int64;
  ModeValue: Byte;
begin
  APayload.Position := 0;
  APayload.ReadBuffer(Version, SizeOf(Version));
  if Version <> PayloadVersion then
    raise EJournalCorrupt.CreateFmt('Unsupported journal payload version: %d', [Version]);
  Id := string(ReadText(APayload));
  CallsignText := ReadText(APayload);
  FrequencyValue := ReadInt64LE(APayload);
  APayload.ReadBuffer(ModeValue, SizeOf(ModeValue));
  SentExchange := ReadText(APayload);
  ReceivedExchange := ReadText(APayload);
  OccurredAtUtcMs := ReadInt64LE(APayload);

  if (Id = '') or not TCallsign.TryCreate(CallsignText, Callsign) or
    not TFrequencyHz.TryCreate(FrequencyValue, Frequency) or
    (ModeValue <= Ord(emUnknown)) or (ModeValue > Ord(High(TEmissionMode))) or
    (APayload.Position <> APayload.Size) then
    raise EJournalCorrupt.Create('Invalid QSO payload in journal');
  Result := TQso.Create(Id, Callsign, Frequency, TEmissionMode(ModeValue),
    SentExchange, ReceivedExchange, OccurredAtUtcMs);
end;

constructor TJournalQsoRepository.Create(const AFileName: string);
var
  DirectoryName: string;
begin
  inherited Create;
  if Trim(AFileName) = '' then
    raise EArgumentException.Create('Journal filename must not be empty');
  FFileName := ExpandFileName(AFileName);
  DirectoryName := ExtractFileDir(FFileName);
  if (DirectoryName <> '') and not DirectoryExists(DirectoryName) and
    not ForceDirectories(DirectoryName) then
    raise EJournalError.CreateFmt('Cannot create journal directory: %s', [DirectoryName]);
  FMemory := TInMemoryQsoRepository.Create;
  if FileExists(FFileName) then
    FStream := TFileStream.Create(FFileName, fmOpenReadWrite or fmShareDenyWrite)
  else
    FStream := TFileStream.Create(FFileName, fmCreate or fmShareDenyWrite);
  LoadAndRecover;
end;

destructor TJournalQsoRepository.Destroy;
begin
  FStream.Free;
  FMemory := nil;
  inherited Destroy;
end;

procedure TJournalQsoRepository.LoadAndRecover;
var
  RecordStart, LastCompletePosition: Int64;
  Magic: array[0..3] of Byte;
  PayloadLength, ExpectedCrc: LongWord;
  Payload: TMemoryStream;
  Qso: TQso;
begin
  FStream.Position := 0;
  LastCompletePosition := 0;
  while FStream.Position < FStream.Size do
  begin
    RecordStart := FStream.Position;
    if FStream.Size - RecordStart < HeaderSize then
      Break;
    FStream.ReadBuffer(Magic, SizeOf(Magic));
    if not CompareMem(@Magic[0], @RecordMagic[0], SizeOf(Magic)) then
      raise EJournalCorrupt.CreateFmt('Invalid record marker at byte %d', [RecordStart]);
    PayloadLength := ReadUInt32LE(FStream);
    ExpectedCrc := ReadUInt32LE(FStream);
    if PayloadLength > MaximumPayloadSize then
      raise EJournalCorrupt.CreateFmt('Record at byte %d is too large', [RecordStart]);
    if FStream.Size - FStream.Position < PayloadLength then
      Break;
    Payload := TMemoryStream.Create;
    try
      Payload.CopyFrom(FStream, PayloadLength);
      if PayloadCrc(Payload) <> ExpectedCrc then
        raise EJournalCorrupt.CreateFmt('CRC mismatch at byte %d', [RecordStart]);
      Qso := DeserializeQso(Payload);
      try
        FMemory.Add(Qso);
      finally
        Qso.Free;
      end;
    finally
      Payload.Free;
    end;
    LastCompletePosition := FStream.Position;
  end;
  if LastCompletePosition <> FStream.Size then
    FStream.Size := LastCompletePosition;
  FStream.Position := FStream.Size;
end;

procedure TJournalQsoRepository.AppendRecord(const AQso: TQso);
var
  Payload: TMemoryStream;
  RecordStart: Int64;
begin
  Payload := SerializeQso(AQso);
  try
    RecordStart := FStream.Size;
    try
      FStream.Position := RecordStart;
      FStream.WriteBuffer(RecordMagic, SizeOf(RecordMagic));
      WriteUInt32LE(FStream, Payload.Size);
      WriteUInt32LE(FStream, PayloadCrc(Payload));
      FStream.CopyFrom(Payload, 0);
      if not FileFlush(FStream.Handle) then
        raise EJournalError.CreateFmt('Unable to flush journal: %s', [FFileName]);
    except
      { Keep this repository usable when an append fails before acknowledgement. }
      try
        FStream.Size := RecordStart;
        FStream.Position := RecordStart;
      except
        { The original write exception is more useful; reopen will recover the tail. }
      end;
      raise;
    end;
  finally
    Payload.Free;
  end;
end;

procedure TJournalQsoRepository.Add(const AQso: TQso);
var
  Existing: TQso;
begin
  if not Assigned(AQso) then
    raise EArgumentNilException.Create('AQso');
  Existing := FMemory.FindById(AQso.Id);
  try
    if Assigned(Existing) then
      raise EJournalError.CreateFmt('Duplicate QSO identifier: %s', [AQso.Id]);
  finally
    Existing.Free;
  end;
  AppendRecord(AQso);
  FMemory.Add(AQso);
end;

function TJournalQsoRepository.Count: Integer;
begin
  Result := FMemory.Count;
end;

function TJournalQsoRepository.FindById(const AId: string): TQso;
begin
  Result := FMemory.FindById(AId);
end;

end.
