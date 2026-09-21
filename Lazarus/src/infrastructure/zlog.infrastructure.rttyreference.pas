unit ZLog.Infrastructure.RttyReference;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, ZLog.Application.Rtty;

type
  TScalarRttyWaveformGenerator = class(TInterfacedObject,
    IRttyWaveformGenerator)
  private
    FProfile: TRttyProfile;
  public
    constructor Create(const AProfile: TRttyProfile);
    function Generate(const ABits: array of Byte): TSingleArray;
  end;

  TScalarRttyBitDemodulator = class(TInterfacedObject,
    IRttyBitDemodulator)
  private
    FProfile: TRttyProfile;
    function TonePower(const ASamples: array of Single;
      const AFirst, ACount: Integer; const AFrequencyHz: Double): Double;
  public
    constructor Create(const AProfile: TRttyProfile);
    function Decode(const ASamples: array of Single;
      const AExpectedBitCount: Integer; out ABits: TByteArray;
      out AConfidence: TSingleArray): Boolean;
  end;

implementation

const
  WaveformAmplitude = 0.8;
  MinimumPower = 1.0E-20;
  MaximumReferenceSamples = 16 * 1024 * 1024;

constructor TScalarRttyWaveformGenerator.Create(const AProfile: TRttyProfile);
begin
  inherited Create;
  if AProfile.SampleRate <= 0 then
    raise EArgumentException.Create('AProfile is not initialized');
  FProfile := AProfile;
end;

function TScalarRttyWaveformGenerator.Generate(
  const ABits: array of Byte): TSingleArray;
var
  SampleCount: Integer;
  SampleIndex: Integer;
  BitIndex: Integer;
  BitValue: Byte;
  Frequency: Double;
  Phase: Double;
  PhaseStep: Double;
  ExactSampleCount: Double;
begin
  if Length(ABits) = 0 then
  begin
    SetLength(Result, 0);
    Exit;
  end;
  ExactSampleCount := (Double(Length(ABits)) * FProfile.SampleRate) /
    FProfile.Baud;
  if ExactSampleCount > MaximumReferenceSamples then
    raise EArgumentOutOfRangeException.Create('Waveform exceeds the safety limit');
  SampleCount := Ceil(ExactSampleCount);
  SetLength(Result, SampleCount);
  Phase := 0;
  for SampleIndex := 0 to SampleCount - 1 do
  begin
    BitIndex := Trunc((SampleIndex * FProfile.Baud) / FProfile.SampleRate);
    if BitIndex > High(ABits) then
      BitIndex := High(ABits);
    BitValue := ABits[BitIndex] and 1;
    if FProfile.Reversed then
      BitValue := BitValue xor 1;
    if BitValue = 1 then
      Frequency := FProfile.MarkHz
    else
      Frequency := FProfile.SpaceHz;
    Result[SampleIndex] := WaveformAmplitude * Sin(Phase);
    PhaseStep := 2 * Pi * Frequency / FProfile.SampleRate;
    Phase := Phase + PhaseStep;
    if Phase >= 2 * Pi then
      Phase := Phase - 2 * Pi;
  end;
end;

constructor TScalarRttyBitDemodulator.Create(const AProfile: TRttyProfile);
begin
  inherited Create;
  if AProfile.SampleRate <= 0 then
    raise EArgumentException.Create('AProfile is not initialized');
  FProfile := AProfile;
end;

function TScalarRttyBitDemodulator.TonePower(
  const ASamples: array of Single; const AFirst, ACount: Integer;
  const AFrequencyHz: Double): Double;
var
  Index: Integer;
  Phase: Double;
  PhaseStep: Double;
  InPhase: Double;
  Quadrature: Double;
begin
  InPhase := 0;
  Quadrature := 0;
  Phase := 0;
  PhaseStep := 2 * Pi * AFrequencyHz / FProfile.SampleRate;
  for Index := 0 to ACount - 1 do
  begin
    InPhase := InPhase + ASamples[AFirst + Index] * Cos(Phase);
    Quadrature := Quadrature + ASamples[AFirst + Index] * Sin(Phase);
    Phase := Phase + PhaseStep;
  end;
  Result := InPhase * InPhase + Quadrature * Quadrature;
end;

function TScalarRttyBitDemodulator.Decode(const ASamples: array of Single;
  const AExpectedBitCount: Integer; out ABits: TByteArray;
  out AConfidence: TSingleArray): Boolean;
var
  RequiredSamples: Integer;
  BitIndex: Integer;
  FirstSample: Integer;
  EndSample: Integer;
  SampleCount: Integer;
  MarkPower: Double;
  SpacePower: Double;
  Decision: Byte;
  ExactSampleCount: Double;
begin
  SetLength(ABits, 0);
  SetLength(AConfidence, 0);
  if AExpectedBitCount <= 0 then
    Exit(False);
  ExactSampleCount := (Double(AExpectedBitCount) * FProfile.SampleRate) /
    FProfile.Baud;
  if ExactSampleCount > MaximumReferenceSamples then
    Exit(False);
  RequiredSamples := Ceil(ExactSampleCount);
  if Length(ASamples) < RequiredSamples then
    Exit(False);
  SetLength(ABits, AExpectedBitCount);
  SetLength(AConfidence, AExpectedBitCount);
  for BitIndex := 0 to AExpectedBitCount - 1 do
  begin
    FirstSample := Floor((Double(BitIndex) * FProfile.SampleRate) /
      FProfile.Baud);
    EndSample := Floor((Double(BitIndex + 1) * FProfile.SampleRate) /
      FProfile.Baud);
    if BitIndex = AExpectedBitCount - 1 then
      EndSample := RequiredSamples;
    SampleCount := EndSample - FirstSample;
    MarkPower := TonePower(ASamples, FirstSample, SampleCount, FProfile.MarkHz);
    SpacePower := TonePower(ASamples, FirstSample, SampleCount, FProfile.SpaceHz);
    if MarkPower >= SpacePower then
      Decision := 1
    else
      Decision := 0;
    if FProfile.Reversed then
      Decision := Decision xor 1;
    ABits[BitIndex] := Decision;
    AConfidence[BitIndex] := Abs(MarkPower - SpacePower) /
      (MarkPower + SpacePower + MinimumPower);
  end;
  Result := True;
end;

end.
