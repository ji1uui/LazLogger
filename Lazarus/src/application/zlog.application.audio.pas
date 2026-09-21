unit ZLog.Application.Audio;

{$mode objfpc}{$H+}

interface

type
  TAudioQueueSnapshot = record
    Capacity: Integer;
    Available: Integer;
    HighWaterMark: Integer;
    OverrunCount: QWord;
  end;

  IAudioSampleQueue = interface
    ['{7BA288DF-5C9C-4D65-87DE-A56993794D41}']
    { SPSC: exactly one audio producer and one DSP consumer. }
    function TryPush(const ASamples: array of Single): Boolean;
    function Pop(var ADestination: array of Single): Integer;
    function Snapshot: TAudioQueueSnapshot;
  end;

implementation

end.
