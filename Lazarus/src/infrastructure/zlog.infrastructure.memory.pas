unit ZLog.Infrastructure.Memory;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, ZLog.Domain.Qso, ZLog.Application.Ports;

type
  TInMemoryQsoRepository = class(TInterfacedObject, IQsoRepository)
  private
    FItems: TList;
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
  FItems := TList.Create;
end;

destructor TInMemoryQsoRepository.Destroy;
var
  Index: Integer;
begin
  for Index := 0 to FItems.Count - 1 do
    TObject(FItems[Index]).Free;
  FItems.Free;
  inherited Destroy;
end;

procedure TInMemoryQsoRepository.Add(const AQso: TQso);
begin
  if not Assigned(AQso) then
    raise EArgumentNilException.Create('AQso');
  if IndexOfId(AQso.Id) >= 0 then
    raise EListError.CreateFmt('Duplicate QSO identifier: %s', [AQso.Id]);
  FItems.Add(AQso.Clone);
end;

function TInMemoryQsoRepository.IndexOfId(const AId: string): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to FItems.Count - 1 do
    if TQso(FItems[Index]).Id = AId then
      Exit(Index);
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
    Result := TQso(FItems[Index]).Clone;
end;

end.
