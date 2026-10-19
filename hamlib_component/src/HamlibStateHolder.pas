{
  HamlibStateHolder.pas

  Reference-counted holder for the TRigState snapshot (the Pull model).

  TRigState スナップショット (Pull モデル) の参照カウント管理ホルダー。

  Layer:    L4 support
  Depends:  HamlibInterfaces, SyncObjs

  --------------------------------------------------------------------
  Why this exists (Rev.4.1)
  本ユニットの存在理由 (Rev.4.1)
  --------------------------------------------------------------------
  Rev.4.0 passed a raw ^TRigState plus a raw TCriticalSection reference
  into every frequency dispatcher. A dispatcher can outlive the Service:
  it is invoked from the UI thread's synchronize queue, which may drain
  after TRigService.Destroy has already freed the lock. Writing through
  those raw pointers at that moment is undefined behaviour.

  Rev.4.0 は生の ^TRigState と生の TCriticalSection 参照を各周波数
  ディスパッチャに渡していました。ディスパッチャは Service より長生き
  し得ます。UI スレッドの同期キューから呼ばれるため、TRigService.Destroy
  がロックを解放した後に消化される可能性があるからです。その時点で生
  ポインタ経由に書き込むのは未定義動作です。

  Here the state and its lock live in one reference-counted object. The
  Service holds a reference, and so does every in-flight dispatcher. The
  holder is destroyed only when the last of them is gone, so a late
  callback writes into a live object instead of freed memory. The holder
  never references the Service, so no cycle is created.

  本ユニットでは状態とそのロックを 1 つの参照カウント管理オブジェクトに
  収めます。Service も実行中の各ディスパッチャも参照を保持します。
  ホルダーは最後の参照が消えて初めて破棄されるため、遅延したコールバックは
  解放済みメモリではなく生存中のオブジェクトに書き込みます。ホルダーは
  Service を参照しないため循環は生じません。
}
unit HamlibStateHolder;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, SyncObjs,
  HamlibInterfaces;

type
  { Thread-safe owner of the rig state snapshot.
    リグ状態スナップショットのスレッドセーフな所有者。 }
  IRigStateHolder = interface
    ['{7C4E1A93-2B5D-4E86-9F10-3A6D8C2B5E47}']

    { Return a copy of the current snapshot. Safe from any thread.
      現在のスナップショットのコピーを返します。任意のスレッドから安全。 }
    function  Snapshot: TRigState;

    { Record a frequency for one VFO and stamp the update time.
      1 つの VFO の周波数を記録し、更新時刻を刻みます。 }
    procedure SetFreq(AVfo: TRigVfo; AFreq: Double);

    { Record mode and passband for the current VFO. ARawMode is kept
      alongside the named mode so a snapshot of an unrecognised mode
      still carries the original value.
      カレント VFO のモードと帯域幅を記録します。ARawMode を名前付き
      モードと併せて保持し、未知のモードのスナップショットでも元の値が
      残るようにします。 }
    procedure SetMode(AMode: TRigMode; APassbandHz: Integer;
                      ARawMode: Int64);

    { Record connection state. 接続状態を記録します。 }
    procedure SetConnected(AConnected: Boolean);

    { Record PTT state. PTT 状態を記録します。 }
    procedure SetPtt(AActive: Boolean);

    { Record the S-meter reading, in dB relative to S9.
      S9 基準 dB の S メータ読み値を記録します。 }
    procedure SetStrength(ADb: Integer);

    { Record split state and, when split is on, the transmit frequency.
      スプリット状態と、スプリット時の送信周波数を記録します。 }
    procedure SetSplit(AOn: Boolean; ATxVfo: TRigVfo; ATxFreq: Double);

    { Record which VFO the rig currently has selected.
      リグが現在選択している VFO を記録します。 }
    procedure SetSelectedVfo(AVfo: TRigVfo);

    { Zero the snapshot (used on disconnect).
      スナップショットをゼロクリアします (切断時に使用)。 }
    procedure Reset;
  end;

  TRigStateHolder = class(TInterfacedObject, IRigStateHolder)
  private
    FLock:  TCriticalSection;
    FState: TRigState;
    procedure Stamp;   { caller must hold FLock / 呼び出し側が FLock 保持 }
  public
    constructor Create;
    destructor  Destroy; override;

    function  Snapshot: TRigState;
    procedure SetFreq(AVfo: TRigVfo; AFreq: Double);
    procedure SetMode(AMode: TRigMode; APassbandHz: Integer;
                      ARawMode: Int64);
    procedure SetConnected(AConnected: Boolean);
    procedure SetPtt(AActive: Boolean);
    procedure SetStrength(ADb: Integer);
    procedure SetSplit(AOn: Boolean; ATxVfo: TRigVfo; ATxFreq: Double);
    procedure SetSelectedVfo(AVfo: TRigVfo);
    procedure Reset;
  end;

