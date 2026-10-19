{
  DxPanel.lpr

  The second sample application: a split-operation panel.

  2 つ目のサンプルアプリケーション: スプリット運用パネル。

  Why a second sample / 2 つ目のサンプルを作る理由
  ------------------------------------------------------------------
  RigPanel (demo/) exercises the component's single-VFO surface with
  independent commands: set a frequency, read a mode, key the PTT.
  Driving it found two defects no unit test had reached.

  DxPanel asks the questions RigPanel could not. It is built around the
  parts of Hamlib that real applications lean on hardest — the ones
  surveyed in COVERAGE_MATRIX.md — and around the shape of use that
  RigPanel never had:

    - a frequency *pair*, which is what split operation is
    - a multi-step operation that can fail halfway and must then undo
      what it already did (DxSplitSequence)
    - a level read on a timer, with the back-pressure that needs
    - a float level set (RF power) next to an integer level read
      (the S-meter), because the component's float/int distinction is
      only tested by using both
    - rig_get_caps_int displayed honestly, including what it cannot say

  RigPanel (demo/) はコンポーネントの単一 VFO 面を、独立したコマンドで
  検査します。周波数を設定し、モードを読み、PTT を押す。これを駆動した
  ことで、どのユニットテストも到達していなかった欠陥 2 件が見つかりました。

  DxPanel は RigPanel が問えなかったことを問います。実アプリケーションが
  最も強く依存する Hamlib の部分 (COVERAGE_MATRIX.md の調査対象) と、
  RigPanel には無かった使用形態を軸にしています (上記 5 点)。

  Build:
    lazbuild DxPanel.lpi

  Run:
    ./DxPanel                        (wait for the operator)
    ./DxPanel --model=1 --port=      (open Hamlib's dummy rig)
    ./DxPanel --model=1 --port= --setup=14.023,14.205

  Model 1 is Hamlib's dummy backend: no hardware, no serial port.
  モデル 1 は Hamlib のダミーバックエンドです。ハードウェアもシリアル
  ポートも不要です。
}
program DxPanel;

{$mode objfpc}{$H+}

uses
  { cthreads first on Unix, LCL or not: the component uses TThread, and
    without it the program dies at startup with runtime error 232. This
    is not theoretical — it is what happened while building the first
    sample.

    Unix では LCL か否かに関わらず cthreads を最初に置きます。本
    コンポーネントは TThread を使い、これがないとプログラムは起動時に
    実行時エラー 232 で停止します。理論上の話ではなく、最初のサンプルを
    作っている最中に実際に起きたことです。 }
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, SysUtils,
  DxMainForm;

var
  Panel:  TDxForm;
  i:      Integer;
  Arg:    string;
  Model:  Integer;
  Port:   string;
  Setup:  string;
  RxMHz:  Double;
  TxMHz:  Double;
  Comma:  Integer;

begin
  { The form is built in code, so the LCL must not insist on a form
    resource.
    フォームはコードで構築するため、LCL にフォームリソースを要求させ
    ません。 }
  RequireDerivedFormResource := False;
  Application.Title := 'DxPanel';
  Application.Initialize;
  Application.CreateForm(TDxForm, Panel);

  Model := 0;
  Port  := '';
  Setup := '';
  for i := 1 to ParamCount do
  begin
    Arg := ParamStr(i);
    if Copy(Arg, 1, 8) = '--model=' then
      Model := StrToIntDef(Copy(Arg, 9, MaxInt), 0)
    else if Copy(Arg, 1, 7) = '--port=' then
      Port := Copy(Arg, 8, MaxInt)
    else if Copy(Arg, 1, 8) = '--setup=' then
      Setup := Copy(Arg, 9, MaxInt);
  end;

  if Model > 0 then
    Panel.AutoConnect(Model, Port);

  if (Model > 0) and (Setup <> '') then
  begin
    Comma := Pos(',', Setup);
    if Comma > 1 then
    begin
      RxMHz := StrToFloatDef(Copy(Setup, 1, Comma - 1), 0);
      TxMHz := StrToFloatDef(Copy(Setup, Comma + 1, MaxInt), 0);
      if (RxMHz > 0) and (TxMHz > 0) then
        Panel.AutoSetup(RxMHz, TxMHz);
    end;
  end;

  Application.Run;
end.
