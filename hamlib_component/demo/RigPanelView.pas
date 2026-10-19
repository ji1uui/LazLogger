{
  RigPanelView.pas

  IRigView — what the RigPanel demo application's UI can do, expressed
  without naming a single LCL control.

  IRigView - RigPanel デモアプリの UI ができることを、LCL のコントロール
  名を一切出さずに表現したインターフェース。

  Why an interface and not just a form / なぜフォームではなくインターフェースか
  ------------------------------------------------------------------
  This is the Passive View half of MVP. The presenter decides what the
  operator should see; the view only displays it. Two consequences
  matter in practice:

    1. the presenter can be driven by a test double (see
       demo/ScenarioTest.lpr) and run with no LCL and no screen;
    2. the form cannot accumulate logic, because the only thing it is
       allowed to do is assign to controls and forward events.

  これは MVP の Passive View 側です。何を見せるかは presenter が決め、
  view は表示するだけです。実務上の帰結は 2 つあります。

    1. presenter はテストダブルで駆動でき、LCL も画面もなしに実行できる
       (demo/ScenarioTest.lpr)。
    2. フォームにロジックが溜まらない。許されているのはコントロールへの
       代入とイベント転送だけだからです。

  Every method is "show this"; none of them ask a question. A view that
  can be queried invites the presenter to read state back out of the UI,
  which is how a passive view stops being passive.

  全メソッドは「これを表示せよ」で、問い合わせるものは 1 つもありません。
  問い合わせ可能な view は、presenter が UI から状態を読み戻すことを
  誘発します。それが Passive View が受動でなくなる経路です。

  Layer:    demo (application)
  Depends:  HamlibInterfaces
}
unit RigPanelView;

{$mode objfpc}{$H+}

interface

uses
  HamlibInterfaces;

type
  { How the connection button and the port/model selectors should look.
    Derived from the connection state, so the view never has to work it
    out from several separate flags.

    接続ボタンと ポート/機種 選択の見え方。接続状態から導出されるため、
    view が複数のフラグから自力で判断する必要はありません。 }
  TRigUiMode = (
    ruiDisconnected,  { selectors enabled, button says "Connect"
                        / 選択可、ボタンは「接続」 }
    ruiConnecting,    { everything disabled, button says "Connecting..."
                        / すべて不可、ボタンは「接続中...」 }
    ruiConnected      { selectors locked, controls live, button "Disconnect"
                        / 選択はロック、操作可、ボタンは「切断」 }
  );

  { Severity of a line written to the status area. The view chooses the
    colour; the presenter only says how bad it is.
    ステータス欄に書く行の重大度。色は view が選び、presenter は深刻さ
    だけを伝えます。 }
  TRigNoticeLevel = (rnlInfo, rnlWarning, rnlError);

  IRigView = interface
    ['{9F3B2C85-7D41-4E26-B0A9-5C8D1E7F3A64}']

    { Fill the rig selector. An empty list means the loaded Hamlib could
      not be enumerated, and the view should offer a number entry field
      instead.
      機種選択を埋めます。空リストはロードした Hamlib を列挙できなかった
      ことを意味し、view は番号入力欄を代わりに出すべきです。 }
    procedure ShowRigList(const AItems: array of string;
                          AEnumerationAvailable: Boolean);

    { Frequency in Hz. 0 means "not known yet" and should read as blank
      rather than as 0.000 MHz.
      周波数 [Hz]。0 は「未取得」であり、0.000 MHz ではなく空欄として
      表示すべきです。 }
    procedure ShowFrequency(AHz: Double);

    { Mode and passband. AMode is already a domain value; the view does
      not translate bitmasks.
      モードと帯域幅。AMode は既にドメイン値であり、view がビットマスクを
      変換することはありません。 }
    procedure ShowMode(AMode: TRigMode; APassbandHz: Integer);

    { Transmit indicator. 送信インジケータ。 }
    procedure ShowPtt(AActive: Boolean);

    { Enable/disable groups of controls as one decision.
      コントロール群の有効・無効を 1 つの判断として設定します。 }
    procedure SetUiMode(AMode: TRigUiMode);

    { One line for the operator. Replaces the previous line; this is a
      status bar, not a log.
      オペレータ向けの 1 行。前の行を置き換えます。これはログではなく
      ステータス表示です。 }
    procedure ShowNotice(ALevel: TRigNoticeLevel; const AText: string);

    { Library provenance, shown once after loading: path, version and
      whether it is inside the verified range.
      ライブラリの出自。ロード後に 1 度表示します。パス、バージョン、
      検証済み範囲内かどうか。 }
    procedure ShowLibraryInfo(const AText: string);

    { Pending command count and breaker state, for the diagnostics
      corner of the window.
      保留コマンド数と遮断器の状態。ウィンドウの診断表示用。 }
    procedure ShowQueueDepth(ADepth: Integer; ABreakerOpen: Boolean);
  end;

implementation

end.
