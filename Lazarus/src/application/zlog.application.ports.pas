unit ZLog.Application.Ports;

{$mode objfpc}{$H+}

interface

uses
  ZLog.Domain.Qso;

type
  IClock = interface
    ['{3F74B0A8-6EB4-48C3-9905-C02781F04C6E}']
    function UtcNowMs: Int64;
  end;

  IIdGenerator = interface
    ['{F3604B7B-1064-4B95-829C-F82A49BEA859}']
    function NextId: string;
  end;

  IQsoReadRepository = interface
    ['{0178B14D-76E5-4A49-B227-7C59FF4F36CB}']
    function Count: Integer;
    { Returns an owned snapshot. The caller must free a non-nil result. }
    function FindById(const AId: string): TQso;
    { Returns newest first. Records contain no repository-owned references. }
    function GetRecent(const AMaximumCount: Integer): TQsoSnapshotArray;
  end;

  IQsoRepository = interface(IQsoReadRepository)
    ['{C6E595E5-F629-42C2-BB51-82D9D6EE66E8}']
    procedure Add(const AQso: TQso);
  end;

implementation

end.
