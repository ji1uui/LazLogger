unit Muninn.Core.Version;

{$mode objfpc}{$H+}

interface

const
  ApplicationName = 'MuninnLog';
  ApplicationVersion = '0.0.0';

function VersionText: string;

implementation

function VersionText: string;
begin
  Result := ApplicationName + ' ' + ApplicationVersion;
end;

end.
