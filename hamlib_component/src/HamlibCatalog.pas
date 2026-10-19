{
  HamlibCatalog.pas

  TRigModelCatalog — the list of rigs the loaded Hamlib can drive,
  obtained from that library at run time.

  TRigModelCatalog - ロードされた Hamlib が扱えるリグの一覧。実行時に
  そのライブラリ自身から取得します。

  Why this exists / 存在理由
  ------------------------------------------------------------------
  Up to Rev.4.2 an application had to write RIG_MODEL_IC7300 = 3073 in
  its own source, which means two separate repositories had to agree on
  a number with nothing checking that they did. Those constants were in
  fact wrong in Rev.4.1 — IC-7300 was 3085, which is the IC-705 — and a
  wrong number is not a compile error; it either refuses to open or
  silently drives a different radio's protocol.

  Rev.4.2 までは、アプリケーション自身のソースに
  RIG_MODEL_IC7300 = 3073 と書く必要がありました。これは 2 つの別個の
  リポジトリが 1 つの数値で一致していなければならず、しかもそれを検査
  する仕組みが無いことを意味します。実際 Rev.4.1 ではこの定数が誤って
  おり (IC-7300 が 3085、すなわち IC-705 の番号になっていた)、番号の
  誤りはコンパイルエラーになりません。開くのを拒否されるか、別の無線機の
  プロトコルで静かに通信してしまうかのどちらかです。

  Asking the library removes the agreement entirely: the numbers come
  from the same binary that will use them, so a Hamlib upgrade adds new
  rigs to the application without recompiling it.

  ライブラリに問い合わせれば、この取り決め自体が不要になります。番号は
  それを使う当のバイナリから来るため、Hamlib を更新すればアプリを
  再コンパイルせずに新機種が増えます。

  Layer:    L2
  Depends:  HamlibInterfaces, HamlibErrors
}
unit HamlibCatalog;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  HamlibInterfaces, HamlibErrors;

type
  { ====================================================================
    TRigModelCatalog — snapshot of the loaded library's rig list.
    TRigModelCatalog - ロード済みライブラリのリグ一覧のスナップショット。
    ====================================================================
    Built once in the constructor and immutable afterwards, so it can be
    read from any thread without a lock. Reference-counted: hold it in
    an IRigModelCatalog field and it is released automatically.

    コンストラクタで 1 度構築した後は不変であるため、ロックなしで任意の
    スレッドから読めます。参照カウント管理です。IRigModelCatalog 型の
    フィールドで保持すれば自動的に解放されます。

    Enumeration forces Hamlib to load every backend, which takes tens of
    milliseconds. That is why this is a snapshot taken once, rather than
    a query run per lookup.

    列挙は Hamlib に全バックエンドのロードを強制するため数十ミリ秒
    かかります。問い合わせごとに実行するのではなく 1 度のスナップショット
    にしているのはそのためです。 }
  TRigModelCatalog = class(TInterfacedObject, IRigModelCatalog)
  private
    FItems:     TRigModelInfoArray;
    FAvailable: Boolean;

    { Insertion sort by manufacturer then model name. The list is a few
      hundred entries and is sorted exactly once, so the simplest
      correct algorithm is the right one; a QuickSort here would be
      optimising the wrong thing.

      メーカー名→機種名の挿入ソート。一覧は数百件で、ソートは厳密に 1 回
      だけです。したがって最も単純で正しいアルゴリズムが適切です。ここで
      QuickSort を使うのは最適化対象を誤っています。 }
    procedure SortItems;
  public
    { Build the catalogue from a loader. ALoader may be any
      IHamlibLoader; if it does not also implement IHamlibCatalog, or
      the library is too old to enumerate, the catalogue is simply
      empty and IsAvailable returns False. Construction never fails for
      that reason — a missing catalogue is a degraded UI, not an error.

      ローダからカタログを構築します。ALoader は任意の IHamlibLoader で
      構いません。IHamlibCatalog を併せて実装していない場合、または
      ライブラリが古くて列挙できない場合、カタログは空になり IsAvailable
      は False を返します。その理由で構築が失敗することはありません。
      カタログの欠落は UI の機能低下であってエラーではないためです。 }
    { ALoader is passed by value, NOT as const, and that is deliberate.

      A const interface parameter suppresses the compiler's temporary
      reference. If the caller writes

          Catalog := TRigModelCatalog.Create(TMyLoader.Create);

      the object arrives with a reference count of zero and nothing in
      this constructor is obliged to touch it, so whether it is ever
      freed would depend on which optional role interfaces it happens
      to implement — Supports() taking a reference and releasing it is
      what would destroy it. A loader without the catalogue role would
      simply leak. Passing by value makes the lifetime deterministic:
      the reference is taken on entry and released on exit, so an
      object the caller did not keep is destroyed here, every time.

      ALoader は const ではなく値渡しです。これは意図的です。

      const のインターフェース引数はコンパイラの一時参照を抑制します。
      呼び出し元が

          Catalog := TRigModelCatalog.Create(TMyLoader.Create);

      と書いた場合、オブジェクトは参照カウント 0 で到着し、本
      コンストラクタはそれに触れる義務を負いません。結果として解放
      されるか否かは、そのオブジェクトがどの任意 role インターフェースを
      実装しているか次第になります。Supports() が参照を取って解放する
      ことが破棄の契機になってしまうからです。カタログ role を持たない
      ローダは単に漏れます。値渡しにすれば生存期間は決定的になります。
      入口で参照を取り出口で解放するため、呼び出し元が保持しなかった
      オブジェクトは必ずここで破棄されます。 }
    constructor Create(ALoader: IHamlibLoader);

    { ----------------- IRigModelCatalog implementation ----------------- }
    function GetIsAvailable: Boolean;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TRigModelInfo;
    function FindByNumber(AModelNumber: Integer;
                          out AInfo: TRigModelInfo): Boolean;
    function FindByName(const AManufacturer, AModelName: string;
                        out AInfo: TRigModelInfo): Boolean;
  end;

