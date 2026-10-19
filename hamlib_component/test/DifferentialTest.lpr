{
  DifferentialTest.lpr

  Runs a fixed sequence of operations through the component and prints
  each result in a normalised form, so an external oracle — Hamlib's
  own rigctld — can be made to run the identical sequence and the two
  answers compared.

  固定された一連の操作をコンポーネント経由で実行し、各結果を正規化した
  形で出力します。外部オラクル (Hamlib 自身の rigctld) に同一の順序を
  実行させ、両者の答えを比較できるようにするためです。

  Why an external oracle / 外部オラクルが必要な理由
  ------------------------------------------------------------------
  Every other test in this project checks the component against our own
  understanding of Hamlib. That is a closed loop: a misreading of the C
  API produces a test that asserts the misreading, and the suite goes
  green. The only way out of the loop is to compare against something
  that was written independently of us and that is authoritative about
  what Hamlib means — which is Hamlib's own reference client.

  本プロジェクトの他のすべてのテストは、コンポーネントを「我々の Hamlib
  理解」と照合します。これは閉じた環です。C API の読み違いは、その読み
  違いを主張するテストを生み、テスト群は緑になります。環から出る唯一の
  方法は、我々と独立に書かれ、かつ Hamlib の意味について権威を持つもの
  と比較することです。それが Hamlib 自身の参照クライアントです。

  Output format / 出力形式
  ------------------------------------------------------------------
  One line per step:

      <step-id>|<value>

  where <value> is either the normalised reading or 'RPRT <code>' with
  the native Hamlib code, exactly as rigctld reports a failure. The
  comparison is done by tools/differential.py.

  1 ステップ 1 行。<value> は正規化した読み値、または失敗時は rigctld が
  報告するのと同じ 'RPRT <コード>' (Hamlib のネイティブコード付き) です。
  比較は tools/differential.py が行います。

  Build:
    fpc -Mobjfpc -Sh -Sa -Criot -gh -Fu../src -FE. DifferentialTest.lpr
}
program DifferentialTest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  HamlibInterfaces, HamlibErrors, HamlibModeCodec, HamlibTimeoutPolicy,
  HamlibService, HamlibFactory;

const
  MODEL_DUMMY = 1;

{ ------------------------------------------------------------------
  Normalisation. rigctld prints VFOs as VFOA / VFOB / Main / Sub, and
  modes as Hamlib's own mode strings. The component uses its own
  domain values, so one of the two has to be translated into the
  other's vocabulary — and it must be ours, because translating
  rigctld's output into our vocabulary would use the very translation
  table under test.

  正規化。rigctld は VFO を VFOA / VFOB / Main / Sub、モードを Hamlib
  自身のモード文字列で出力します。コンポーネントは独自のドメイン値を
  使うため、どちらかを他方の語彙へ翻訳する必要があります。そしてそれは
  我々の側でなければなりません。rigctld の出力を我々の語彙へ翻訳すると、
  まさに検査対象の変換表を使うことになるからです。
  ------------------------------------------------------------------ }
function VfoAsRigctl(AVfo: TRigVfo): string;
begin
  case AVfo of
    rvfoA:    Result := 'VFOA';
    rvfoB:    Result := 'VFOB';
    rvfoMain: Result := 'Main';
    rvfoSub:  Result := 'Sub';
    rvfoCurr: Result := 'currVFO';
  else
    Result := 'UNKNOWN';
  end;
end;

{ ------------------------------------------------------------------
  A harness that turns an asynchronous call into one printed line.
  非同期呼び出しを 1 行の出力に変えるハーネス。
  ------------------------------------------------------------------ }
type
  THarness = class
    Done:    Boolean;
    Status:  TRigCommandStatus;
    Native:  Integer;
    Text:    string;
    procedure OnCommand(const R: TRigResult);
    procedure OnFreq(const R: TRigFreqResult);
    procedure OnMode(const R: TRigModeResult);
    procedure OnLevel(const R: TRigLevelResult);
    procedure OnFunc(const R: TRigFuncResult);
    procedure OnSplit(const R: TRigSplitResult);
    procedure OnVfo(const R: TRigVfoResult);
    procedure Reset;
  end;

var
  H: THarness;

procedure THarness.Reset;
begin
  Done   := False;
  Status := rcsSuccess;
  Native := 0;
  Text   := '';
end;

procedure THarness.OnCommand(const R: TRigResult);
begin
  Status := R.Status; Native := R.NativeCode; Text := 'RPRT 0'; Done := True;
end;

procedure THarness.OnFreq(const R: TRigFreqResult);
begin
  Status := R.Status; Native := R.NativeCode;
  Text   := Format('%.0f', [R.Freq]);
  Done   := True;
end;

procedure THarness.OnMode(const R: TRigModeResult);
begin
  Status := R.Status; Native := R.NativeCode;
  Text   := Format('%s|%d',
                   [THamlibModeCodec.ToDisplayString(R.Mode), R.Passband]);
  Done   := True;
end;

procedure THarness.OnLevel(const R: TRigLevelResult);
begin
  Status := R.Status; Native := R.NativeCode;
  if R.IsFloat then
    Text := Format('%.6f', [R.FloatValue])
  else
    Text := IntToStr(R.IntValue);
  Done := True;
end;

procedure THarness.OnFunc(const R: TRigFuncResult);
begin
  Status := R.Status; Native := R.NativeCode;
  if R.Active then Text := '1' else Text := '0';
  Done := True;
end;

