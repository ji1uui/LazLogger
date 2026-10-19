{
  HamlibErrors.pas

  Exception types and error code conversion for the Hamlib wrapper.
  Application code typically interacts with errors through the
  TRigResult.ErrorCode/ErrorMsg fields, not via exceptions directly.

  Hamlib ラッパーの例外型とエラーコード変換。
  アプリケーションコードは通常 TRigResult.ErrorCode/ErrorMsg 経由で
  エラーを扱い、例外を直接キャッチすることは稀です。

  Layer:    L2 (type and error conversion / 型・エラー変換層)
  Depends:  HamlibInterfaces
}
unit HamlibErrors;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  HamlibInterfaces;

type
  { Raised when the Hamlib library cannot be loaded or required symbols
    cannot be resolved. Typically caught only at startup.

    Hamlib ライブラリがロードできない、または必須シンボルが解決できない
    ときに発生する例外。通常は起動時にのみキャッチします。 }
  EHamlibLoadError = class(Exception);

  { Raised on Hamlib API errors during command execution. Carries the
    original Hamlib error code in the Code property. The Worker thread
    catches this and converts to TRigResult.

    コマンド実行中の Hamlib API エラーで発生する例外。元の Hamlib
    エラーコードを Code プロパティで保持します。Worker スレッドがこれを
    捕まえて TRigResult に変換します。 }
  ERigError = class(Exception)
  private
    FCode: Integer;
    FKind: TRigErrorKind;
  public
    { Construct from a Hamlib error code, looking up the human-readable
      message via the loader's CallRigError method.
      Hamlib エラーコードから生成し、ローダの CallRigError で人間可読の
      メッセージを取得します。 }
    constructor CreateFromHamlib(ACode: Integer; ALoader: IHamlibLoader);

    { What went wrong, classified. Branch on this.
      何が起きたかの分類。分岐はこちらで行います。 }
    property Kind: TRigErrorKind read FKind;

    { The original Hamlib error code (negative integer). Diagnostic only.
      元の Hamlib エラーコード (負の整数)。診断用途のみ。 }
    property Code: Integer read FCode;
  end;

  { Raised when an argument fails validation, e.g. invalid policy.
    引数のバリデーションに失敗したときに発生する例外 (例: 無効なポリシー)。 }
  EArgumentException = class(Exception);

  { Raised when an operation is attempted on a closed service.
    Every public async method on IRigService raises this (NOT an Assert)
    when called before Open or after Close, so the guard also holds in
    release builds.

    閉じられたサービスに対して操作を試みたときに発生する例外。
    IRigService の全公開非同期メソッドは、Open 前および Close 後に
    呼ばれたとき Assert ではなくこの例外を発生させます。これにより
    リリースビルドでもガードが有効です。 }
  ERigServiceClosed = class(Exception);

  { Raised when Open is called on a service that is already open.
    すでに開いているサービスに対して Open を呼んだときに発生する例外。 }
  ERigServiceOpen = class(Exception);

  { Raised when the loaded Hamlib is outside the range this component has
    been verified against. Symbol resolution succeeding does NOT imply ABI
    compatibility: a future Hamlib may keep every function name while
    widening a type, which would corrupt the argument list silently.
    Refusing to start is the only way to turn that into a visible failure.

    Opt in with TRigServiceFactory.AllowUntestedVersion when you have
    verified a newer Hamlib yourself.

    ロードされた Hamlib が本コンポーネントの検証済み範囲外のときに発生します。
    シンボルが解決できることは ABI 互換を意味しません。将来の Hamlib が
    関数名を保ったまま型幅を変えれば、引数列が静かに壊れます。起動を拒否する
    ことが、それを可視化する唯一の手段です。

    新しい Hamlib を自分で検証した場合は
    TRigServiceFactory.AllowUntestedVersion で明示的に許可してください。 }
  EHamlibUnsupportedVersion = class(Exception);

  { Raised when Open is given a model number the loaded Hamlib does not
    know. Catches both a stale constant in this component and a renumbering
    on the Hamlib side.

    ロードされた Hamlib が知らないモデル番号で Open されたときに発生します。
    本コンポーネント側の定数の古さと、Hamlib 側の採番変更の双方を捕まえます。 }
  ERigModelUnknown = class(Exception);

