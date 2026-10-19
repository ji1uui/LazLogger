# HamlibComponent Rev.4.1 — 最適化レポート

**実施日**: 2026-10-12
**基準**: Rev.4.0（コードレビューで検出した P0×3 / P1×1 / P2×3 / P3×1）
**検証環境**: FPC 3.2.2 (x86_64-linux)、heaptrc、実行可能テスト 7 本

---

## サマリ

レビューで指摘した 8 件すべてを修正し、**実測で効果を確認**しました。
修正の過程で新たに 1 件（FPC の構文上の罠）を発見し、あわせて対処しています。

| # | 項目 | 修正前 | 修正後 | 検証手段 |
|---|---|---|---|---|
| P0-1 | Service⇄Poller 循環参照 | Close 忘れで **デストラクタが動かない**／1,394 B リーク／スレッド永久稼働 | **解消**（0 B） | LifecycleTest TEST 3、LeakTest2 |
| P0-2 | `Enqueue(nil)` の自己矛盾 | **Debug ビルドで Close が必ず例外** | 解消 | `-Sa` ビルドで全テスト通過 |
| P0-3 | 接続失敗時の nil PRIG | nil が Hamlib 呼び出しに到達し **`rcsSuccess` を返す** | `rcsRejected`／到達 0 回 | ConnectFailTest |
| P1-4 | 引数検証が `Assert` のみ | Release で `EAccessViolation` | `ERigServiceClosed` 等を送出 | MisuseTest |
| P2-5 | `TThreadList` dupIgnore | 8,000 件で 18 ms（O(n²)） | 2 ms（O(n)、**9 倍速**） | PerfTest |
| P2-6 | Dequeue ロストウェイクアップ | 理論上最大 100 ms 遅延 | 修正済（**実測差は出ず**） | PerfTest 300 回 |
| P2-7 | Poller パラメータ非アトミック | `Double` の破れ読みの恐れ | `TCriticalSection` で保護 | コード検査 |
| P3-8 | `cthreads` 要件が未記載 | 実行時エラー 232 | README に明記 | — |
| **新** | `@Class.Create().Method` | （Rev.4.1 作業中に混入） | ローカル変数経由に統一＋警告コメント | Diag で再現・修正 |
| **追加** | スナップショットの生ポインタ | 遅延コールバックで解放済みロック参照の恐れ | 参照カウント `IRigStateHolder` に置換 | 設計変更 |

コンパイラ診断は **Release / Debug の両構成で警告・Note ともにゼロ**になりました。

---

## P0-1: 循環参照の解消（最重要）

### 原因

`TRigPollerThread` が `FService: IRigService` を保持していました。
`TRigService` は `TInterfacedObject` 派生のため、この代入が参照カウントを
増やし、次の循環を作っていました。

```
TRigService ──(素のポインタ FPoller、+0)──► TRigPollerThread
TRigPollerThread ──(IRigService、+1)──► TRigService
```

`Close()` を呼べば `DisablePolling` が poller を解放して循環が切れるため
問題が表面化せず、**呼び忘れたときだけ壊れる**という、自己防衛デストラクタの
意図と正反対の挙動になっていました。

### 修正

Poller が Service をインターフェースで持つのをやめ、**メソッドポインタ**
2 本に置き換えました。メソッドポインタは `(コードアドレス, インスタンス
アドレス)` だけを保持し、参照カウントに触れません。

```pascal
{ HamlibPoller.pas }
type
  TRigPollTickProc   = procedure(ACallback: TRigPollerFreqCallback) of object;
  TRigPollCanRunFunc = function: Boolean of object;

  TRigPollerThread = class(TThread)
  private
    FOnPollTick: TRigPollTickProc;     { 参照カウントを取らない }
    FCanRun:     TRigPollCanRunFunc;
    …
  public
    constructor Create(AOnPollTick: TRigPollTickProc;
                       ACanRun: TRigPollCanRunFunc;
                       AIntervalMs: Cardinal = 200);
  end;
```

```pascal
{ HamlibService.pas }
FPoller := TRigPollerThread.Create(@PollerTick, @PollerCanRun, AIntervalMs);

function TRigService.PollerCanRun: Boolean;
begin
  Result := FOpen and Assigned(FWorker)
            and (FWorker.QueueDepth < POLL_QUEUE_HIGH_WATER);
end;

procedure TRigService.PollerTick(ACallback: TRigPollerFreqCallback);
begin
  if not (FOpen and Assigned(FWorker)) then Exit;
  GetFrequencyAsync(rvfoCurr, ACallback);
end;
```

素のインスタンスポインタを渡すことになりますが、`DisablePolling` が
`Stop → WaitFor → Free` の順で poller を完全に終了させてから Service が
破棄されるため、ダングリングは発生しません。

あわせて `Execute` に `try/except` を追加しました。`CanRun` と実際の投入は
不可分ではないため、別スレッドの `Close()` が間に割り込むと Service が
`ERigServiceClosed` を発生させ得ます。これが `Execute` の外へ出ると
以降セッション全体でポーリングが静かに停止してしまいます。

