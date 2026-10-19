{
  HamlibModeCodec.pas

  Mode value codec — the single place that knows which bit of Hamlib's
  64-bit rmode_t corresponds to which operating mode. Nothing above L3
  should contain a mode bit number, and nothing below L2 should contain
  a TRigMode.

  モード値コーデック — Hamlib の 64bit rmode_t のどのビットがどの動作
  モードに対応するかを知る唯一の場所です。L3 より上にモードのビット番号
  を書いてはならず、L2 より下に TRigMode を書いてはなりません。

  Why a table and not arithmetic / 計算ではなく表にする理由
  ------------------------------------------------------------------
  The bit numbers are not a formula; they are a historical list that
  Hamlib extends by filling reserved positions. A table can be checked
  against the headers mechanically (tools/check_abi.py does exactly
  that), whereas a clever expression could not.

  ビット番号は数式ではなく、Hamlib が予約位置を埋めて拡張してきた
  歴史的な一覧です。表であればヘッダと機械的に照合できます
  (tools/check_abi.py がまさにそれを行います)。巧妙な式ではできません。

  Layer:    L2
  Depends:  HamlibInterfaces
}
unit HamlibModeCodec;

{$mode objfpc}{$H+}

interface

uses
  HamlibInterfaces;

type
  { Static class; stateless, no instance needed. Use the class methods
    directly: THamlibModeCodec.ToHamlib(rmUSB).

    静的クラス。状態を持たずインスタンス化不要です。クラスメソッドを
    直接使ってください: THamlibModeCodec.ToHamlib(rmUSB)。 }
  THamlibModeCodec = class
  public
    { Convert a named mode to the rmode_t bit value Hamlib expects.
      rmUnknown returns 0, which Hamlib treats as RIG_MODE_NONE — callers
      that must not send 0 should reject rmUnknown before calling.

      名前付きモードを Hamlib が期待する rmode_t ビット値に変換します。
      rmUnknown は 0 を返し、Hamlib は RIG_MODE_NONE として扱います。
      0 を送ってはならない呼び出し側は、呼ぶ前に rmUnknown を弾いて
      ください。 }
    class function ToHamlib(AMode: TRigMode): Int64;

    { Convert a reported rmode_t back to a named mode. Returns rmUnknown
      for 0, for a bit this binding has no name for, and for a mask with
      more than one bit set — all three are cases where guessing would
      be worse than admitting ignorance.

      報告された rmode_t を名前付きモードに戻します。0、本バインディング
      に名前が無いビット、複数ビットが立ったマスクのいずれでも rmUnknown
      を返します。3 つとも、推測するより無知を認める方が安全な場合です。 }
    class function FromHamlib(AValue: Int64): TRigMode;

    { Short display label, e.g. 'USB', 'PKT-USB', 'CW-R'. For rmUnknown
      the label is '---'; use FormatRaw when you want to show the number.

      短い表示ラベル。例: 'USB'、'PKT-USB'、'CW-R'。rmUnknown のラベルは
      '---' です。数値を見せたい場合は FormatRaw を使ってください。 }
    class function ToDisplayString(AMode: TRigMode): string;

    { Label for a raw rmode_t: the mode name when recognised, otherwise
      'Mode($...)' so an unknown value is still identifiable in a log or
      on screen.

      生 rmode_t のラベル。認識できればモード名、できなければ
      'Mode($...)' を返し、未知の値もログや画面で識別できるようにします。 }
    class function FormatRaw(AValue: Int64): string;

    { Decode a whole capability mask into the set of named modes it
      contains. Bits with no name are dropped, so the result is "the
      modes we can talk about", not "every bit the rig set".

      能力マスク全体を、それが含む名前付きモードの集合に展開します。
      名前の無いビットは落とされるため、結果は「我々が扱えるモード」で
      あり「リグが立てた全ビット」ではありません。 }
    class function SetFromHamlib(AValue: Int64): TRigModeSet;
  end;

implementation

uses
  SysUtils;

{ Bit numbers taken from Hamlib include/hamlib/rig.h,
  CONSTANT_64BIT_FLAG(n), verified against 4.5.5 and 4.7.2 on 2026-10-13.

  Bit 20 is unassigned in both versions and so has no entry here.
  Bits 40..46 were RIG_MODE_BIT40..46 (reserved) in 4.5.5 and became
  USBD1..3 / LSBD1..3 / WFMS in 4.6+; a 4.5.5 library simply never
  reports them.

  ビット番号は Hamlib の include/hamlib/rig.h の CONSTANT_64BIT_FLAG(n)
  から取得し、2026-10-13 に 4.5.5 と 4.7.2 で照合しました。

  ビット 20 は両版で未割り当てのため項目がありません。
  ビット 40..46 は 4.5.5 では RIG_MODE_BIT40..46 (予約) で、4.6 以降で
  USBD1..3 / LSBD1..3 / WFMS になりました。4.5.5 のライブラリはそれらを
  報告しません。

  MODE_BIT_UNDEFINED marks rmUnknown, which owns no bit.
  MODE_BIT_UNDEFINED は、ビットを持たない rmUnknown を表します。 }
