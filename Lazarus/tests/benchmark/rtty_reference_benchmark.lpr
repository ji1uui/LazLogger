program ZLogRttyReferenceBenchmark;

{$mode objfpc}{$H+}

uses
  SysUtils, ZLog.Application.Rtty, ZLog.Infrastructure.RttyReference;

const
  BitCount = 10000;

var
  Profile: TRttyProfile;
  Generator: IRttyWaveformGenerator;
  Demodulator: IRttyBitDemodulator;
  Bits: TByteArray;
  Decoded: TByteArray;
  Samples: TSingleArray;
  Confidence: TSingleArray;
  Index: Integer;
  Errors: Integer;
  StartedAt: QWord;
  ElapsedMs: QWord;
  ConfidenceTotal: Double;
begin
  if not TRttyProfile.TryCreate(8000, 45.45, 2125, 2295, False,
    Profile) then
    Halt(1);
  SetLength(Bits, BitCount);
  for Index := 0 to High(Bits) do
    Bits[Index] := ((Index * 17) xor (Index shr 2)) and 1;
  Generator := TScalarRttyWaveformGenerator.Create(Profile);
  Demodulator := TScalarRttyBitDemodulator.Create(Profile);
  Samples := Generator.Generate(Bits);
  StartedAt := GetTickCount64;
  if not Demodulator.Decode(Samples, Length(Bits), Decoded, Confidence) then
    Halt(1);
  ElapsedMs := GetTickCount64 - StartedAt;
  Errors := 0;
  ConfidenceTotal := 0;
  for Index := 0 to High(Bits) do
  begin
    if Decoded[Index] <> Bits[Index] then
      Inc(Errors);
    ConfidenceTotal := ConfidenceTotal + Confidence[Index];
  end;
  WriteLn('{');
  WriteLn('  "bits": ', BitCount, ',');
  WriteLn('  "samples": ', Length(Samples), ',');
  WriteLn('  "elapsed_ms": ', ElapsedMs, ',');
  if ElapsedMs = 0 then
    WriteLn('  "bits_per_second": 0,')
  else
    WriteLn('  "bits_per_second": ', (QWord(BitCount) * 1000) div ElapsedMs, ',');
  WriteLn('  "bit_errors": ', Errors, ',');
  WriteLn('  "mean_confidence_ppm": ',
    Round((ConfidenceTotal / BitCount) * 1000000));
  WriteLn('}');
  if Errors <> 0 then
    Halt(1);
end.
