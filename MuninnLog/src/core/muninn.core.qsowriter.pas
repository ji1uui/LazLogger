unit Muninn.Core.QsoWriter;

{ The QSO writer port: saves QSOs without making the caller wait for the
  disk (docs/04_ARCHITECTURE.md section 7, ADR 0011). Submit queues a QSO and
  returns a ticket at once; the result arrives later on the main thread
  (queued with TThread.Queue, so a program without the LCL calls
  CheckSynchronize). Results arrive in submission order. A QSO reported saved
  is on disk and survives a crash; one still pending may not. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Muninn.Core.Qso;

type
  { The queue is full: the disk has not kept up for a long time. }
  EQsoQueueFull = class(Exception);

  TQsoSavedEvent = procedure(const ATicket: Int64; const AQsoId: string) of object;
  { The QSO stays queued and is tried again; it may still be saved. }
  TQsoSaveFailedEvent = procedure(const ATicket: Int64;
    const AMessage: string) of object;

  IQsoWriter = interface
    ['{2B7E4D19-8C3A-4F61-B0D5-9E1A6C3F7B28}']
    { Takes ownership of AQso, also when it raises (EQsoQueueFull). }
    function Submit(const AQso: TQsoRecord): Int64;
    function PendingCount: Integer;
    procedure SetOnSaved(AHandler: TQsoSavedEvent);
    procedure SetOnFailed(AHandler: TQsoSaveFailedEvent);
    { Waits up to ATimeoutMs for every queued QSO to be saved; True when none
      is left. Results are still delivered through the queue. }
    function Flush(const ATimeoutMs: Cardinal): Boolean;
  end;

implementation

end.
