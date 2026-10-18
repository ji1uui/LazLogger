unit Muninn.Tests.Runtime;

{ Checks that the test program is linked the way every MuninnLog program must be.
  The Lazarus/ prototype crashed on Unix because cwstring was missing from uses.
  Without Muninn.Core.Utf8Default, string loses Japanese text on Windows. }

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  SysUtils, fpcunit, testregistry;

type
  TRuntimeTests = class(TTestCase)
  published
    procedure UnicodeCaseConversionWorks;
    procedure StringIsUtf8;
  end;

implementation

procedure TRuntimeTests.UnicodeCaseConversionWorks;
begin
  AssertEquals('ASCII', UnicodeString('JA1ZLO'),
    UnicodeUpperCase(UnicodeString('ja1zlo')));
  AssertEquals('Japanese text is unchanged', UnicodeString('東京'),
    UnicodeUpperCase(UnicodeString('東京')));
end;

procedure TRuntimeTests.StringIsUtf8;
var
  Text: string;
begin
  AssertEquals('default code page', CP_UTF8, DefaultSystemCodePage);
  Text := UTF8Encode(UnicodeString('東京'));
  AssertEquals('round trip through string', UnicodeString('東京'),
    UTF8Decode(Text));
  Text := string(UnicodeString('東京'));
  AssertEquals('UTF-8 bytes', 6, Length(Text));
end;

initialization
  RegisterTest(TRuntimeTests);
end.
