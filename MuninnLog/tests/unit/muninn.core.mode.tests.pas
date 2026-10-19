unit Muninn.Core.Mode.Tests;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  fpcunit, testregistry, Muninn.Core.Mode;

type
  TModeTests = class(TTestCase)
  private
    procedure CheckDisplay(const AText, AMode, ASubmode: string);
  published
    procedure NormalizesModeAndSubmode;
    procedure RejectsInvalidTokens;
    procedure KeepsUnknownModes;
    procedure ClassifiesKnownModes;
    procedure ParsesModesAndImpliedSubmodes;
    procedure RejectsUnknownDisplayText;
    procedure ShowsSubmodeWhenPresent;
  end;

implementation

procedure TModeTests.CheckDisplay(const AText, AMode, ASubmode: string);
var
  Mode: TMode;
begin
  AssertTrue('parse ' + AText, TMode.TryParseDisplay(AText, Mode));
  AssertEquals('mode for ' + AText, AMode, Mode.Mode);
  AssertEquals('submode for ' + AText, ASubmode, Mode.Submode);
end;

procedure TModeTests.NormalizesModeAndSubmode;
var
  Mode: TMode;
begin
  AssertTrue(TMode.TryCreate(' ssb ', 'usb', Mode));
  AssertEquals('SSB', Mode.Mode);
  AssertEquals('USB', Mode.Submode);
  AssertTrue(TMode.TryCreate('CW', '', Mode));
  AssertEquals('', Mode.Submode);
end;

procedure TModeTests.RejectsInvalidTokens;
var
  Mode: TMode;
begin
  AssertFalse('empty mode', TMode.TryCreate('', 'USB', Mode));
  AssertFalse('control character', TMode.TryCreate('SS'#9'B', '', Mode));
  AssertFalse('non-ASCII', TMode.TryCreate('SSB', 'ＵＳＢ', Mode));
  AssertFalse('double space', TMode.TryCreate('DYNAMIC', 'VARA  HF', Mode));
  AssertEquals('cleared on failure', '', Mode.Mode);
end;

procedure TModeTests.KeepsUnknownModes;
var
  Mode: TMode;
begin
  AssertTrue('values outside the ADIF enumeration are kept',
    TMode.TryCreate('olivia 8-250', '', Mode));
  AssertEquals('OLIVIA 8-250', Mode.Mode);
  AssertFalse(Mode.IsKnown);
  AssertTrue('ADIF submodes may have spaces and slashes',
    TMode.TryCreate('olivia', 'olivia 4/125', Mode));
  AssertEquals('OLIVIA 4/125', Mode.Submode);
  AssertTrue(TMode.TryCreate('DOMINO', 'DOM-M', Mode));
  AssertFalse('not in the known table', Mode.IsKnown);
  AssertTrue(Mode.Category = mcUnknown);
end;

procedure TModeTests.ClassifiesKnownModes;
var
  Mode: TMode;
begin
  AssertTrue(TMode.TryCreate('CW', '', Mode));
  AssertTrue('CW', Mode.Category = mcCw);
  AssertTrue(TMode.TryCreate('SSB', 'LSB', Mode));
  AssertTrue('SSB', Mode.Category = mcPhone);
  AssertTrue(TMode.TryCreate('FM', '', Mode));
  AssertTrue('FM', Mode.Category = mcPhone);
  AssertTrue(TMode.TryCreate('FT8', '', Mode));
  AssertTrue('FT8', Mode.Category = mcDigital);
  AssertTrue(TMode.TryCreate('RTTY', '', Mode));
  AssertTrue('RTTY', Mode.Category = mcDigital);
  AssertTrue(Mode.IsKnown);
end;

procedure TModeTests.ParsesModesAndImpliedSubmodes;
begin
  CheckDisplay('cw', 'CW', '');
  CheckDisplay('FT8', 'FT8', '');
  CheckDisplay('usb', 'SSB', 'USB');
  CheckDisplay('LSB', 'SSB', 'LSB');
  CheckDisplay('FT4', 'MFSK', 'FT4');
  CheckDisplay('JS8', 'MFSK', 'JS8');
  CheckDisplay('PSK31', 'PSK', 'PSK31');
end;

procedure TModeTests.RejectsUnknownDisplayText;
var
  Mode: TMode;
begin
  AssertFalse(TMode.TryParseDisplay('', Mode));
  AssertFalse(TMode.TryParseDisplay('PHONE', Mode));
end;

procedure TModeTests.ShowsSubmodeWhenPresent;
var
  Mode: TMode;
begin
  AssertTrue(TMode.TryCreate('MFSK', 'FT4', Mode));
  AssertEquals('FT4', Mode.DisplayName);
  AssertTrue(TMode.TryCreate('CW', '', Mode));
  AssertEquals('CW', Mode.DisplayName);
end;

initialization
  RegisterTest(TModeTests);
end.
