{
  HamlibLevelCodec.pas

  Level and function codec — the single place that knows which bit of
  Hamlib's 64-bit setting_t corresponds to which level or function, and
  which levels are carried as a float rather than an int.

  レベル・ファンクション コーデック — Hamlib の 64bit setting_t のどの
  ビットがどのレベル・ファンクションに対応するか、そしてどのレベルが
  int ではなく float で運ばれるかを知る唯一の場所です。

  Why this unit exists / 本ユニットの存在理由
  ------------------------------------------------------------------
  rig_get_level and rig_set_level take a value_t, which is a C UNION.
  Whether a given level is read as .i or as .f is not something the
  caller may guess: Hamlib fixes it per level, and reading an int out
  of a float union member yields a number that looks plausible and is
  nonsense. RIG_LEVEL_IS_FLOAT in rig.h is the authority, and
  IsFloatLevel below mirrors that list exactly.

  rig_get_level / rig_set_level は value_t、すなわち C の「共用体」を
  取ります。あるレベルを .i と .f のどちらで読むかは呼び出し側が推測して
  よい事柄ではありません。Hamlib がレベルごとに固定しており、float の
  メンバから int を読むと、もっともらしく見えて無意味な数値になります。
  rig.h の RIG_LEVEL_IS_FLOAT が典拠であり、下記 IsFloatLevel はその
  リストを正確に写しています。

  Layer:    L2
  Depends:  HamlibInterfaces
}
unit HamlibLevelCodec;

{$mode objfpc}{$H+}

interface

uses
  HamlibInterfaces;

type
  THamlibLevelCodec = class
  public
    { Named level to the setting_t bit Hamlib expects. rlvNone gives 0.
      名前付きレベルを Hamlib が期待する setting_t ビットに変換します。
      rlvNone は 0 を返します。 }
    class function ToHamlib(ALevel: TRigLevel): Int64;

    { A setting_t bit back to a named level; rlvNone when unrecognised.
      setting_t のビットを名前付きレベルに戻します。未知なら rlvNone。 }
    class function FromHamlib(AValue: Int64): TRigLevel;

    { True when this level travels in value_t.f rather than value_t.i.
      Mirrors RIG_LEVEL_IS_FLOAT in rig.h.
      このレベルが value_t.i ではなく value_t.f で運ばれるとき True。
      rig.h の RIG_LEVEL_IS_FLOAT を写したものです。 }
    class function IsFloatLevel(ALevel: TRigLevel): Boolean;

    { True when the rig only ever reports this level and cannot be told
      it — a meter. Setting one is a programming error, not a rig
      limitation, so the Service rejects it rather than asking the rig.
      リグが報告するだけで設定できないレベル (メータ類) のとき True。
      設定しようとするのはリグの制限ではなくプログラミングの誤りなので、
      Service はリグに尋ねず拒否します。 }
    class function IsReadOnlyLevel(ALevel: TRigLevel): Boolean;

    { Short label, e.g. 'S-meter', 'RF power'.
      短いラベル。例: 'S-meter'、'RF power'。 }
    class function ToDisplayString(ALevel: TRigLevel): string;

    { Expand a rig's has_get_level / has_set_level mask into the set of
      levels this binding can name.
      リグの has_get_level / has_set_level マスクを、本バインディングが
      名前を付けられるレベルの集合に展開します。 }
    class function SetFromHamlib(AValue: Int64): TRigLevelSet;
  end;

  THamlibFuncCodec = class
  public
    class function ToHamlib(AFunc: TRigFunc): Int64;
    class function FromHamlib(AValue: Int64): TRigFunc;
    class function ToDisplayString(AFunc: TRigFunc): string;
    class function SetFromHamlib(AValue: Int64): TRigFuncSet;
  end;

implementation

uses
  SysUtils;

