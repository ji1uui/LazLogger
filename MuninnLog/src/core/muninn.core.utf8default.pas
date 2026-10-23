unit Muninn.Core.Utf8Default;

{ Makes UTF-8 the code page of string (AnsiString) for the whole program, as
  the LCL does for GUI programs. Without it, programs that do not use the LCL
  (muninn-cli, the test runners) convert string to the OS ANSI code page and
  lose Japanese text on Windows or under a C locale.
  It also makes UTF-8 the code page of file names passed to the OS.
  Every MuninnLog program lists this unit in uses, right after
  cthreads and cwstring. }

{$mode objfpc}{$H+}

interface

implementation

initialization
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteRTLFileSystemCodePage(CP_UTF8);
  { The code page of file names passed to the OS. On Unix, cwstring takes it
    from the locale, so under a C locale FileExists turned a Japanese name into
    '?' and missed a file SQLite had created with its UTF-8 name. macOS and
    current Linux use UTF-8 file names. On Windows the RTL calls the UTF-16
    file API, converting from the string's own code page. }
  SetMultiByteFileSystemCodePage(CP_UTF8);
end.
