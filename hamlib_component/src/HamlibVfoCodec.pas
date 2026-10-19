{
  HamlibVfoCodec.pas

  VFO value codec — converts between TRigVfo (high-level enum) and the
  raw integer values that Hamlib's C API expects. Hamlib 3.x and 4.x
  use slightly different conventions; this codec abstracts that away.

  VFO 値コーデック — TRigVfo (上位 enum) と Hamlib C API が期待する
  生整数値を相互変換します。Hamlib 3.x と 4.x で慣習が微妙に異なるため、
  本コーデックがその差異を吸収します。

  Layer:    L2
  Depends:  HamlibInterfaces
}
unit HamlibVfoCodec;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,          { Format, for the unlabelled-value message }
  HamlibInterfaces;

type
  { Static class with VFO conversion routines. Stateless; no instance
    needed. Use class methods directly: TVfoCodec.ToHamlib(rvfoA, 4).

    VFO 変換ルーチンを持つ静的クラス。状態を持たず、インスタンス化不要です。
    クラスメソッドを直接使ってください: TVfoCodec.ToHamlib(rvfoA, 4)。 }
  TVfoCodec = class
  public
    { Convert a TRigVfo to the integer value Hamlib expects.
      AApiMajor is the Hamlib major version (e.g. 4 for Hamlib 4.x).
      TRigVfo を Hamlib が期待する整数値に変換します。
      AApiMajor は Hamlib メジャーバージョン (Hamlib 4.x なら 4)。 }
    class function ToHamlib(AVfo: TRigVfo; AApiMajor: Integer): Integer;

    { Convert a Hamlib raw integer back to TRigVfo.
      Hamlib の生整数値を TRigVfo に戻します。 }
    class function FromHamlib(AValue: Integer; AApiMajor: Integer): TRigVfo;
  end;

{ ------------------------------------------------------------------
  Does the VFO the rig reports correspond to the one that was asked
  for?

  Hamlib normalises the A/B pair onto MAIN/SUB. Measured against real
  Hamlib 4.5.5 with the built-in dummy rig:

      rig_set_vfo(RIG_VFO_A)  then rig_get_vfo -> RIG_VFO_MAIN
      rig_set_vfo(RIG_VFO_B)  then rig_get_vfo -> RIG_VFO_SUB

  So an application that compares its request to the answer with "="
  concludes the selection failed when it in fact succeeded. This
  function answers the question the application meant to ask.

  The equivalence is about SELECTION, not identity. On a true
  dual-receiver rig MAIN and SUB are different receivers from A and B,
  and an application that needs to address a specific receiver should
  name rvfoMain or rvfoSub and compare exactly. Use this when checking
  "did my VFO change take effect", not when deciding which receiver to
  put a frequency on.

  リグが報告した VFO は、要求した VFO に対応するか?

  Hamlib は A/B の対を MAIN/SUB に正規化します。実 Hamlib 4.5.5 と内蔵
  ダミーリグで実測した結果が上記です。そのため、要求と応答を "=" で
  比較するアプリケーションは、実際には成功した選択を失敗と判断します。
  本関数はアプリケーションが尋ねたかった問いに答えます。

  この同値性は「選択」についてであり、同一性ではありません。真の
  デュアル受信機では MAIN と SUB は A と B とは別の受信機であり、特定の
  受信機を指定する必要があるアプリケーションは rvfoMain / rvfoSub を
  名指しして厳密に比較すべきです。本関数は「VFO 変更が効いたか」の確認に
  使い、「どちらの受信機に周波数を載せるか」の判断には使わないでください。
  ------------------------------------------------------------------ }
function RigVfoSelectionMatches(ARequested, AReported: TRigVfo): Boolean;

{ ------------------------------------------------------------------
  The VFO's name, for a display. Added in Rev.6.0 because both sample
  applications wrote their own case statement over TRigVfo, and a
  display label that every application has to reinvent belongs with
  the type.

  This is a label, not a protocol token: it is for a panel, a log line
  or a message to the operator. Nothing parses it back.

  表示用の VFO 名。Rev.6.0 で追加しました。両サンプルアプリが TRigVfo
  に対する case 文を各自書いていたためです。どのアプリも作り直さなければ
  ならない表示用ラベルは、型と同じ場所に属します。

  これはラベルであり、プロトコル上のトークンではありません。パネル、
  ログ行、オペレータへのメッセージのためのものです。解析して戻す
  ものはありません。
  ------------------------------------------------------------------ }
function RigVfoToString(AVfo: TRigVfo): string;

implementation