### 実測

```
修正前  TEST 3: ServiceFreed = FALSE   *** LEAK - destructor never ran ***
        heaptrc: 16 unfreed memory blocks : 1394

修正後  TEST 3: >> TRigService.Destroy CALLED
                ServiceFreed = TRUE
                RESULT: OK (self-defending destructor worked)
        heaptrc: 0 unfreed memory blocks : 0
```

---

## P0-2: `Enqueue(nil)` の自己矛盾

`RequestStop` が nil を番兵として積む一方、`Enqueue` は nil を禁止して
いました。番兵方式をやめ、シグナル専用メソッドを追加しています。

```pascal
{ HamlibCommandQueue.pas }
procedure TCommandQueue.WakeUp;
begin
  RTLEventSetEvent(FNewItem);   { 何も積まずに消費者を起こす }
end;

{ HamlibWorker.pas }
procedure TRigWorker.RequestStop;
begin
  Terminate;
  FQueue.WakeUp;
end;
```

`Enqueue` の検査も `Assert` から `EArgumentException` に変更しました。

**実測**: `-Sa`（Lazarus Debug 既定）で全テストが通過。修正前は
`EAssertionFailed: Cannot enqueue nil command` で必ず落ちていました。

---

## P0-3: 接続失敗時の nil PRIG

`ProcessCommand` の実行前チェックに接続状態を追加しました。

```pascal
else if (FRig = nil) or (not FConnected) then
begin
  { nil の PRIG を渡すと Hamlib 内部で rig->state を参照して
    プロセス全体がセグフォルトするため、コマンドを拒否する }
  R.Status   := rcsRejected;
  R.ErrorMsg := 'Rig is not connected';
  …
end
```

接続失敗時に `TripCircuitBreaker` を呼ぶようにし、Worker を永久アイドルに
せず通常の自動再接続サイクルへ乗せています。

### 実測（ConnectFailTest：`rig_open` が常に失敗するローダ）

```
Rev.4.0   status: 0 (rcsSuccess)   nil-PRIG call count: 1
          *** UNSAFE - a nil PRIG reached the Hamlib call ***

Rev.4.1   status: 4 (rcsRejected)  nil-PRIG call count: 0
          OK (command rejected, no nil PRIG dereference)
```

修正前は nil が Hamlib に渡るうえ **成功扱いで返っていた**点が特に問題でした。

---

## P1-4: 引数検証を例外ベースへ

`Assert` は Release ビルド（`-Sa` なし）でコンパイラが削除するため、
公開 API の契約検査には使えません。宣言だけされて未使用だった
`ERigServiceClosed` を実際に使い、`ERigServiceOpen` を新設しました。

```pascal
procedure TRigService.EnsureOpen;
begin
  if (not FOpen) or (not Assigned(FWorker)) then
    raise ERigServiceClosed.Create(
      'Service is not open. Call Open() before issuing commands.');
end;
```

全非同期メソッドがこのガードを通り、`SetFrequencyAsync` は範囲検査、
`SetModeAsync` は `AMode = 0` と負の passband も弾きます。

**実測**: `EAccessViolation` → `ERigServiceClosed: Service is not open. Call Open() before issuing commands.`

---

## P2-5 / P2-6: キューの最適化

`TThreadList.Duplicates` の既定 `dupIgnore` は `Add` ごとに O(n) の
`IndexOf` を走らせます。コマンドポインタは構造上一意なので無駄です。

```pascal
FList.Duplicates := dupAccept;
```

`Dequeue` のリセット位置も、最初の覗き見の**前**に移しました。覗き見の後に
リセットすると、アンロードからリセットまでの隙間に生産側が立てたシグナルを
捨ててしまいます。

### 実測

| 件数 | Rev.4.0 | Rev.4.1 |
|---|---|---|
| 2,000 件 enqueue | 1 ms | 1 ms |
| 8,000 件 enqueue | **18 ms** | **2 ms** |

件数 4 倍に対し修正前は時間 18 倍（O(n²)）、修正後は 2 倍（O(n)）で、
計算量の改善が確認できます。

一方 **ロストウェイクアップは 300 回の試行でも再現しませんでした**
（両版とも worst 1〜2 ms）。競合窓が数マイクロ秒と極めて狭いためです。
修正は理論上正しいものの、**実測上の効果は示せていない**ことを明記します。

---

## 新規発見: `@TClass.Create(...).Method` の罠

ボイラープレート削減のため、一時オブジェクトに対して直接メソッドポインタを
取る書き方を試したところ、**FPC が不正な `Self` を持つメソッドポインタを
生成**し、UI スレッドが実行した時点で `EThreadError` と glibc の
`pthread_tpp_change_priority` アサーション失敗を引き起こしました。

