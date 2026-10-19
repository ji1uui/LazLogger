{
  HamlibCancellation.pas

  Implementation of ICancellationToken using atomic flag operations.
  Tokens are returned from every async API on IRigService. Application
  code may keep a token to support per-command cancellation, or simply
  discard it (CancelAllPending in Service.Destroy handles cleanup).

  ICancellationToken のアトミックフラグ操作による実装。トークンは
  IRigService の各非同期 API から返されます。アプリケーションコードは
  個別キャンセルのためにトークンを保持しても、破棄してもかまいません
  (Service.Destroy 内の CancelAllPending が後始末を行います)。

  Layer:    L3
  Depends:  HamlibInterfaces
}
unit HamlibCancellation;

{$mode objfpc}{$H+}

interface

uses
  HamlibInterfaces;

type
  { Concrete cancellation token. The flag is read/written using
    InterlockedExchange/ExchangeAdd, making it safe under multi-thread
    access on x86, x86_64, and AArch64 (Apple Silicon).

    具象キャンセルトークン。フラグは InterlockedExchange/ExchangeAdd で
    読み書きされ、x86・x86_64・AArch64 (Apple Silicon) のすべてで
    マルチスレッドアクセスが安全です。 }
  TRigCancellationToken = class(TInterfacedObject, ICancellationToken)
  private
    FFlag: LongInt;     { 0 = not cancelled, 1 = cancelled
                          / 0 = 未キャンセル、1 = キャンセル済み }
  public
    { ICancellationToken implementation. Atomic and idempotent.
      ICancellationToken 実装。アトミックかつ冪等。 }
    procedure Cancel;
    function  IsCancelled: Boolean;
  end;

implementation

uses
  SysUtils;

procedure TRigCancellationToken.Cancel;
begin
  { Atomic write: safe from any thread.
    アトミック書き込み: 任意のスレッドから安全。 }
  System.InterlockedExchange(FFlag, 1);
end;

function TRigCancellationToken.IsCancelled: Boolean;
begin
  { Atomic read with memory barrier (ExchangeAdd of 0 acts as barrier).
    メモリバリア付きアトミック読み出し (0 加算が結果としてバリアになる)。 }
  Result := System.InterlockedExchangeAdd(FFlag, 0) <> 0;
end;

end.
