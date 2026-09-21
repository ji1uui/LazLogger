unit ZLog.Infrastructure.Health;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, SyncObjs, ZLog.Application.Diagnostics;

type
  TInMemoryHealthMonitor = class(TInterfacedObject, IDiagnosticSink,
    IHealthQuery)
  private type
    TComponentHealth = record
      Name: string;
      Status: THealthStatus;
      Code: TDiagnosticCode;
      Message: string;
    end;
  private
    FLock: TCriticalSection;
    FState: THealthSnapshot;
    FComponents: array[0..15] of TComponentHealth;
    FComponentCount: Integer;
    class function BoundedText(const AValue: string): string; static;
    function FindComponent(const AComponent: string;
      const ACreate: Boolean): Integer;
    procedure RecalculateStatus;
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

function TInMemoryHealthMonitor.FindComponent(const AComponent: string;
  const ACreate: Boolean): Integer;
var
  Index: Integer;
  ComponentName: string;
begin
  ComponentName := BoundedText(AComponent);
  for Index := 0 to FComponentCount - 1 do
    if FComponents[Index].Name = ComponentName then
      Exit(Index);
  if not ACreate or (FComponentCount >= Length(FComponents)) then
    Exit(-1);
  Result := FComponentCount;
  Inc(FComponentCount);
  FComponents[Result].Name := ComponentName;
  FComponents[Result].Status := hsHealthy;
  FComponents[Result].Code := dcNone;
end;

procedure TInMemoryHealthMonitor.RecalculateStatus;
var
  Index: Integer;
  SelectedIndex: Integer;
begin
  FState.Status := hsHealthy;
  SelectedIndex := -1;
  for Index := 0 to FComponentCount - 1 do
    if FComponents[Index].Status > FState.Status then
    begin
      FState.Status := FComponents[Index].Status;
      SelectedIndex := Index;
    end;
  if SelectedIndex < 0 then
  begin
    FState.LastCode := dcNone;
    FState.LastComponent := '';
    FState.LastMessage := '';
  end
  else
  begin
    FState.LastCode := FComponents[SelectedIndex].Code;
    FState.LastComponent := FComponents[SelectedIndex].Name;
    FState.LastMessage := FComponents[SelectedIndex].Message;
  end;
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
var
  ComponentIndex: Integer;
begin
  FLock.Acquire;
  try
    ComponentIndex := FindComponent(AComponent, True);
begin
  FLock.Acquire;
  try
    case ASeverity of
      dsWarning:
        begin
          Inc(FState.WarningCount);
          if ComponentIndex >= 0 then
            FComponents[ComponentIndex].Status := hsDegraded;
          FState.Status := hsDegraded;
        end;
      dsError:
        begin
          Inc(FState.ErrorCount);
          if ComponentIndex >= 0 then
            FComponents[ComponentIndex].Status := hsDegraded;
          FState.Status := hsDegraded;
        end;
      dsCritical:
        begin
          Inc(FState.ErrorCount);
          if ComponentIndex >= 0 then
            FComponents[ComponentIndex].Status := hsFailed;
        end;
    end;
    if ComponentIndex >= 0 then
    begin
      FComponents[ComponentIndex].Code := ACode;
      FComponents[ComponentIndex].Message := BoundedText(AMessage);
    end;
    RecalculateStatus;
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
var
  ComponentIndex: Integer;
begin
  FLock.Acquire;
  try
    ComponentIndex := FindComponent(AComponent, False);
    if ComponentIndex < 0 then
      Exit;
    FComponents[ComponentIndex].Status := hsHealthy;
    FComponents[ComponentIndex].Code := dcNone;
    FComponents[ComponentIndex].Message := '';
    RecalculateStatus;
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
