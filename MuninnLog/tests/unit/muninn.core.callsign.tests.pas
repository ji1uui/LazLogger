unit Muninn.Core.Callsign.Tests;

{ Full-width inputs are written as UTF-8 byte escapes so the test does not depend
  on the compiler's source code page or the system ANSI code page on Windows. }

{$mode objfpc}{$H+}

interface

uses
  fpcunit, testregistry, Muninn.Core.Callsign;

type
  TCallsignTests = class(TTestCase)
  private
    procedure CheckValid(const ARaw, AExpected: string);
    procedure CheckInvalid(const ARaw: string; const AExpected: TCallsignError);
  published
    procedure AcceptsPlainCallsign;
    procedure NormalizesCaseAndSpaces;
    procedure FoldsFullWidthInput;
    procedure AcceptsPortableAndPrefixedForms;
    procedure RejectsEmptyAndLengthErrors;
    procedure RejectsInvalidCharacters;
    procedure RejectsMisplacedSeparators;
    procedure RequiresLetterAndDigit;
    procedure ComparesNormalizedValues;
  end;

implementation

const
  { 'ＪＡ１ＡＢＣ' : U+FF2A U+FF21 U+FF11 U+FF21 U+FF22 U+FF23 }
  FullWidthJa1Abc = #$EF#$BC#$AA#$EF#$BC#$A1#$EF#$BC#$91 +
    #$EF#$BC#$A1#$EF#$BC#$A2#$EF#$BC#$A3;
  { '／' U+FF0F and 'ｐ' U+FF50 }
  FullWidthSlash = #$EF#$BC#$8F;
  FullWidthSmallP = #$EF#$BD#$90;
  { U+3000 IDEOGRAPHIC SPACE }
  IdeographicSpace = #$E3#$80#$80;
  { 'あ' U+3042 }
  Hiragana = #$E3#$81#$82;

procedure TCallsignTests.CheckValid(const ARaw, AExpected: string);
var
  Callsign: TCallsign;
  Error: TCallsignError;
begin
  AssertTrue('accepts ' + AExpected, TCallsign.TryCreate(ARaw, Callsign, Error));
  AssertTrue('no error for ' + AExpected, Error = ceNone);
  AssertEquals(AExpected, Callsign.ToString);
end;

procedure TCallsignTests.CheckInvalid(const ARaw: string;
  const AExpected: TCallsignError);
var
  Callsign: TCallsign;
  Error: TCallsignError;
begin
  AssertFalse('rejects ' + ARaw, TCallsign.TryCreate(ARaw, Callsign, Error));
  AssertTrue('error kind for ' + ARaw, Error = AExpected);
  AssertTrue('empty result for ' + ARaw, Callsign.IsEmpty);
end;

procedure TCallsignTests.AcceptsPlainCallsign;
begin
  CheckValid('JA1ZLO', 'JA1ZLO');
  CheckValid('W1AW', 'W1AW');
  CheckValid('8J1A', '8J1A');
end;

procedure TCallsignTests.NormalizesCaseAndSpaces;
begin
  CheckValid('  ja1zlo  ', 'JA1ZLO');
  CheckValid(IdeographicSpace + 'jr1abc' + IdeographicSpace, 'JR1ABC');
end;

procedure TCallsignTests.FoldsFullWidthInput;
begin
  CheckValid(FullWidthJa1Abc, 'JA1ABC');
  CheckValid(FullWidthJa1Abc + FullWidthSlash + FullWidthSmallP, 'JA1ABC/P');
end;

procedure TCallsignTests.AcceptsPortableAndPrefixedForms;
begin
  CheckValid('JA1ABC/3', 'JA1ABC/3');
  CheckValid('KH0/JA1ABC', 'KH0/JA1ABC');
  CheckValid('VP2E/W1AW/QRP', 'VP2E/W1AW/QRP');
end;

procedure TCallsignTests.RejectsEmptyAndLengthErrors;
begin
  CheckInvalid('', ceEmpty);
  CheckInvalid('   ', ceEmpty);
  CheckInvalid('J1', ceTooShort);
  CheckInvalid('JA1ABC/JA1ABC/JA1ABC1', ceTooLong);
end;

procedure TCallsignTests.RejectsInvalidCharacters;
begin
  CheckInvalid('JA1-ABC', ceInvalidCharacter);
  CheckInvalid('JA1 ABC', ceInvalidCharacter);
  CheckInvalid('JA1' + Hiragana, ceInvalidCharacter);
end;

procedure TCallsignTests.RejectsMisplacedSeparators;
begin
  CheckInvalid('/JA1ABC', ceInvalidSeparator);
  CheckInvalid('JA1ABC/', ceInvalidSeparator);
  CheckInvalid('JA1ABC//3', ceInvalidSeparator);
end;

procedure TCallsignTests.RequiresLetterAndDigit;
begin
  CheckInvalid('ABCDEF', ceMissingDigit);
  CheckInvalid('123456', ceMissingLetter);
end;

procedure TCallsignTests.ComparesNormalizedValues;
var
  Left, Right, Other: TCallsign;
begin
  AssertTrue(TCallsign.TryCreate('ja1abc', Left));
  AssertTrue(TCallsign.TryCreate(FullWidthJa1Abc, Right));
  AssertTrue(TCallsign.TryCreate('JA1ABD', Other));
  AssertTrue('same callsign', Left.Equals(Right));
  AssertFalse('different callsign', Left.Equals(Other));
end;

initialization
  RegisterTest(TCallsignTests);
end.