const
  MODE_BIT_UNDEFINED = 255;

  MODE_BITS: array[TRigMode] of Byte = (
    MODE_BIT_UNDEFINED,  { rmUnknown }
    0,                   { rmAM      }
    1,                   { rmCW      }
    2,                   { rmUSB     }
    3,                   { rmLSB     }
    4,                   { rmRTTY    }
    5,                   { rmFM      }
    6,                   { rmWFM     }
    7,                   { rmCWR     }
    8,                   { rmRTTYR   }
    9,                   { rmAMS     }
    10,                  { rmPktLSB  }
    11,                  { rmPktUSB  }
    12,                  { rmPktFM   }
    13,                  { rmEcssUSB }
    14,                  { rmEcssLSB }
    15,                  { rmFax     }
    16,                  { rmSAM     }
    17,                  { rmSAL     }
    18,                  { rmSAH     }
    19,                  { rmDSB     }
    21,                  { rmFMN     — note the gap at 20 / 20 は欠番 }
    22,                  { rmPktAM   }
    23,                  { rmP25     }
    24,                  { rmDStar   }
    25,                  { rmDPMR    }
    26,                  { rmNxdnVN  }
    27,                  { rmNxdnN   }
    28,                  { rmDCR     }
    29,                  { rmAMN     }
    30,                  { rmPSK     }
    31,                  { rmPSKR    }
    32,                  { rmDD      }
    33,                  { rmC4FM    }
    34,                  { rmPktFMN  }
    35,                  { rmSpec    }
    36,                  { rmCWN     }
    37,                  { rmIQ      }
    38,                  { rmIsbUSB  }
    39,                  { rmIsbLSB  }
    40,                  { rmUsbD1   }
    41,                  { rmUsbD2   }
    42,                  { rmUsbD3   }
    43,                  { rmLsbD1   }
    44,                  { rmLsbD2   }
    45,                  { rmLsbD3   }
    46                   { rmWfmS    }
  );

  { Display labels. Kept next to the bit table so a new mode cannot be
    added to one without the other being obviously incomplete.
    表示ラベル。ビット表の隣に置くことで、一方だけにモードを追加した
    場合に不備が目に見えるようにします。 }
  MODE_LABELS: array[TRigMode] of string = (
    '---',       { rmUnknown }
    'AM',        'CW',       'USB',      'LSB',      'RTTY',
    'FM',        'WFM',      'CW-R',     'RTTY-R',   'AMS',
    'PKT-LSB',   'PKT-USB',  'PKT-FM',   'ECSS-USB', 'ECSS-LSB',
    'FAX',       'SAM',      'SAL',      'SAH',      'DSB',
    'FM-N',      'PKT-AM',   'P25',      'D-STAR',   'dPMR',
    'NXDN-VN',   'NXDN-N',   'DCR',      'AM-N',     'PSK',
    'PSK-R',     'DD',       'C4FM',     'PKT-FM-N', 'SPEC',
    'CW-N',      'IQ',       'ISB-USB',  'ISB-LSB',
    'USB-D1',    'USB-D2',   'USB-D3',
    'LSB-D1',    'LSB-D2',   'LSB-D3',   'WFM-S'
  );

class function THamlibModeCodec.ToHamlib(AMode: TRigMode): Int64;
begin
  if MODE_BITS[AMode] = MODE_BIT_UNDEFINED then
    Result := 0
  else
    Result := Int64(1) shl MODE_BITS[AMode];
end;

class function THamlibModeCodec.FromHamlib(AValue: Int64): TRigMode;
var
  M: TRigMode;
begin
  Result := rmUnknown;
  if AValue = 0 then Exit;

  { A mask with several bits set is a capability list, not a current
    mode. Refusing to pick one of them keeps the caller from acting on
    an arbitrary choice; SetFromHamlib is the API for that case.

    複数ビットが立ったマスクは能力一覧であって現在のモードではありません。
    そのうちの 1 つを選ばないことで、呼び出し側が任意の選択に基づいて
    動作するのを防ぎます。その用途には SetFromHamlib を使います。 }
  if (AValue and (AValue - 1)) <> 0 then Exit;

  for M := Low(TRigMode) to High(TRigMode) do
    if (MODE_BITS[M] <> MODE_BIT_UNDEFINED)
       and ((Int64(1) shl MODE_BITS[M]) = AValue) then
    begin
      Result := M;
      Exit;
    end;
end;

class function THamlibModeCodec.ToDisplayString(AMode: TRigMode): string;
begin
  Result := MODE_LABELS[AMode];
end;

class function THamlibModeCodec.FormatRaw(AValue: Int64): string;
var
  M: TRigMode;
begin
  M := FromHamlib(AValue);
  if M <> rmUnknown then
    Result := MODE_LABELS[M]
  else if AValue = 0 then
    Result := '---'
  else
    Result := 'Mode($' + HexStr(AValue, 16) + ')';
end;

class function THamlibModeCodec.SetFromHamlib(AValue: Int64): TRigModeSet;
var
  M: TRigMode;
begin
  Result := [];
  for M := Low(TRigMode) to High(TRigMode) do
    if (MODE_BITS[M] <> MODE_BIT_UNDEFINED)
       and ((AValue and (Int64(1) shl MODE_BITS[M])) <> 0) then
      Include(Result, M);
end;

end.
