{
  DxPanelView.pas

  IDxView — what the DxPanel application's UI can do, expressed without
  naming an LCL control.

  IDxView - DxPanel アプリの UI ができることを、LCL のコントロール名を
  出さずに表現したインターフェース。

  Why a second view interface and not a reuse of IRigView
  なぜ IRigView を再利用せず 2 つ目の view インターフェースを作るか
  ------------------------------------------------------------------
  IRigView describes a single-VFO panel: one frequency, one mode, a PTT
  lamp. DxPanel is about a *pair* of frequencies, a live meter and a
  multi-step operation that can fail halfway. Widening IRigView to cover
  both would give RigPanel methods it must implement and never calls,
  which is the Interface Segregation violation the component itself
  avoids by splitting IHamlibDiagnostics / IHamlibCatalog /
  IHamlibRigControl. Two small view interfaces are cheaper than one
  wide one.

  IRigView は単一 VFO のパネル (周波数 1 つ、モード 1 つ、PTT ランプ) を
  表します。DxPanel が扱うのは周波数の「対」、生きているメータ、そして
  途中で失敗しうる多段操作です。両方を覆うよう IRigView を広げると、
  RigPanel は実装するだけで決して呼ばないメソッドを持つことになります。
  これはコンポーネント自身が IHamlibDiagnostics / IHamlibCatalog /
  IHamlibRigControl の分割で避けている Interface Segregation 違反です。
  小さな view インターフェース 2 つは、広い 1 つより安価です。

  As in RigPanel every method is "show this". None asks a question, so
  the presenter can never read application state back out of the UI.

  RigPanel と同じく全メソッドは「これを表示せよ」です。問い合わせるもの
  はないため、presenter が UI からアプリ状態を読み戻すことはできません。

  Layer:    demo2 (application)
  Depends:  HamlibInterfaces
}
unit DxPanelView;

{$mode objfpc}{$H+}

interface

uses
  HamlibInterfaces;

type
  { What the window should allow right now.

    duiSequenceRunning is the state RigPanel had no equivalent of: a
    multi-step operation is in flight, so the frequency fields must be
    locked (editing them mid-sequence would describe a rig state that is
    no longer being built) while Abort stays live.

    ウィンドウが今何を許すべきか。

    duiSequenceRunning は RigPanel に相当するものがなかった状態です。
    多段操作が進行中であり、周波数欄はロックしなければなりません
    (途中で編集すると、もう構築していないリグ状態を指すことになる)。
    一方で中断は有効なままです。 }
  TDxUiMode = (
    duiDisconnected,
    duiConnecting,
    duiConnected,
    duiSequenceRunning
  );

  TDxNoticeLevel = (dnlInfo, dnlWarning, dnlError);

  IDxView = interface
    ['{2C6F94A1-8B37-4D52-A0E8-7F1B36D9C425}']

    { Rig selector. An empty list means the library could not be
      enumerated and the view should offer a model-number entry.
      機種選択。空リストは列挙できなかったことを意味し、view は機種番号
      の入力欄を出すべきです。 }
    procedure ShowRigList(const AItems: array of string;
                          AEnumerationAvailable: Boolean);

    { The receive frequency, in Hz. 0 reads as blank, not 0.000 MHz.
      受信周波数 [Hz]。0 は 0.000 MHz ではなく空欄として表示します。 }
    procedure ShowRxFrequency(AHz: Double);

    { The transmit side as one decision. When ASplitOn is False the
      view should make clear that transmit follows receive, rather than
      showing a stale split frequency that is no longer in effect — an
      operator who misreads this transmits on the wrong frequency.

      送信側を 1 つの判断として渡します。ASplitOn が False のとき view
      は「送信は受信に追従する」ことを明示すべきです。効力を失った
      スプリット周波数を残して表示すると、読み違えたオペレータは誤った
      周波数で送信します。 }
    procedure ShowTxFrequency(ASplitOn: Boolean; ATxVfo: TRigVfo;
                              AHz: Double);

    { Which VFO the rig says is selected, plus the raw vfo_t it
      answered with. Both are shown because Hamlib normalises A/B to
      MAIN/SUB on some backends and an operator comparing the panel
      with the rig's own display needs to see why they differ.

      リグが選択中と答えた VFO と、その生の vfo_t。両方を表示するのは、
      Hamlib がバックエンドによって A/B を MAIN/SUB に正規化するため
      です。パネルとリグ本体の表示を見比べるオペレータには、差異の理由
      が見える必要があります。 }
    procedure ShowSelectedVfo(AVfo: TRigVfo; ARawVfo: Integer);

    { Received signal strength in dB relative to S9. AValid is False
      when no reading has arrived yet or the rig refused the level —
      the view must then show "no reading", never 0 dB, which is a
      legitimate and strong value (S9).

      S9 を基準とした受信信号強度 [dB]。AValid が False なのは、まだ
      読み取りが届いていないか、リグがそのレベルを拒否した場合です。
      view は「読み取りなし」を表示しなければならず、0 dB と表示して
      はいけません。0 dB は正当かつ強い値 (S9) です。 }
    procedure ShowSignal(ADb: Integer; AValid: Boolean);

    { Progress of the split-setup sequence. AStepIndex is 1-based;
      0 means "not running".
      スプリット設定シーケンスの進行。AStepIndex は 1 起点で、0 は
      「実行中でない」を意味します。 }
    procedure ShowSequenceProgress(AStepIndex, AStepCount: Integer;
                                   const ACaption: string);

    { Terminal result of the sequence, including whether the rollback
      ran. Separate from ShowNotice because this is the one message the
      operator must not miss.
      シーケンスの最終結果。ロールバックが走ったかどうかも含みます。
      オペレータが見逃してはならない唯一のメッセージなので ShowNotice
      とは分けています。 }
    procedure ShowSequenceOutcome(ASucceeded: Boolean;
                                  const AMessage: string);

    { The capability panel: one line per fact the component could
      establish about the connected model.
      能力パネル。接続中の機種について確定できた事実を 1 行ずつ。 }
    procedure ShowCapabilities(const ALines: array of string);

    procedure SetUiMode(AMode: TDxUiMode);
    procedure ShowNotice(ALevel: TDxNoticeLevel; const AText: string);
    procedure ShowLibraryInfo(const AText: string);

    { Pending command count and breaker state. During a sequence this
      is how an operator sees that the queue is draining rather than
      stuck.
      保留コマンド数と遮断器の状態。シーケンス中、キューが詰まって
      いるのではなく流れていることをオペレータが見る手段です。 }
    procedure ShowQueueDepth(ADepth: Integer; ABreakerOpen: Boolean);
  end;

implementation

end.