{ ------------------------------------------------------------------
  Helper procedure used inside L3 commands.
  Raises ERigError if ACode < 0; does nothing otherwise.

  L3 コマンド内部で使うヘルパー手続き。
  ACode < 0 の場合 ERigError を発生し、それ以外では何もしません。
  ------------------------------------------------------------------ }
procedure CheckRig(ACode: Integer; ALoader: IHamlibLoader);

{ ------------------------------------------------------------------
  Classify a raw Hamlib return code.

  Hamlib's RIG_E* enum values are POSITIVE ordinals and its functions
  return the NEGATED value, so -5 is RIG_ETIMEOUT. This function accepts
  the value as returned (negative or zero); a positive value is treated
  as its own negation, because a caller passing RIG_ETIMEOUT directly is
  far more likely to have made the sign mistake than to have a genuine
  positive code — Hamlib defines none.

  A code with no name here maps to rekUnrecognised rather than to
  rekInternal: inventing a classification for an unknown number would
  make a newer Hamlib look like a Hamlib bug.

  生の Hamlib 戻り値を分類します。

  Hamlib の RIG_E* は「正」の序数で、関数はそれを符号反転して返すため
  -5 は RIG_ETIMEOUT です。本関数は戻り値のまま (負または 0) を受け取り
  ます。正の値はその符号反転として扱います。RIG_ETIMEOUT を直接渡した
  呼び出し側は、本物の正コードを持っているより符号を間違えている可能性
  が圧倒的に高いためです (Hamlib は正コードを定義していません)。

  ここに名前の無いコードは rekInternal ではなく rekUnrecognised に
  写します。未知の数値に分類を捏造すると、新しい Hamlib が Hamlib の
  バグのように見えてしまいます。
  ------------------------------------------------------------------ }
function RigErrorKindFromCode(ACode: Integer): TRigErrorKind;

{ ------------------------------------------------------------------
  Short English label for a kind, for logs and message boxes. Use the
  ErrorMsg that accompanies a result when you want Hamlib's own wording.

  種別の短い英語ラベル。ログやメッセージボックス向けです。Hamlib 自身の
  文面が欲しい場合は、結果に同行する ErrorMsg を使ってください。
  ------------------------------------------------------------------ }
function RigErrorKindToString(AKind: TRigErrorKind): string;

implementation

function RigErrorKindFromCode(ACode: Integer): TRigErrorKind;
var
  Ordinal: Integer;
begin
  if ACode = 0 then
  begin
    Result := rekNone;
    Exit;
  end;

  if ACode < 0 then
    Ordinal := -ACode
  else
    Ordinal := ACode;

  case Ordinal of
     1: Result := rekInvalidArgument;      { RIG_EINVAL }
     2: Result := rekConfiguration;        { RIG_ECONF }
     3: Result := rekOutOfMemory;          { RIG_ENOMEM }
     4: Result := rekNotImplemented;       { RIG_ENIMPL }
     5: Result := rekTimeout;              { RIG_ETIMEOUT }
     6: Result := rekIo;                   { RIG_EIO }
     7: Result := rekInternal;             { RIG_EINTERNAL }
     8: Result := rekProtocol;             { RIG_EPROTO }
     9: Result := rekRigRejected;          { RIG_ERJCTED }
    10: Result := rekTruncated;            { RIG_ETRUNC }
    11: Result := rekNotAvailable;         { RIG_ENAVAIL }
    12: Result := rekVfoNotTargetable;     { RIG_ENTARGET }
    13: Result := rekBusError;             { RIG_BUSERROR }
    14: Result := rekBusBusy;              { RIG_BUSBUSY }
    15: Result := rekInvalidHandle;        { RIG_EARG }
    16: Result := rekInvalidVfo;           { RIG_EVFO }
    17: Result := rekOutOfDomain;          { RIG_EDOM }
    18: Result := rekDeprecated;           { RIG_EDEPRECATED }
    19: Result := rekSecurity;             { RIG_ESECURITY }
    20: Result := rekPowerOff;             { RIG_EPOWER }
    21: Result := rekLimitExceeded;        { RIG_ELIMIT }
    22: Result := rekAccessDenied;         { RIG_EACCESS }
  else
    Result := rekUnrecognised;
  end;
