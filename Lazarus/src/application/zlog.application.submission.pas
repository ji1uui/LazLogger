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

implementation

end.
