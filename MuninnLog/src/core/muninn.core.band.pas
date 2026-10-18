unit Muninn.Core.Band;

{ Amateur bands as defined by the ADIF Band enumeration. The table was taken from
  the ADIF 3.1.4 exports; the ADIF 3.1.8 change list (2026-10-12) records no
  Band changes after 3.1.4, so it matches 3.1.8.
  The ADIF band name is the stable code used for storage and exchange;
  never persist Ord(TBand). Band edges are inclusive. }

{$mode objfpc}{$H+}

interface

uses
  Muninn.Core.Frequency;

type
  TBand = (bnd2190m, bnd630m, bnd560m, bnd160m, bnd80m, bnd60m, bnd40m,
    bnd30m, bnd20m, bnd17m, bnd15m, bnd12m, bnd10m, bnd8m, bnd6m, bnd5m,
    bnd4m, bnd2m, bnd1_25m, bnd70cm, bnd33cm, bnd23cm, bnd13cm, bnd9cm,
    bnd6cm, bnd3cm, bnd1_25cm, bnd6mm, bnd4mm, bnd2_5mm, bnd2mm, bnd1mm,
    bndSubmm);

function BandAdifName(const ABand: TBand): string;
function BandLowerHz(const ABand: TBand): Int64;
function BandUpperHz(const ABand: TBand): Int64;
{ Accepts the ADIF band name in any letter case, e.g. '20m' or '20M'. }
function TryParseBand(const AName: string; out ABand: TBand): Boolean;
{ False when the frequency lies outside every ADIF band. }
function TryBandOfFrequency(const AFrequency: TFrequencyHz;
  out ABand: TBand): Boolean;

implementation

uses
  SysUtils;

type
  TBandDefinition = record
    Name: string;
    LowerHz: Int64;
    UpperHz: Int64;
  end;

const
  Bands: array[TBand] of TBandDefinition = (
    (Name: '2190m'; LowerHz: 135700; UpperHz: 137800),
    (Name: '630m'; LowerHz: 472000; UpperHz: 479000),
    (Name: '560m'; LowerHz: 501000; UpperHz: 504000),
    (Name: '160m'; LowerHz: 1800000; UpperHz: 2000000),
    (Name: '80m'; LowerHz: 3500000; UpperHz: 4000000),
    (Name: '60m'; LowerHz: 5060000; UpperHz: 5450000),
    (Name: '40m'; LowerHz: 7000000; UpperHz: 7300000),
    (Name: '30m'; LowerHz: 10100000; UpperHz: 10150000),
    (Name: '20m'; LowerHz: 14000000; UpperHz: 14350000),
    (Name: '17m'; LowerHz: 18068000; UpperHz: 18168000),
    (Name: '15m'; LowerHz: 21000000; UpperHz: 21450000),
    (Name: '12m'; LowerHz: 24890000; UpperHz: 24990000),
    (Name: '10m'; LowerHz: 28000000; UpperHz: 29700000),
    (Name: '8m'; LowerHz: 40000000; UpperHz: 45000000),
    (Name: '6m'; LowerHz: 50000000; UpperHz: 54000000),
    (Name: '5m'; LowerHz: 54000001; UpperHz: 69900000),
    (Name: '4m'; LowerHz: 70000000; UpperHz: 71000000),
    (Name: '2m'; LowerHz: 144000000; UpperHz: 148000000),
    (Name: '1.25m'; LowerHz: 222000000; UpperHz: 225000000),
    (Name: '70cm'; LowerHz: 420000000; UpperHz: 450000000),
    (Name: '33cm'; LowerHz: 902000000; UpperHz: 928000000),
    (Name: '23cm'; LowerHz: 1240000000; UpperHz: 1300000000),
    (Name: '13cm'; LowerHz: 2300000000; UpperHz: 2450000000),
    (Name: '9cm'; LowerHz: 3300000000; UpperHz: 3500000000),
    (Name: '6cm'; LowerHz: 5650000000; UpperHz: 5925000000),
    (Name: '3cm'; LowerHz: 10000000000; UpperHz: 10500000000),
    (Name: '1.25cm'; LowerHz: 24000000000; UpperHz: 24250000000),
    (Name: '6mm'; LowerHz: 47000000000; UpperHz: 47200000000),
    (Name: '4mm'; LowerHz: 75500000000; UpperHz: 81000000000),
    (Name: '2.5mm'; LowerHz: 119980000000; UpperHz: 123000000000),
    (Name: '2mm'; LowerHz: 134000000000; UpperHz: 149000000000),
    (Name: '1mm'; LowerHz: 241000000000; UpperHz: 250000000000),
    (Name: 'submm'; LowerHz: 300000000000; UpperHz: 7500000000000));

function BandAdifName(const ABand: TBand): string;
begin
  Result := Bands[ABand].Name;
end;

function BandLowerHz(const ABand: TBand): Int64;
begin
  Result := Bands[ABand].LowerHz;
end;

function BandUpperHz(const ABand: TBand): Int64;
begin
  Result := Bands[ABand].UpperHz;
end;

function TryParseBand(const AName: string; out ABand: TBand): Boolean;
var
  Candidate: TBand;
  Normalized: string;
begin
  Normalized := LowerCase(Trim(AName));
  for Candidate := Low(TBand) to High(TBand) do
    if Bands[Candidate].Name = Normalized then
    begin
      ABand := Candidate;
      Exit(True);
    end;
  ABand := Low(TBand);
  Result := False;
end;

function TryBandOfFrequency(const AFrequency: TFrequencyHz;
  out ABand: TBand): Boolean;
var
  Candidate: TBand;
begin
  for Candidate := Low(TBand) to High(TBand) do
    if (AFrequency.Hz >= Bands[Candidate].LowerHz) and
      (AFrequency.Hz <= Bands[Candidate].UpperHz) then
    begin
      ABand := Candidate;
      Exit(True);
    end;
  ABand := Low(TBand);
  Result := False;
end;

end.
