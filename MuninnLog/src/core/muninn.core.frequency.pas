unit Muninn.Core.Frequency;

{ Frequency value object held as integer hertz, so no rounding can move a QSO
  across a band edge. }

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

const
  { Upper edge of the ADIF "submm" band (7,500,000 MHz). }
  MaximumFrequencyHz = Int64(7500000000000);

type
  TFrequencyHz = record
  private
    FValue: Int64;
  public
    class function TryFromHz(const AHz: Int64;
      out AFrequency: TFrequencyHz): Boolean; static;
    function Hz: Int64;
    function Equals(const AOther: TFrequencyHz): Boolean;
  end;

implementation

class function TFrequencyHz.TryFromHz(const AHz: Int64;
  out AFrequency: TFrequencyHz): Boolean;
begin
  Result := (AHz > 0) and (AHz <= MaximumFrequencyHz);
  if Result then
    AFrequency.FValue := AHz
  else
    AFrequency.FValue := 0;
end;

function TFrequencyHz.Hz: Int64;
begin
  Result := FValue;
end;

function TFrequencyHz.Equals(const AOther: TFrequencyHz): Boolean;
begin
  Result := FValue = AOther.FValue;
end;

end.
