unit Muninn.Core.Utf8Default;

{ Makes UTF-8 the code page of string (AnsiString) for the whole program, as
  the LCL does for GUI programs. Without it, programs that do not use the LCL
  (muninn-cli, the test runners) convert string to the OS ANSI code page and
  lose Japanese text on Windows or under a C locale.
  Every MuninnLog program lists this unit in uses, right after
  cthreads and cwstring. }

{$mode objfpc}{$H+}

interface

implementation

initialization
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteRTLFileSystemCodePage(CP_UTF8);
end.
