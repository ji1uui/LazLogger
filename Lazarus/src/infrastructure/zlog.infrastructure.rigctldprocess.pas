unit ZLog.Infrastructure.RigctldProcess;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Process, ZLog.Infrastructure.Rigctld;

type
  TRigctldProcessSession = class(TInterfacedObject, IRigctldProcessSession)
  private
    FExecutable: string;
    FParameters: TStringList;
    FProcess: TProcess;
    FReadBuffer: RawByteString;
    procedure DrainErrorOutput;
    function TryExtractLine(out ALine: string): Boolean;
  public
    constructor Create(const AExecutable: string;
      const AParameters: TStrings = nil);
    destructor Destroy; override;
    function Start: Boolean;
    procedure Stop;
    function IsRunning: Boolean;
    function Exchange(const ACommand: string; const ATimeoutMs: Integer;
      out AResponse: string): TRigctldTransportResult;
  end;

implementation

const
  PipePollIntervalMs = 2;
  StopWaitMs = 1000;
  MaximumResponseBytes = 64 * 1024;

constructor TRigctldProcessSession.Create(const AExecutable: string;
  const AParameters: TStrings);
begin
  inherited Create;
  if Trim(AExecutable) = '' then
    raise EArgumentException.Create('AExecutable must not be empty');
  FExecutable := AExecutable;
  FParameters := TStringList.Create;
  if Assigned(AParameters) then
    FParameters.Assign(AParameters);
end;

destructor TRigctldProcessSession.Destroy;
begin
  Stop;
  FParameters.Free;
  inherited Destroy;
end;

function TRigctldProcessSession.Start: Boolean;
begin
  if IsRunning then
    Exit(True);
  FreeAndNil(FProcess);
  FReadBuffer := '';
  FProcess := TProcess.Create(nil);
  try
    FProcess.Executable := FExecutable;
    FProcess.Parameters.Assign(FParameters);
    FProcess.Options := [poUsePipes];
    FProcess.Execute;
    Result := FProcess.Running;
    if not Result then
      FreeAndNil(FProcess);
  except
    FreeAndNil(FProcess);
    Result := False;
  end;
end;

procedure TRigctldProcessSession.Stop;
var
  Deadline: QWord;
begin
  if not Assigned(FProcess) then
    Exit;
  if FProcess.Running then
  begin
    FProcess.Terminate(0);
    Deadline := GetTickCount64 + StopWaitMs;
    while FProcess.Running and (GetTickCount64 < Deadline) do
      Sleep(PipePollIntervalMs);
  end;
  FreeAndNil(FProcess);
  FReadBuffer := '';
end;

function TRigctldProcessSession.IsRunning: Boolean;
begin
  Result := Assigned(FProcess) and FProcess.Running;
end;

procedure TRigctldProcessSession.DrainErrorOutput;
var
  Buffer: array[0..1023] of Byte;
  Count: LongInt;
begin
  if not Assigned(FProcess) then
    Exit;
  Count := FProcess.Stderr.NumBytesAvailable;
  if Count > SizeOf(Buffer) then
    Count := SizeOf(Buffer);
  if Count > 0 then
    FProcess.Stderr.Read(Buffer, Count);
end;

function TRigctldProcessSession.TryExtractLine(out ALine: string): Boolean;
var
  LineEnd: SizeInt;
  RawLine: RawByteString;
begin
  LineEnd := Pos(#10, FReadBuffer);
  Result := LineEnd > 0;
  if not Result then
    Exit;
  RawLine := Copy(FReadBuffer, 1, LineEnd - 1);
  Delete(FReadBuffer, 1, LineEnd);
  if (Length(RawLine) > 0) and (RawLine[Length(RawLine)] = #13) then
    Delete(RawLine, Length(RawLine), 1);
  ALine := string(RawLine);
end;

function TRigctldProcessSession.Exchange(const ACommand: string;
  const ATimeoutMs: Integer; out AResponse: string): TRigctldTransportResult;
var
  Request: RawByteString;
  Chunk: RawByteString;
  Buffer: array[0..4095] of Byte;
  Count: LongInt;
  Deadline: QWord;
begin
  AResponse := '';
  if ATimeoutMs <= 0 then
    Exit(rtrProtocolError);
  if not IsRunning then
    Exit(rtrDisconnected);
  Request := RawByteString(ACommand + LineEnding);
  try
    FProcess.Input.WriteBuffer(Request[1], Length(Request));
  except
    Exit(rtrDisconnected);
  end;

  Deadline := GetTickCount64 + QWord(ATimeoutMs);
  repeat
    DrainErrorOutput;
    if TryExtractLine(AResponse) then
      Exit(rtrSuccess);
    if FProcess.Output.NumBytesAvailable > 0 then
    begin
      Count := FProcess.Output.NumBytesAvailable;
      if Count > SizeOf(Buffer) then
        Count := SizeOf(Buffer);
      Count := FProcess.Output.Read(Buffer, Count);
      if Count > 0 then
      begin
        SetString(Chunk, PAnsiChar(@Buffer[0]), Count);
        FReadBuffer := FReadBuffer + Chunk;
        if Length(FReadBuffer) > MaximumResponseBytes then
          Exit(rtrProtocolError);
      end;
      Continue;
    end;
    if not FProcess.Running then
      Exit(rtrDisconnected);
    Sleep(PipePollIntervalMs);
  until GetTickCount64 >= Deadline;
  Result := rtrTimeout;
end;

end.