end;

function RigErrorKindToString(AKind: TRigErrorKind): string;
begin
  case AKind of
    rekNone:             Result := 'no error';
    rekInvalidArgument:  Result := 'invalid argument';
    rekConfiguration:    Result := 'invalid configuration';
    rekOutOfMemory:      Result := 'out of memory';
    rekNotImplemented:   Result := 'not implemented';
    rekTimeout:          Result := 'communication timed out';
    rekIo:               Result := 'I/O error';
    rekInternal:         Result := 'internal Hamlib error';
    rekProtocol:         Result := 'protocol error';
    rekRigRejected:      Result := 'rejected by the rig';
    rekTruncated:        Result := 'argument truncated';
    rekNotAvailable:     Result := 'function not available on this rig';
    rekVfoNotTargetable: Result := 'VFO cannot be targeted directly';
    rekBusError:         Result := 'bus error';
    rekBusBusy:          Result := 'bus busy';
    rekInvalidHandle:    Result := 'invalid handle';
    rekInvalidVfo:       Result := 'invalid VFO';
    rekOutOfDomain:      Result := 'argument out of range';
    rekDeprecated:       Result := 'deprecated function';
    rekSecurity:         Result := 'security error';
    rekPowerOff:         Result := 'rig is not powered on';
    rekLimitExceeded:    Result := 'limit exceeded';
    rekAccessDenied:     Result := 'access denied';

    { The component's own conditions. Without these five the fallback
      labelled every one of them "unrecognised error", which is how a
      tripped circuit breaker came out of RigErrorKindToString looking
      like an unknown Hamlib code. A test that only asserted the label
      was non-empty did not catch it.

      本コンポーネント自身の状態。この 5 つが無いと、フォールバックが
      すべてを "unrecognised error" と表示し、遮断された Circuit Breaker が
      未知の Hamlib コードのように見えていました。ラベルが空でないこと
      しか検査していないテストでは捕まりません。 }
    rekUnrecognised:     Result := 'unrecognised Hamlib error code';
    rekConnectFailed:    Result := 'could not open the rig';
    rekCircuitOpen:      Result := 'paused after repeated failures';
    rekNotConnected:     Result := 'not connected';
    rekComponentFault:   Result := 'internal component error';
  else
    { Only reachable if a kind is added to the enum and not to this
      case. Naming the ordinal makes that omission findable.
      列挙型に種別を追加し、この case に追加しなかった場合にのみ到達
      します。序数を出すことで、その漏れを追跡できます。 }
    Result := Format('unlabelled error kind %d', [Ord(AKind)]);
  end;
end;

constructor ERigError.CreateFromHamlib(ACode: Integer; ALoader: IHamlibLoader);
var
  Msg: string;
begin
  FCode := ACode;
  FKind := RigErrorKindFromCode(ACode);
  Msg   := '';
  if Assigned(ALoader) and ALoader.IsLoaded then
    Msg := ALoader.CallRigError(ACode);
  if Msg = '' then
    Msg := Format('Hamlib error %d', [ACode]);
  inherited Create(Msg);
end;

procedure CheckRig(ACode: Integer; ALoader: IHamlibLoader);
begin
  if ACode < 0 then
    raise ERigError.CreateFromHamlib(ACode, ALoader);
end;

end.
