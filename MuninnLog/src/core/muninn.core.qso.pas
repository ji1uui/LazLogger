unit Muninn.Core.Qso;

{ One QSO as recorded (docs/03_DATA_MODEL.md section 3.10). The values that
  need units or calendar rules are typed; every other value is kept under its
  ADIF field name in OtherFields, in the order it was recorded, so nothing an
  imported log carries is lost. Codes such as STATE and CNTY stay strings and
  keep their leading zeros. }

{$mode objfpc}{$H+}

interface

uses
  Muninn.Core.Time, Muninn.Core.Mode, Muninn.Core.Adif;

const
  NoFrequency = 0;
  NoPower = -1;

type
  TQsoRecord = class
  private
    FOtherFields: TAdifRecord;
  public
    { ADIF CALL, upper case. }
    Call: string;
    TimeOn: TUtcInstant;
    HasTimeOff: Boolean;
    TimeOff: TUtcInstant;
    { NoFrequency when not recorded. }
    FrequencyHz: Int64;
    FrequencyRxHz: Int64;
    { ADIF band names in lower case, e.g. '20m'; empty when not recorded. }
    Band: string;
    BandRx: string;
    Mode: TMode;
    { ADIF TX_PWR in milliwatts; NoPower when not recorded. }
    TxPowerMw: Int64;
    constructor Create;
    destructor Destroy; override;
    { Every other ADIF field, e.g. RST_SENT, NAME, STATE, CNTY, APP_* fields. }
    property OtherFields: TAdifRecord read FOtherFields;
  end;

implementation

constructor TQsoRecord.Create;
begin
  inherited Create;
  FOtherFields := TAdifRecord.Create;
  FrequencyHz := NoFrequency;
  FrequencyRxHz := NoFrequency;
  TxPowerMw := NoPower;
end;

destructor TQsoRecord.Destroy;
begin
  FOtherFields.Free;
  inherited Destroy;
end;

end.
