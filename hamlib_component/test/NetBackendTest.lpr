{
  NetBackendTest.lpr

  Opens the component against RIG_MODEL_NETRIGCTL (model 2) talking to
  a running rigctld, instead of the dummy backend it has always been
  tested with.

  本コンポーネントを、常に使ってきたダミーバックエンドではなく、稼働中の
  rigctld に対する RIG_MODEL_NETRIGCTL (モデル 2) で開きます。

  Why / 理由
  ------------------------------------------------------------------
  Every test so far has opened model 1 with an empty port. That
  exercises one backend and one transport, and it is the transport
  that does the least: the dummy answers in the same process with no
  I/O at all. Two things therefore remained untested:

    - the port string. Model 2 takes "host:port", not a device path,
      and the component has only ever been given '' or a /dev name.
      A component that silently mangled the port would have passed
      every previous test.

    - a backend whose calls can actually fail mid-sequence, because
      there is a socket between the call and the answer.

  これまでのテストはすべて、空のポートでモデル 1 を開いていました。
  それが動かすのはバックエンド 1 つとトランスポート 1 つであり、しかも
  そのトランスポートは最も仕事をしないものです。ダミーは同一プロセス内
  で、I/O を一切伴わずに答えます。したがって 2 点が未検査のままでした。

    - ポート文字列。モデル 2 が取るのはデバイスパスではなく
      "host:port" であり、コンポーネントには '' か /dev 名しか与えた
      ことがありませんでした。ポートを静かに壊すコンポーネントは、
      これまでのすべてのテストに合格していたはずです。

    - 呼び出しと答えの間にソケットがあるために、本当に途中で失敗
      しうるバックエンド。

  This test is skipped, not failed, when no rigctld is listening: it
  is a test of the component, not of the operator's environment.

  rigctld が待ち受けていない場合、本テストは失敗ではなくスキップします。
  これはコンポーネントのテストであって、実行環境のテストではありません。

  Usage:
    rigctld -m 1 -t 4598 &
    ./NetBackendTest 127.0.0.1:4598
}
program NetBackendTest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  HamlibInterfaces, HamlibErrors, HamlibVfoCodec, HamlibTimeoutPolicy,
  HamlibService, HamlibFactory;

const
  { RIG_MODEL_NETRIGCTL. Hamlib's own backend that speaks the rigctld
    protocol over TCP — the same path every non-C application uses.
    RIG_MODEL_NETRIGCTL。rigctld プロトコルを TCP で話す Hamlib 自身の
    バックエンドであり、C 以外のすべてのアプリケーションが通る経路です。 }
  MODEL_NETRIGCTL = 2;

var
  Passed: Integer = 0;
  Failed: Integer = 0;

procedure Check(const ALabel: string; ACondition: Boolean;
                const ADetail: string = '');
begin
  if ACondition then
  begin
    Inc(Passed);
    WriteLn('    [ok]   ', ALabel);
  end
  else
  begin
    Inc(Failed);
    if ADetail <> '' then
      WriteLn('    [FAIL] ', ALabel, '  <-- ', ADetail)
    else
      WriteLn('    [FAIL] ', ALabel);
  end;
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

type
  THarness = class
    GotFreq:  Boolean;
    GotMode:  Boolean;
    GotSplit: Boolean;
    GotVfo:   Boolean;
    GotLevel: Boolean;
    Freq:     TRigFreqResult;
    Mode:     TRigModeResult;
    Split:    TRigSplitResult;
    Vfo:      TRigVfoResult;
    Level:    TRigLevelResult;
    procedure OnFreq(const R: TRigFreqResult);
    procedure OnMode(const R: TRigModeResult);
    procedure OnSplit(const R: TRigSplitResult);
    procedure OnVfo(const R: TRigVfoResult);
    procedure OnLevel(const R: TRigLevelResult);
  end;

procedure THarness.OnFreq(const R: TRigFreqResult);
begin Freq := R; GotFreq := True; end;
procedure THarness.OnMode(const R: TRigModeResult);
begin Mode := R; GotMode := True; end;
procedure THarness.OnSplit(const R: TRigSplitResult);
begin Split := R; GotSplit := True; end;
procedure THarness.OnVfo(const R: TRigVfoResult);
begin Vfo := R; GotVfo := True; end;
procedure THarness.OnLevel(const R: TRigLevelResult);
begin Level := R; GotLevel := True; end;

var
  Factory: IRigServiceFactory;
  Svc:     IRigService;
  H:       THarness;
  Port:    string;
  St:      TRigState;
  Opened:  Boolean;

