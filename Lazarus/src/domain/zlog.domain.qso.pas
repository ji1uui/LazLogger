unit ZLog.Domain.Qso;

{$mode objfpc}{$H+}

interface

uses
  ZLog.Domain.Types;

type
  TQsoDraft = record
    Callsign: string;
    FrequencyHz: Int64;
    Mode: TEmissionMode;
    SentExchange: string;
    ReceivedExchange: string;
  end;

  TQso = class
  private
    FId: string;
    FCallsign: TCallsign;
    FFrequency: TFrequencyHz;
    FMode: TEmissionMode;
    FSentExchange: string;
    FReceivedExchange: string;
    FOccurredAtUtcMs: Int64;
  public
    constructor Create(const AId: string; const ACallsign: TCallsign;
      const AFrequency: TFrequencyHz; const AMode: TEmissionMode;
      const ASentExchange, AReceivedExchange: string;
      const AOccurredAtUtcMs: Int64);
    function Clone: TQso;
    property Id: string read FId;
    property Callsign: TCallsign read FCallsign;
    property Frequency: TFrequencyHz read FFrequency;
    property Mode: TEmissionMode read FMode;
    property SentExchange: string read FSentExchange;
    property ReceivedExchange: string read FReceivedExchange;
    property OccurredAtUtcMs: Int64 read FOccurredAtUtcMs;
  end;

implementation

constructor TQso.Create(const AId: string; const ACallsign: TCallsign;
  const AFrequency: TFrequencyHz; const AMode: TEmissionMode;
  const ASentExchange, AReceivedExchange: string;
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
