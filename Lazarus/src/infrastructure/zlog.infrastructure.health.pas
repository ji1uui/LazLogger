unit ZLog.Infrastructure.Health;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, SyncObjs, ZLog.Application.Diagnostics;

type
  TInMemoryHealthMonitor = class(TInterfacedObject, IDiagnosticSink,
    IHealthQuery)
  private
    FLock: TCriticalSection;
    FState: THealthSnapshot;
    class function BoundedText(const AValue: string): string; static;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Report(const ACode: TDiagnosticCode;
      const ASeverity: TDiagnosticSeverity; const AComponent,
      AMessage: string);
    procedure ReportHealthy(const AComponent: string);
    function Snapshot: THealthSnapshot;
  end;

implementation

const
  MaximumDiagnosticTextLength = 256;

constructor TInMemoryHealthMonitor.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FState.Status := hsHealthy;
  FState.LastCode := dcNone;
end;

destructor TInMemoryHealthMonitor.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

class function TInMemoryHealthMonitor.BoundedText(
  const AValue: string): string;
begin
  Result := Copy(AValue, 1, MaximumDiagnosticTextLength);
end;

procedure TInMemoryHealthMonitor.Report(const ACode: TDiagnosticCode;
  const ASeverity: TDiagnosticSeverity; const AComponent, AMessage: string);
begin
  FLock.Acquire;
  try
    case ASeverity of
      dsWarning:
        begin
          Inc(FState.WarningCount);
          FState.Status := hsDegraded;
        end;
      dsError:
        begin
          Inc(FState.ErrorCount);
          FState.Status := hsDegraded;
        end;
      dsCritical:
        begin
          Inc(FState.ErrorCount);
          FState.Status := hsFailed;
        end;
    end;
    FState.LastCode := ACode;
    FState.LastComponent := BoundedText(AComponent);
    FState.LastMessage := BoundedText(AMessage);
  finally
    FLock.Release;
  end;
end;

procedure TInMemoryHealthMonitor.ReportHealthy(const AComponent: string);
begin
  FLock.Acquire;
  try
    if (FState.Status <> hsHealthy) and
      (FState.LastComponent <> BoundedText(AComponent)) then
      Exit;
    FState.Status := hsHealthy;
    FState.LastCode := dcNone;
    FState.LastComponent := BoundedText(AComponent);
    FState.LastMessage := '';
  finally
    FLock.Release;
  end;
end;

function TInMemoryHealthMonitor.Snapshot: THealthSnapshot;
begin
  FLock.Acquire;
  try
    Result := FState;
  finally
    FLock.Release;
  end;
end;

end.
