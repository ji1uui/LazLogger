unit ZLog.Application.Submission;

{$mode objfpc}{$H+}

interface

uses
  ZLog.Domain.Qso, ZLog.Application.LogQso;

type
  IQsoSubmissionObserver = interface
    ['{7996F20E-020C-49E0-A814-6B10791C75F2}']
    { Implementations must deliver this callback on the UI thread. }
    procedure SubmissionCompleted(const AResult: TLogQsoResult);
  end;

  IQsoSubmissionPort = interface
    ['{02E1F7A5-49A6-40E1-BB44-D744DFE24DC2}']
    { Must enqueue work and return without performing repository I/O.
      It retains the observer and completes it exactly once, including cancel and
      worker failure, so the ownership cycle is always released. }
    procedure Submit(const ADraft: TQsoDraft;
      const AObserver: IQsoSubmissionObserver);
  end;

  IQsoCompletionDispatcher = interface
    ['{93817305-08FB-43B5-84BE-A0CF617F7D9D}']
    { Enqueues completion for delivery on the UI thread. }
    procedure Dispatch(const AObserver: IQsoSubmissionObserver;
      const AResult: TLogQsoResult);
  end;

  ISubmissionWorkPump = interface
    ['{019F83D2-4B15-429B-9B82-A8B55836978D}']
    { Called by one persistence worker; never by the UI thread. }
    function ProcessNext: Boolean;
    procedure CancelPending;
    function PendingCount: Integer;
  end;

  IManagedQsoSubmissionPort = interface(IQsoSubmissionPort)
    ['{119B83C5-771D-4D22-A5C5-C09EC0F089B8}']
    { Stops and joins the worker, then cancels work that never started. }
    procedure Shutdown;
  end;

  ICompletionPump = interface
    ['{EB47605B-C069-47C4-8025-3DF9E0D41301}']
    { Called only by the UI thread. Returns the number of callbacks delivered. }
    function Drain(const AMaximumItems: Integer): Integer;
    function PendingCount: Integer;
  end;

implementation

end.
