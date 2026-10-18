unit Muninn.Core.AdifModes.Tests;

{$mode objfpc}{$H+}

interface

uses
  fpcunit, testregistry, Muninn.Core.AdifModes;

type
  TAdifModesTests = class(TTestCase)
  published
    procedure HasTheWholeEnumeration;
    procedure FindsParentModes;
    procedure ConvertsImportOnlyModes;
    procedure LeavesOtherModesAlone;
  end;

implementation

procedure TAdifModesTests.HasTheWholeEnumeration;
begin
  { ADIF 3.1.8 III.B.10: 49 modes and 198 submodes. }
  AssertEquals(49, AdifModeCount);
  AssertEquals(198, AdifSubmodeCount);
  AssertTrue(IsAdifMode('ft8'));
  AssertTrue(IsAdifMode('WSPR'));
  AssertFalse('import-only', IsAdifMode('C4FM'));
  AssertFalse('a Morse key type, not a mode', IsAdifMode('BUG'));
end;

procedure TAdifModesTests.FindsParentModes;
var
  Mode: string;
begin
  AssertTrue(TryAdifParentMode('usb', Mode));
  AssertEquals('SSB', Mode);
  AssertTrue(TryAdifParentMode('VARA HF', Mode));
  AssertEquals('DYNAMIC', Mode);
  AssertTrue(TryAdifParentMode('OLIVIA 4/125', Mode));
  AssertEquals('OLIVIA', Mode);
  AssertTrue('listed without a comma in the specification',
    TryAdifParentMode('MFSK128L', Mode));
  AssertEquals('MFSK', Mode);
  AssertFalse(TryAdifParentMode('FT8', Mode));
  AssertEquals('', Mode);
end;

procedure TAdifModesTests.ConvertsImportOnlyModes;
var
  Mode, Submode: string;
begin
  Mode := 'C4FM';
  Submode := '';
  AssertTrue(TryConvertImportOnlyMode(Mode, Submode));
  AssertEquals('DIGITALVOICE', Mode);
  AssertEquals('C4FM', Submode);
  Mode := 'psk31';
  Submode := 'PSK31';
  AssertTrue('same submode given', TryConvertImportOnlyMode(Mode, Submode));
  AssertEquals('PSK', Mode);
end;

procedure TAdifModesTests.LeavesOtherModesAlone;
var
  Mode, Submode: string;
begin
  Mode := 'SSB';
  Submode := 'USB';
  AssertFalse(TryConvertImportOnlyMode(Mode, Submode));
  AssertEquals('SSB', Mode);
  Mode := 'VARA';
  Submode := '';
  AssertFalse('unknown', TryConvertImportOnlyMode(Mode, Submode));
  Mode := 'PSK31';
  Submode := 'PSK63';
  AssertFalse('conflicting submode', TryConvertImportOnlyMode(Mode, Submode));
  AssertEquals('PSK31', Mode);
end;

initialization
  RegisterTest(TAdifModesTests);
end.
