unit Muninn.Core.AdifModes;
{ The ADIF 3.1.8 Mode and Submode enumerations (section III.B.10), generated
  from docs/references/ADIF_3.1.8_excerpt.txt. The specification omits the comma
  between the MFSK submodes MFSK128 and MFSK128L; they are listed separately.
  Import-only (deprecated) modes are all submodes of a current mode; per ADIF
  policy II.B they are accepted on import and exported as MODE + SUBMODE,
  e.g. MODE C4FM -> MODE DIGITALVOICE, SUBMODE C4FM. }

{$mode objfpc}{$H+}

interface

const
  AdifModeCount = 49;
  AdifSubmodeCount = 198;

{ True when AMode is a current ADIF mode (case-insensitive). }
function IsAdifMode(const AMode: string): Boolean;
{ The mode that ASubmode belongs to, e.g. 'USB' -> 'SSB' (case-insensitive). }
function TryAdifParentMode(const ASubmode: string; out AMode: string): Boolean;
{ Converts an import-only mode to MODE + SUBMODE. Returns False and leaves the
  values unchanged when AMode is a current mode or not an ADIF value at all, or
  when ASubmode is set to something other than AMode. }
function TryConvertImportOnlyMode(var AMode, ASubmode: string): Boolean;

implementation

uses
  SysUtils;

type
  TAdifSubmode = record
    Submode: string;
    Mode: string;
  end;

