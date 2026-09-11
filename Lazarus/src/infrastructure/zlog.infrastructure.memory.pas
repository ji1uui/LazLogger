unit ZLog.Infrastructure.Memory;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, ZLog.Domain.Qso, ZLog.Application.Ports;

type
  TInMemoryQsoRepository = class(TInterfacedObject, IQsoRepository)
  private
    FItems: TStringList;
    function IndexOfId(const AId: string): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AQso: TQso);
    function Count: Integer;
    function FindById(const AId: string): TQso;
  end;

implementation

constructor TInMemoryQsoRepository.Create;
begin
  inherited Create;
  FItems := TStringList.Create;
  FItems.Sorted := True;
  FItems.CaseSensitive := True;
  FItems.Duplicates := dupError;
  FItems.OwnsObjects := True;
end;

destructor TInMemoryQsoRepository.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TInMemoryQsoRepository.Add(const AQso: TQso);
begin
  if not Assigned(AQso) then
    raise EArgumentNilException.Create('AQso');
  if IndexOfId(AQso.Id) >= 0 then
    raise EListError.CreateFmt('Duplicate QSO identifier: %s', [AQso.Id]);
  FItems.AddObject(AQso.Id, AQso.Clone);
end;

function TInMemoryQsoRepository.IndexOfId(const AId: string): Integer;
begin
  if not FItems.Find(AId, Result) then
    Result := -1;
end;

function TInMemoryQsoRepository.Count: Integer;
begin
  Result := FItems.Count;
end;

function TInMemoryQsoRepository.FindById(const AId: string): TQso;
var
  Index: Integer;
begin
  Result := nil;
  Index := IndexOfId(AId);
  if Index >= 0 then
    Result := TQso(FItems.Objects[Index]).Clone;
end;

end.