procedure THarness.OnSplit(const R: TRigSplitResult);
begin
  Status := R.Status; Native := R.NativeCode;
  if R.SplitOn then
    Text := '1|' + VfoAsRigctl(R.TxVfo)
  else
    Text := '0|' + VfoAsRigctl(R.TxVfo);
  Done := True;
end;

procedure THarness.OnVfo(const R: TRigVfoResult);
begin
  Status := R.Status; Native := R.NativeCode;
  Text   := VfoAsRigctl(R.Vfo);
  Done   := True;
end;

procedure Pump(AMs: Integer);
var
  i: Integer;
begin
  for i := 1 to AMs div 10 do
  begin
    CheckSynchronize(5);
    Sleep(5);
  end;
end;

{ Waits for the harness and prints the step. A failure is printed the
  way rigctld prints one, so the comparator does not have to know two
  error vocabularies.
  ハーネスを待ってステップを出力します。失敗は rigctld と同じ形で出力し、
  比較器が 2 つのエラー語彙を知らなくて済むようにします。 }
procedure Emit(const AStepId: string);
var
  i: Integer;
begin
  i := 0;
  while (not H.Done) and (i < 200) do
  begin
    Pump(10);
    Inc(i);
  end;

  if not H.Done then
  begin
    WriteLn(AStepId, '|TIMEOUT-NO-CALLBACK');
    Exit;
  end;

  if H.Status = rcsSuccess then
    WriteLn(AStepId, '|', H.Text)
  else
    WriteLn(AStepId, '|RPRT ', H.Native);
end;

var
  Factory: IRigServiceFactory;
  Svc:     IRigService;

begin
  Factory := TRigServiceFactory.Create;
  Svc     := Factory.CreateService;
  H       := THarness.Create;
  try
    Svc.ApplyTimeoutPolicy(RigPolicy_FastUsb);
    Svc.Open(MODEL_DUMMY, '');

    { The sequence. It must match tools/differential.py step for step,
      including the order, because the dummy backend's answers depend
      on the state built by the steps before them — the S-meter reading
      changes with the frequency that was set.

      この順序は tools/differential.py と 1 ステップずつ一致しなければ
      なりません。順序も含めてです。ダミーバックエンドの答えは、それ
      以前のステップが作った状態に依存します。S メータの読み値は設定
      した周波数によって変わります。 }

    H.Reset; Svc.SetFrequencyAsync(14205000, rvfoCurr, @H.OnCommand);
    Emit('01-set-freq');

    H.Reset; Svc.GetFrequencyAsync(rvfoCurr, @H.OnFreq);
    Emit('02-get-freq');

    H.Reset; Svc.SetModeAsync(rmUSB, 2400, rvfoCurr, @H.OnCommand);
    Emit('03-set-mode');

    H.Reset; Svc.GetModeAsync(rvfoCurr, @H.OnMode);
    Emit('04-get-mode');

    H.Reset; Svc.SetVfoAsync(rvfoB, @H.OnCommand);
    Emit('05-set-vfo');

    H.Reset; Svc.GetVfoAsync(@H.OnVfo);
    Emit('06-get-vfo');

    H.Reset; Svc.SetSplitAsync(True, rvfoB, @H.OnCommand);
    Emit('07-set-split');

    H.Reset; Svc.GetSplitAsync(@H.OnSplit);
    Emit('08-get-split');

    H.Reset; Svc.SetSplitFreqAsync(14250000, @H.OnCommand);
    Emit('09-set-split-freq');

    H.Reset; Svc.GetSplitAsync(@H.OnSplit);
    Emit('10-get-split-again');

    H.Reset; Svc.GetLevelAsync(rlvStrength, @H.OnLevel);
    Emit('11-get-strength');

    H.Reset; Svc.SetLevelFloatAsync(rlvRfPower, 0.42, @H.OnCommand);
    Emit('12-set-rfpower');

    H.Reset; Svc.GetLevelAsync(rlvRfPower, @H.OnLevel);
    Emit('13-get-rfpower');

    H.Reset; Svc.SetFuncAsync(rfnNoiseBlanker, True, @H.OnCommand);
    Emit('14-set-nb');

    H.Reset; Svc.GetFuncAsync(rfnNoiseBlanker, @H.OnFunc);
    Emit('15-get-nb');

    { The step that matters most. rigctld answers RPRT -16 here, and
      a component that quietly reported success would be hiding a
      refusal from the application.
      最も重要なステップ。rigctld はここで RPRT -16 を返します。黙って
      成功を報告するコンポーネントは、拒否をアプリケーションから隠して
      いることになります。 }
    H.Reset; Svc.VfoOpAsync(rvoToggle, @H.OnCommand);
    Emit('16-vfo-op-toggle');

    H.Reset; Svc.GetVfoAsync(@H.OnVfo);
    Emit('17-get-vfo-again');

    H.Reset; Svc.SetLevelIntAsync(rlvKeySpeed, 27, @H.OnCommand);
    Emit('18-set-keyspeed');

    H.Reset; Svc.GetLevelAsync(rlvKeySpeed, @H.OnLevel);
    Emit('19-get-keyspeed');

    H.Reset; Svc.SetSplitAsync(False, rvfoCurr, @H.OnCommand);
    Emit('20-split-off');

    H.Reset; Svc.GetSplitAsync(@H.OnSplit);
    Emit('21-get-split-off');

    Svc.Close;
  finally
    H.Free;
    Svc     := nil;
    Factory := nil;
  end;
end.
