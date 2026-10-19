{
  SoakTest.lpr

  Runs the component continuously for a long time and watches the
  resources the leak trace cannot see.

  コンポーネントを長時間連続運転し、リークトレースでは見えない資源を
  監視します。

  Why heaptrc is not enough / heaptrc では足りない理由
  ------------------------------------------------------------------
  `-gh` reports Pascal heap blocks that were allocated and never freed,
  at exit. It says nothing about:

    - file descriptors (a port opened per connect and never closed
      shows up as a process that dies at 1024 open files, hours in)
    - threads (a worker or watchdog that is created per Open and never
      joined)
    - resident memory that grows without unfreed *blocks* — a list that
      is appended to forever and freed correctly at exit is a leak to
      the operator and not a leak to heaptrc
    - throughput that degrades as a queue, a string list or a cache
      grows

  Each of those is invisible in a test that runs for two seconds and
  obvious in one that runs for twenty minutes.

  `-gh` は終了時に、確保されたまま解放されなかった Pascal ヒープ
  ブロックを報告します。しかし次については何も言いません。

    - ファイルディスクリプタ (接続のたびに開かれ閉じられないポートは、
      数時間後に「開いているファイルが 1024 で死ぬプロセス」として
      現れます)
    - スレッド (Open のたびに生成され join されないワーカーや
      ウォッチドッグ)
    - 未解放「ブロック」を伴わずに増える常駐メモリ (永遠に追記され、
      終了時には正しく解放されるリストは、オペレータにとってはリーク
      であり、heaptrc にとってはリークではありません)
    - キューや文字列リストやキャッシュが育つにつれ劣化するスループット

  いずれも 2 秒のテストでは見えず、20 分のテストでは明らかになります。

  What it does / 動作
  ------------------------------------------------------------------
  Open / poll / issue a mix of commands / Close, repeatedly, sampling
  RSS, open file descriptors and thread count once per cycle. It fails
  if any of them grows monotonically across the run rather than
  settling.

  Open / ポーリング / 各種コマンド発行 / Close を繰り返し、1 周ごとに
  RSS、開いている FD 数、スレッド数を採取します。いずれかが安定せず
  単調に増え続ける場合は失敗とします。

  Usage:
    ./SoakTest [minutes]        default 15 / 既定 15 分
}
program SoakTest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads, BaseUnix,{$ENDIF}
  Classes, SysUtils, Math,
  HamlibInterfaces, HamlibErrors, HamlibTimeoutPolicy,
  HamlibService, HamlibFactory;

const
  MODEL_DUMMY = 1;

type
  TSample = record
    Cycle:   Integer;
    RssKb:   Int64;
    Fds:     Integer;
    Threads: Integer;
    Elapsed: QWord;
  end;

var
  Samples:     array of TSample;
  SampleCount: Integer = 0;
  Sink:        Integer = 0;

{ ------------------------------------------------------------------
  Reading the process's own resource use from /proc. Linux-only, which
  is why the whole program is guarded: a soak test that silently
  measures nothing on another platform is worse than one that says it
  cannot run.

  /proc から自プロセスの資源使用量を読みます。Linux 専用であり、だから
  プログラム全体をガードしています。他のプラットフォームで黙って何も
  測定しないソークテストは、動かせないと述べるものより悪いからです。
  ------------------------------------------------------------------ }

function ReadStatusField(const AName: string): Int64;
var
  F:    TextFile;
  Line: string;
  P:    Integer;
begin
  Result := -1;
  if not FileExists('/proc/self/status') then
    Exit;
  AssignFile(F, '/proc/self/status');
  Reset(F);
  try
    while not Eof(F) do
    begin
      ReadLn(F, Line);
      if Copy(Line, 1, Length(AName)) = AName then
      begin
        P := Pos(':', Line);
        Line := Trim(Copy(Line, P + 1, MaxInt));
        P := Pos(' ', Line);
        if P > 0 then
          Line := Copy(Line, 1, P - 1);
        Result := StrToInt64Def(Trim(Line), -1);
        Exit;
      end;
    end;
  finally
    CloseFile(F);
  end;
end;

function CountFds: Integer;
var
  Rec: TSearchRec;
begin
  Result := 0;
  if FindFirst('/proc/self/fd/*', faAnyFile, Rec) = 0 then
  begin
    repeat
      if (Rec.Name <> '.') and (Rec.Name <> '..') then
        Inc(Result);
    until FindNext(Rec) <> 0;
    FindClose(Rec);
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

{ A callback that does nothing but prove the result arrived. Kept as a
  class so the method pointer is real.
  結果が届いたことを示すだけのコールバック。メソッドポインタを実体化
  するためクラスにしています。 }
type
  TCounter = class
    procedure OnResult(const AResult: TRigResult);
    procedure OnFreq(const AResult: TRigFreqResult);
    procedure OnLevel(const AResult: TRigLevelResult);
  end;

procedure TCounter.OnResult(const AResult: TRigResult);
begin
  Inc(Sink);
end;

