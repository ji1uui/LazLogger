unit Muninn.Tests.Runtime;

{ Checks that the test program is linked the way every MuninnLog program must be.
  The Lazarus/ prototype crashed on Unix because cwstring was missing from uses. }

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  SysUtils, fpcunit, testregistry;

type
  TRuntimeTests = class(TTestCase)
  published
    procedure UnicodeCaseConversionWorks;
  end;

implementation

procedure TRuntimeTests.UnicodeCaseConversionWorks;
begin
  AssertEquals('ASCII', UnicodeString('JA1ZLO'),
    UnicodeUpperCase(UnicodeString('ja1zlo')));
  AssertEquals('Japanese text is unchanged', UnicodeString('東京'),
    UnicodeUpperCase(UnicodeString('東京')));
end;

initialization
  RegisterTest(TRuntimeTests);
end.
