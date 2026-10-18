unit Muninn.Core.Band.Tests;

{$mode objfpc}{$H+}

interface

uses
  fpcunit, testregistry, Muninn.Core.Frequency, Muninn.Core.Band;

type
  TFrequencyTests = class(TTestCase)
  published
    procedure AcceptsPositiveFrequencies;
    procedure RejectsOutOfRange;
  end;

  TBandTests = class(TTestCase)
  private
    procedure CheckBand(const AHz: Int64; const AExpected: TBand);
    procedure CheckNoBand(const AHz: Int64);
  published
    procedure FindsBandForCommonFrequencies;
    procedure TreatsEdgesAsInclusive;
    procedure ReportsFrequenciesOutsideBands;
    procedure CoversLowFrequencyBands;
    procedure ParsesEveryAdifName;
    procedure ParsesNamesInAnyCase;
    procedure RejectsUnknownNames;
    procedure KeepsBandsOrderedAndDisjoint;
  end;

implementation

uses
  SysUtils;

procedure TFrequencyTests.AcceptsPositiveFrequencies;
var
  Frequency: TFrequencyHz;
begin
  AssertTrue(TFrequencyHz.TryFromHz(7025000, Frequency));
  AssertEquals(Int64(7025000), Frequency.Hz);
  AssertTrue(TFrequencyHz.TryFromHz(1, Frequency));
  AssertTrue(TFrequencyHz.TryFromHz(MaximumFrequencyHz, Frequency));
end;

procedure TFrequencyTests.RejectsOutOfRange;
var
  Frequency: TFrequencyHz;
begin
  AssertFalse('zero', TFrequencyHz.TryFromHz(0, Frequency));
  AssertFalse('negative', TFrequencyHz.TryFromHz(-1, Frequency));
  AssertFalse('above submm', TFrequencyHz.TryFromHz(MaximumFrequencyHz + 1, Frequency));
end;

procedure TBandTests.CheckBand(const AHz: Int64; const AExpected: TBand);
var
  Frequency: TFrequencyHz;
  Band: TBand;
begin
  AssertTrue('valid frequency ' + IntToStr(AHz), TFrequencyHz.TryFromHz(AHz, Frequency));
  AssertTrue('band found for ' + IntToStr(AHz), TryBandOfFrequency(Frequency, Band));
  AssertEquals('band for ' + IntToStr(AHz), BandAdifName(AExpected), BandAdifName(Band));
end;

procedure TBandTests.CheckNoBand(const AHz: Int64);
var
  Frequency: TFrequencyHz;
  Band: TBand;
begin
  AssertTrue(TFrequencyHz.TryFromHz(AHz, Frequency));
  AssertFalse('no band for ' + IntToStr(AHz), TryBandOfFrequency(Frequency, Band));
end;

procedure TBandTests.FindsBandForCommonFrequencies;
begin
  CheckBand(1910000, bnd160m);     { JA 1.9 MHz allocation }
  CheckBand(3535000, bnd80m);
  CheckBand(3800000, bnd80m);      { JA 3.8 MHz allocation }
  CheckBand(7074000, bnd40m);
  CheckBand(14074000, bnd20m);
  CheckBand(50313000, bnd6m);
  CheckBand(144100000, bnd2m);
  CheckBand(433000000, bnd70cm);
  CheckBand(1295000000, bnd23cm);
end;

procedure TBandTests.TreatsEdgesAsInclusive;
begin
  CheckBand(7000000, bnd40m);
  CheckBand(7300000, bnd40m);
  CheckBand(54000000, bnd6m);
  CheckBand(54000001, bnd5m);
end;

procedure TBandTests.ReportsFrequenciesOutsideBands;
begin
  CheckNoBand(7300001);
  CheckNoBand(4630000);            { JA emergency frequency, not an ADIF band }
  CheckNoBand(100000);
end;

procedure TBandTests.CoversLowFrequencyBands;
begin
  CheckBand(135700, bnd2190m);
  CheckBand(475000, bnd630m);
end;

procedure TBandTests.ParsesEveryAdifName;
var
  Band, Parsed: TBand;
begin
  for Band := Low(TBand) to High(TBand) do
  begin
    AssertTrue('parse ' + BandAdifName(Band), TryParseBand(BandAdifName(Band), Parsed));
    AssertTrue('round trip ' + BandAdifName(Band), Parsed = Band);
  end;
end;

procedure TBandTests.ParsesNamesInAnyCase;
var
  Band: TBand;
begin
  AssertTrue(TryParseBand(' 20M ', Band));
  AssertTrue(Band = bnd20m);
  AssertTrue(TryParseBand('70CM', Band));
  AssertTrue(Band = bnd70cm);
  AssertTrue(TryParseBand('SUBMM', Band));
  AssertTrue(Band = bndSubmm);
end;

procedure TBandTests.RejectsUnknownNames;
var
  Band: TBand;
begin
  AssertFalse(TryParseBand('', Band));
  AssertFalse(TryParseBand('11m', Band));
  AssertFalse(TryParseBand('20', Band));
end;

procedure TBandTests.KeepsBandsOrderedAndDisjoint;
var
  Band: TBand;
begin
  for Band := Low(TBand) to High(TBand) do
  begin
    AssertTrue('lower <= upper ' + BandAdifName(Band),
      BandLowerHz(Band) <= BandUpperHz(Band));
    if Band > Low(TBand) then
      AssertTrue('after previous ' + BandAdifName(Band),
        BandLowerHz(Band) > BandUpperHz(Pred(Band)));
  end;
end;

initialization
  RegisterTest(TFrequencyTests);
  RegisterTest(TBandTests);
end.
