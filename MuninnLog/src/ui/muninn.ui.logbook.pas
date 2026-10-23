unit Muninn.UI.Logbook;

{ Opening, creating and closing the logbook, without the LCL (T12). The
  presenter keeps the open logbook and the list of recently used ones; the
  view shows them and asks for file names. }

{$mode objfpc}{$H+}

interface

uses
  Classes, Muninn.Core.Logbook;

type
  ILogbookView = interface
    ['{6D2E8A41-0B7C-4F35-A9D1-3C5E7B9F2A64}']
    procedure ShowLogbook(const APath: string; const AQsoCount: Int64);
    procedure ShowNoLogbook;
    procedure ShowLogbookError(const AMessage: string);
    procedure ShowRecentLogbooks(const APaths: TStrings);
  end;

  { Saves the recent list (Muninn.Storage.Settings in the application). }
  TRecentLogbooksSaver = procedure(const APaths: TStrings) of object;

  TLogbookPresenter = class
  private
    FStore: ILogbookStore;
    FView: ILogbookView;
    FSaveRecent: TRecentLogbooksSaver;
    FRecent: TStringList;
    FLogbook: ILogbook;
    function IndexOfRecent(const APath: string): Integer;
    procedure RememberRecent(const APath: string);
    procedure ForgetRecent(const APath: string);
    procedure RecentChanged;
    function Switch(const APath: string; const ACreate: Boolean): Boolean;
  public
    const
      MaxRecent = 8;
    constructor Create(const AStore: ILogbookStore; const AView: ILogbookView;
      const ASaveRecent: TRecentLogbooksSaver);
    destructor Destroy; override;
    { The list as loaded from the settings, most recent first. }
    procedure SetRecentLogbooks(const APaths: TStrings);
    { Opens APath. On failure the open logbook stays open, the view shows the
      error, and a missing file leaves the recent list. }
    function OpenRequested(const APath: string): Boolean;
    function NewRequested(const APath: string): Boolean;
    procedure CloseRequested;
    { Opens the most recent logbook, if any; at start-up. }
    function OpenMostRecent: Boolean;
    function HasLogbook: Boolean;
    property Logbook: ILogbook read FLogbook;
    property Recent: TStringList read FRecent;
  end;

{ Text for the user, by error kind. }
function LogbookErrorText(const AError: ELogbookError): string;

implementation

uses
  SysUtils;

function LogbookErrorText(const AError: ELogbookError): string;
begin
  case AError.Kind of
    lekNotFound: Result := 'The logbook file was not found.';
    lekAlreadyExists: Result := 'A file with that name already exists.';
    lekNewerVersion:
      Result := 'This logbook was written by a newer MuninnLog. ' +
        'It was left unchanged; open it with that version.';
    lekNotALogbook: Result := 'This file is not a MuninnLog logbook, or it is damaged.';
    lekBusy: Result := 'Another program is using this logbook. Close it and try again.';
  else
    Result := 'The logbook could not be opened.';
  end;
  Result := Result + LineEnding + AError.Message;
end;

constructor TLogbookPresenter.Create(const AStore: ILogbookStore;
  const AView: ILogbookView; const ASaveRecent: TRecentLogbooksSaver);
begin
  inherited Create;
  if (AStore = nil) or (AView = nil) then
    raise EArgumentNilException.Create('TLogbookPresenter needs a store and a view');
  FStore := AStore;
  FView := AView;
  FSaveRecent := ASaveRecent;
  FRecent := TStringList.Create;
end;

destructor TLogbookPresenter.Destroy;
begin
  FLogbook := nil;
  FRecent.Free;
  FView := nil;
  inherited Destroy;
end;

function TLogbookPresenter.IndexOfRecent(const APath: string): Integer;
begin
  for Result := 0 to FRecent.Count - 1 do
    if SameFileName(ExpandFileName(FRecent[Result]), ExpandFileName(APath)) then
      Exit;
  Result := -1;
end;

procedure TLogbookPresenter.RecentChanged;
begin
  FView.ShowRecentLogbooks(FRecent);
  if Assigned(FSaveRecent) then
    FSaveRecent(FRecent);
end;

procedure TLogbookPresenter.RememberRecent(const APath: string);
var
  Index: Integer;
begin
  Index := IndexOfRecent(APath);
  if Index >= 0 then
    FRecent.Delete(Index);
  FRecent.Insert(0, ExpandFileName(APath));
  while FRecent.Count > MaxRecent do
    FRecent.Delete(FRecent.Count - 1);
  RecentChanged;
end;

procedure TLogbookPresenter.ForgetRecent(const APath: string);
var
  Index: Integer;
begin
  Index := IndexOfRecent(APath);
  if Index < 0 then
    Exit;
  FRecent.Delete(Index);
  RecentChanged;
end;

procedure TLogbookPresenter.SetRecentLogbooks(const APaths: TStrings);
var
  Index: Integer;
begin
  FRecent.Clear;
  for Index := 0 to APaths.Count - 1 do
    if (IndexOfRecent(APaths[Index]) < 0) and (FRecent.Count < MaxRecent) then
      FRecent.Add(APaths[Index]);
  FView.ShowRecentLogbooks(FRecent);
end;

function TLogbookPresenter.Switch(const APath: string; const ACreate: Boolean): Boolean;
var
  Opened: ILogbook;
begin
  Result := False;
  try
    if ACreate then
      Opened := FStore.CreateNew(APath)
    else
      Opened := FStore.Open(APath);
  except
    on E: ELogbookError do
    begin
      if E.Kind = lekNotFound then
        ForgetRecent(APath);
      FView.ShowLogbookError(LogbookErrorText(E));
      Exit;
    end;
  end;
  { Close the old one only once the new one is open. }
  FLogbook := Opened;
  RememberRecent(FLogbook.Path);
  FView.ShowLogbook(FLogbook.Path, FLogbook.QsoCount);
  Result := True;
end;

function TLogbookPresenter.OpenRequested(const APath: string): Boolean;
begin
  Result := Switch(APath, False);
end;

function TLogbookPresenter.NewRequested(const APath: string): Boolean;
begin
  Result := Switch(APath, True);
end;

procedure TLogbookPresenter.CloseRequested;
begin
  FLogbook := nil;
  FView.ShowNoLogbook;
end;

function TLogbookPresenter.OpenMostRecent: Boolean;
begin
  Result := (FRecent.Count > 0) and OpenRequested(FRecent[0]);
end;

function TLogbookPresenter.HasLogbook: Boolean;
begin
  Result := FLogbook <> nil;
end;

end.
