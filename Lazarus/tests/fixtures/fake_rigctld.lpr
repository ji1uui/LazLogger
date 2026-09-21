program FakeRigctld;

{$mode objfpc}{$H+}

uses
  SysUtils;

var
  Command: string;
begin
  while not EOF(Input) do
  begin
    ReadLn(Command);
    if Command = 'f' then
      WriteLn('7100000')
    else if Pos('F ', Command) = 1 then
      WriteLn('RPRT 0')
    else if Command = 'delay' then
    begin
      Sleep(250);
      WriteLn('late');
    end
    else if Command = 'quit' then
      Halt(0)
    else
      WriteLn('RPRT -1');
    Flush(Output);
  end;
end.