begin
  WriteLn('NetBackendTest — the component over TCP, against model 2');
  WriteLn('========================================================');

  if ParamCount < 1 then
    Port := '127.0.0.1:4598'
  else
    Port := ParamStr(1);
  WriteLn('    port string: "', Port, '"');

  Factory := TRigServiceFactory.Create;
  Svc     := Factory.CreateService;
  H       := THarness.Create;
  try
    Svc.ApplyTimeoutPolicy(RigPolicy_SlowCat);

    Opened := False;
    try
      Svc.Open(MODEL_NETRIGCTL, Port);
      Opened := True;
    except
      on E: Exception do
      begin
        { No server, or it refused. Report and stop — a missing rigctld
          is not a defect in the component.
          サーバがない、または拒否された。報告して終了します。rigctld が
          無いことはコンポーネントの欠陥ではありません。 }
        WriteLn;
        WriteLn('    SKIPPED: could not reach rigctld at "', Port, '"');
        WriteLn('             (', E.ClassName, ': ', E.Message, ')');
        WriteLn('    Start one with:  rigctld -m 1 -t 4598 &');
        WriteLn;
        WriteLn('RESULT: SKIPPED');
        ExitCode := 0;
        H.Free;
        Svc := nil; Factory := nil;
        Halt(0);
      end;
    end;

    Check('the component opened a NETWORK backend', Opened and Svc.IsOpen);

    { The port string survived. A component that split on ':' and kept
      only the host, or that treated the string as a device path, would
      have failed to open at all — so reaching here already proves it,
      and LibraryStatus is checked so the proof is recorded rather than
      implied.
      ポート文字列が壊れずに届いたこと。':' で分割してホストだけを残す、
      あるいはデバイスパスとして扱うコンポーネントは、そもそも開けません。
      したがってここに到達した時点で証明されています。暗黙ではなく記録と
      して残すため LibraryStatus も確認します。 }
    Check('and reports the library it used',
          Svc.LibraryStatus.VersionText <> '');
    WriteLn('    ', Svc.LibraryStatus.VersionText);

    Pump(300);

    { ---- the same operations, now with a socket in the way ---- }
    WriteLn;
    WriteLn('OPERATIONS over TCP');

    Svc.SetFrequencyAsync(18100000);
    Pump(500);
    H.GotFreq := False;
    Svc.GetFrequencyAsync(rvfoCurr, @H.OnFreq);
    Pump(800);
    Check('a frequency round-trips over the network backend',
          H.GotFreq and (H.Freq.Status = rcsSuccess)
          and (Abs(H.Freq.Freq - 18100000) < 1.0),
          Format('%.0f', [H.Freq.Freq]));

    Svc.SetModeAsync(rmCW, 500);
    Pump(500);
    H.GotMode := False;
    Svc.GetModeAsync(rvfoCurr, @H.OnMode);
    Pump(800);
    Check('a mode round-trips over the network backend',
          H.GotMode and (H.Mode.Status = rcsSuccess)
          and (H.Mode.Mode = rmCW),
          Format('mode %d passband %d', [Ord(H.Mode.Mode), H.Mode.Passband]));

    Svc.SetVfoAsync(rvfoB);
    Pump(500);
    H.GotVfo := False;
    Svc.GetVfoAsync(@H.OnVfo);
    Pump(800);
    Check('a VFO selection round-trips over the network backend',
          H.GotVfo and (H.Vfo.Status = rcsSuccess)
          and RigVfoSelectionMatches(rvfoB, H.Vfo.Vfo),
          Format('enum %d raw $%s', [Ord(H.Vfo.Vfo),
                                     HexStr(H.Vfo.RawVfo, 8)]));

    Svc.SetSplitAsync(True, rvfoB);
    Pump(500);
    Svc.SetSplitFreqAsync(18160000);
    Pump(500);
    H.GotSplit := False;
    Svc.GetSplitAsync(@H.OnSplit);
    Pump(800);
    Check('split works over the network backend',
          H.GotSplit and (H.Split.Status = rcsSuccess) and H.Split.SplitOn,
          Format('status %d', [Ord(H.Split.Status)]));
    Check('and carries the transmit frequency back',
          Abs(H.Split.TxFreq - 18160000) < 1.0,
          Format('%.0f', [H.Split.TxFreq]));

    H.GotLevel := False;
    Svc.GetLevelAsync(rlvStrength, @H.OnLevel);
    Pump(800);
    Check('a level reads over the network backend',
          H.GotLevel and (H.Level.Status = rcsSuccess),
          Format('status %d %s', [Ord(H.Level.Status), H.Level.ErrorMsg]));
    Check('and comes back as an integer, not a float',
          H.GotLevel and (not H.Level.IsFloat));

    { Polling across a socket is the case the poller has never seen.
      ソケット越しのポーリングは、ポーラが一度も見ていない事例です。 }
    Svc.EnablePolling(200);
    Pump(1200);
    Svc.DisablePolling;
    Pump(300);
    St := Svc.CurrentState;
    Check('polling fills the snapshot over the network backend',
          St.CurrentFreq > 0, Format('%.0f', [St.CurrentFreq]));
    Check('and the circuit breaker stayed closed',
          not Svc.CircuitBreakerOpen);

    Svc.SetSplitAsync(False);
    Pump(400);

    Svc.Close;
    Check('the network backend closed cleanly', not Svc.IsOpen);
  finally
    H.Free;
    Svc     := nil;
    Factory := nil;
  end;

  WriteLn;
  WriteLn(Format('--- %d / %d checks passed ---', [Passed, Passed + Failed]));
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
