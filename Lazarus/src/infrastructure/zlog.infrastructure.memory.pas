unit ZLog.Infrastructure.Memory;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, SyncObjs, ZLog.Domain.Qso, ZLog.Application.Ports;

type
  TInMemoryQsoRepository = class(TInterfacedObject, IQsoRepository)
  private
    FItems: TList;
    FIndex: TStringList;
    FLock: TCriticalSection;
    function IndexOfId(const AId: string): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AQso: TQso);
    function Count: Integer;
    function FindById(const AId: string): TQso;
    function GetRecent(const AMaximumCount: Integer): TQsoSnapshotArray;
  end;

implementation

constructor TInMemoryQsoRepository.Create;
begin
  inherited Create;
  FItems := TList.Create;
  FIndex := TStringList.Create;
  FLock := TCriticalSection.Create;
  FIndex.Sorted := True;
  FIndex.CaseSensitive := True;
  FIndex.Duplicates := dupError;
  FIndex.OwnsObjects := False;
end;

destructor TInMemoryQsoRepository.Destroy;
begin
  while FItems.Count > 0 do
  begin
    TObject(FItems[FItems.Count - 1]).Free;
    FItems.Delete(FItems.Count - 1);
  end;
  FIndex.Free;
  FItems.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TInMemoryQsoRepository.Add(const AQso: TQso);
var
  Stored: TQso;
begin
  if not Assigned(AQso) then
    raise EArgumentNilException.Create('AQso');
  FLock.Acquire;
  try
    if IndexOfId(AQso.Id) >= 0 then
      raise EListError.CreateFmt('Duplicate QSO identifier: %s', [AQso.Id]);
    Stored := AQso.Clone;
    try
      FItems.Add(Stored);
      try
        FIndex.AddObject(Stored.Id, Stored);
      except
        FItems.Delete(FItems.Count - 1);
        raise;
      end;
    except
      Stored.Free;
      raise;
    end;
  finally
    FLock.Release;
  end;
end;

function TInMemoryQsoRepository.IndexOfId(const AId: string): Integer;
begin
  if not FIndex.Find(AId, Result) then
    Result := -1;
end;

function TInMemoryQsoRepository.Count: Integer;
begin
  FLock.Acquire;
  try
    Result := FItems.Count;
  finally
    FLock.Release;
  end;
end;

function TInMemoryQsoRepository.FindById(const AId: string): TQso;
var
  Index: Integer;
begin
  Result := nil;
  FLock.Acquire;
  try
    Index := IndexOfId(AId);
    if Index >= 0 then
      Result := TQso(FIndex.Objects[Index]).Clone;
  finally
    FLock.Release;
  end;
end;

function TInMemoryQsoRepository.GetRecent(
  const AMaximumCount: Integer): TQsoSnapshotArray;
var
  ResultCount: Integer;
  ResultIndex: Integer;
  SourceIndex: Integer;
begin
  if AMaximumCount < 0 then
    raise EArgumentOutOfRangeException.Create('AMaximumCount must not be negative');
  FLock.Acquire;
  try
    ResultCount := AMaximumCount;
    if ResultCount > FItems.Count then
      ResultCount := FItems.Count;
    SetLength(Result, ResultCount);
    for ResultIndex := 0 to ResultCount - 1 do
    begin
      SourceIndex := FItems.Count - 1 - ResultIndex;
      Result[ResultIndex] := TQso(FItems[SourceIndex]).ToSnapshot;
    end;
  finally
    FLock.Release;
  end;
end;

end.
