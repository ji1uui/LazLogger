unit ZLog.Application.Diagnostics;

{$mode objfpc}{$H+}

interface

type
  TDiagnosticSeverity = (dsInfo, dsWarning, dsError, dsCritical);
  TDiagnosticCode = (dcNone, dcQsoPersistenceFailed,
    dcCompletionDispatchFailed);
  THealthStatus = (hsHealthy, hsDegraded, hsFailed);

  THealthSnapshot = record
    Status: THealthStatus;
    WarningCount: QWord;
    ErrorCount: QWord;
    LastCode: TDiagnosticCode;
    LastComponent: string;
    LastMessage: string;
  end;

  IDiagnosticSink = interface
    ['{31DA39F8-324B-43D9-A251-04E94D81D847}']
    { Implementations must be thread-safe, bounded, and must not raise. }
    procedure Report(const ACode: TDiagnosticCode;
      const ASeverity: TDiagnosticSeverity; const AComponent,
      AMessage: string);
    procedure ReportHealthy(const AComponent: string);
  end;

  IHealthQuery = interface
    ['{091C0038-B433-4E67-A923-4543FB843478}']
    function Snapshot: THealthSnapshot;
  end;

implementation

end.