procedure TCounter.OnFreq(const AResult: TRigFreqResult);
begin
  Inc(Sink);
end;

procedure TCounter.OnLevel(const AResult: TRigLevelResult);
begin
  Inc(Sink);
end;

{ ------------------------------------------------------------------
  One cycle: a whole session's worth of work.
  1 周: 1 セッション分の作業。
  ------------------------------------------------------------------ }
procedure RunCycle(const AFactory: IRigServiceFactory; ACounter: TCounter;
                   ACycle: Integer);
var
  Svc: IRigService;
  i:   Integer;
begin
  Svc := AFactory.CreateService;
  try
    Svc.ApplyTimeoutPolicy(RigPolicy_FastUsb);
    Svc.AddConfToken('ptt_type', 'RIG');
    Svc.Open(MODEL_DUMMY, '');
    Svc.EnablePolling(50);

    for i := 1 to 20 do
    begin
      Svc.SetFrequencyAsync(14000000 + i * 1000, rvfoA, @ACounter.OnResult);
      Svc.GetFrequencyAsync(rvfoCurr, @ACounter.OnFreq);
      Svc.GetLevelAsync(rlvStrength, @ACounter.OnLevel);
      Svc.SetSplitAsync(True, rvfoB, @ACounter.OnResult);
      Svc.SetSplitFreqAsync(14200000 + i * 100, @ACounter.OnResult);
      Svc.SetLevelFloatAsync(rlvRfPower, (i mod 10) / 10.0,
                             @ACounter.OnResult);
      Svc.SetFuncAsync(rfnNoiseBlanker, Odd(i), @ACounter.OnResult);
      Svc.VfoOpAsync(rvoToggle, @ACounter.OnResult);
      Svc.SetSplitAsync(False, rvfoCurr, @ACounter.OnResult);
      Pump(40);
    end;

    { Every fourth cycle, leave without closing. The destructor is
      supposed to defend itself; a soak run is where a destructor that
      leaks a thread or a descriptor per session becomes visible.
      4 周に 1 度は Close せずに離脱します。デストラクタは自己防衛する
      はずです。セッションごとにスレッドや FD を漏らすデストラクタは、
      ソーク運転でこそ姿を現します。 }
    if (ACycle mod 4) <> 0 then
    begin
      Svc.DisablePolling;
      Svc.CancelAllPending;
      Svc.Close;
    end;
  finally
    Svc := nil;
    Pump(200);
  end;
end;

{ ------------------------------------------------------------------
  Verdict. "Grew" is not the same as "leaked": an allocator that keeps
  a high-water mark is normal. The test asks whether the last third of
  the run is still climbing relative to the middle third, which is the
  shape a per-cycle leak makes and a settled allocator does not.

  判定。「増えた」は「漏れた」と同義ではありません。最高水位を保持する
  アロケータは正常です。本検査が問うのは、運転の最後の 1/3 が中間の
  1/3 に対してなお上昇しているかです。それは周回ごとのリークが作る形
  であり、落ち着いたアロケータが作る形ではありません。
  ------------------------------------------------------------------ }
function Climbing(const AValues: array of Int64; const AName: string;
                  ATolerance: Double): Boolean;
var
  n, i:         Integer;
  MidSum, EndSum: Double;
  MidN, EndN:   Integer;
  MidAvg, EndAvg, Growth: Double;
begin
  n := Length(AValues);
  if n < 6 then
  begin
    WriteLn('    ', AName, ': too few samples to judge');
    Exit(False);
  end;

  MidSum := 0; MidN := 0;
  EndSum := 0; EndN := 0;
  for i := n div 3 to (2 * n) div 3 - 1 do
  begin
    MidSum := MidSum + AValues[i];
    Inc(MidN);
  end;
  for i := (2 * n) div 3 to n - 1 do
  begin
    EndSum := EndSum + AValues[i];
    Inc(EndN);
  end;
  if (MidN = 0) or (EndN = 0) then Exit(False);

  MidAvg := MidSum / MidN;
  EndAvg := EndSum / EndN;
  if MidAvg <= 0 then Exit(False);

  Growth := (EndAvg - MidAvg) / MidAvg;

  { FPC's Format has no '+' flag — '%+.2f' is emitted literally, which
    in the first run of this test produced "growth 6863.4.2f %" and
    made the number unreadable. The sign is therefore written by hand.
    FPC の Format に '+' フラグはなく、'%+.2f' はそのまま出力されます。
    本検査の初回実行では "growth 6863.4.2f %" となり数値が読めません
    でした。そのため符号は手で書きます。 }
  WriteLn(Format('    %-22s middle %.1f  final %.1f  growth %s%.2f %% '
                 + ' (tolerance %.2f %%)',
                 [AName, MidAvg, EndAvg,
                  specialize IfThen<string>(Growth >= 0, '+', ''),
                  Growth * 100, ATolerance * 100]));
  Result := Growth > ATolerance;
end;