implementation

constructor TRigStateHolder.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FillChar(FState, SizeOf(FState), 0);
end;

destructor TRigStateHolder.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TRigStateHolder.Stamp;
begin
  FState.Timestamp := GetTickCount64;
end;

function TRigStateHolder.Snapshot: TRigState;
begin
  FLock.Acquire;
  try
    { Whole-record copy under the lock; the caller then owns an
      independent value and needs no further synchronisation.
      ロック内で全レコードをコピー。呼び出し元は独立した値を所有し、
      以降の同期は不要です。 }
    Result := FState;
  finally
    FLock.Release;
  end;
end;

procedure TRigStateHolder.SetFreq(AVfo: TRigVfo; AFreq: Double);
begin
  FLock.Acquire;
  try
    { rvfoCurr is NOT VFO A. A poll asks for "the frequency" and gets
      whichever VFO the rig has selected, which the operator may have
      changed from the rig's front panel. Filing that under VfoAFreq —
      as this unit did up to Rev.5.1 — makes the snapshot assert
      something it was never told.

      rvfoCurr は VFO A ではありません。ポーリングは「周波数」を尋ね、
      リグが選択している VFO の値を受け取ります。その選択はオペレータ
      がリグ本体で変更しえます。それを VfoAFreq へ格納すること
      — Rev.5.1 までの本ユニットの動作 — は、スナップショットに、
      告げられていないことを主張させることです。 }
    case AVfo of
      rvfoCurr:         FState.CurrentFreq := AFreq;
      rvfoA, rvfoMain:  FState.VfoAFreq    := AFreq;
      rvfoB, rvfoSub:   FState.VfoBFreq    := AFreq;
    end;
    Stamp;
  finally
    FLock.Release;
  end;
end;

procedure TRigStateHolder.SetMode(AMode: TRigMode; APassbandHz: Integer;
                                  ARawMode: Int64);
begin
  Assert(APassbandHz >= 0, 'APassbandHz must be >= 0');
  FLock.Acquire;
  try
    FState.Mode     := AMode;
    FState.Passband := APassbandHz;
    FState.RawMode  := ARawMode;
    Stamp;
  finally
    FLock.Release;
  end;
end;

procedure TRigStateHolder.SetStrength(ADb: Integer);
begin
  FLock.Acquire;
  try
    FState.StrengthDb  := ADb;
    FState.HasStrength := True;
    Stamp;
  finally
    FLock.Release;
  end;
end;

procedure TRigStateHolder.SetSplit(AOn: Boolean; ATxVfo: TRigVfo;
                                   ATxFreq: Double);
begin
  FLock.Acquire;
  try
    FState.SplitOn := AOn;
    FState.TxVfo   := ATxVfo;
    { Keep the last known transmit frequency when the rig did not
      report one, rather than blanking a display that was right a
      moment ago.
      リグが送信周波数を報告しなかった場合は、直前まで正しかった表示を
      消すのではなく、最後に判明した値を保持します。 }
    if ATxFreq > 0 then
      FState.TxFreq := ATxFreq;
    if not AOn then
      FState.TxFreq := 0;
    Stamp;
  finally
    FLock.Release;
  end;
end;

procedure TRigStateHolder.SetSelectedVfo(AVfo: TRigVfo);
begin
  FLock.Acquire;
  try
    FState.SelectedVfo := AVfo;
    Stamp;
  finally
    FLock.Release;
  end;
end;

procedure TRigStateHolder.SetConnected(AConnected: Boolean);
begin
  FLock.Acquire;
  try
    FState.Connected := AConnected;
    Stamp;
  finally
    FLock.Release;
  end;
end;

procedure TRigStateHolder.SetPtt(AActive: Boolean);
begin
  FLock.Acquire;
  try
    FState.PttActive := AActive;
    Stamp;
  finally
    FLock.Release;
  end;
end;

procedure TRigStateHolder.Reset;
begin
  FLock.Acquire;
  try
    FillChar(FState, SizeOf(FState), 0);
  finally
    FLock.Release;
  end;
end;

end.
