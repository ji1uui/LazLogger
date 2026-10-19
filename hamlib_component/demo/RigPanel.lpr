{
  RigPanel.lpr

  The RigPanel demo application: a small rig-control panel built on the
  Hamlib wrapper component.

  RigPanel デモアプリケーション: Hamlib ラッパーコンポーネントの上に
  作った小さなリグ制御パネル。

  What it is for / 目的
  ------------------------------------------------------------------
  Two things at once:

    1. a worked example of using the component from an LCL application,
       written the way the design document says an application should be
       structured (MVP Passive View, form limited to control placement
       and event forwarding);
    2. a test of the component as a component. Driving it through an
       application found two real defects that none of the unit tests
       had reached — see REV5_REPORT.md section 9.

  2 つを兼ねています。

    1. LCL アプリケーションからコンポーネントを使う実例。設計書が言う
       アプリケーションの構造 (MVP Passive View、フォームの責務は
       コントロール配置とイベント転送に限定) に従って書いています。
    2. コンポーネントを「コンポーネントとして」試すテスト。アプリ
       経由で駆動したことで、どのユニットテストも到達していなかった
       実在の欠陥 2 件が見つかりました (REV5_REPORT.md の第 9 章)。

  Build:
    lazbuild RigPanel.lpi
  or:
    fpc -Mobjfpc -Sh -Fu../src -Fu. RigPanel.lpr   (needs LCL paths)

  No real Hamlib library is needed to start the program: it reports that
  the library could not be loaded and stays usable. With Hamlib present
  the rig list is populated from it.

  起動に実 Hamlib ライブラリは不要です。ロードできなかったことを報告し、
  操作可能なまま起動します。Hamlib があれば機種一覧がそこから埋まります。
}
program RigPanel;

{$mode objfpc}{$H+}

uses
  { cthreads FIRST, then Interfaces, then everything else.

    An earlier version of this file said an LCL application does not
    need cthreads because the widgetset pulls it in. Running the built
    program proved that wrong: with Lazarus 3.0 / FPC 3.2.2 on gtk2 it
    died at startup with

        This binary has no thread support compiled in.
        Runtime error 232

    The component uses TThread, so the rule is simply "a Unix program
    that uses threads puts cthreads first" — LCL or not. Some widgetset
    and version combinations happen to link it anyway; relying on that
    is how you ship an application that starts on your machine and not
    on the user's.

    cthreads を最初に、次に Interfaces、その後に他を置きます。

    本ファイルの以前の版は「LCL アプリはウィジェットセットが cthreads を
    引き込むため不要」と書いていました。ビルドしたプログラムを実行した
    結果、それは誤りでした。Lazarus 3.0 / FPC 3.2.2 の gtk2 では起動時に
    「This binary has no thread support compiled in / 実行時エラー 232」で
    停止します。

    本コンポーネントは TThread を使うため、規則は単純に「スレッドを使う
    Unix プログラムは cthreads を最初に置く」です。LCL か否かは関係あり
    ません。ウィジェットセットとバージョンの組み合わせによっては偶然
    リンクされますが、それに頼ると「自分の環境では起動し、利用者の環境
    では起動しない」アプリケーションを出荷することになります。 }
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, SysUtils,
  MainForm;

var
  Panel: TMainForm;
  i:     Integer;
  Model: Integer;
  Arg:   string;
  Port:  string;

begin
  { The form is built in code rather than from a .lfm, so the LCL must
    not insist on a form resource.
    フォームは .lfm ではなくコードで構築するため、LCL にフォーム
    リソースを要求させません。 }
  RequireDerivedFormResource := False;
  Application.Title := 'RigPanel';
  Application.Initialize;
  Application.CreateForm(TMainForm, Panel);

  { Optional scripted start: --model=N [--port=NAME]. Used by the
    demo's screenshot script and handy as a smoke test against a real
    rig. With no arguments the panel simply waits for the operator.

    任意の自動起動: --model=N [--port=NAME]。デモのスクリーンショット
    取得スクリプトが使い、実機に対するスモークテストにも便利です。
    引数が無ければパネルはオペレータの操作を待つだけです。 }
  Model := 0;
  Port  := '';
  for i := 1 to ParamCount do
  begin
    Arg := ParamStr(i);
    if Copy(Arg, 1, 8) = '--model=' then
      Model := StrToIntDef(Copy(Arg, 9, MaxInt), 0)
    else if Copy(Arg, 1, 7) = '--port=' then
      Port := Copy(Arg, 8, MaxInt);
  end;
  if Model > 0 then
    Panel.AutoConnect(Model, Port);

  Application.Run;
end.
