unit Muninn.Storage.Logbook.Tests;

{ Opening, creating and closing logbooks through the presenter, on SQLite
  (T12), and the recent-logbook list in the settings directory. }

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Muninn.Core.Logbook,
  Muninn.UI.Logbook;

type
  TFakeLogbookView = class(TInterfacedObject, ILogbookView)
  public
    ShownPath: string;
    ShownCount: Int64;
    Closed: Integer;
    Error: string;
    Recent: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure ShowLogbook(const APath: string; const AQsoCount: Int64);
    procedure ShowNoLogbook;
    procedure ShowLogbookError(const AMessage: string);
    procedure ShowRecentLogbooks(const APaths: TStrings);
  end;

  TLogbookTests = class(TTestCase)
  private
    FDirectory: string;
    FViewObject: TFakeLogbookView;
    FView: ILogbookView;
    FPresenter: TLogbookPresenter;
    FSaved: TStringList;
    function PathOf(const AName: string): string;
    procedure SaveRecent(const APaths: TStrings);
    procedure ExpectError(const AKind: TLogbookErrorKind; const APath: string;
      const ACreate: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure CreatesOpensAndCloses;
    procedure RefusesToCreateOverAFile;
    procedure RefusesToOpenAMissingFile;
    procedure RefusesAFileThatIsNotALogbook;
    procedure RefusesANewerLogbookUnchanged;
    procedure KeepsTheOpenLogbookWhenOpeningFails;
    procedure RemembersRecentLogbooks;
    procedure ForgetsAMissingRecentLogbook;
    procedure OpensTheMostRecentLogbook;
    procedure SavesAndLoadsTheRecentList;
    procedure HandlesNonAsciiPaths;
  end;

implementation

uses
  Muninn.Storage.Logbook, Muninn.Storage.Sqlite, Muninn.Storage.Settings;

{ TFakeLogbookView }

constructor TFakeLogbookView.Create;
begin
  inherited Create;
  Recent := TStringList.Create;
end;

destructor TFakeLogbookView.Destroy;
begin
  Recent.Free;
  inherited Destroy;
end;

procedure TFakeLogbookView.ShowLogbook(const APath: string; const AQsoCount: Int64);
begin
  ShownPath := APath;
  ShownCount := AQsoCount;
  Error := '';
end;

procedure TFakeLogbookView.ShowNoLogbook;
begin
  ShownPath := '';
  Inc(Closed);
end;

procedure TFakeLogbookView.ShowLogbookError(const AMessage: string);
begin
  Error := AMessage;
end;

procedure TFakeLogbookView.ShowRecentLogbooks(const APaths: TStrings);
begin
  Recent.Assign(APaths);
end;

{ TLogbookTests }

procedure TLogbookTests.SetUp;
begin
  FDirectory := IncludeTrailingPathDelimiter(GetTempDir(False)) +
    Format('muninn-logbook-%d-%d', [GetProcessID, Random(MaxInt)]);
  ForceDirectories(FDirectory);
  FViewObject := TFakeLogbookView.Create;
  FView := FViewObject;
  FSaved := TStringList.Create;
  FPresenter := TLogbookPresenter.Create(TSqliteLogbookStore.Create, FView,
    @SaveRecent);
end;

procedure TLogbookTests.TearDown;

  procedure RemoveTree(const ADirectory: string);
  var
    Search: TSearchRec;
    Path: string;
  begin
    if FindFirst(IncludeTrailingPathDelimiter(ADirectory) + AllFilesMask,
      faAnyFile, Search) = 0 then
      try
        repeat
          if (Search.Name = '.') or (Search.Name = '..') then
            Continue;
          Path := IncludeTrailingPathDelimiter(ADirectory) + Search.Name;
          if (Search.Attr and faDirectory) <> 0 then
            RemoveTree(Path)
          else
            DeleteFile(Path);
        until FindNext(Search) <> 0;
      finally
        FindClose(Search);
      end;
    RemoveDir(ADirectory);
  end;

begin
  FPresenter.Free;
  FView := nil;
  FSaved.Free;
  RemoveTree(FDirectory);
end;

function TLogbookTests.PathOf(const AName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(FDirectory) + AName;
end;

procedure TLogbookTests.SaveRecent(const APaths: TStrings);
begin
  FSaved.Assign(APaths);
end;

procedure TLogbookTests.ExpectError(const AKind: TLogbookErrorKind;
  const APath: string; const ACreate: Boolean);
var
  Store: ILogbookStore;
begin
  Store := TSqliteLogbookStore.Create;
  try
    if ACreate then
      Store.CreateNew(APath)
    else
      Store.Open(APath);
    Fail('no error for ' + APath);
  except
    on E: ELogbookError do
      AssertEquals('error kind for ' + APath, Ord(AKind), Ord(E.Kind));
  end;
end;

procedure TLogbookTests.CreatesOpensAndCloses;
var
  Path: string;
begin
  Path := PathOf('daily.muninnlog');
  AssertTrue('created', FPresenter.NewRequested(Path));
  AssertTrue(FileExists(Path));
  AssertEquals(ExpandFileName(Path), ExpandFileName(FViewObject.ShownPath));
  AssertEquals(0, FViewObject.ShownCount);
  FPresenter.CloseRequested;
  AssertFalse(FPresenter.HasLogbook);
  AssertEquals(1, FViewObject.Closed);
  AssertTrue('reopened', FPresenter.OpenRequested(Path));
  AssertTrue(FPresenter.HasLogbook);
end;

procedure TLogbookTests.RefusesToCreateOverAFile;
var
  Path: string;
begin
  Path := PathOf('taken.muninnlog');
  with TStringList.Create do
    try
      Add('not a logbook');
      SaveToFile(Path);
    finally
      Free;
    end;
  ExpectError(lekAlreadyExists, Path, True);
  AssertFalse(FPresenter.NewRequested(Path));
  AssertTrue('error shown', FViewObject.Error <> '');
end;

procedure TLogbookTests.RefusesToOpenAMissingFile;
var
  Path: string;
begin
  Path := PathOf('missing.muninnlog');
  ExpectError(lekNotFound, Path, False);
  AssertFalse('not created by opening', FileExists(Path));
end;

procedure TLogbookTests.RefusesAFileThatIsNotALogbook;
var
  Path: string;
  Bytes: TFileStream;
  Junk: array[0..4095] of Byte;
begin
  Path := PathOf('notes.txt');
  FillChar(Junk, SizeOf(Junk), Ord('x'));
  Bytes := TFileStream.Create(Path, fmCreate);
  try
    Bytes.WriteBuffer(Junk, SizeOf(Junk));
  finally
    Bytes.Free;
  end;
  ExpectError(lekNotALogbook, Path, False);
end;

procedure TLogbookTests.RefusesANewerLogbookUnchanged;
var
  Path: string;
  Database: TSqliteDatabase;
begin
  Path := PathOf('future.muninnlog');
  AssertTrue(FPresenter.NewRequested(Path));
  FPresenter.CloseRequested;
  Database := TSqliteDatabase.Open(Path);
  try
    Database.Execute('PRAGMA user_version = 9999');
  finally
    Database.Free;
  end;
  ExpectError(lekNewerVersion, Path, False);
  Database := TSqliteDatabase.Open(Path);
  try
    AssertEquals('left unchanged', 9999, Database.QueryInt64('PRAGMA user_version'));
  finally
    Database.Free;
  end;
end;

procedure TLogbookTests.KeepsTheOpenLogbookWhenOpeningFails;
var
  Path: string;
begin
  Path := PathOf('kept.muninnlog');
  AssertTrue(FPresenter.NewRequested(Path));
  AssertFalse(FPresenter.OpenRequested(PathOf('missing.muninnlog')));
  AssertTrue('still open', FPresenter.HasLogbook);
  AssertEquals(ExpandFileName(Path), ExpandFileName(FPresenter.Logbook.Path));
end;

procedure TLogbookTests.RemembersRecentLogbooks;
var
  Index: Integer;
begin
  for Index := 1 to TLogbookPresenter.MaxRecent + 2 do
    AssertTrue(FPresenter.NewRequested(PathOf(Format('log%d.muninnlog', [Index]))));
  AssertTrue('reopening moves it to the top',
    FPresenter.OpenRequested(PathOf('log5.muninnlog')));
  AssertEquals(TLogbookPresenter.MaxRecent, FSaved.Count);
  AssertEquals(ExpandFileName(PathOf('log5.muninnlog')), FSaved[0]);
  AssertEquals(ExpandFileName(PathOf('log10.muninnlog')), FSaved[1]);
  AssertEquals('the view gets the same list', FSaved.Text, FViewObject.Recent.Text);
end;

procedure TLogbookTests.ForgetsAMissingRecentLogbook;
var
  Path: string;
begin
  Path := PathOf('gone.muninnlog');
  AssertTrue(FPresenter.NewRequested(Path));
  FPresenter.CloseRequested;
  AssertTrue(DeleteFile(Path));
  AssertFalse(FPresenter.OpenMostRecent);
  AssertEquals('dropped from the list', 0, FSaved.Count);
end;

procedure TLogbookTests.OpensTheMostRecentLogbook;
var
  List: TStringList;
  Path: string;
begin
  Path := PathOf('last.muninnlog');
  AssertTrue(FPresenter.NewRequested(Path));
  FPresenter.CloseRequested;
  List := TStringList.Create;
  try
    List.Add(Path);
    List.Add(Path);
    FPresenter.SetRecentLogbooks(List);
  finally
    List.Free;
  end;
  AssertEquals('duplicates dropped', 1, FPresenter.Recent.Count);
  AssertTrue(FPresenter.OpenMostRecent);
  AssertEquals(ExpandFileName(Path), ExpandFileName(FPresenter.Logbook.Path));
end;

procedure TLogbookTests.SavesAndLoadsTheRecentList;
var
  Directory: string;
  List, Loaded: TStringList;
begin
  Directory := PathOf('settings' + PathDelim + 'nested');
  List := TStringList.Create;
  Loaded := TStringList.Create;
  try
    List.Add(PathOf('a.muninnlog'));
    List.Add(PathOf('ログ帳.muninnlog'));
    SaveRecentLogbooks(Directory, List);
    SaveRecentLogbooks(Directory, List);
    LoadRecentLogbooks(Directory, Loaded);
    AssertEquals(List.Text, Loaded.Text);
    LoadRecentLogbooks(PathOf('nowhere'), Loaded);
    AssertEquals('a missing file is an empty list', 0, Loaded.Count);
  finally
    Loaded.Free;
    List.Free;
  end;
end;

procedure TLogbookTests.HandlesNonAsciiPaths;
var
  Path: string;
begin
  Path := PathOf('日常ログ.muninnlog');
  AssertTrue('created: ' + FViewObject.Error, FPresenter.NewRequested(Path));
  AssertTrue('file exists', FileExists(Path));
  FPresenter.CloseRequested;
  AssertTrue('reopened: ' + FViewObject.Error, FPresenter.OpenRequested(Path));
end;

initialization
  RegisterTest(TLogbookTests);

end.
