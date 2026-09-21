unit ZLog.Application.Rig;

{$mode objfpc}{$H+}

interface

type
  TRigConnectionState = (rcsDisconnected, rcsConnecting, rcsReady,
    rcsDegraded);

  TRigSnapshot = record
    State: TRigConnectionState;
    FrequencyHz: Int64;
    PendingFrequencyHz: Int64;
    HasPendingFrequency: Boolean;
    ConsecutiveFailures: Integer;
    NextRetryAtMs: Int64;
  end;

  IRigCommandPort = interface
    ['{299CC97D-FB54-4167-BB63-E852BE0F6DA2}']
    { Non-blocking: replaces an older unsent frequency with the latest value. }
    function RequestFrequency(const AFrequencyHz: Int64): Boolean;
    procedure RequestRefresh;
    function Snapshot: TRigSnapshot;
  end;

  IRigWorkPump = interface
    ['{B5DE39D2-B419-4807-A964-3A06DCE74F76}']
    { Called only by a dedicated rig worker, never by the UI thread. }
    function ProcessNext(const ANowMs: Int64): Boolean;
  end;

implementation

end.
