unit Muninn.Core.Version.Tests;

{$mode objfpc}{$H+}

interface

uses
  fpcunit, testregistry, Muninn.Core.Version;

type
  TVersionTests = class(TTestCase)
  published
    procedure VersionTextJoinsNameAndVersion;
  end;

implementation

procedure TVersionTests.VersionTextJoinsNameAndVersion;
begin
  AssertEquals('MuninnLog 0.0.0', VersionText);
end;

initialization
  RegisterTest(TVersionTests);
end.
