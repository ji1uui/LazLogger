unit Muninn.Core.Logbook;

{ The logbook port: opening, creating and closing a logbook file, without
  knowing how it is stored (the SQLite implementation is
  Muninn.Storage.Logbook). Releasing the last reference closes the file. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Muninn.Core.QsoWriter;

type
  { What the duplicate check needs from one logged QSO. }
  TWorkedEntry = record
    Call: string;
    { ADIF band name in lower case; '' when neither band nor frequency was
      recorded. }
    Band: string;
    { ADIF MODE (not SUBMODE). }
    Mode: string;
  end;
  TWorkedEntries = array of TWorkedEntry;

  TLogbookErrorKind = (
    lekNotFound,
    lekAlreadyExists,
    { Written by a newer MuninnLog; left unchanged. }
    lekNewerVersion,
    { Not a logbook (another kind of file, or damaged). }
    lekNotALogbook,
    { Another program holds it locked. }
    lekBusy,
    lekFailed);

  ELogbookError = class(Exception)
  private
    FKind: TLogbookErrorKind;
  public
    constructor CreateKind(const AKind: TLogbookErrorKind; const AMessage: string);
    property Kind: TLogbookErrorKind read FKind;
  end;

  ILogbook = interface
    ['{3E9B1C52-7A0D-4F6E-8B21-5C4D9E7F0A16}']
    function Path: string;
    function QsoCount: Int64;
    { Every QSO's call, band and mode, for the duplicate and partial check. }
    function LoadWorked: TWorkedEntries;
    { A writer with its own connection to this logbook. }
    function CreateWriter: IQsoWriter;
  end;

  ILogbookStore = interface
    ['{A4C82E19-5B3F-4D70-9E6A-1F2B8C7D4E05}']
    { Opens an existing logbook, bringing its schema up to date. }
    function Open(const APath: string): ILogbook;
    { Creates a logbook at APath; refuses an existing file. }
    function CreateNew(const APath: string): ILogbook;
  end;

implementation

constructor ELogbookError.CreateKind(const AKind: TLogbookErrorKind;
  const AMessage: string);
begin
  inherited Create(AMessage);
  FKind := AKind;
end;

end.