var
  Factory:  IRigServiceFactory;
  Counter:  TCounter;
  Minutes:  Integer;
  Deadline: QWord;
  Started:  QWord;
  Cycle:    Integer;
  S:        TSample;
  Rss, Fds, Thr: array of Int64;
  i:        Integer;
  Bad:      Integer;

begin
  SetLength(Samples, 0);
  SampleCount := 0;
  Minutes := StrToIntDef(ParamStr(1), 15);
  WriteLn('SoakTest — ', Minutes, ' minute(s) of continuous operation');
  WriteLn('==================================================');

  if not FileExists('/proc/self/status') then
  begin
    WriteLn('SKIP: /proc is not available, so resource use cannot be '
            + 'measured here.');
    ExitCode := 0;
    Halt;
  end;

  Factory := TRigServiceFactory.Create;
  Counter := TCounter.Create;
  Started  := GetTickCount64;
  Deadline := Started + QWord(Minutes) * 60 * 1000;
  Cycle    := 0;

  try
    while GetTickCount64 < Deadline do
    begin
      Inc(Cycle);
      RunCycle(Factory, Counter, Cycle);

      S.Cycle   := Cycle;
      S.RssKb   := ReadStatusField('VmRSS');
      S.Fds     := CountFds;
      S.Threads := ReadStatusField('Threads');
      S.Elapsed := GetTickCount64 - Started;
      { Grow geometrically, not by one.

        The first version of this test did SetLength(Samples,
        Length(Samples) + 1) every cycle. FPC reallocates and copies
        on each call, so a run of N cycles churns O(N^2) bytes through
        the heap — about 10 MB over 700 cycles — and the resulting
        fragmentation shows up as exactly what this test is looking
        for: resident memory climbing steadily while heaptrc reports
        nothing unfreed. The measuring instrument was producing the
        signal it was built to detect.

        1 件ずつではなく幾何級数的に伸ばします。

        本検査の初版は毎周 SetLength(Samples, Length(Samples) + 1) を
        行っていました。FPC は呼び出しごとに再確保とコピーを行うため、
        N 周の実行はヒープに O(N^2) バイトを通します (700 周で約 10 MB)。
        そして生じた断片化は、本検査が探しているものそのものとして
        現れます。heaptrc が未解放なしと報告する一方で常駐メモリが着実に
        増える、という形です。測定器が、検出するために作られた信号を
        自ら生み出していました。 }
      if SampleCount = Length(Samples) then
        SetLength(Samples, Max(64, Length(Samples) * 2));
      Samples[SampleCount] := S;
      Inc(SampleCount);

      WriteLn(Format('  cycle %3d  t=%5.1f s  RSS %7d kB  fds %3d  '
                     + 'threads %2d  results %d',
                     [S.Cycle, S.Elapsed / 1000, S.RssKb, S.Fds,
                      S.Threads, Sink]));
      Flush(Output);
    end;
  finally
    Counter.Free;
    Factory := nil;
  end;

  WriteLn;
  WriteLn(Format('%d cycles, %d results delivered', [Cycle, Sink]));
  WriteLn;
  WriteLn('  trend (middle third vs final third):');

  SetLength(Rss, SampleCount);
  SetLength(Fds, SampleCount);
  SetLength(Thr, SampleCount);
  for i := 0 to SampleCount - 1 do
  begin
    Rss[i] := Samples[i].RssKb;
    Fds[i] := Samples[i].Fds;
    Thr[i] := Samples[i].Threads;
  end;

  Bad := 0;

  { Resident memory is allowed a little drift: the allocator keeps a
    high-water mark and the heap trace will catch an actual unfreed
    block. 2 % across the second half of a long run is generous for
    noise and far below what one leaked buffer per cycle would produce.
    常駐メモリには多少の変動を許します。アロケータは最高水位を保持し、
    実際の未解放ブロックはヒープトレースが捕まえます。長時間運転の
    後半で 2 % はノイズに対して十分広く、周回ごとに 1 つバッファを
    漏らした場合に生じる値よりはるかに小さい値です。 }
  if Climbing(Rss, 'resident memory (kB)', 0.02) then
  begin
    WriteLn('    ^ FAIL: resident memory is still climbing at the end '
            + 'of the run');
    Inc(Bad);
  end;

  { Descriptors and threads are allowed none. Either one growing per
    cycle is a defect with a known end: the process dies.
    FD とスレッドには一切許しません。いずれかが周回ごとに増えるのは、
    終着点が分かっている欠陥です。プロセスが死にます。 }
  if Climbing(Fds, 'open descriptors', 0.0) then
  begin
    WriteLn('    ^ FAIL: a descriptor is leaking per session');
    Inc(Bad);
  end;
  if Climbing(Thr, 'threads', 0.0) then
  begin
    WriteLn('    ^ FAIL: a thread is leaking per session');
    Inc(Bad);
  end;

  WriteLn;
  if Bad = 0 then
  begin
    WriteLn('RESULT: OK — resources settled across the run');
    ExitCode := 0;
  end
  else
  begin
    WriteLn(Format('RESULT: %d resource trend(s) FAILED', [Bad]));
    ExitCode := 1;
  end;
end.
