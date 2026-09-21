unit ZLog.Infrastructure.Deterministic;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, ZLog.Application.Ports;

type
  TFixedClock = class(TInterfacedObject, IClock)
  private
    FValue: Int64;
  public
    constructor Create(const AValue: Int64);
    function UtcNowMs: Int64;
  end;

  TSequentialIdGenerator = class(TInterfacedObject, IIdGenerator)
  private
    FPrefix: string;
    FNextValue: QWord;
  public
    constructor Create(const APrefix: string; const AFirstValue: QWord = 1);
    function NextId: string;
  end;

implementation

constructor TFixedClock.Create(const AValue: Int64);
begin
  inherited Create;
  FValue := AValue;
end;

function TFixedClock.UtcNowMs: Int64;
begin
  Result := FValue;
end;

constructor TSequentialIdGenerator.Create(const APrefix: string;
  const AFirstValue: QWord);
begin
  inherited Create;
  FPrefix := APrefix;
  FNextValue := AFirstValue;
end;

function TSequentialIdGenerator.NextId: string;
begin
  Result := FPrefix + IntToStr(FNextValue);
  Inc(FNextValue);
end;

end.
