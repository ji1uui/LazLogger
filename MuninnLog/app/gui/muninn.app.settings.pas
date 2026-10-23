unit Muninn.App.Settings;

{ Saves the recent-logbook list to the settings directory (ADR 0010). A
  failure to save is not worth stopping the user for: the list is a
  convenience, so it is reported on stderr where there is one. }

{$mode objfpc}{$H+}

interface

uses
  Classes;

type
  TRecentLogbookFile = class
  private
    FDirectory: string;
  public
    constructor Create(const ADirectory: string);
    procedure Load(const AList: TStrings);
    procedure Save(const APaths: TStrings);
    property Directory: string read FDirectory;
  end;

implementation

uses
  SysUtils, Muninn.Storage.Settings;

constructor TRecentLogbookFile.Create(const ADirectory: string);
begin
  inherited Create;
  FDirectory := ADirectory;
end;

procedure TRecentLogbookFile.Load(const AList: TStrings);
begin
  try
    LoadRecentLogbooks(FDirectory, AList);
  except
    on E: EInOutError do
      AList.Clear;
    on E: EStreamError do
      AList.Clear;
  end;
end;

procedure TRecentLogbookFile.Save(const APaths: TStrings);
begin
  try
    SaveRecentLogbooks(FDirectory, APaths);
  except
    on E: EInOutError do
      if IsConsole then
        WriteLn(StdErr, 'muninn-gui: cannot save the recent logbooks: ', E.Message);
    on E: EStreamError do
      if IsConsole then
        WriteLn(StdErr, 'muninn-gui: cannot save the recent logbooks: ', E.Message);
  end;
end;

end.