{ Hamlib 4.x VFO constants from include/hamlib/rig.h:
    RIG_VFO_NONE     0
    RIG_VFO_A        (1<<0)
    RIG_VFO_B        (1<<1)
    RIG_VFO_C        (1<<2)
    RIG_VFO_CURR     (1<<29)
    RIG_VFO_MEM      (1<<28)
    RIG_VFO_MAIN     (1<<27)
    RIG_VFO_SUB      (1<<26)

  Hamlib 3.x had a different but largely compatible scheme.
  The lower bits (VFO_A/B/C, MAIN, SUB) are stable across versions.

  Hamlib 4.x の VFO 定数 (include/hamlib/rig.h より):
  下位ビット (VFO_A/B/C、MAIN、SUB) はバージョン間で安定しています。 }

{ Verified against Hamlib master (4.7.x) include/hamlib/rig.h, 2026-10-12:

    #define RIG_VFO_N(n)   (1u<<(n))
    #define RIG_VFO_NONE   0
    #define RIG_VFO_A      RIG_VFO_N(0)
    #define RIG_VFO_B      RIG_VFO_N(1)
    #define RIG_VFO_SUB    RIG_VFO_N(25)
    #define RIG_VFO_MAIN   RIG_VFO_N(26)
    #define RIG_VFO_CURR   RIG_VFO_N(29)

  MAIN and SUB are adjacent, so transposing them silently addresses the
  wrong receiver on a dual-receiver rig rather than failing outright.
  Do not "tidy" these numbers without re-reading rig.h.

  2026-10-12 に Hamlib master (4.7.x) の include/hamlib/rig.h と照合済み。
  MAIN と SUB は隣接ビットのため、取り違えてもエラーにはならず、
  デュアル受信機で静かに別の受信機を操作してしまいます。
  rig.h を読み直さずにこの数値を「整理」しないこと。 }
const
  HL_VFO_NONE = 0;
  HL_VFO_A    = (1 shl 0);
  HL_VFO_B    = (1 shl 1);
  HL_VFO_SUB  = (1 shl 25);
  HL_VFO_MAIN = (1 shl 26);
  HL_VFO_CURR = (1 shl 29);


function RigVfoToString(AVfo: TRigVfo): string;
begin
  case AVfo of
    rvfoCurr: Result := 'current';
    rvfoA:    Result := 'A';
    rvfoB:    Result := 'B';
    rvfoMain: Result := 'MAIN';
    rvfoSub:  Result := 'SUB';
  else
    { An unlabelled value is a bug in this unit, not in the caller, so
      it says so rather than returning an empty string that would be
      mistaken for "no VFO".
      ラベルのない値は呼び出し側ではなく本ユニットの不具合です。
      そのため「VFO なし」と誤読されうる空文字列ではなく、そう述べます。 }
    Result := Format('unlabelled VFO %d', [Ord(AVfo)]);
  end;
end;

function RigVfoSelectionMatches(ARequested, AReported: TRigVfo): Boolean;

  function Normalise(AVfo: TRigVfo): TRigVfo;
  begin
    { Collapse the pair Hamlib itself collapses, and nothing else.
      Hamlib 自身が畳む対だけを畳み、それ以外は畳みません。 }
    case AVfo of
      rvfoMain: Result := rvfoA;
      rvfoSub:  Result := rvfoB;
    else
      Result := AVfo;
    end;
  end;

begin
  { rvfoCurr means "whatever is current", so it matches anything the
    rig reports — the request did not name a VFO to verify.
    rvfoCurr は「現在のもの」という意味なので、リグが報告する何にでも
    一致します。要求が検証対象の VFO を名指ししていないからです。 }
  if (ARequested = rvfoCurr) or (AReported = rvfoCurr) then
    Exit(True);
  Result := Normalise(ARequested) = Normalise(AReported);
end;

class function TVfoCodec.ToHamlib(AVfo: TRigVfo; AApiMajor: Integer): Integer;
begin
  case AVfo of
    rvfoCurr: Result := HL_VFO_CURR;
    rvfoA:    Result := HL_VFO_A;
    rvfoB:    Result := HL_VFO_B;
    rvfoMain: Result := HL_VFO_MAIN;
    rvfoSub:  Result := HL_VFO_SUB;
  else
    Result := HL_VFO_CURR;
  end;
  { Note: AApiMajor is currently ignored because the values above are
    stable in both 3.x and 4.x. Reserved for future Hamlib 5.x.

    注: AApiMajor は 3.x と 4.x で上記値が安定しているため現在は未使用です。
    将来の Hamlib 5.x のために予約されています。 }
end;

class function TVfoCodec.FromHamlib(AValue: Integer; AApiMajor: Integer): TRigVfo;
begin
  if (AValue and HL_VFO_MAIN) <> 0 then
    Result := rvfoMain
  else if (AValue and HL_VFO_SUB) <> 0 then
    Result := rvfoSub
  else if (AValue and HL_VFO_A) <> 0 then
    Result := rvfoA
  else if (AValue and HL_VFO_B) <> 0 then
    Result := rvfoB
  else
    Result := rvfoCurr;
end;

end.
