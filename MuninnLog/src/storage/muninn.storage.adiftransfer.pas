unit Muninn.Storage.AdifTransfer;

{ Imports an ADI file into a logbook and exports a logbook as ADI text
  (ADR 0006). An import runs in one transaction: either every valid record is
  stored or, on a storage error, none is. Records that are not QSOs are
  reported in AIssues and skipped. }

{$mode objfpc}{$H+}

interface

uses
  Muninn.Core.Adif, Muninn.Core.Time, Muninn.Storage.Sqlite;

type
  TAdifImportSummary = record
    { ADIF records in the file. }
    RecordCount: Integer;
    Imported: Integer;
    Rejected: Integer;
  end;

{ Raises EFileNotFoundException or EStreamError when AFileName cannot be read,
  and ESqliteError on a storage error (nothing is stored then). }
function ImportAdifFile(const ADatabase: TSqliteDatabase; const AFileName: string;
  const ANowUtcMs: Int64; const AIssues: TAdifIssues): TAdifImportSummary;
{ ADI text for every QSO in the logbook, oldest insert first. }
function ExportAdifText(const ADatabase: TSqliteDatabase; const ACreated: TUtcInstant;
  const AProgramVersion: string): string;

function ReadFileBytes(const AFileName: string): string;
procedure WriteFileBytes(const AFileName, AText: string);

implementation

uses
  Classes, SysUtils, Contnrs, Muninn.Core.AdifQso, Muninn.Core.Qso,
  Muninn.Storage.QsoRepository;

const
  AdifSource = 'adif';

function ReadFileBytes(const AFileName: string): string;
var
  Stream: TFileStream;
begin
  if not FileExists(AFileName) then
    raise EFileNotFoundException.CreateFmt('File not found: %s', [AFileName]);
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    Result := '';
    SetLength(Result, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Result[1], Stream.Size);
  finally
    Stream.Free;
  end;
end;

procedure WriteFileBytes(const AFileName, AText: string);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(AFileName, fmCreate);
  try
    if AText <> '' then
      Stream.WriteBuffer(AText[1], Length(AText));
  finally
    Stream.Free;
  end;
end;

function ImportAdifFile(const ADatabase: TSqliteDatabase; const AFileName: string;
  const ANowUtcMs: Int64; const AIssues: TAdifIssues): TAdifImportSummary;
var
  Document: TAdifDocument;
  Qsos: TObjectList;
  Repository: TQsoRepository;
  Index: Integer;
begin
  Result := Default(TAdifImportSummary);
  Document := TAdifDocument.Create;
  Qsos := TObjectList.Create(True);
  Repository := TQsoRepository.Create(ADatabase);
  try
    ReadAdi(ReadFileBytes(AFileName), Document, AIssues);
    ImportAdifDocument(Document, AIssues, Qsos);
    Result.RecordCount := Document.RecordCount;
    Result.Imported := Qsos.Count;
    Result.Rejected := Document.RecordCount - Qsos.Count;
    ADatabase.BeginTransaction;
    try
      Repository.SaveUserFields(Document.Header, AIssues);
      for Index := 0 to Qsos.Count - 1 do
        Repository.Insert(TQsoRecord(Qsos[Index]), AdifSource, ANowUtcMs);
      ADatabase.Commit;
    except
      ADatabase.Rollback;
      raise;
    end;
  finally
    Repository.Free;
    Qsos.Free;
    Document.Free;
  end;
end;

function ExportAdifText(const ADatabase: TSqliteDatabase; const ACreated: TUtcInstant;
  const AProgramVersion: string): string;
var
  Repository: TQsoRepository;
  Qsos: TObjectList;
  UserFields: TAdifRecord;
  Document: TAdifDocument;
begin
  Repository := TQsoRepository.Create(ADatabase);
  Qsos := TObjectList.Create(True);
  UserFields := nil;
  Document := nil;
  try
    Repository.LoadAll(Qsos);
    UserFields := Repository.LoadUserFieldHeader;
    Document := ExportAdifDocument(Qsos, ACreated, AProgramVersion, UserFields);
    Result := WriteAdi(Document);
  finally
    Document.Free;
    UserFields.Free;
    Qsos.Free;
    Repository.Free;
  end;
end;

end.