```pascal
{ NG — 一時オブジェクトに対してアドレスが解決され Self が壊れる }
TThread.Queue(nil, @TWWErrorDispatch.Create(FOnError, ACode, AMsg).RunOnUIThread);

{ OK — ローカル変数を必ず経由する }
Sink := TWWErrorDispatch.Create(FOnError, ACode, AMsg);
TThread.Queue(nil, @Sink.RunOnUIThread);
```

該当 5 箇所すべてをローカル変数経由に統一し、再発防止のコメントを
日英で残しました。この副作用で出る Note 5027（「代入されたが未使用」）は
FPC がメソッドポインタ取得を読み出しと見なさない誤検知のため、
`{$PUSH}{$WARN 5027 OFF}` … `{$POP}` で範囲を限定して抑制しています。

---

## 追加改善: スナップショットの参照カウント化

Rev.4.0 はスナップショット更新のため、生の `^TRigState` と生の
`TCriticalSection` をディスパッチャに渡していました。ディスパッチャは
UI スレッドの同期キューから呼ばれるため、`TRigService.Destroy` が
ロックを解放した後に実行され得ます。

新設した `IRigStateHolder`（`HamlibStateHolder.pas`）に状態とロックを
まとめ、Service と実行中の全ディスパッチャが参照を共有する形にしました。
ホルダーは最後の参照が消えて初めて破棄されるため、遅延コールバックは
必ず生存中のオブジェクトに書き込みます。ホルダーは Service を参照しないため
新たな循環も生じません。

```pascal
IRigStateHolder = interface
  function  Snapshot: TRigState;
  procedure SetFreq(AVfo: TRigVfo; AFreq: Double);
  procedure SetMode(AMode: Int64; APassband: Int64);
  procedure SetConnected(AConnected: Boolean);
  procedure SetPtt(AActive: Boolean);
  procedure Reset;
end;
```

---

## 副次的な整理

**非同期 API の DRY 化**: 5 箇所に重複していたディスパッチャ生成の定型句を
`MakeCommandSink` / `MakeFreqSink` / `MakeModeSink` の 3 ファクトリに集約し、
「Self を捕捉しない」規則を 1 箇所に閉じ込めました。各非同期メソッドは
「引数検証 → トークン生成 → コマンド投入」の 3 行に揃っています。

**Linux での同梱配布対応**: ローダの探索候補に実行ファイル隣接の
`lib/libhamlib.so.4` と `./libhamlib.so.4` を追加しました。これにより
AppImage/tarball 配布がシステム全体へのインストールなしで動作し、同時に
`ExeDir` 未使用の Note も解消されました。

---

## 検証資材

| ファイル | 検証内容 |
|---|---|
| `test/LifecycleTest.lpr` | Open/Close/破棄の 3 パターン（P0-1・P0-2） |
| `test/ConnectFailTest.lpr` | **新規** 接続失敗時の nil PRIG 安全性（P0-3） |
| `test/MisuseTest.lpr` | Open 前 API 呼び出し（P1-4） |
| `test/PerfTest.lpr` | **新規** enqueue スループットと起床遅延（P2-5・P2-6） |
| `test/DanglingTest.lpr` | 破棄済みオブジェクトへのコールバック |
| `test/LeakTest.lpr` / `LeakTest2.lpr` | heaptrc によるリーク検査 |

```bash
cd test
# Debug（アサーション＋範囲/オーバーフロー検査＋ヒープトレース）
fpc -Mobjfpc -Sh -Sa -Criot -gh -gl -B -Fu../src -FE. LifecycleTest.lpr && ./LifecycleTest
fpc -Mobjfpc -Sh -Sa -Criot -gh -gl -B -Fu../src -FE. ConnectFailTest.lpr && ./ConnectFailTest
# Release
fpc -Mobjfpc -Sh -O2 -B -Fu../src -FE. PerfTest.lpr && ./PerfTest
```

Linux のコンソールアプリでは `uses` の先頭に `{$IFDEF UNIX}cthreads,{$ENDIF}`
が必須です（LCL アプリでは不要）。

---

## 残る既知の限界

**ロストウェイクアップの実証ができていません。** 修正は競合の筋から見て
正しいものの、300 回の試行で差が出ませんでした。実効性は未確認です。

**実機での検証は未実施です。** 全テストは Fake ローダまたは
`rig_open` が失敗するローダによるもので、実際の Hamlib ライブラリや
無線機に対しては動かしていません。特に P0-3 の修正は「nil PRIG が
Hamlib に到達しない」ことを確認したにとどまり、実機での接続断・復帰
シナリオは別途検証が必要です。

**`TRigService.Close` の並行呼び出しは想定外です。** 複数スレッドから
同時に `Close` と非同期 API を呼ぶ場合の保護は入れていません。
現状の設計は「UI スレッドが Service のライフサイクルを単独で管理する」
前提に立っています。

---

*Optimization Report Rev.1.0 / 2026-10-12 — FPC 3.2.2 実測検証つき*