const
  BIT_UNDEFINED = 255;

  { Bit numbers from Hamlib include/hamlib/rig.h, CONSTANT_64BIT_FLAG(n),
    verified against 4.5.5 and 4.7.2. Bit 31 is RIG_LEVEL_SQLSTAT, which
    rig.h has commented out as deprecated ("use get_dcd instead"), so it
    has no entry here.

    ビット番号は Hamlib の include/hamlib/rig.h の CONSTANT_64BIT_FLAG(n)
    から取得し、4.5.5 と 4.7.2 で照合済み。ビット 31 は
    RIG_LEVEL_SQLSTAT で、rig.h 上で非推奨としてコメントアウトされている
    ため項目がありません。 }
  LEVEL_BITS: array[TRigLevel] of Byte = (
    BIT_UNDEFINED,  { rlvNone }
    0,              { rlvPreamp }
    1,              { rlvAtt }
    2,              { rlvVoxDelay }
    3,              { rlvAf }
    4,              { rlvRf }
    5,              { rlvSql }
    6,              { rlvIfShift }
    7,              { rlvApf }
    8,              { rlvNr }
    9,              { rlvPbtIn }
    10,             { rlvPbtOut }
    11,             { rlvCwPitch }
    12,             { rlvRfPower }
    13,             { rlvMicGain }
    14,             { rlvKeySpeed }
    15,             { rlvNotchF }
    16,             { rlvComp }
    17,             { rlvAgc }
    18,             { rlvBkInDelay }
    19,             { rlvBalance }
    20,             { rlvMeter }
    21,             { rlvVoxGain }
    22,             { rlvAntiVox }
    23,             { rlvSlopeLow }
    24,             { rlvSlopeHigh }
    25,             { rlvBkInDelayMs }
    26,             { rlvRawStrength }
    28,             { rlvSwr }
    29,             { rlvAlc }
    30,             { rlvStrength }
    32,             { rlvRfPowerMeter }
    33,             { rlvCompMeter }
    34,             { rlvVdMeter }
    35,             { rlvIdMeter }
    37,             { rlvMonitorGain }
    38,             { rlvNb }
    39              { rlvRfPowerMeterWatts }
  );

  LEVEL_LABELS: array[TRigLevel] of string = (
    '(none)',
    'Preamp', 'Attenuator', 'VOX delay', 'AF gain', 'RF gain',
    'Squelch', 'IF shift', 'Audio peak filter', 'Noise reduction',
    'PBT in', 'PBT out', 'CW pitch', 'RF power', 'Mic gain',
    'Keyer speed', 'Notch', 'Compression', 'AGC', 'Break-in delay',
    'Balance', 'Meter', 'VOX gain', 'Anti-VOX', 'Slope low',
    'Slope high', 'Break-in delay (ms)', 'Raw S-meter', 'SWR', 'ALC',
    'S-meter', 'Power meter', 'Compression meter', 'Vd meter',
    'Id meter', 'Monitor gain', 'Noise blanker', 'Power meter (W)'
  );

  { RIG_LEVEL_FLOAT_LIST, rig.h line 1026. Everything not listed here
    travels as an int.
    rig.h 1026 行の RIG_LEVEL_FLOAT_LIST。ここに無いものは int で運ばれます。 }
  FLOAT_LEVELS: TRigLevelSet = [
    rlvAf, rlvRf, rlvSql, rlvApf, rlvNr, rlvPbtIn, rlvPbtOut,
    rlvRfPower, rlvMicGain, rlvComp, rlvBalance, rlvSwr, rlvAlc,
    rlvVoxGain, rlvAntiVox, rlvRfPowerMeter, rlvRfPowerMeterWatts,
    rlvCompMeter, rlvVdMeter, rlvIdMeter, rlvMonitorGain, rlvNb
  ];

  { RIG_LEVEL_READONLY_LIST, rig.h line 1028.
    rig.h 1028 行の RIG_LEVEL_READONLY_LIST。 }
  READONLY_LEVELS: TRigLevelSet = [
    rlvSwr, rlvAlc, rlvStrength, rlvRawStrength, rlvRfPowerMeter,
    rlvCompMeter, rlvVdMeter, rlvIdMeter, rlvRfPowerMeterWatts
  ];

  FUNC_BITS: array[TRigFunc] of Byte = (
    BIT_UNDEFINED,  { rfnNone }
    0,              { rfnFastAgc }
    1,              { rfnNoiseBlanker }
    2,              { rfnCompression }
    3,              { rfnVox }
    4,              { rfnTone }
    5,              { rfnToneSql }
    6,              { rfnSemiBreakIn }
    7,              { rfnFullBreakIn }
    8,              { rfnAutoNotch }
    9,              { rfnNoiseReduction }
    12,             { rfnMonitor }
    13,             { rfnManualNotch }
    16,             { rfnLock }
    17,             { rfnMute }
    19,             { rfnReverse }
    20,             { rfnSquelch }
    24,             { rfnRit }
    25,             { rfnAfc }
    26,             { rfnSatMode }
    30,             { rfnTuner }
    31              { rfnXit }
  );

  FUNC_LABELS: array[TRigFunc] of string = (
    '(none)',
    'Fast AGC', 'Noise blanker', 'Speech compression', 'VOX',
    'CTCSS tone', 'CTCSS squelch', 'Semi break-in', 'Full break-in',
    'Auto notch', 'Noise reduction', 'Monitor', 'Manual notch',
    'Lock', 'Mute', 'Reverse split', 'Squelch', 'RIT', 'AFC',
    'Satellite mode', 'Antenna tuner', 'XIT'
  );

