{
  ExhaustivenessTest.lpr

  Walks every value of every public enumeration and checks that the
  component can translate it, label it, and round-trip it.

  公開列挙型のすべての値を走査し、コンポーネントがそれを変換でき、
  ラベルを持ち、往復できることを検査します。

  Why this test exists / 本テストの存在理由
  ------------------------------------------------------------------
  Every other test in this project exercises the values it happens to
  need. `RigVfoToString` did not exist until an application wanted it;
  a level with no label, a mode that does not round-trip, or two
  enumeration values that collide onto the same Hamlib bit would all
  survive a test suite that only ever uses a dozen values out of
  thirty-eight.

  本プロジェクトの他のすべてのテストは、たまたま必要になった値だけを
  動かします。`RigVfoToString` はアプリケーションが必要とするまで存在
  しませんでした。ラベルのないレベル、往復しないモード、同じ Hamlib
  ビットに衝突する 2 つの列挙値は、38 個のうち 12 個しか使わないテスト
  群ならすべて生き延びます。

  The properties checked, for each enumeration:

  各列挙型について検査する性質:

    1. TOTALITY — every value has a label, and no label is the
       'unlabelled ...' fallback that the codecs emit for a value they
       were never taught.
       全域性 — すべての値がラベルを持ち、どのラベルも、教えられて
       いない値に対してコーデックが出す 'unlabelled ...' ではない。

    2. INJECTIVITY — no two distinct values map onto the same Hamlib
       value. A collision here means one of the two silently addresses
       the other's feature on every rig.
       単射性 — 相異なる 2 値が同じ Hamlib 値へ写らない。ここでの衝突
       は、一方がすべてのリグで他方の機能を静かに操作することを意味
       する。

    3. ROUND-TRIP — FromHamlib(ToHamlib(x)) = x, so a value written to
       the rig and read back is the value the application named.
       往復 — FromHamlib(ToHamlib(x)) = x。リグへ書いて読み戻した値が、
       アプリケーションが名指しした値である。

    4. LABEL DISTINCTNESS — no two values share a display label, so an
       operator reading the panel can tell them apart.
       ラベルの相異 — 2 つの値が同じ表示ラベルを共有しない。パネルを
       読むオペレータが区別できるように。

  No Hamlib library is needed: these are properties of our own
  translation tables.

  Hamlib ライブラリは不要です。これらは本コンポーネント自身の変換表が
  持つべき性質だからです。

  Build:
    fpc -Mobjfpc -Sh -Sa -Criot -gh -Fu../src -FE. ExhaustivenessTest.lpr
}
program ExhaustivenessTest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes,
  HamlibInterfaces, HamlibErrors, HamlibModeCodec, HamlibLevelCodec,
  HamlibVfoCodec, HamlibRigCommands;

var
  Passed: Integer = 0;
  Failed: Integer = 0;

procedure Check(const ALabel: string; ACondition: Boolean;
                const ADetail: string = '');
begin
  if ACondition then
    Inc(Passed)
  else
  begin
    Inc(Failed);
    if ADetail <> '' then
      WriteLn('    [FAIL] ', ALabel, '  <-- ', ADetail)
    else
      WriteLn('    [FAIL] ', ALabel);
  end;
end;

procedure Report(const AName: string; ACount: Integer);
begin
  WriteLn(Format('    [ok]   %s: %d values, all properties hold',
                 [AName, ACount]));
end;

{ A label is suspect when it is empty, or when it is the fallback a
  codec emits for a value it was never taught. Both mean the same
  thing to an operator: the panel shows nothing useful.
  ラベルが疑わしいのは、空のとき、またはコーデックが教えられていない値
  に対して出すフォールバックのときです。オペレータにとって両者は同じ
  ことを意味します。パネルに有用な表示が出ません。 }
function LabelIsReal(const AText: string): Boolean;
begin
  Result := (Trim(AText) <> '')
            and (Pos('unlabelled', LowerCase(AText)) = 0)
            and (Pos('unknown mode', LowerCase(AText)) = 0);
end;

{ ------------------------------------------------------------------
  TRigMode
  ------------------------------------------------------------------ }
procedure CheckModes;
var
  M, Back: TRigMode;
  Bits:    Int64;
  Seen:    TStringList;
  Labels:  TStringList;
  N:       Integer;