{ ------------------------------------------------------------------
  Display label for one entry, e.g. "Icom IC-7300 (Stable)". Keeps the
  formatting decision in one place so a combo box and a log line agree.

  1 項目の表示ラベル。例: "Icom IC-7300 (Stable)"。コンボボックスと
  ログ行の表記が一致するよう、整形の判断を 1 箇所に集めます。
  ------------------------------------------------------------------ }
function RigModelInfoToString(const AInfo: TRigModelInfo): string;

implementation

function RigModelInfoToString(const AInfo: TRigModelInfo): string;
begin
  Result := Trim(AInfo.Manufacturer + ' ' + AInfo.ModelName);
  if Result = '' then
    Result := Format('model %d', [AInfo.ModelNumber]);
  if AInfo.BackendStatus <> '' then
    Result := Result + ' (' + AInfo.BackendStatus + ')';
end;

constructor TRigModelCatalog.Create(ALoader: IHamlibLoader);
var
  Cat: IHamlibCatalog;
begin
  inherited Create;
  SetLength(FItems, 0);
  FAvailable := False;

  Assert(Assigned(ALoader), 'ALoader must not be nil');
  if not Assigned(ALoader) then Exit;

  { Supports() rather than a hard dependency: a test fake that
    implements only IHamlibLoader stays valid, and so does a trimmed
    Hamlib build.
    ハードな依存ではなく Supports() を使います。IHamlibLoader だけを
    実装するテストフェイクも、機能を削った Hamlib ビルドも有効なまま
    です。 }
  if not Supports(ALoader, IHamlibCatalog, Cat) then Exit;

  FAvailable := Cat.ListModels(FItems);
  if not FAvailable then
    SetLength(FItems, 0)
  else
    SortItems;
end;

procedure TRigModelCatalog.SortItems;
var
  i, j:    Integer;
  Tmp:     TRigModelInfo;
  KeyA:    string;
  KeyB:    string;
begin
  for i := 1 to High(FItems) do
  begin
    Tmp  := FItems[i];
    KeyA := LowerCase(Tmp.Manufacturer + #1 + Tmp.ModelName);
    j    := i - 1;
    while j >= 0 do
    begin
      KeyB := LowerCase(FItems[j].Manufacturer + #1 + FItems[j].ModelName);
      if KeyB <= KeyA then Break;
      FItems[j + 1] := FItems[j];
      Dec(j);
    end;
    FItems[j + 1] := Tmp;
  end;
end;

function TRigModelCatalog.GetIsAvailable: Boolean;
begin
  Result := FAvailable;
end;

function TRigModelCatalog.GetCount: Integer;
begin
  Result := Length(FItems);
end;

function TRigModelCatalog.GetItem(AIndex: Integer): TRigModelInfo;
begin
  { A real exception, not an Assert: an index out of range usually comes
    from a UI control's selection and must fail the same way in a
    release build.
    Assert ではなく実例外です。範囲外の添字は通常 UI コントロールの選択
    から来るため、リリースビルドでも同じように失敗しなければなりません。 }
  if (AIndex < 0) or (AIndex > High(FItems)) then
    raise EArgumentException.CreateFmt(
      'Catalog index %d is out of range (0..%d)', [AIndex, High(FItems)]);
  Result := FItems[AIndex];
end;

function TRigModelCatalog.FindByNumber(AModelNumber: Integer;
                                        out AInfo: TRigModelInfo): Boolean;
var
  i: Integer;
begin
  Result := False;
  { Field-by-field, not FillChar: the record holds managed strings and
    zeroing their pointers behind the compiler's back is how refcount
    corruption starts.
    FillChar ではなくフィールド単位で初期化します。本レコードは管理
    文字列を含み、その参照をコンパイラの知らないところでゼロ化すると
    参照カウントの破壊が始まります。 }
  AInfo.ModelNumber   := 0;
  AInfo.Manufacturer  := '';
  AInfo.ModelName     := '';
  AInfo.BackendStatus := '';
  for i := 0 to High(FItems) do
    if FItems[i].ModelNumber = AModelNumber then
    begin
      AInfo  := FItems[i];
      Result := True;
      Exit;
    end;
end;

function TRigModelCatalog.FindByName(const AManufacturer, AModelName: string;
                                      out AInfo: TRigModelInfo): Boolean;
var
  i: Integer;
begin
  Result := False;
  { Field-by-field, not FillChar: the record holds managed strings and
    zeroing their pointers behind the compiler's back is how refcount
    corruption starts.
    FillChar ではなくフィールド単位で初期化します。本レコードは管理
    文字列を含み、その参照をコンパイラの知らないところでゼロ化すると
    参照カウントの破壊が始まります。 }
  AInfo.ModelNumber   := 0;
  AInfo.Manufacturer  := '';
  AInfo.ModelName     := '';
  AInfo.BackendStatus := '';
  for i := 0 to High(FItems) do
    if SameText(FItems[i].Manufacturer, AManufacturer)
       and SameText(FItems[i].ModelName, AModelName) then
    begin
      AInfo  := FItems[i];
      Result := True;
      Exit;
    end;
end;

end.
