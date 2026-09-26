unit ZLog.Application.Rtty;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

type
  TByteArray = array of Byte;
  TSingleArray = array of Single;

  TRttyProfile = record
    SampleRate: Integer;
    Baud: Double;
    MarkHz: Double;
    SpaceHz: Double;
    Reversed: Boolean;
    class function TryCreate(const ASampleRate: Integer; const ABaud,
      AMarkHz, ASpaceHz: Double; const AReversed: Boolean;
      out AProfile: TRttyProfile): Boolean; static;
  end;

  IRttyWaveformGenerator = interface
    ['{03057540-9419-4214-B797-136FC6FB17E5}']
    function Generate(const ABits: array of Byte): TSingleArray;
  end;

  IRttyBitDemodulator = interface
    ['{85EF5170-E002-438A-BFD8-B855714DC9D5}']
    function Decode(const ASamples: array of Single;
      const AExpectedBitCount: Integer; out ABits: TByteArray;
      out AConfidence: TSingleArray): Boolean;
  end;

implementation

class function TRttyProfile.TryCreate(const ASampleRate: Integer;
  const ABaud, AMarkHz, ASpaceHz: Double; const AReversed: Boolean;
  out AProfile: TRttyProfile): Boolean;
begin
  AProfile.SampleRate := 0;
  AProfile.Baud := 0;
  AProfile.MarkHz := 0;
  AProfile.SpaceHz := 0;
  AProfile.Reversed := False;
  Result := (ASampleRate >= 8000) and (ASampleRate <= 384000) and
    (ABaud >= 20) and (ABaud <= 1000) and
    (AMarkHz > 0) and (AMarkHz < ASampleRate / 2) and
    (ASpaceHz > 0) and (ASpaceHz < ASampleRate / 2) and
    (Abs(AMarkHz - ASpaceHz) >= 10);
  if Result then
  begin
    AProfile.SampleRate := ASampleRate;
    AProfile.Baud := ABaud;
    AProfile.MarkHz := AMarkHz;
    AProfile.SpaceHz := ASpaceHz;
    AProfile.Reversed := AReversed;
  end;
end;

end.
