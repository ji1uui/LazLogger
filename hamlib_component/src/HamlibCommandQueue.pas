{
  HamlibCommandQueue.pas

  Thread-safe FIFO command queue. Producers (any thread) call Enqueue;
  the single Worker thread consumer calls Dequeue. Uses TThreadList
  for storage and PRTLEvent for signalling.

  スレッドセーフな FIFO コマンドキュー。プロデューサー (任意のスレッド) が
  Enqueue を呼び、単一の Worker スレッドコンシューマーが Dequeue を呼び
  ます。ストレージに TThreadList、シグナルに PRTLEvent を使用します。

  Layer:    L3
  Depends:  HamlibCommandBase
}
unit HamlibCommandQueue;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs,
  HamlibInterfaces, HamlibErrors, HamlibCommandBase;

type
  { Specialized queue for TRigCommand instances. Owns the commands
    until Dequeue is called; the dequeuer assumes ownership.

    TRigCommand インスタンス専用のキュー。Dequeue が呼ばれるまでコマンドを
    所有します。Dequeue する側が所有権を引き継ぎます。 }
  TCommandQueue = class
  private
    FList:     TThreadList;
    FNewItem:  PRTLEvent;
  public
    constructor Create;
    destructor  Destroy; override;

    { Add a command to the back of the queue. Signals waiting consumers.
      キューの末尾にコマンドを追加します。待機中のコンシューマーにシグナル。 }
    procedure Enqueue(ACmd: TRigCommand);

    { Wake a consumer blocked in Dequeue without queueing anything.
      Used for shutdown signalling.
      何も積まずに Dequeue で待機中の消費者を起こします。
      シャットダウン通知に使用します。 }
    procedure WakeUp;

    { Remove and return the front command. ATimeoutMs=0 returns nil
      immediately if the queue is empty; otherwise waits up to
      ATimeoutMs milliseconds.

      先頭のコマンドを取り出して返します。ATimeoutMs=0 はキューが空の場合
      即座に nil を返します。それ以外は ATimeoutMs ミリ秒まで待機します。 }
    function Dequeue(ATimeoutMs: Cardinal): TRigCommand;

    { Drain all queued commands and return them as a list. Caller
      assumes ownership of the returned commands. Used by the Worker
      during shutdown to deliver rcsCancelled to all pending commands.

      キュー内の全コマンドを取り出してリストとして返します。呼び出し元が
      返却コマンドの所有権を引き継ぎます。Worker のシャットダウン時に
      保留中の全コマンドへ rcsCancelled を配送するために使われます。 }
    procedure DrainAll(AOutput: TList);

    { Number of commands currently queued. Snapshot only — value may
      change immediately after returning. Useful for diagnostics.

      現在キューに入っているコマンド数。スナップショットのため、戻った
      直後に値が変わる可能性があります。診断用途に有用。 }
    function Count: Integer;
  end;

implementation

constructor TCommandQueue.Create;
begin
  inherited Create;
  FList := TThreadList.Create;
  { TThreadList defaults to dupIgnore, which makes every Add perform an
    O(n) IndexOf scan. Command pointers are unique by construction, so
    the scan is pure overhead — and O(n^2) once the queue gets deep.

    TThreadList の既定は dupIgnore で、Add のたびに O(n) の IndexOf が
    走ります。コマンドポインタは構造上一意なので、この走査は純粋な
    オーバーヘッドであり、キューが深くなると O(n^2) になります。 }
  FList.Duplicates := dupAccept;
  FNewItem := RTLEventCreate;
end;

destructor TCommandQueue.Destroy;
var
  L:    TList;
  Cmd:  TRigCommand;
  i:    Integer;
begin
  { Defensive: free any orphan commands. The Worker should normally
    have drained the queue, but if not, prevent leaks here.

    防衛的: 孤児となったコマンドを解放します。通常は Worker がキューを
    ドレインしているはずですが、そうでない場合のリーク防止。 }
  L := FList.LockList;
  try
    for i := 0 to L.Count - 1 do
    begin
      Cmd := TRigCommand(L[i]);
      Cmd.Free;
    end;
    L.Clear;
  finally
    FList.UnlockList;
  end;
  FList.Free;
  RTLEventDestroy(FNewItem);
  inherited;
end;

procedure TCommandQueue.Enqueue(ACmd: TRigCommand);
begin
  if not Assigned(ACmd) then
    raise EArgumentException.Create('Cannot enqueue a nil command');
  FList.Add(ACmd);
  RTLEventSetEvent(FNewItem);
end;

procedure TCommandQueue.WakeUp;
begin
  { Used by the Worker's RequestStop to break out of a pending Dequeue
    without putting a nil sentinel into the queue. Rev.4.0 enqueued nil,
    which collided with Enqueue's own nil check and crashed every
    Close() in assertion-enabled (Debug) builds.

    Worker の RequestStop が、キューに nil 番兵を入れずに待機中の
    Dequeue を抜けさせるために使います。Rev.4.0 は nil を積んでおり、
    Enqueue 自身の nil チェックと衝突して、アサーション有効 (Debug)
    ビルドでは Close() が必ずクラッシュしていました。 }
  RTLEventSetEvent(FNewItem);
end;

function TCommandQueue.Dequeue(ATimeoutMs: Cardinal): TRigCommand;
var
  L: TList;
begin
  Result := nil;

  { Reset BEFORE the first peek, not after it. Resetting after the peek
    discards a signal raised by a producer in the gap between unlocking
    and resetting, costing a full ATimeoutMs of latency on a command
    that was already available.

    最初の覗き見の「前」にリセットします。覗き見の後にリセットすると、
    アンロックからリセットまでの隙間に生産側が立てたシグナルを捨ててしまい、
    すでに利用可能なコマンドに対して ATimeoutMs 丸ごとの遅延が生じます。 }
  RTLEventResetEvent(FNewItem);

  L := FList.LockList;
  try
    if L.Count > 0 then
    begin
      Result := TRigCommand(L[0]);
      L.Delete(0);
      Exit;
    end;
  finally
    FList.UnlockList;
  end;

  { Empty: wait for a signal. ATimeoutMs may be 0 (return immediately).
    空: シグナルを待ちます。ATimeoutMs=0 なら即座に戻ります。 }
  if ATimeoutMs = 0 then Exit;

  RTLEventWaitFor(FNewItem, ATimeoutMs);

  { Try once more after the wait. 待機後にもう一度試します。 }
  L := FList.LockList;
  try
    if L.Count > 0 then
    begin
      Result := TRigCommand(L[0]);
      L.Delete(0);
    end;
  finally
    FList.UnlockList;
  end;
end;

procedure TCommandQueue.DrainAll(AOutput: TList);
var
  L: TList;
  i: Integer;
begin
  Assert(Assigned(AOutput), 'Output list required');
  L := FList.LockList;
  try
    for i := 0 to L.Count - 1 do
      AOutput.Add(L[i]);
    L.Clear;
  finally
    FList.UnlockList;
  end;
end;

function TCommandQueue.Count: Integer;
var
  L: TList;
begin
  L := FList.LockList;
  try
    Result := L.Count;
  finally
    FList.UnlockList;
  end;
end;

end.