{ ============= THamlibLevelCodec ============= }

class function THamlibLevelCodec.ToHamlib(ALevel: TRigLevel): Int64;
begin
  if LEVEL_BITS[ALevel] = BIT_UNDEFINED then
    Result := 0
  else
    Result := Int64(1) shl LEVEL_BITS[ALevel];
end;

class function THamlibLevelCodec.FromHamlib(AValue: Int64): TRigLevel;
var
  L: TRigLevel;
begin
  Result := rlvNone;
  if AValue = 0 then Exit;
  if (AValue and (AValue - 1)) <> 0 then Exit;   { a mask, not one level }

  for L := Low(TRigLevel) to High(TRigLevel) do
    if (LEVEL_BITS[L] <> BIT_UNDEFINED)
       and ((Int64(1) shl LEVEL_BITS[L]) = AValue) then
    begin
      Result := L;
      Exit;
    end;
end;

class function THamlibLevelCodec.IsFloatLevel(ALevel: TRigLevel): Boolean;
begin
  Result := ALevel in FLOAT_LEVELS;
end;

class function THamlibLevelCodec.IsReadOnlyLevel(ALevel: TRigLevel): Boolean;
begin
  Result := ALevel in READONLY_LEVELS;
end;

class function THamlibLevelCodec.ToDisplayString(ALevel: TRigLevel): string;
begin
  Result := LEVEL_LABELS[ALevel];
end;

class function THamlibLevelCodec.SetFromHamlib(AValue: Int64): TRigLevelSet;
var
  L: TRigLevel;
begin
  Result := [];
  for L := Low(TRigLevel) to High(TRigLevel) do
    if (LEVEL_BITS[L] <> BIT_UNDEFINED)
       and ((AValue and (Int64(1) shl LEVEL_BITS[L])) <> 0) then
      Include(Result, L);
end;

{ ============= THamlibFuncCodec ============= }

class function THamlibFuncCodec.ToHamlib(AFunc: TRigFunc): Int64;
begin
  if FUNC_BITS[AFunc] = BIT_UNDEFINED then
    Result := 0
  else
    Result := Int64(1) shl FUNC_BITS[AFunc];
end;

class function THamlibFuncCodec.FromHamlib(AValue: Int64): TRigFunc;
var
  F: TRigFunc;
begin
  Result := rfnNone;
  if AValue = 0 then Exit;
  if (AValue and (AValue - 1)) <> 0 then Exit;

  for F := Low(TRigFunc) to High(TRigFunc) do
    if (FUNC_BITS[F] <> BIT_UNDEFINED)
       and ((Int64(1) shl FUNC_BITS[F]) = AValue) then
    begin
      Result := F;
      Exit;
    end;
end;

class function THamlibFuncCodec.ToDisplayString(AFunc: TRigFunc): string;
begin
  Result := FUNC_LABELS[AFunc];
end;

class function THamlibFuncCodec.SetFromHamlib(AValue: Int64): TRigFuncSet;
var
  F: TRigFunc;
begin
  Result := [];
  for F := Low(TRigFunc) to High(TRigFunc) do
    if (FUNC_BITS[F] <> BIT_UNDEFINED)
       and ((AValue and (Int64(1) shl FUNC_BITS[F])) <> 0) then
      Include(Result, F);
end;

end.