const
  AdifModes: array[0..AdifModeCount - 1] of string = (
    'AM', 'ARDOP', 'ATV', 'CHIP', 'CLO', 'CONTESTI', 'CW', 'DIGITALVOICE',
    'DOMINO', 'DYNAMIC', 'FAX', 'FM', 'FSK441', 'FSK', 'FT8', 'HELL',
    'ISCAT', 'JT4', 'JT6M', 'JT9', 'JT44', 'JT65', 'MFSK', 'MSK144',
    'MTONE', 'MT63', 'OFDM', 'OLIVIA', 'OPERA', 'PAC', 'PAX', 'PKT', 'PSK',
    'PSK2K', 'Q15', 'QRA64', 'ROS', 'RTTY', 'RTTYM', 'SSB', 'SSTV', 'T10',
    'THOR', 'THRB', 'TOR', 'V4', 'VOI', 'WINMOR', 'WSPR');

  AdifSubmodes: array[0..AdifSubmodeCount - 1] of TAdifSubmode = (
    (Submode: 'CHIP64'; Mode: 'CHIP'),
    (Submode: 'CHIP128'; Mode: 'CHIP'),
    (Submode: 'PCW'; Mode: 'CW'),
    (Submode: 'C4FM'; Mode: 'DIGITALVOICE'),
    (Submode: 'DMR'; Mode: 'DIGITALVOICE'),
    (Submode: 'DSTAR'; Mode: 'DIGITALVOICE'),
    (Submode: 'FREEDV'; Mode: 'DIGITALVOICE'),
    (Submode: 'M17'; Mode: 'DIGITALVOICE'),
    (Submode: 'DOM-M'; Mode: 'DOMINO'),
    (Submode: 'DOM4'; Mode: 'DOMINO'),
    (Submode: 'DOM5'; Mode: 'DOMINO'),
    (Submode: 'DOM8'; Mode: 'DOMINO'),
    (Submode: 'DOM11'; Mode: 'DOMINO'),
    (Submode: 'DOM16'; Mode: 'DOMINO'),
    (Submode: 'DOM22'; Mode: 'DOMINO'),
    (Submode: 'DOM44'; Mode: 'DOMINO'),
    (Submode: 'DOM88'; Mode: 'DOMINO'),
    (Submode: 'DOMINOEX'; Mode: 'DOMINO'),
    (Submode: 'DOMINOF'; Mode: 'DOMINO'),
    (Submode: 'FREEDATA'; Mode: 'DYNAMIC'),
    (Submode: 'VARA HF'; Mode: 'DYNAMIC'),
    (Submode: 'VARA SATELLITE'; Mode: 'DYNAMIC'),
    (Submode: 'VARA FM 1200'; Mode: 'DYNAMIC'),
    (Submode: 'VARA FM 9600'; Mode: 'DYNAMIC'),
    (Submode: 'SCAMP_FAST'; Mode: 'FSK'),
    (Submode: 'SCAMP_SLOW'; Mode: 'FSK'),
    (Submode: 'SCAMP_VSLOW'; Mode: 'FSK'),
    (Submode: 'FMHELL'; Mode: 'HELL'),
    (Submode: 'FSKH105'; Mode: 'HELL'),
    (Submode: 'FSKH245'; Mode: 'HELL'),
    (Submode: 'FSKHELL'; Mode: 'HELL'),
    (Submode: 'HELL80'; Mode: 'HELL'),
    (Submode: 'HELLX5'; Mode: 'HELL'),
    (Submode: 'HELLX9'; Mode: 'HELL'),
    (Submode: 'HFSK'; Mode: 'HELL'),
    (Submode: 'PSKHELL'; Mode: 'HELL'),
    (Submode: 'SLOWHELL'; Mode: 'HELL'),
    (Submode: 'ISCAT-A'; Mode: 'ISCAT'),
    (Submode: 'ISCAT-B'; Mode: 'ISCAT'),
    (Submode: 'JT4A'; Mode: 'JT4'),
    (Submode: 'JT4B'; Mode: 'JT4'),
    (Submode: 'JT4C'; Mode: 'JT4'),
    (Submode: 'JT4D'; Mode: 'JT4'),
    (Submode: 'JT4E'; Mode: 'JT4'),
    (Submode: 'JT4F'; Mode: 'JT4'),
    (Submode: 'JT4G'; Mode: 'JT4'),
    (Submode: 'JT9-1'; Mode: 'JT9'),
    (Submode: 'JT9-2'; Mode: 'JT9'),
    (Submode: 'JT9-5'; Mode: 'JT9'),
    (Submode: 'JT9-10'; Mode: 'JT9'),
    (Submode: 'JT9-30'; Mode: 'JT9'),
    (Submode: 'JT9A'; Mode: 'JT9'),
    (Submode: 'JT9B'; Mode: 'JT9'),
    (Submode: 'JT9C'; Mode: 'JT9'),
    (Submode: 'JT9D'; Mode: 'JT9'),
    (Submode: 'JT9E'; Mode: 'JT9'),
    (Submode: 'JT9E FAST'; Mode: 'JT9'),
    (Submode: 'JT9F'; Mode: 'JT9'),
    (Submode: 'JT9F FAST'; Mode: 'JT9'),
    (Submode: 'JT9G'; Mode: 'JT9'),
    (Submode: 'JT9G FAST'; Mode: 'JT9'),
    (Submode: 'JT9H'; Mode: 'JT9'),
    (Submode: 'JT9H FAST'; Mode: 'JT9'),
    (Submode: 'JT65A'; Mode: 'JT65'),
    (Submode: 'JT65B'; Mode: 'JT65'),
    (Submode: 'JT65B2'; Mode: 'JT65'),
    (Submode: 'JT65C'; Mode: 'JT65'),
    (Submode: 'JT65C2'; Mode: 'JT65'),
    (Submode: 'FSQCALL'; Mode: 'MFSK'),
    (Submode: 'FST4'; Mode: 'MFSK'),
    (Submode: 'FST4W'; Mode: 'MFSK'),
    (Submode: 'FT2'; Mode: 'MFSK'),
    (Submode: 'FT4'; Mode: 'MFSK'),
    (Submode: 'JS8'; Mode: 'MFSK'),
    (Submode: 'JTMS'; Mode: 'MFSK'),
    (Submode: 'JTTY'; Mode: 'MFSK'),
    (Submode: 'MFSK4'; Mode: 'MFSK'),
    (Submode: 'MFSK8'; Mode: 'MFSK'),
    (Submode: 'MFSK11'; Mode: 'MFSK'),
    (Submode: 'MFSK16'; Mode: 'MFSK'),
    (Submode: 'MFSK22'; Mode: 'MFSK'),
    (Submode: 'MFSK31'; Mode: 'MFSK'),
    (Submode: 'MFSK32'; Mode: 'MFSK'),
    (Submode: 'MFSK64'; Mode: 'MFSK'),
    (Submode: 'MFSK64L'; Mode: 'MFSK'),
    (Submode: 'MFSK128'; Mode: 'MFSK'),
    (Submode: 'MFSK128L'; Mode: 'MFSK'),
    (Submode: 'Q65'; Mode: 'MFSK'),
    (Submode: 'SCAMP_OO'; Mode: 'MTONE'),
    (Submode: 'SCAMP_OO_SLW'; Mode: 'MTONE'),
    (Submode: 'RIBBIT_PIX'; Mode: 'OFDM'),
    (Submode: 'RIBBIT_SMS'; Mode: 'OFDM'),
    (Submode: 'OLIVIA 4/125'; Mode: 'OLIVIA'),
    (Submode: 'OLIVIA 4/250'; Mode: 'OLIVIA'),
    (Submode: 'OLIVIA 8/250'; Mode: 'OLIVIA'),
    (Submode: 'OLIVIA 8/500'; Mode: 'OLIVIA'),
    (Submode: 'OLIVIA 16/500'; Mode: 'OLIVIA'),
    (Submode: 'OLIVIA 16/1000'; Mode: 'OLIVIA'),
    (Submode: 'OLIVIA 32/1000'; Mode: 'OLIVIA'),
    (Submode: 'OPERA-BEACON'; Mode: 'OPERA'),
    (Submode: 'OPERA-QSO'; Mode: 'OPERA'),
    (Submode: 'PAC2'; Mode: 'PAC'),
    (Submode: 'PAC3'; Mode: 'PAC'),
    (Submode: 'PAC4'; Mode: 'PAC'),
    (Submode: 'PAX2'; Mode: 'PAX'),
    (Submode: '8PSK125'; Mode: 'PSK'),
    (Submode: '8PSK125F'; Mode: 'PSK'),
    (Submode: '8PSK125FL'; Mode: 'PSK'),
    (Submode: '8PSK250'; Mode: 'PSK'),
    (Submode: '8PSK250F'; Mode: 'PSK'),
    (Submode: '8PSK250FL'; Mode: 'PSK'),
    (Submode: '8PSK500'; Mode: 'PSK'),
    (Submode: '8PSK500F'; Mode: 'PSK'),
    (Submode: '8PSK1000'; Mode: 'PSK'),
    (Submode: '8PSK1000F'; Mode: 'PSK'),
    (Submode: '8PSK1200F'; Mode: 'PSK'),
    (Submode: 'FSK31'; Mode: 'PSK'),
    (Submode: 'PSK10'; Mode: 'PSK'),
    (Submode: 'PSK31'; Mode: 'PSK'),
    (Submode: 'PSK63'; Mode: 'PSK'),
    (Submode: 'PSK63F'; Mode: 'PSK'),
    (Submode: 'PSK63RC4'; Mode: 'PSK'),
    (Submode: 'PSK63RC5'; Mode: 'PSK'),
    (Submode: 'PSK63RC10'; Mode: 'PSK'),
    (Submode: 'PSK63RC20'; Mode: 'PSK'),
    (Submode: 'PSK63RC32'; Mode: 'PSK'),
    (Submode: 'PSK125'; Mode: 'PSK'),
    (Submode: 'PSK125C12'; Mode: 'PSK'),
    (Submode: 'PSK125R'; Mode: 'PSK'),
    (Submode: 'PSK125RC10'; Mode: 'PSK'),
    (Submode: 'PSK125RC12'; Mode: 'PSK'),
    (Submode: 'PSK125RC16'; Mode: 'PSK'),
    (Submode: 'PSK125RC4'; Mode: 'PSK'),
    (Submode: 'PSK125RC5'; Mode: 'PSK'),
    (Submode: 'PSK250'; Mode: 'PSK'),
    (Submode: 'PSK250C6'; Mode: 'PSK'),
    (Submode: 'PSK250R'; Mode: 'PSK'),
    (Submode: 'PSK250RC2'; Mode: 'PSK'),
    (Submode: 'PSK250RC3'; Mode: 'PSK'),
    (Submode: 'PSK250RC5'; Mode: 'PSK'),
    (Submode: 'PSK250RC6'; Mode: 'PSK'),
    (Submode: 'PSK250RC7'; Mode: 'PSK'),
    (Submode: 'PSK500'; Mode: 'PSK'),
    (Submode: 'PSK500C2'; Mode: 'PSK'),
    (Submode: 'PSK500C4'; Mode: 'PSK'),
    (Submode: 'PSK500R'; Mode: 'PSK'),
    (Submode: 'PSK500RC2'; Mode: 'PSK'),
    (Submode: 'PSK500RC3'; Mode: 'PSK'),
    (Submode: 'PSK500RC4'; Mode: 'PSK'),
    (Submode: 'PSK800C2'; Mode: 'PSK'),
    (Submode: 'PSK800RC2'; Mode: 'PSK'),
    (Submode: 'PSK1000'; Mode: 'PSK'),
    (Submode: 'PSK1000C2'; Mode: 'PSK'),
    (Submode: 'PSK1000R'; Mode: 'PSK'),
    (Submode: 'PSK1000RC2'; Mode: 'PSK'),
    (Submode: 'PSKAM10'; Mode: 'PSK'),
    (Submode: 'PSKAM31'; Mode: 'PSK'),
    (Submode: 'PSKAM50'; Mode: 'PSK'),
    (Submode: 'PSKFEC31'; Mode: 'PSK'),
    (Submode: 'QPSK31'; Mode: 'PSK'),
    (Submode: 'QPSK63'; Mode: 'PSK'),
    (Submode: 'QPSK125'; Mode: 'PSK'),
    (Submode: 'QPSK250'; Mode: 'PSK'),
    (Submode: 'QPSK500'; Mode: 'PSK'),
    (Submode: 'SIM31'; Mode: 'PSK'),
    (Submode: 'QRA64A'; Mode: 'QRA64'),
    (Submode: 'QRA64B'; Mode: 'QRA64'),
    (Submode: 'QRA64C'; Mode: 'QRA64'),
    (Submode: 'QRA64D'; Mode: 'QRA64'),
    (Submode: 'QRA64E'; Mode: 'QRA64'),
    (Submode: 'ROS-EME'; Mode: 'ROS'),
    (Submode: 'ROS-HF'; Mode: 'ROS'),
    (Submode: 'ROS-MF'; Mode: 'ROS'),
    (Submode: 'ASCI'; Mode: 'RTTY'),
    (Submode: 'LSB'; Mode: 'SSB'),
    (Submode: 'USB'; Mode: 'SSB'),
    (Submode: 'THOR-M'; Mode: 'THOR'),
    (Submode: 'THOR4'; Mode: 'THOR'),
    (Submode: 'THOR5'; Mode: 'THOR'),
    (Submode: 'THOR8'; Mode: 'THOR'),
    (Submode: 'THOR11'; Mode: 'THOR'),
    (Submode: 'THOR16'; Mode: 'THOR'),
    (Submode: 'THOR22'; Mode: 'THOR'),
    (Submode: 'THOR25X4'; Mode: 'THOR'),
    (Submode: 'THOR50X1'; Mode: 'THOR'),
    (Submode: 'THOR50X2'; Mode: 'THOR'),
    (Submode: 'THOR100'; Mode: 'THOR'),
    (Submode: 'THRBX'; Mode: 'THRB'),
    (Submode: 'THRBX1'; Mode: 'THRB'),
    (Submode: 'THRBX2'; Mode: 'THRB'),
    (Submode: 'THRBX4'; Mode: 'THRB'),
    (Submode: 'THROB1'; Mode: 'THRB'),
    (Submode: 'THROB2'; Mode: 'THRB'),
    (Submode: 'THROB4'; Mode: 'THRB'),
    (Submode: 'AMTORFEC'; Mode: 'TOR'),
    (Submode: 'GTOR'; Mode: 'TOR'),
    (Submode: 'NAVTEX'; Mode: 'TOR'),
    (Submode: 'SITORB'; Mode: 'TOR'));

function IsAdifMode(const AMode: string): Boolean;
var
  Mode: string;
  Candidate: string;
begin
  Mode := UpperCase(Trim(AMode));
  for Candidate in AdifModes do
    if Candidate = Mode then
      Exit(True);
  Result := False;
end;

function TryAdifParentMode(const ASubmode: string; out AMode: string): Boolean;
var
  Submode: string;
  Index: Integer;
begin
  Submode := UpperCase(Trim(ASubmode));
  for Index := Low(AdifSubmodes) to High(AdifSubmodes) do
    if AdifSubmodes[Index].Submode = Submode then
    begin
      AMode := AdifSubmodes[Index].Mode;
      Exit(True);
    end;
  AMode := '';
  Result := False;
end;

function TryConvertImportOnlyMode(var AMode, ASubmode: string): Boolean;
var
  Parent: string;
begin
  Result := False;
  if IsAdifMode(AMode) or not TryAdifParentMode(AMode, Parent) then
    Exit;
  if (Trim(ASubmode) <> '') and (UpperCase(Trim(ASubmode)) <> UpperCase(Trim(AMode))) then
    Exit;
  ASubmode := UpperCase(Trim(AMode));
  AMode := Parent;
  Result := True;
end;

end.
