unit ZLog.Infrastructure.Runtime;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, DateUtils, ZLog.Application.Ports;

type
  TSystemClock = class(TInterfacedObject, IClock)
  public
    function UtcNowMs: Int64;
  end;

  TGuidIdGenerator = class(TInterfacedObject, IIdGenerator)
  public
    function NextId: string;
  end;

implementation

function TSystemClock.UtcNowMs: Int64;
var
  CurrentTime: TDateTime;
begin
  CurrentTime := Now;
  Result := DateTimeToUnix(CurrentTime, False) * 1000 +
    MilliSecondOf(CurrentTime);
end;

function TGuidIdGenerator.NextId: string;
var
  Value: TGuid;
begin
  if CreateGuid(Value) <> 0 then
    raise EConvertError.Create('Unable to generate a QSO identifier');
  Result := LowerCase(GuidToString(Value));
  Delete(Result, Length(Result), 1);
  Delete(Result, 1, 1);
end;

end.