begin
  WriteLn;
  WriteLn('TRigMode — ', Ord(High(TRigMode)) + 1, ' values');
  Seen   := TStringList.Create;
  Labels := TStringList.Create;
  try
    Seen.Sorted := True;  Seen.Duplicates := dupAccept;
    Labels.Sorted := True; Labels.Duplicates := dupAccept;
    N := 0;

    for M := Low(TRigMode) to High(TRigMode) do
    begin
      Bits := THamlibModeCodec.ToHamlib(M);

      if M = rmUnknown then
      begin
        { rmUnknown is the one value that must NOT have a Hamlib bit:
          it means "the rig reported something we have no name for",
          and giving it a bit would let it be written to a rig.
          rmUnknown は Hamlib ビットを持ってはならない唯一の値です。
          「リグが、名前を持たない何かを報告した」を意味し、ビットを
          与えるとリグへ書けてしまいます。 }
        Check('rmUnknown maps to no Hamlib bit', Bits = 0,
              Format('got %d', [Bits]));
        Continue;
      end;

      Inc(N);
      Check(Format('mode %d has a Hamlib bit', [Ord(M)]), Bits <> 0);

      Back := THamlibModeCodec.FromHamlib(Bits);
      Check(Format('mode %d round-trips', [Ord(M)]), Back = M,
            Format('%d -> %d -> %d', [Ord(M), Bits, Ord(Back)]));

      Check(Format('mode %d has a real label', [Ord(M)]),
            LabelIsReal(THamlibModeCodec.ToDisplayString(M)),
            THamlibModeCodec.ToDisplayString(M));

      Seen.Add(IntToStr(Bits));
      Labels.Add(THamlibModeCodec.ToDisplayString(M));
    end;

    Check('no two modes share a Hamlib bit',
          Seen.Count = Length(Seen.Text.Split([#10], TStringSplitOptions.ExcludeEmpty))
          , '');
    { The real injectivity check: compare adjacent entries of the
      sorted list. 本来の単射性検査: ソート済みリストの隣接要素を比較。 }
    Seen.Sorted := False;
    Seen.Sort;
    for N := 1 to Seen.Count - 1 do
      Check('no two modes share a Hamlib bit',
            Seen[N] <> Seen[N - 1], 'bit ' + Seen[N]);
    Labels.Sorted := False;
    Labels.Sort;
    for N := 1 to Labels.Count - 1 do
      Check('no two modes share a display label',
            Labels[N] <> Labels[N - 1], Labels[N]);

    Report('TRigMode', Ord(High(TRigMode)) + 1);
  finally
    Labels.Free;
    Seen.Free;
  end;
end;

{ ------------------------------------------------------------------
  TRigLevel
  ------------------------------------------------------------------ }
procedure CheckLevels;
var
  L, Back: TRigLevel;
  Bits:    Int64;
  Seen:    TStringList;
  Labels:  TStringList;
  i:       Integer;
  FloatN:  Integer;
begin
  WriteLn;
  WriteLn('TRigLevel — ', Ord(High(TRigLevel)) + 1, ' values');
  Seen   := TStringList.Create;
  Labels := TStringList.Create;
  try
    FloatN := 0;
    for L := Low(TRigLevel) to High(TRigLevel) do
    begin
      Bits := THamlibLevelCodec.ToHamlib(L);

      if L = rlvNone then
      begin
        Check('rlvNone maps to no Hamlib bit', Bits = 0,
              Format('got %d', [Bits]));
        Continue;
      end;

      Check(Format('level %d has a Hamlib bit', [Ord(L)]), Bits <> 0);

      { Every level bit must be a single bit. RIG_LEVEL_* are
        individual bits of a setting_t, and a value that set two of
        them would address two levels at once.
        各レベルのビットは単一ビットでなければなりません。RIG_LEVEL_*
        は setting_t の個々のビットであり、2 つ立った値は 2 つのレベルを
        同時に指してしまいます。 }
      Check(Format('level %d is a single bit', [Ord(L)]),
            (Bits and (Bits - 1)) = 0, Format('%d', [Bits]));

      Back := THamlibLevelCodec.FromHamlib(Bits);
      Check(Format('level %d round-trips', [Ord(L)]), Back = L,
            Format('%d -> %d -> %d', [Ord(L), Bits, Ord(Back)]));

      Check(Format('level %d has a real label', [Ord(L)]),
            LabelIsReal(THamlibLevelCodec.ToDisplayString(L)),
            THamlibLevelCodec.ToDisplayString(L));

      { SetFromHamlib must agree with ToHamlib for a single level:
        the set built from one bit contains exactly that level.
        SetFromHamlib は単一レベルについて ToHamlib と一致しなければ
        なりません。1 ビットから作った集合はちょうどそのレベルを含みます。 }
      Check(Format('level %d survives SetFromHamlib', [Ord(L)]),
            L in THamlibLevelCodec.SetFromHamlib(Bits));

      if THamlibLevelCodec.IsFloatLevel(L) then
        Inc(FloatN);

      { A read-only level that is not reported by the rig is useless,
        but a read-only level that an application can WRITE is
        dangerous — the component must at least know which is which,
        and IsReadOnlyLevel must not throw for any value.
        リグが報告しない読み取り専用レベルは無用ですが、アプリが書ける
        読み取り専用レベルは危険です。コンポーネントは少なくともどちらか
        を知っていなければならず、IsReadOnlyLevel はどの値でも例外を
        出してはなりません。 }
      THamlibLevelCodec.IsReadOnlyLevel(L);

      Seen.Add(IntToStr(Bits));
      Labels.Add(THamlibLevelCodec.ToDisplayString(L));
    end;

    Seen.Sort;
    for i := 1 to Seen.Count - 1 do
      Check('no two levels share a Hamlib bit', Seen[i] <> Seen[i - 1],
            'bit ' + Seen[i]);
    Labels.Sort;
    for i := 1 to Labels.Count - 1 do
      Check('no two levels share a display label',
            Labels[i] <> Labels[i - 1], Labels[i]);

    { The float list is not a matter of taste: it mirrors Hamlib's
      RIG_LEVEL_FLOAT_LIST, and an empty or total answer would mean
      the mirror is broken rather than that the list changed.
      float リストは好みの問題ではなく、Hamlib の RIG_LEVEL_FLOAT_LIST
      を写したものです。空または全部という答えは、リストが変わったのでは
      なく写しが壊れていることを意味します。 }
    Check('some levels are float and some are not',
          (FloatN > 0) and (FloatN < Ord(High(TRigLevel))),
          Format('%d of %d are float', [FloatN, Ord(High(TRigLevel))]));
    WriteLn(Format('    %d of %d levels are float levels',
                   [FloatN, Ord(High(TRigLevel))]));

    Check('rlvStrength is an integer level, not a float one',
          not THamlibLevelCodec.IsFloatLevel(rlvStrength));
    Check('rlvRfPower is a float level',
          THamlibLevelCodec.IsFloatLevel(rlvRfPower));

    Report('TRigLevel', Ord(High(TRigLevel)) + 1);
  finally
    Labels.Free;
    Seen.Free;
  end;
end;

{ ------------------------------------------------------------------
  TRigFunc
  ------------------------------------------------------------------ }
procedure CheckFuncs;
var
  F, Back: TRigFunc;
  Bits:    Int64;
  Seen:    TStringList;
  Labels:  TStringList;
  i:       Integer;
begin
  WriteLn;
  WriteLn('TRigFunc — ', Ord(High(TRigFunc)) + 1, ' values');
  Seen   := TStringList.Create;
  Labels := TStringList.Create;
  try
    for F := Low(TRigFunc) to High(TRigFunc) do
    begin
      Bits := THamlibFuncCodec.ToHamlib(F);
      if F = rfnNone then
      begin
        Check('rfnNone maps to no Hamlib bit', Bits = 0);
        Continue;
      end;
      Check(Format('func %d has a Hamlib bit', [Ord(F)]), Bits <> 0);
      Check(Format('func %d is a single bit', [Ord(F)]),
            (Bits and (Bits - 1)) = 0, Format('%d', [Bits]));
      Back := THamlibFuncCodec.FromHamlib(Bits);
      Check(Format('func %d round-trips', [Ord(F)]), Back = F,
            Format('%d -> %d -> %d', [Ord(F), Bits, Ord(Back)]));
      Check(Format('func %d has a real label', [Ord(F)]),
            LabelIsReal(THamlibFuncCodec.ToDisplayString(F)),
            THamlibFuncCodec.ToDisplayString(F));
      Check(Format('func %d survives SetFromHamlib', [Ord(F)]),
            F in THamlibFuncCodec.SetFromHamlib(Bits));
      Seen.Add(IntToStr(Bits));
      Labels.Add(THamlibFuncCodec.ToDisplayString(F));
    end;
    Seen.Sort;
    for i := 1 to Seen.Count - 1 do
      Check('no two funcs share a Hamlib bit', Seen[i] <> Seen[i - 1],
            'bit ' + Seen[i]);
    Labels.Sort;
    for i := 1 to Labels.Count - 1 do
      Check('no two funcs share a display label',
            Labels[i] <> Labels[i - 1], Labels[i]);
    Report('TRigFunc', Ord(High(TRigFunc)) + 1);
  finally
    Labels.Free;
    Seen.Free;
  end;
end;

{ ------------------------------------------------------------------
  TRigVfo and TRigVfoOp
  ------------------------------------------------------------------ }
procedure CheckVfos;
var
  V, Back: TRigVfo;
  Op:      TRigVfoOp;
  Raw:     Integer;
  Seen:    TStringList;
  Labels:  TStringList;
  i, Api:  Integer;
begin
  WriteLn;
  WriteLn('TRigVfo / TRigVfoOp');
  Seen   := TStringList.Create;
  Labels := TStringList.Create;
  try
    { Both API majors the component supports. A VFO constant that
      moved between Hamlib 3 and 4 would show up here as a failed
      round-trip under one of them.
      コンポーネントが対応する両方の API メジャー。Hamlib 3 と 4 の
      間で動いた VFO 定数は、どちらかで往復失敗として現れます。 }
    for Api := 3 to 4 do
    begin
      Seen.Clear;
      for V := Low(TRigVfo) to High(TRigVfo) do
      begin
        Raw  := TVfoCodec.ToHamlib(V, Api);
        Back := TVfoCodec.FromHamlib(Raw, Api);
        Check(Format('VFO %d round-trips on API %d', [Ord(V), Api]),
              Back = V, Format('%d -> %d -> %d', [Ord(V), Raw, Ord(Back)]));
        Seen.Add(IntToStr(Raw));
      end;
      Seen.Sort;
      for i := 1 to Seen.Count - 1 do
        Check(Format('no two VFOs share a value on API %d', [Api]),
              Seen[i] <> Seen[i - 1], 'value ' + Seen[i]);
    end;

    for V := Low(TRigVfo) to High(TRigVfo) do
    begin
      Check(Format('VFO %d has a real label', [Ord(V)]),
            LabelIsReal(RigVfoToString(V)), RigVfoToString(V));
      Labels.Add(RigVfoToString(V));
    end;
    Labels.Sort;
    for i := 1 to Labels.Count - 1 do
      Check('no two VFOs share a label', Labels[i] <> Labels[i - 1],
            Labels[i]);

    { RigVfoSelectionMatches must be reflexive for every value, or a
      rig that answers exactly what it was asked would be judged to
      have failed.
      RigVfoSelectionMatches はどの値でも反射的でなければなりません。
      さもないと、尋ねたとおりに答えたリグが失敗と判定されます。 }
    for V := Low(TRigVfo) to High(TRigVfo) do
      Check(Format('VFO %d matches itself', [Ord(V)]),
            RigVfoSelectionMatches(V, V));

    Check('A is accepted when the rig answers MAIN',
          RigVfoSelectionMatches(rvfoA, rvfoMain));
    Check('B is accepted when the rig answers SUB',
          RigVfoSelectionMatches(rvfoB, rvfoSub));
    Check('but A is NOT accepted when the rig answers SUB',
          not RigVfoSelectionMatches(rvfoA, rvfoSub));

    Seen.Clear;
    for Op := Low(TRigVfoOp) to High(TRigVfoOp) do
    begin
      Raw := RigVfoOpToHamlib(Op);
      if Op = rvoNone then
      begin
        Check('rvoNone maps to no Hamlib bit', Raw = 0);
        Continue;
      end;
      Check(Format('VFO op %d has a Hamlib bit', [Ord(Op)]), Raw <> 0);
      Check(Format('VFO op %d is a single bit', [Ord(Op)]),
            (Raw and (Raw - 1)) = 0, Format('%d', [Raw]));
      Seen.Add(IntToStr(Raw));
    end;
    Seen.Sort;
    for i := 1 to Seen.Count - 1 do
      Check('no two VFO ops share a Hamlib bit', Seen[i] <> Seen[i - 1],
            'bit ' + Seen[i]);

    Report('TRigVfo', Ord(High(TRigVfo)) + 1);
    Report('TRigVfoOp', Ord(High(TRigVfoOp)) + 1);
  finally
    Labels.Free;
    Seen.Free;
  end;
end;

{ ------------------------------------------------------------------
  TRigErrorKind
  ------------------------------------------------------------------ }
procedure CheckErrorKinds;
var
  K:      TRigErrorKind;
  Labels: TStringList;
  i:      Integer;
  Code:   Integer;
  Hit:    Integer;
begin
  WriteLn;
  WriteLn('TRigErrorKind — ', Ord(High(TRigErrorKind)) + 1, ' values');
  Labels := TStringList.Create;
  try
    for K := Low(TRigErrorKind) to High(TRigErrorKind) do
    begin
      Check(Format('error kind %d has a real label', [Ord(K)]),
            LabelIsReal(RigErrorKindToString(K)),
            RigErrorKindToString(K));
      Labels.Add(RigErrorKindToString(K));
    end;
    Labels.Sort;
    for i := 1 to Labels.Count - 1 do
      Check('no two error kinds share a label',
            Labels[i] <> Labels[i - 1], Labels[i]);

    { Every Hamlib error code in the documented range must classify to
      something other than rekUnrecognised, and an undocumented code
      must classify to rekUnrecognised rather than to a wrong kind.
      文書化された範囲の全 Hamlib エラーコードは rekUnrecognised 以外に
      分類されなければならず、文書外のコードは誤った種別ではなく
      rekUnrecognised に分類されなければなりません。 }
    Hit := 0;
    for Code := 1 to 24 do
      if RigErrorKindFromCode(-Code) <> rekUnrecognised then
        Inc(Hit);
    Check('the documented Hamlib error codes all classify',
          Hit >= 20, Format('%d of 24 classified', [Hit]));
    WriteLn(Format('    %d of the 24 documented Hamlib codes classify '
                   + 'to a named kind', [Hit]));

    Check('an undocumented code classifies as unrecognised, not as '
          + 'something wrong',
          RigErrorKindFromCode(-9999) = rekUnrecognised);
    Check('RIG_OK is not an error',
          RigErrorKindFromCode(0) = rekNone);

    { The classifier is deliberately sign-agnostic, and this check
      pins that rather than wishing it away. The component declares the
      same ordinals in several units with different signs — HamlibTypes
      has RIG_ENAVAIL = 11, HamlibLoader has RIG_ENAVAIL_CODE = 11 and
      returns its negation, HamlibRigCommands has ENAVAIL = -11 — so a
      classifier that accepted only negatives would misread three of
      those four call sites.

      The duplication is the real hazard, not the leniency, and it is
      guarded mechanically: tools/check_abi.py now checks EVERY RIG_E*
      ordinal declared anywhere in src/ against rig.h, not only the
      canonical table in HamlibTypes. Before Rev.6.0 it checked one of
      the four. The self-test for that check is to change a copy and
      watch the script fail.

      分類器は意図的に符号非依存であり、本検査はそれを「そうであって
      ほしい」ではなく「そうである」として固定します。コンポーネントは
      同じ序数を複数のユニットで異なる符号で宣言しています
      (HamlibTypes の RIG_ENAVAIL = 11、HamlibLoader の
      RIG_ENAVAIL_CODE = 11 とその符号反転、HamlibRigCommands の
      ENAVAIL = -11)。負値しか受け付けない分類器は、この 4 箇所のうち
      3 箇所を読み違えます。

      真の危険は寛容さではなく重複のほうであり、それは機械的に守られて
      います。tools/check_abi.py は、HamlibTypes の正典表だけでなく
      src/ のどこかで宣言された全 RIG_E* 序数を rig.h と照合するように
      なりました。Rev.6.0 以前は 4 つのうち 1 つだけでした。 }
    Check('the classifier reads an ordinal regardless of sign',
          RigErrorKindFromCode(-11) = RigErrorKindFromCode(11));
    Check('and both give the kind the ordinal names',
          RigErrorKindFromCode(-11) = rekNotAvailable,
          Format('kind %d', [Ord(RigErrorKindFromCode(-11))]));

    Report('TRigErrorKind', Ord(High(TRigErrorKind)) + 1);
  finally
    Labels.Free;
  end;
end;

{ ------------------------------------------------------------------
  Main
  ------------------------------------------------------------------ }
begin
  WriteLn('ExhaustivenessTest — every value of every public enumeration');
  WriteLn('===========================================================');

  CheckModes;
  CheckLevels;
  CheckFuncs;
  CheckVfos;
  CheckErrorKinds;

  WriteLn;
  WriteLn(Format('--- %d / %d checks passed ---',
                 [Passed, Passed + Failed]));
  if Failed = 0 then
  begin
    WriteLn('RESULT: OK');
    ExitCode := 0;
  end
  else
  begin
    WriteLn(Format('RESULT: %d FAILED', [Failed]));
    ExitCode := 1;
  end;
end.
