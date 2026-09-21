program ZLogAudioRingBenchmark;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, ZLog.Application.Audio, ZLog.Infrastructure.AudioRing;

const
  Iterations = 100000;
  BlockSize = 256;
  QueueCapacity = 8192;

var
  Queue: IAudioSampleQueue;
  Input: array[0..BlockSize - 1] of Single;
  Output: array[0..BlockSize - 1] of Single;
  Index: Integer;
  Iteration: Integer;
  StartedAt: QWord;
  ElapsedMs: QWord;
  Snapshot: TAudioQueueSnapshot;
  TotalSamples: QWord;
begin
  for Index := Low(Input) to High(Input) do
    Input[Index] := Index / BlockSize;
  Queue := TLockFreeSpscAudioRing.Create(QueueCapacity);
  StartedAt := GetTickCount64;
  for Iteration := 1 to Iterations do
  begin
    if not Queue.TryPush(Input) then
      Halt(1);
    if Queue.Pop(Output) <> BlockSize then
      Halt(1);
  end;
  ElapsedMs := GetTickCount64 - StartedAt;
  Snapshot := Queue.Snapshot;
  TotalSamples := QWord(Iterations) * BlockSize;
  WriteLn('{');
  WriteLn('  "iterations": ', Iterations, ',');
  WriteLn('  "block_size": ', BlockSize, ',');
  WriteLn('  "samples": ', TotalSamples, ',');
  WriteLn('  "elapsed_ms": ', ElapsedMs, ',');
  if ElapsedMs = 0 then
    WriteLn('  "samples_per_second": 0,')
  else
    WriteLn('  "samples_per_second": ', (TotalSamples * 1000) div ElapsedMs, ',');
  WriteLn('  "high_water_mark": ', Snapshot.HighWaterMark, ',');
  WriteLn('  "overruns": ', Snapshot.OverrunCount);
  WriteLn('}');
end.
