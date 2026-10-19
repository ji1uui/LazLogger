unit Muninn.Core.Radio;

{ The radio port: what the core needs from a transceiver, independent of how
  it is controlled (docs/04_ARCHITECTURE.md section 4, ADR 0008). The
  HamlibComponent adapter in src/integrations implements it.

  Every operation is asynchronous. Its callback runs on the main thread when
  that thread processes queued calls (the LCL does this; a program without the
  LCL calls CheckSynchronize). A call made while not connected, or with an
  argument the radio cannot take, reports the error to its callback before the
  method returns. Disconnect cancels the calls still waiting; their callbacks
  report reCancelled, possibly before Disconnect returns. Releasing the port
  drops the results still waiting: their callbacks are not called. }

{$mode objfpc}{$H+}

interface

uses
  Muninn.Core.Frequency, Muninn.Core.Mode;

type
  TRadioError = (
    reNone,
    { Not connected, or the connection was lost. }
    reNotConnected,
    { Opening the radio failed (wrong port, wrong model, radio off). }
    reConnectFailed,
    { Another program has the port open. }
    rePortBusy,
    reTimeout,
    { The radio or its driver cannot do this, or the mode has no mapping. }
    reNotSupported,
    { Refused for now, e.g. while the adapter backs off after repeated errors. }
    reTemporarilyUnavailable,
    reCancelled,
    reFailed);

  TRadioResult = record
    Error: TRadioError;
    { Text for the log, e.g. the driver's message. }
    Message: string;
  end;

  { A mode read from the radio. RadioText is the radio's own name, e.g.
    'USB' or 'PKT-USB'. HasMode is False when no ADIF mode follows from it
    (data modes: the radio cannot tell FT8 from RTTY over USB). }
  TRadioModeReading = record
    RadioText: string;
    HasMode: Boolean;
    Mode: TMode;
  end;

  TRadioCommandCallback = procedure(const AResult: TRadioResult) of object;
  TRadioFrequencyCallback = procedure(const AResult: TRadioResult;
    const AFrequency: TFrequencyHz) of object;
  TRadioModeCallback = procedure(const AResult: TRadioResult;
    const AReading: TRadioModeReading) of object;
  TRadioConnectionEvent = procedure(Sender: TObject; AConnected: Boolean) of object;
  TRadioFrequencyEvent = procedure(Sender: TObject;
    const AFrequency: TFrequencyHz) of object;
  { Errors that belong to no call: a failed connection, a lost radio. }
  TRadioErrorEvent = procedure(Sender: TObject; const AResult: TRadioResult) of object;

  TRadioSetting = record
    Name: string;
    Value: string;
  end;

  { Where and how to reach the radio (the transceiver's connection settings of
    Station Facility, docs/03_DATA_MODEL.md section 3.8). }
  TRadioConnection = record
    { The driver's model number, from its model catalog. }
    ModelId: Integer;
    { For logs and the UI; the model is chosen by ModelId. }
    ModelName: string;
    { Serial port ('COM5', '/dev/ttyUSB0'), 'host:port' for a network
      daemon, or '' for a simulated radio. }
    Port: string;
    { Driver settings applied before opening, e.g. serial_speed=38400. }
    Settings: array of TRadioSetting;
    { 0 turns polling off. }
    PollIntervalMs: Cardinal;
  end;

  IRadioPort = interface
    ['{8B6E2A41-6C1D-4F8E-9E1B-3E6D2C7A9F10}']
    { Starts connecting; OnConnectionChanged and OnError report the outcome.
      Raises EInvalidOperation when already connected, EArgumentException
      for a model id below 1, and the driver's exception for settings it
      refuses; after an exception the port is not connected. Only the
      settings given here apply. }
    procedure Connect(const AConnection: TRadioConnection);
    { Does not fire OnConnectionChanged. }
    procedure Disconnect;
    { True from Connect until Disconnect, also while the link is down or
      still being made; OnConnectionChanged reports the link itself. }
    function IsConnected: Boolean;
    procedure SetFrequency(const AFrequency: TFrequencyHz;
      ACallback: TRadioCommandCallback);
    procedure GetFrequency(ACallback: TRadioFrequencyCallback);
    { Raises nothing: a mode without a radio mode reports reNotSupported. }
    procedure SetMode(const AMode: TMode; ACallback: TRadioCommandCallback);
    procedure GetMode(ACallback: TRadioModeCallback);
    procedure SetTransmit(AOn: Boolean; ACallback: TRadioCommandCallback);
    procedure SetOnConnectionChanged(AHandler: TRadioConnectionEvent);
    { Fires when polling sees the frequency change. }
    procedure SetOnFrequencyChanged(AHandler: TRadioFrequencyEvent);
    procedure SetOnError(AHandler: TRadioErrorEvent);
  end;

function RadioResultOk: TRadioResult;
function RadioResultError(const AError: TRadioError; const AMessage: string): TRadioResult;
{ A stable name for logs, e.g. 'port-busy'. }
function RadioErrorName(const AError: TRadioError): string;

implementation

const
  ErrorNames: array[TRadioError] of string = ('none', 'not-connected',
    'connect-failed', 'port-busy', 'timeout', 'not-supported',
    'temporarily-unavailable', 'cancelled', 'failed');

function RadioResultOk: TRadioResult;
begin
  Result.Error := reNone;
  Result.Message := '';
end;

function RadioResultError(const AError: TRadioError; const AMessage: string): TRadioResult;
begin
  Result.Error := AError;
  Result.Message := AMessage;
end;

function RadioErrorName(const AError: TRadioError): string;
begin
  Result := ErrorNames[AError];
end;

end.
