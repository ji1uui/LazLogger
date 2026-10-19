{
  HamlibTypes.pas

  Constants and helper functions for Hamlib types. Most application
  code uses higher-level enums in HamlibInterfaces; this unit is for
  cases where raw Hamlib values (e.g. RIG_MODE_USB) are needed.

  Hamlib 型のための定数とヘルパー関数。多くのアプリケーションコードは
  HamlibInterfaces の上位 enum を使います。このユニットは生の Hamlib
  値 (例: RIG_MODE_USB) が必要な場合のものです。

  Layer:    L2
  Depends:  HamlibInterfaces, HamlibModeCodec (implementation only)
}
unit HamlibTypes;

{$mode objfpc}{$H+}

interface

uses
  HamlibInterfaces;

const
  { ====================================================================
    Hamlib mode constants (rmode_t).
    Hamlib モード定数 (rmode_t)。
    ====================================================================
    These are bit flags; use them as Int64 values when calling
    SetModeAsync. Hamlib 4.x defines rmode_t as 64-bit.
    これらはビットフラグです。SetModeAsync 呼び出し時に Int64 として
    使ってください。Hamlib 4.x では rmode_t は 64bit です。 }

  RIG_MODE_NONE   : Int64 = 0;
  RIG_MODE_AM     : Int64 = (Int64(1) shl 0);
  RIG_MODE_CW     : Int64 = (Int64(1) shl 1);
  RIG_MODE_USB    : Int64 = (Int64(1) shl 2);
  RIG_MODE_LSB    : Int64 = (Int64(1) shl 3);
  RIG_MODE_RTTY   : Int64 = (Int64(1) shl 4);
  RIG_MODE_FM     : Int64 = (Int64(1) shl 5);
  RIG_MODE_WFM    : Int64 = (Int64(1) shl 6);
  RIG_MODE_CWR    : Int64 = (Int64(1) shl 7);
  RIG_MODE_RTTYR  : Int64 = (Int64(1) shl 8);
  RIG_MODE_AMS    : Int64 = (Int64(1) shl 9);
  RIG_MODE_PKTLSB : Int64 = (Int64(1) shl 10);
  RIG_MODE_PKTUSB : Int64 = (Int64(1) shl 11);
  RIG_MODE_PKTFM  : Int64 = (Int64(1) shl 12);
  RIG_MODE_ECSSUSB: Int64 = (Int64(1) shl 13);
  RIG_MODE_ECSSLSB: Int64 = (Int64(1) shl 14);
  RIG_MODE_FAX    : Int64 = (Int64(1) shl 15);

  { Common Hamlib model numbers as a convenience for callers.
    See "rigctl --list" for the full list.
    呼び出し元の便宜のため、よく使われる Hamlib モデル番号を定義します。
    完全なリストは "rigctl --list" を参照してください。 }
  { Model numbers follow riglist.h:
      RIG_MAKE_MODEL(backend, n) = MAX_MODELS_PER_BACKEND * backend + n
      MAX_MODELS_PER_BACKEND = 1000
      RIG_DUMMY = 0, RIG_YAESU = 1, RIG_KENWOOD = 2, RIG_ICOM = 3
    Elecraft rigs live in the Kenwood backend.

    モデル番号は riglist.h の規則に従います:
      RIG_MAKE_MODEL(backend, n) = 1000 * backend + n
    Elecraft 機は Kenwood バックエンドに属します。

    Verified against Hamlib master (4.7.x) riglist.h on 2026-10-12.
    2026-10-12 に Hamlib master (4.7.x) の riglist.h と照合済み。

    For any model not listed here, read the number from riglist.h or run
    `rigctl --list`; do not guess.
    ここに無い機種は riglist.h を読むか `rigctl --list` で確認してください。
    推測してはいけません。 }

  RIG_MODEL_DUMMY        = 1;       { Built-in test rig / 内蔵テスト用リグ }
  RIG_MODEL_NETRIGCTL    = 2;       { Hamlib rigctld / Hamlib rigctld }

  { Yaesu (backend 1) }
  RIG_MODEL_FT991        = 1035;    { Yaesu FT-991 / FT-991A
                                      (Hamlib has no separate FT991A entry)
                                      (Hamlib に FT991A の独立項目はない) }
  RIG_MODEL_FTDX10       = 1042;    { Yaesu FT-DX10 }

  { Kenwood (backend 2) — Elecraft included }
  RIG_MODEL_K3           = 2029;    { Elecraft K3 }
  RIG_MODEL_TS890S       = 2041;    { Kenwood TS-890S }
  RIG_MODEL_K3S          = 2043;    { Elecraft K3S }
  RIG_MODEL_KX3          = 2045;    { Elecraft KX3 }
  RIG_MODEL_K4           = 2047;    { Elecraft K4 }

  { Icom (backend 3) }
  RIG_MODEL_IC7600       = 3063;    { Icom IC-7600 }
  RIG_MODEL_IC7300       = 3073;    { Icom IC-7300 }
  RIG_MODEL_IC7610       = 3078;    { Icom IC-7610 }
  RIG_MODEL_IC705        = 3085;    { Icom IC-705 }

  { ====================================================================
    Hamlib error codes.
    Hamlib エラーコード。
    ====================================================================
    The RIG_E* enum values below are POSITIVE. Hamlib functions return
    the NEGATED value, so a returned -6 means RIG_EIO. Compare an
    ErrorCode from TRigResult against -RIG_EIO, not RIG_EIO.

    下記 RIG_E* の enum 値は「正」です。Hamlib 関数はその符号を反転した
    値を返すため、戻り値 -6 は RIG_EIO を意味します。TRigResult の
    ErrorCode は RIG_EIO ではなく -RIG_EIO と比較してください。 }

  RIG_OK          = 0;    { No error / エラーなし }
  RIG_EINVAL      = 1;    { Invalid parameter / 無効な引数 }
  RIG_ECONF       = 2;    { Invalid configuration / 無効な設定 }
  RIG_ENOMEM      = 3;    { Memory shortage / メモリ不足 }
  RIG_ENIMPL      = 4;    { Not implemented yet / 未実装 }
  RIG_ETIMEOUT    = 5;    { Communication timed out / 通信タイムアウト }
  RIG_EIO         = 6;    { IO error, including open failed
                            / I/O エラー (open 失敗を含む) }
  RIG_EINTERNAL   = 7;    { Internal Hamlib error / Hamlib 内部エラー }
  RIG_EPROTO      = 8;    { Protocol error / プロトコルエラー }
  RIG_ERJCTED     = 9;    { Command rejected by the rig / リグがコマンドを拒否 }
  RIG_ETRUNC      = 10;   { Command performed, arg truncated / 引数が切り詰められた }
  RIG_ENAVAIL     = 11;   { Function not available / 機能が利用不可 }
  RIG_ENTARGET    = 12;   { VFO not targetable / VFO を指定できない }
  RIG_BUSERROR    = 13;   { Error talking on the bus / バス通信エラー }
  RIG_BUSBUSY     = 14;   { Collision on the bus / バス衝突 }
  RIG_EARG        = 15;   { NULL handle or invalid pointer / NULL ハンドル等 }
  RIG_EVFO        = 16;   { Invalid VFO / 無効な VFO }
  RIG_EDOM        = 17;   { Argument out of domain / 引数が定義域外 }
  RIG_EDEPRECATED = 18;   { Function deprecated / 非推奨の関数 }
  RIG_ESECURITY   = 19;   { Security error / セキュリティエラー }
  RIG_EPOWER      = 20;   { Rig not powered on / リグの電源が入っていない }
  RIG_ELIMIT      = 21;   { Limit exceeded / 上限超過 }
  RIG_EACCESS     = 22;   { Access denied, e.g. port already in use
                            / アクセス拒否 (例: ポートが使用中) }

