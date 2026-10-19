{
  HamlibRegister.pas

  Component package registration unit for the Lazarus IDE.
  This unit makes the Hamlib wrapper visible in the Lazarus
  component palette under the "Hamlib" tab.

  Lazarus IDE 用パッケージ登録ユニット。
  本ユニットにより Hamlib ラッパーが Lazarus のコンポーネント
  パレットに「Hamlib」タブとして表示されます。
}
unit HamlibRegister;

{$mode objfpc}{$H+}

interface

uses
  Classes;

{ ------------------------------------------------------------------
  Register procedure called by Lazarus when the package is installed.
  Lazarus がパッケージをインストールするときに呼ぶ Register 手続き。

  Note that this component package is primarily a non-visual library;
  no design-time controls are added to the palette in the current
  release. The procedure exists so that the IDE recognizes the package.

  注意: このパッケージは主に非ビジュアルライブラリであり、
  現リリースではパレットへのデザイン時コントロール追加はありません。
  手続きは IDE がパッケージを認識するために存在します。
  ------------------------------------------------------------------ }
procedure Register;

implementation

procedure Register;
begin
  { No visual components are registered at this time.
    Future versions may add a TRigStateMonitor non-visual component here.

    現時点ではビジュアルコンポーネントは登録しません。
    将来バージョンで TRigStateMonitor 等の非ビジュアルコンポーネントを
    ここで登録する予定です。 }
end;

end.
