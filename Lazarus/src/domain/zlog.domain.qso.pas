unit ZLog.Domain.Qso;

{$mode objfpc}{$H+}

interface

uses
  ZLog.Domain.Types;

type
  TQsoDraft = record
    Callsign: UnicodeString;
    FrequencyHz: Int64;
    Mode: TEmissionMode;
    SentExchange: UnicodeString;
    ReceivedExchange: UnicodeString;
  end;

  TQso = class
  private
    FId: string;
    FCallsign: TCallsign;
    FFrequency: TFrequencyHz;
    FMode: TEmissionMode;
    FSentExchange: UnicodeString;
    FReceivedExchange: UnicodeString;
    FOccurredAtUtcMs: Int64;
  public
    constructor Create(const AId: string; const ACallsign: TCallsign;
      const AFrequency: TFrequencyHz; const AMode: TEmissionMode;
      const ASentExchange, AReceivedExchange: UnicodeString;
      const AOccurredAtUtcMs: Int64);
    function Clone: TQso;
    property Id: string read FId;
    property Callsign: TCallsign read FCallsign;
    property Frequency: TFrequencyHz read FFrequency;
    property Mode: TEmissionMode read FMode;
    property SentExchange: UnicodeString read FSentExchange;
    property ReceivedExchange: UnicodeString read FReceivedExchange;
    property OccurredAtUtcMs: Int64 read FOccurredAtUtcMs;
  end;

implementation

constructor TQso.Create(const AId: string; const ACallsign: TCallsign;
  const AFrequency: TFrequencyHz; const AMode: TEmissionMode;
  const ASentExchange, AReceivedExchange: UnicodeString;
  const AOccurredAtUtcMs: Int64);
begin
  inherited Create;
  FId := AId;
  FCallsign := ACallsign;
  FFrequency := AFrequency;
  FMode := AMode;
  FSentExchange := ASentExchange;
  FReceivedExchange := AReceivedExchange;
  FOccurredAtUtcMs := AOccurredAtUtcMs;
end;

function TQso.Clone: TQso;
begin
  Result := TQso.Create(FId, FCallsign, FFrequency, FMode, FSentExchange,
    FReceivedExchange, FOccurredAtUtcMs);
end;

end.
