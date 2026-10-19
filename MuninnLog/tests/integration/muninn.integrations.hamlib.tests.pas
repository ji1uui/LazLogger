unit Muninn.Integrations.Hamlib.Tests;

{ THamlibRadio over HamlibComponent (ADR 0008). TFakeHamlibLoader tests the
  adapter without a library; THamlibDummyRigTests drives Hamlib's own dummy
  radio (model 1) through the real library. Without the library those tests
  are ignored, unless MUNINN_REQUIRE_HAMLIB=1 (set in CI where it is
  installed) makes them fail. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Muninn.Core.Frequency,
  Muninn.Core.Mode, Muninn.Core.Radio, Muninn.Integrations.Hamlib,
  HamlibInterfaces;

type
  { Collects what the port reports, and waits for it on the main thread. }
  TRadioProbe = class
  public
    Done: Boolean;
    Result: TRadioResult;
    Frequency: TFrequencyHz;
    Reading: TRadioModeReading;
    ConnectedEvents: Integer;
    Connected: Boolean;
    ErrorEvents: Integer;
    LastError: TRadioResult;
    PolledFrequency: TFrequencyHz;
    PolledEvents: Integer;
    procedure Reset;
    procedure CommandDone(const AResult: TRadioResult);
    procedure FrequencyDone(const AResult: TRadioResult;
      const AFrequency: TFrequencyHz);
    procedure ModeDone(const AResult: TRadioResult;
      const AReading: TRadioModeReading);
    procedure ConnectionChanged(Sender: TObject; AConnected: Boolean);
    procedure FrequencyChanged(Sender: TObject; const AFrequency: TFrequencyHz);
    procedure ErrorReported(Sender: TObject; const AResult: TRadioResult);
  end;

  TRadioTestCase = class(TTestCase)
  protected
    FProbe: TRadioProbe;
    FRadio: IRadioPort;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Attach(const AService: IRigService);
    { Processes queued calls until ADone^ is set; fails after 5 s. }
    procedure WaitFor(const ADone: PBoolean; const AWhat: string);
    procedure WaitForConnection;
    procedure ExpectOk(const AWhat: string);
    procedure SetModeAndWait(const AMode, ASubmode: string);
    function NewMode(const AMode, ASubmode: string): TMode;
  end;

  TRadioModeMappingTests = class(TTestCase)
  published
    procedure MapsVoiceModes;
    procedure MapsDataModesToPacketUsb;
    procedure RefusesModesWithoutRadioMode;
    procedure ReadsRadioModes;
    procedure MapsFailures;
  end;

  THamlibFakeRadioTests = class(TRadioTestCase)
  private
    FLoader: IHamlibLoader;
    function Fake: TObject;
    procedure Connect(const APollMs: Cardinal = 0);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ConnectReportsTheLink;
    procedure ConnectAppliesSettings;
    procedure RefusesSecondConnectAndBadModel;
    procedure SetsAndGetsFrequency;
    procedure SetsModes;
    procedure ReadsModes;
    procedure SetsTransmit;
    procedure ReportsCommandFailure;
    procedure CallsWhileNotConnectedFailAtOnce;
    procedure UnsupportedModeFailsAtOnce;
    procedure PollingReportsFrequencyChanges;
    procedure FreeingWithPendingCallsDropsResults;
  end;

  THamlibDummyRigTests = class(TRadioTestCase)
  protected
    procedure SetUp; override;
  published
    procedure SetsAndGetsFrequency;
    procedure SetsAndGetsMode;
  end;

implementation

uses
  FakeHamlibLoader, HamlibService, HamlibFactory;

const
  WaitLimitMs = 5000;

var
  { HamlibComponent wants one factory per process. }
  SharedFactory: IRigServiceFactory;

{ TRadioProbe }

procedure TRadioProbe.Reset;
begin
  Done := False;
  Result := RadioResultOk;
  Frequency := Default(TFrequencyHz);
  Reading := Default(TRadioModeReading);
end;

procedure TRadioProbe.CommandDone(const AResult: TRadioResult);
begin
  Result := AResult;
  Done := True;
end;

procedure TRadioProbe.FrequencyDone(const AResult: TRadioResult;
  const AFrequency: TFrequencyHz);
begin
  Result := AResult;
  Frequency := AFrequency;
  Done := True;
end;

procedure TRadioProbe.ModeDone(const AResult: TRadioResult;
  const AReading: TRadioModeReading);
begin
  Result := AResult;
  Reading := AReading;
  Done := True;
end;

procedure TRadioProbe.ConnectionChanged(Sender: TObject; AConnected: Boolean);
begin
  Inc(ConnectedEvents);
  Connected := AConnected;
end;

procedure TRadioProbe.FrequencyChanged(Sender: TObject;
  const AFrequency: TFrequencyHz);
begin
  Inc(PolledEvents);
  PolledFrequency := AFrequency;
end;

procedure TRadioProbe.ErrorReported(Sender: TObject; const AResult: TRadioResult);
begin
  Inc(ErrorEvents);
  LastError := AResult;
end;

{ TRadioTestCase }

procedure TRadioTestCase.SetUp;
begin
  FProbe := TRadioProbe.Create;
  FProbe.Reset;
end;

procedure TRadioTestCase.TearDown;
begin
  FRadio := nil;
  { Let results still queued for the freed adapter arrive and be dropped. }
  CheckSynchronize(50);
  FreeAndNil(FProbe);
end;

procedure TRadioTestCase.Attach(const AService: IRigService);
begin
  FRadio := THamlibRadio.Create(AService);
  FRadio.SetOnConnectionChanged(@FProbe.ConnectionChanged);
  FRadio.SetOnFrequencyChanged(@FProbe.FrequencyChanged);
  FRadio.SetOnError(@FProbe.ErrorReported);
end;

procedure TRadioTestCase.WaitFor(const ADone: PBoolean; const AWhat: string);
var
  Deadline: QWord;
begin
  Deadline := GetTickCount64 + WaitLimitMs;
  while not ADone^ and (GetTickCount64 < Deadline) do
    CheckSynchronize(10);
  AssertTrue('no result in time: ' + AWhat, ADone^);
end;

procedure TRadioTestCase.WaitForConnection;
var
  Deadline: QWord;
begin
  Deadline := GetTickCount64 + WaitLimitMs;
  while not FProbe.Connected and (FProbe.ErrorEvents = 0) and
    (GetTickCount64 < Deadline) do
    CheckSynchronize(10);
  AssertEquals('connection error: ' + FProbe.LastError.Message, 0,
    FProbe.ErrorEvents);
  AssertTrue('the radio did not connect in time', FProbe.Connected);
end;

procedure TRadioTestCase.ExpectOk(const AWhat: string);
begin
  WaitFor(@FProbe.Done, AWhat);
  AssertEquals(AWhat + ': ' + FProbe.Result.Message, RadioErrorName(reNone),
    RadioErrorName(FProbe.Result.Error));
end;

function TRadioTestCase.NewMode(const AMode, ASubmode: string): TMode;
begin
  AssertTrue('test mode ' + AMode, TMode.TryCreate(AMode, ASubmode, Result));
end;

procedure TRadioTestCase.SetModeAndWait(const AMode, ASubmode: string);
begin
  FProbe.Reset;
  FRadio.SetMode(NewMode(AMode, ASubmode), @FProbe.CommandDone);
  ExpectOk('set mode ' + AMode);
end;

{ TRadioModeMappingTests }

function RigModeFor(const AMode, ASubmode: string): TRigMode;
var
  Mode: TMode;
  Reason: string;
begin
  if not TMode.TryCreate(AMode, ASubmode, Mode) then
    raise Exception.Create('bad test mode ' + AMode);
  if not TryRigModeFromMode(Mode, Result, Reason) then
    Result := rmUnknown;
end;

procedure TRadioModeMappingTests.MapsVoiceModes;
begin
  AssertTrue('SSB/USB', RigModeFor('SSB', 'USB') = rmUSB);
  AssertTrue('SSB/LSB', RigModeFor('SSB', 'LSB') = rmLSB);
  AssertTrue('CW', RigModeFor('CW', '') = rmCW);
  AssertTrue('AM', RigModeFor('AM', '') = rmAM);
  AssertTrue('FM', RigModeFor('FM', '') = rmFM);
  AssertTrue('RTTY', RigModeFor('RTTY', '') = rmRTTY);
  AssertTrue('C4FM', RigModeFor('DIGITALVOICE', 'C4FM') = rmC4FM);
  AssertTrue('DSTAR', RigModeFor('DIGITALVOICE', 'DSTAR') = rmDStar);
end;

procedure TRadioModeMappingTests.MapsDataModesToPacketUsb;
begin
  AssertTrue('FT8', RigModeFor('FT8', '') = rmPktUSB);
  AssertTrue('MFSK/FT4', RigModeFor('MFSK', 'FT4') = rmPktUSB);
  AssertTrue('PSK/PSK31', RigModeFor('PSK', 'PSK31') = rmPktUSB);
  AssertTrue('SSTV', RigModeFor('SSTV', '') = rmPktUSB);
  AssertTrue('FREEDV', RigModeFor('DIGITALVOICE', 'FREEDV') = rmPktUSB);
end;

procedure TRadioModeMappingTests.RefusesModesWithoutRadioMode;
var
  Mode: TMode;
  RigMode: TRigMode;
  Reason: string;
begin
  AssertTrue(TMode.TryCreate('SSB', '', Mode));
  AssertFalse('SSB without a submode', TryRigModeFromMode(Mode, RigMode, Reason));
  AssertTrue('reason given', Reason <> '');
  AssertTrue('ATV', RigModeFor('ATV', '') = rmUnknown);
  AssertTrue('DIGITALVOICE alone', RigModeFor('DIGITALVOICE', '') = rmUnknown);
  AssertTrue('DMR', RigModeFor('DIGITALVOICE', 'DMR') = rmUnknown);
  { Not an ADIF mode: kept in the log, but no radio mode follows. }
  AssertTrue('unknown mode', RigModeFor('XYZ', '') = rmUnknown);
end;

procedure TRadioModeMappingTests.ReadsRadioModes;
var
  Reading: TRadioModeReading;
begin
  Reading := ModeReadingFromRigMode(rmUSB);
  AssertTrue('USB has a mode', Reading.HasMode);
  AssertEquals('SSB', Reading.Mode.Mode);
  AssertEquals('USB', Reading.Mode.Submode);
  Reading := ModeReadingFromRigMode(rmCWR);
  AssertEquals('CW', Reading.Mode.Mode);
  Reading := ModeReadingFromRigMode(rmC4FM);
  AssertEquals('DIGITALVOICE', Reading.Mode.Mode);
  AssertEquals('C4FM', Reading.Mode.Submode);
  Reading := ModeReadingFromRigMode(rmPktUSB);
  AssertFalse('PKT-USB has no ADIF mode', Reading.HasMode);
  AssertTrue('radio text kept', Reading.RadioText <> '');
end;

procedure TRadioModeMappingTests.MapsFailures;

  procedure Check(const AExpected: TRadioError; const AStatus: TRigCommandStatus;
    const AKind: TRigErrorKind);
  begin
    AssertEquals(RadioErrorName(AExpected),
      RadioErrorName(RadioResultFromRig(AStatus, AKind, 'x').Error));
  end;

begin
  Check(reNone, rcsSuccess, rekNone);
  Check(reCancelled, rcsCancelled, rekNone);
  Check(reTimeout, rcsTimeout, rekNone);
  Check(reTemporarilyUnavailable, rcsRejected, rekNone);
  Check(reNotConnected, rcsError, rekNotConnected);
  Check(reConnectFailed, rcsError, rekConnectFailed);
  Check(rePortBusy, rcsError, rekAccessDenied);
  Check(reNotSupported, rcsError, rekNotImplemented);
  Check(reFailed, rcsError, rekProtocol);
end;

{ THamlibFakeRadioTests }

procedure THamlibFakeRadioTests.SetUp;
begin
  inherited SetUp;
  FLoader := TFakeHamlibLoader.Create;
  Attach(TRigService.Create(FLoader));
end;

procedure THamlibFakeRadioTests.TearDown;
begin
  inherited TearDown;
  FLoader := nil;
end;

function THamlibFakeRadioTests.Fake: TObject;
begin
  Result := FLoader as TObject;
end;

procedure THamlibFakeRadioTests.Connect(const APollMs: Cardinal);
var
  Connection: TRadioConnection;
begin
  Connection := Default(TRadioConnection);
  Connection.ModelId := 1;
  Connection.PollIntervalMs := APollMs;
  FRadio.Connect(Connection);
  WaitForConnection;
end;

procedure THamlibFakeRadioTests.ConnectReportsTheLink;
begin
  AssertFalse('not connected yet', FRadio.IsConnected);
  Connect;
  AssertTrue(FRadio.IsConnected);
  AssertEquals('one connection event', 1, FProbe.ConnectedEvents);
  FRadio.Disconnect;
  AssertFalse('disconnected', FRadio.IsConnected);
end;

procedure THamlibFakeRadioTests.ConnectAppliesSettings;
var
  Connection: TRadioConnection;
begin
  Connection := Default(TRadioConnection);
  Connection.ModelId := 1;
  SetLength(Connection.Settings, 1);
  Connection.Settings[0].Name := 'serial_speed';
  Connection.Settings[0].Value := '38400';
  FRadio.Connect(Connection);
  WaitForConnection;
  AssertEquals('38400',
    TFakeHamlibLoader(Fake).ConfValue['serial_speed']);
end;

procedure THamlibFakeRadioTests.RefusesSecondConnectAndBadModel;
var
  Connection: TRadioConnection;
begin
  Connection := Default(TRadioConnection);
  try
    FRadio.Connect(Connection);
    Fail('model 0 accepted');
  except
    on EArgumentException do ;
  end;
  Connect;
  Connection.ModelId := 1;
  try
    FRadio.Connect(Connection);
    Fail('second Connect accepted');
  except
    on EInvalidOperation do ;
  end;
end;

procedure THamlibFakeRadioTests.SetsAndGetsFrequency;
var
  Frequency: TFrequencyHz;
begin
  Connect;
  AssertTrue(TFrequencyHz.TryFromHz(7074000, Frequency));
  FRadio.SetFrequency(Frequency, @FProbe.CommandDone);
  ExpectOk('set frequency');
  AssertEquals(7074000.0, TFakeHamlibLoader(Fake).SimFreq, 0.5);

  TFakeHamlibLoader(Fake).SimFreq := 21074000;
  FProbe.Reset;
  FRadio.GetFrequency(@FProbe.FrequencyDone);
  ExpectOk('get frequency');
  AssertEquals(21074000, FProbe.Frequency.Hz);
end;

procedure THamlibFakeRadioTests.SetsModes;
const
  ModeUsb = 4;
  ModeCw = 2;
  ModePktUsb = 2048;
begin
  Connect;
  SetModeAndWait('SSB', 'USB');
  AssertEquals('USB', ModeUsb, TFakeHamlibLoader(Fake).SimMode);
  SetModeAndWait('CW', '');
  AssertEquals('CW', ModeCw, TFakeHamlibLoader(Fake).SimMode);
  SetModeAndWait('FT8', '');
  AssertEquals('PKT-USB', ModePktUsb, TFakeHamlibLoader(Fake).SimMode);
end;

procedure THamlibFakeRadioTests.ReadsModes;
begin
  Connect;
  TFakeHamlibLoader(Fake).SimMode := 2;
  FRadio.GetMode(@FProbe.ModeDone);
  ExpectOk('get CW');
  AssertTrue(FProbe.Reading.HasMode);
  AssertEquals('CW', FProbe.Reading.Mode.DisplayName);

  TFakeHamlibLoader(Fake).SimMode := 2048;
  FProbe.Reset;
  FRadio.GetMode(@FProbe.ModeDone);
  ExpectOk('get PKT-USB');
  AssertFalse('a data mode is not known from PKT-USB', FProbe.Reading.HasMode);
  AssertTrue('radio text', FProbe.Reading.RadioText <> '');
end;

procedure THamlibFakeRadioTests.SetsTransmit;
begin
  Connect;
  FRadio.SetTransmit(True, @FProbe.CommandDone);
  ExpectOk('transmit on');
  AssertEquals(1, TFakeHamlibLoader(Fake).SimPtt);
  FProbe.Reset;
  FRadio.SetTransmit(False, @FProbe.CommandDone);
  ExpectOk('transmit off');
  AssertEquals(0, TFakeHamlibLoader(Fake).SimPtt);
end;

procedure THamlibFakeRadioTests.ReportsCommandFailure;
const
  RigEProto = -8;
begin
  Connect;
  TFakeHamlibLoader(Fake).SimulateFailure(RigEProto);
  FRadio.GetFrequency(@FProbe.FrequencyDone);
  WaitFor(@FProbe.Done, 'failed get');
  AssertTrue('an error is reported', FProbe.Result.Error <> reNone);
  AssertTrue('with a message', FProbe.Result.Message <> '');
end;

procedure THamlibFakeRadioTests.CallsWhileNotConnectedFailAtOnce;
var
  Frequency: TFrequencyHz;
begin
  AssertTrue(TFrequencyHz.TryFromHz(7074000, Frequency));
  FRadio.SetFrequency(Frequency, @FProbe.CommandDone);
  AssertTrue('reported before returning', FProbe.Done);
  AssertEquals(RadioErrorName(reNotConnected), RadioErrorName(FProbe.Result.Error));
  FProbe.Reset;
  FRadio.GetMode(@FProbe.ModeDone);
  AssertTrue(FProbe.Done);
  AssertEquals(RadioErrorName(reNotConnected), RadioErrorName(FProbe.Result.Error));
  FProbe.Reset;
  FRadio.SetTransmit(True, @FProbe.CommandDone);
  AssertTrue(FProbe.Done);
  AssertEquals(RadioErrorName(reNotConnected), RadioErrorName(FProbe.Result.Error));
  AssertEquals('nothing keyed', 0, TFakeHamlibLoader(Fake).SimPtt);
end;

procedure THamlibFakeRadioTests.UnsupportedModeFailsAtOnce;
begin
  Connect;
  FRadio.SetMode(NewMode('SSB', ''), @FProbe.CommandDone);
  AssertTrue('reported before returning', FProbe.Done);
  AssertEquals(RadioErrorName(reNotSupported), RadioErrorName(FProbe.Result.Error));
  AssertEquals('mode unchanged', 4, TFakeHamlibLoader(Fake).SimMode);
end;

procedure THamlibFakeRadioTests.PollingReportsFrequencyChanges;
var
  Deadline: QWord;
begin
  Connect(50);
  TFakeHamlibLoader(Fake).SimFreq := 3573000;
  Deadline := GetTickCount64 + WaitLimitMs;
  while (FProbe.PolledFrequency.Hz <> 3573000) and (GetTickCount64 < Deadline) do
    CheckSynchronize(10);
  AssertEquals(3573000, FProbe.PolledFrequency.Hz);
end;

procedure THamlibFakeRadioTests.FreeingWithPendingCallsDropsResults;
var
  Index: Integer;
begin
  Connect;
  for Index := 1 to 20 do
    FRadio.GetFrequency(@FProbe.FrequencyDone);
  FRadio := nil;
  CheckSynchronize(200);
  { Queued calls run only in CheckSynchronize, so every result arrives
    after the adapter is gone and must not reach the caller. }
  AssertFalse('no callback after the adapter was freed', FProbe.Done);
end;

{ THamlibDummyRigTests }

procedure THamlibDummyRigTests.SetUp;
const
  DummyModel = 1;
var
  Connection: TRadioConnection;
  Service: IRigService;
begin
  inherited SetUp;
  try
    if SharedFactory = nil then
      SharedFactory := TRigServiceFactory.Create('');
    Service := SharedFactory.CreateService;
  except
    on E: Exception do
    begin
      SharedFactory := nil;
      if GetEnvironmentVariable('MUNINN_REQUIRE_HAMLIB') = '1' then
        raise;
      Ignore('Hamlib is not available: ' + E.Message);
    end;
  end;
  Attach(Service);
  Connection := Default(TRadioConnection);
  Connection.ModelId := DummyModel;
  Connection.Port := '';
  FRadio.Connect(Connection);
  WaitForConnection;
end;

procedure THamlibDummyRigTests.SetsAndGetsFrequency;
var
  Frequency: TFrequencyHz;
begin
  AssertTrue(TFrequencyHz.TryFromHz(7041000, Frequency));
  FRadio.SetFrequency(Frequency, @FProbe.CommandDone);
  ExpectOk('set frequency');
  FProbe.Reset;
  FRadio.GetFrequency(@FProbe.FrequencyDone);
  ExpectOk('get frequency');
  AssertEquals(7041000, FProbe.Frequency.Hz);
end;

procedure THamlibDummyRigTests.SetsAndGetsMode;

  procedure RoundTrip(const AMode, ASubmode, AExpected: string);
  begin
    SetModeAndWait(AMode, ASubmode);
    FProbe.Reset;
    FRadio.GetMode(@FProbe.ModeDone);
    ExpectOk('get mode ' + AMode);
    AssertTrue('a mode for ' + FProbe.Reading.RadioText, FProbe.Reading.HasMode);
    AssertEquals(AExpected, FProbe.Reading.Mode.DisplayName);
  end;

begin
  RoundTrip('CW', '', 'CW');
  RoundTrip('SSB', 'LSB', 'LSB');
  RoundTrip('FM', '', 'FM');
  { A data mode is set as PKT-USB and cannot be read back as FT8. }
  SetModeAndWait('FT8', '');
  FProbe.Reset;
  FRadio.GetMode(@FProbe.ModeDone);
  ExpectOk('get data mode');
  AssertFalse(FProbe.Reading.HasMode);
end;

initialization
  RegisterTest(TRadioModeMappingTests);
  RegisterTest(THamlibFakeRadioTests);
  RegisterTest(THamlibDummyRigTests);

finalization
  SharedFactory := nil;

end.
