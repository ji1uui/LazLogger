unit ZLog.Infrastructure.AudioRing;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, ZLog.Application.Audio;

type
  TLockFreeSpscAudioRing = class(TInterfacedObject, IAudioSampleQueue)
  private
    FBuffer: array of Single;
    FStorageSize: Integer;
    FCapacity: Integer;
    FReadPosition: LongInt;
    FWritePosition: LongInt;
    FHighWaterMark: LongInt;
    FOverrunCount: LongInt;
    class function AtomicLoad(var AValue: LongInt): LongInt; static;
    function Distance(const AWritePosition, AReadPosition: LongInt): Integer;
  public
    constructor Create(const ACapacity: Integer);
    function TryPush(const ASamples: array of Single): Boolean;
    function Pop(var ADestination: array of Single): Integer;
    function Snapshot: TAudioQueueSnapshot;
  end;

implementation

const
  MaximumAudioQueueCapacity = 16 * 1024 * 1024;

constructor TLockFreeSpscAudioRing.Create(const ACapacity: Integer);
begin
  inherited Create;
  if ACapacity <= 0 then
    raise EArgumentOutOfRangeException.Create('ACapacity must be positive');
  if ACapacity > MaximumAudioQueueCapacity then
    raise EArgumentOutOfRangeException.Create('ACapacity exceeds the safety limit');
  FCapacity := ACapacity;
  FStorageSize := ACapacity + 1;
  SetLength(FBuffer, FStorageSize);
end;

class function TLockFreeSpscAudioRing.AtomicLoad(
  var AValue: LongInt): LongInt;
begin
  Result := InterlockedCompareExchange(AValue, 0, 0);
end;

function TLockFreeSpscAudioRing.Distance(const AWritePosition,
  AReadPosition: LongInt): Integer;
begin
  Result := AWritePosition - AReadPosition;
  if Result < 0 then
    Inc(Result, FStorageSize);
end;

function TLockFreeSpscAudioRing.TryPush(
  const ASamples: array of Single): Boolean;
var
  ReadPosition: LongInt;
  WritePosition: LongInt;
  Available: Integer;
  FreeCount: Integer;
  Index: Integer;
begin
  if Length(ASamples) = 0 then
    Exit(True);
  if Length(ASamples) > FCapacity then
  begin
    InterlockedIncrement(FOverrunCount);
    Exit(False);
  end;
  WritePosition := FWritePosition;
  ReadPosition := AtomicLoad(FReadPosition);
  Available := Distance(WritePosition, ReadPosition);
  FreeCount := FCapacity - Available;
  if Length(ASamples) > FreeCount then
  begin
    InterlockedIncrement(FOverrunCount);
    Exit(False);
  end;
  for Index := 0 to High(ASamples) do
  begin
    FBuffer[WritePosition] := ASamples[Index];
    Inc(WritePosition);
    if WritePosition = FStorageSize then
      WritePosition := 0;
  end;
  InterlockedExchange(FWritePosition, WritePosition);
  Available := Available + Length(ASamples);
  if Available > FHighWaterMark then
    InterlockedExchange(FHighWaterMark, Available);
  Result := True;
end;

function TLockFreeSpscAudioRing.Pop(
  var ADestination: array of Single): Integer;
var
  ReadPosition: LongInt;
  WritePosition: LongInt;
  Index: Integer;
begin
  if Length(ADestination) = 0 then
    Exit(0);
  ReadPosition := FReadPosition;
  WritePosition := AtomicLoad(FWritePosition);
  Result := Distance(WritePosition, ReadPosition);
  if Result > Length(ADestination) then
    Result := Length(ADestination);
  for Index := 0 to Result - 1 do
  begin
    ADestination[Index] := FBuffer[ReadPosition];
    Inc(ReadPosition);
    if ReadPosition = FStorageSize then
      ReadPosition := 0;
  end;
  InterlockedExchange(FReadPosition, ReadPosition);
end;

function TLockFreeSpscAudioRing.Snapshot: TAudioQueueSnapshot;
var
  ReadPosition: LongInt;
  WritePosition: LongInt;
begin
  ReadPosition := AtomicLoad(FReadPosition);
  WritePosition := AtomicLoad(FWritePosition);
  Result.Capacity := FCapacity;
  Result.Available := Distance(WritePosition, ReadPosition);
  Result.HighWaterMark := AtomicLoad(FHighWaterMark);
  Result.OverrunCount := QWord(AtomicLoad(FOverrunCount));
end;

end.