{ ------------------------------------------------------------------
  Convert a Hamlib mode bitmask to a human-readable string.

  Retained for callers that hold a raw rmode_t. It delegates to
  THamlibModeCodec.FormatRaw, which owns the mode table; there is no
  second list of mode names in this unit. New code should work with
  TRigMode and THamlibModeCodec.ToDisplayString instead.

  Hamlib モードビットマスクを人間可読の文字列に変換します。

  生の rmode_t を持つ呼び出し元のために残しています。モード表を所有する
  THamlibModeCodec.FormatRaw に委譲しており、本ユニットにモード名の
  二重定義はありません。新規コードは TRigMode と
  THamlibModeCodec.ToDisplayString を使ってください。
  ------------------------------------------------------------------ }
function HamlibModeToString(AMode: Int64): string;

{ ------------------------------------------------------------------
  Convert a passband width [Hz] to a human-readable string
  (e.g. "2.7kHz", "500Hz", "Auto" for 0).
  通過帯域幅 [Hz] を人間可読の文字列に変換します
  (例: "2.7kHz"、"500Hz"、0 のときは "Auto")。
  ------------------------------------------------------------------ }
function PassbandToString(AWidth: Int64): string;

implementation

uses
  SysUtils,
  HamlibModeCodec;

function HamlibModeToString(AMode: Int64): string;
begin
  Result := THamlibModeCodec.FormatRaw(AMode);
end;

function PassbandToString(AWidth: Int64): string;
begin
  if AWidth <= 0 then
    Result := 'Auto'
  else if AWidth < 1000 then
    Result := Format('%dHz', [AWidth])
  else
    Result := Format('%.1fkHz', [AWidth / 1000]);
end;

end.
