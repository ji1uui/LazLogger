{
  HamlibComponent.pas

  Package master unit. It pulls every public unit into the build and
  reports the package version.

  What it does NOT do is re-export identifiers. Object Pascal has no
  transitive visibility: a unit that uses HamlibComponent does not see
  IRigService or rmUSB. Earlier revisions of this file claimed
  otherwise, which was wrong. The uses clause an application actually
  needs is:

      uses
        HamlibInterfaces,    // types, IRigService, TRigMode, TRigErrorKind
        HamlibFactory,       // TRigServiceFactory
        HamlibErrors,        // exception classes, RigErrorKindToString
        HamlibTimeoutPolicy, // RigPolicy_FastUsb and friends
        HamlibModeCodec,     // mode display strings (optional)
        HamlibLevelCodec,    // level and function labels (optional)
        HamlibCatalog;       // RigModelInfoToString (optional)

  Only the first two are needed for a minimal application.

  パッケージマスターユニット。公開ユニットすべてをビルドに取り込み、
  パッケージバージョンを報告します。

  識別子の再エクスポートは行いません。Object Pascal に推移的な可視性は
  なく、HamlibComponent を uses したユニットから IRigService や rmUSB は
  見えません。本ファイルの以前の版はそう書いていましたが、誤りでした。
  アプリケーションに実際に必要な uses 節は上記のとおりです。最小構成では
  最初の 2 つだけで足ります。
}
unit HamlibComponent;

{$mode objfpc}{$H+}

interface

uses
  { Every public unit of the package. Listing them here means a single
    unit in the .lpk drags in the whole component, which is what makes
    the package registerable as one item.

    パッケージの全公開ユニット。ここに列挙することで、.lpk の 1 ユニット
    がコンポーネント全体を引き込みます。これがパッケージを 1 項目として
    登録可能にしています。 }
  HamlibInterfaces,
  HamlibErrors,
  HamlibTypes,
  HamlibVfoCodec,
  HamlibModeCodec,
  HamlibLevelCodec,
  HamlibTimeoutPolicy,
  HamlibCatalog,
  HamlibRigCommands,
  HamlibFactory;

{ Convenience function: returns the package version string.
  便利関数: パッケージのバージョン文字列を返します。 }
function HamlibComponentVersion: string;

implementation

const
  { Rev.6.1 — six defects found by verification methods the existing
    suite could not reach: a differential test against Hamlib's own
    rigctld, Valgrind, a randomized property test, an exhaustiveness
    sweep, a state matrix and a soak. No public type changed; one
    call became stricter (SetSplitAsync refuses rvfoCurr as the
    transmit VFO) and one interface was added
    (IRigDeliveryKeepAlive). See VERIFICATION_REPORT.md.

    Rev.6.1 — 既存のテスト群が到達できない検証手法によって 6 件の欠陥を
    発見・修正しました。Hamlib 自身の rigctld との差分テスト、Valgrind、
    ランダム化プロパティテスト、列挙網羅、状態マトリクス、ソーク。
    公開型の変更はありません。1 つの呼び出しが厳格になり
    (SetSplitAsync は送信 VFO としての rvfoCurr を拒否)、1 つの
    インターフェースが増えました (IRigDeliveryKeepAlive)。
    VERIFICATION_REPORT.md を参照してください。 }

  { Rev.5.0 — the public types changed incompatibly (TRigMode,
    TRigErrorKind, TRigModelInfo), so the major version moved rather
    than the minor. See MIGRATION in the README.

    Rev.6.1 — three defects found by a verification campaign that went
    outside the dummy backend: a deadlock when a thread was torn down
    before it was ever resumed; Hamlib's backend registration table
    leaked once per IRigService created; and the four Rev.6.0 Get
    commands failing to report or free their callback when cancelled.
    No public type changed; see VERIFICATION_REPORT.md.

    Rev.6.1 — ダミーバックエンドの外へ出た検証作業で見つかった欠陥
    3 件。再開される前に破棄されたスレッドでのデッドロック、
    IRigService の生成ごとに Hamlib のバックエンド登録表が漏れる問題、
    Rev.6.0 の Get コマンド 4 種がキャンセル時にコールバックを報告も
    解放もしない問題。公開型の変更はありません
    (VERIFICATION_REPORT.md 参照)。

    Rev.6.0 — levels (the S-meter), on/off functions, split operation,
    VFO selection and VFO operations, after surveying what applications
    actually ask Hamlib for. New public types, so the major version
    moves again. Nothing from Rev.5.1 changed meaning.

    Rev.6.0 — レベル (S メータ)、オン・オフ機能、スプリット運用、
    VFO 選択、VFO 操作。アプリケーションが実際に Hamlib へ何を要求して
    いるかを調査した結果です。公開型が増えたためメジャーを上げます。
    Rev.5.1 までの意味が変わったものはありません。

    Rev.5.1 — fixes found by building an application on the component
    and running it against the real Hamlib library. No public type
    changed; one method was added (IHamlibLoader implementers gain
    nothing — SetDebugLevel lives on THamlibLoader), and Open now
    accepts an empty port, which previously raised.

    Rev.5.0 — 公開型が非互換に変更された (TRigMode、TRigErrorKind、
    TRigModelInfo) ため、マイナーではなくメジャーを上げました。

    Rev.5.1 — コンポーネントの上にアプリケーションを作り、実 Hamlib
    ライブラリに対して実行して見つかった不具合の修正。公開型の変更は
    なく、メソッドが 1 つ増え (SetDebugLevel は THamlibLoader にあるため
    IHamlibLoader の実装者に影響なし)、Open が空のポートを受け付ける
    ようになりました (従来は例外)。 }
  PACKAGE_VERSION = '6.1.0';

function HamlibComponentVersion: string;
begin
  Result := PACKAGE_VERSION;
end;

end.
