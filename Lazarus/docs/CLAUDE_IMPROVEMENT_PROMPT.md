# zLog Lazarus Edition — 実装状況の問題点整理と Claude への改善指示プロンプト

作成日: 2026-09-28
対象: `Lazarus/` ディレクトリ（master `e4221394` 時点）

---

## Part 1. 問題点の整理（実測に基づく）

以下はドキュメントの記述ではなく、この作業環境に Free Pascal 3.2.2 を導入して
`make test` 等を実際に実行し、git 履歴と GitHub Actions API を照合して確認した事実である。

### 1.1 Critical — master はコンパイルできず、CI は一度も成功していない

| # | 事実 | 証跡 |
|---|---|---|
| C1 | `make test` はコンパイルエラーで失敗する | `test_runner.lpr(9)` Duplicate identifier SYSUTILS 他 |
| C2 | GitHub Actions「Lazarus core」は **77 run 全て failure、success 0** | `GET /repos/ji1uui/LazLogger/actions/runs` |
| C3 | docs / PR 本文に「CI 成功」「完了」と記載があるが、実行証跡が存在しない | IMPLEMENTATION_STATUS.md §1 自身がこれを認めている |
| C4 | PR #27→#28 のマージ (`9e5517af`) でコンフリクト解決時に **両側のコードが残置** された。コンフリクトマーカーは無いが、同じ手続き本体が 2 回連結されている | 影響 12 ファイル（下表） |
| C5 | マージ以前 (`6e07322d`, 2026-09-15) から `zlog.presentation.recentqsos.pas` が `Classes` を uses せず `EInvalidOperation` 未定義 → **約 2 週間、どの commit もビルド不能** | 各 commit で worktree を作り `make test` を実行して確認 |
| C6 | UNIX 系で `cwstring` を uses していないため、`UnicodeUpperCase` 呼び出しで `ENoWideStringSupport` が発生し、demo / test / benchmark が **実行時にクラッシュ** | `./build/zlog-demo` exit 217 |
| C7 | `zlog_gui.lpi` に `<RequiredPackages>`（LCL）が無い | `grep LCL app/zlog_gui.lpi` = 0 |

**C4 のマージ残置が確認されたファイル**

```
src/infrastructure/zlog.infrastructure.submissionqueue.pas   Submit / ExtractFirst / ProcessNext / CancelPending / PendingCount / Destroy に旧新両実装
src/infrastructure/zlog.infrastructure.completionqueue.pas   Destroy に二重解放、TryDispatch 末尾で Notifier を 2 回呼ぶ
src/infrastructure/zlog.infrastructure.health.pas            private 節が 2 つ、Report / ReportHealthy 本体が 2 回
src/infrastructure/zlog.infrastructure.rttyreference.pas     Ceil 版と Floor 版の境界計算が連結（構文エラー）
src/infrastructure/zlog.infrastructure.rigctld.pas           FTransport.Execute が 2 回呼ばれる（副作用が二重化）
src/infrastructure/zlog.infrastructure.submissionworker.pas  Shutdown 内で StopAndJoin / CancelPending が 2 回
tests/unit/test_runner.lpr                                   uses 行重複、NotifyCompletionAvailable 本体重複、ZLog.Application.Ports 欠落
Makefile                                                     .PHONY 3 行、test-runner ルール 2 つ
README.md / docs/QUALITY_REVIEW.md / docs/IMPLEMENTATION_STATUS.md / docs/MODE_ENGINE.md
                                                             「最終更新」2 行、「次の実装順序 4.」が 3 回、末尾に矛盾する旧段落
```

### 1.2 High — テスト自体の不具合（修正後に判明）

上記を暫定修正すると、さらに次が露見した。最終的に **540 assertions PASS** まで到達できたが、
到達に必要な差分は約 94 行であり、master 単体では 1 件も検証されていない状態である。

| # | 事実 |
|---|---|
| H1 | `CopyFilePrefix` が `TFileStream.CopyFrom(Source, 0)` を呼ぶ。FPC では Count=0 は「全体コピー」の意味であり、tail recovery テストが cut=0 で誤判定する |
| H2 | C4 の `FTransport.Execute` 二重呼び出しにより `CallCount` が 2 となり、backoff テストが失敗する（実装のバグがテストで正しく検出されている） |
| H3 | benchmark 4 本も `cwstring` 欠落で実行時クラッシュ（journal / memory / audio / rtty） |

### 1.3 プロセス上の問題

1. **ローカル検証なしのマージ**: 各 `codex/*` ブランチが master を取り込む際、手動コンフリクト解決の結果が
   コンパイルされていない。CI が赤のままマージが続いている。
2. **ドキュメント先行**: README「現在の実装」節が 20 段落超に肥大し、末尾に「OS 固有 process API は未実装」など
   現状と矛盾する旧段落が残る。実装より説明が先に「完了」を主張する構造になっている。
3. **単一 test runner の肥大化**: 1,474 行の手書き runner。FPCUnit 未採用。失敗時に最初の 1 件で停止し、
   残りの結果が得られない。
4. **benchmark baseline が保存されない**: JSON を artifact に上げる定義はあるが、比較対象・許容退行率が
   repository にない（IMPLEMENTATION_STATUS §5 も同旨）。

### 1.4 設計・機能面の問題（ビルドが直った後の課題）

| 優先 | 領域 | 問題 |
|---|---|---|
| High | Contest core | dupe / point / multiplier / serial / score / contest rule が **一切ない**。QSO の訂正・削除も不可。「zLog」としての本質機能が Phase 2 未着手 |
| High | データモデル | `TQso` に band、operator、station、serial、contest、points、multi が無い。後から versioned migration が必要 |
| High | 永続化 | append-only journal に tombstone / revision record が無く、訂正・削除を表現できない。起動時に全 record を object として再生するため O(n) メモリ |
| Medium | GUI | `UpdateFromState` が非表示時にも `SetFocus` を呼ぶ（LCL では例外になり得る）。`CanFocus` ガードなし |
| Medium | キュー | `TList.Delete(0)` による O(n) FIFO（容量 32/64 では許容だが CAT/decoder event には不可） |
| Medium | 時刻 | `TSystemClock.UtcNowMs` が `Now`（ローカル）→ `DateTimeToUnix(…, False)` と `MilliSecondOf` を別々に評価し、秒境界でずれ得る |
| Medium | 検証基盤 | Delphi 版との golden 比較 fixture が無い。Windows/macOS 実機起動証跡が無い |
| Low | 実行時 | `zlog.lpr`（console demo）が固定 QSO を追記するだけで、`GetAppConfigDir` を使う GUI と journal 位置が異なる |

---

## Part 2. Claude への改善指示プロンプト

以下をそのまま Claude に渡す。

````markdown
# 役割

あなたは Free Pascal / Lazarus と並行処理・永続化に精通したシニアエンジニアです。
`Lazarus/` ディレクトリで開発中の zLog Lazarus Edition を、**「master が常にビルド・テスト・CI 通過する状態」に戻し、
その状態を維持する仕組みを入れた上で**、Contest core（Phase 2）へ進める準備を整えてください。

# 前提（すでに検証済みの事実。再調査は不要）

- 現在の master (`e4221394`) は `make test` がコンパイルエラーで失敗する。
- GitHub Actions「Lazarus core」は 77 run すべて failure。成功実績はゼロ。
- 原因は主に 2 つ:
  1. PR #28 のマージ `9e5517af` でコンフリクト解決時に **両側のコードが残置**（マーカーは無い）。
     影響: submissionqueue / completionqueue / health / rttyreference / rigctld / submissionworker の各 .pas、
     test_runner.lpr、Makefile、README.md、docs/QUALITY_REVIEW.md、docs/IMPLEMENTATION_STATUS.md、docs/MODE_ENGINE.md
  2. それ以前から `zlog.presentation.recentqsos.pas` が `Classes` を uses しておらず `EInvalidOperation` が未定義。
- 加えて UNIX で `cwstring` が uses されておらず、`UnicodeUpperCase` で `ENoWideStringSupport` 実行時クラッシュ。
- `test_runner.lpr` の `CopyFilePrefix` が `CopyFrom(Source, 0)` を呼び、FPC では「全体コピー」になるため
  tail recovery テストが cut=0 で誤判定する。
- `zlog_gui.lpi` に LCL の `<RequiredPackages>` が無い。
- 上記をすべて直すと 540 assertions が PASS することは確認済み。

# 作業原則（厳守）

1. **既存アーキテクチャを尊重する。** domain → application → infrastructure → presentation の依存方向、
   bounded queue、worker thread 分離、append-only journal の設計は正しい。書き直さず、壊れた箇所だけ直す。
2. **マージ残置の解決方針**: 2 つのバージョンが連結されている場合、**新しい側**（`FPendingCompletion` /
   `FInFlight` / `ExtractForProcessing` / `FindComponent` / `RecalculateStatus` / `Ceil` 境界 / try-except 付き
   `FTransport.Execute`）を採用し、旧側を削除する。判断に迷う場合は `git show 5706b3d7:<path>` と
   `git show 6f5298cb:<path>` を比較し、両者の意図が両立するよう統合する。
3. **1 コミット = 1 論点。** 各コミット後に必ず `cd Lazarus && make clean test` を実行し、出力を
   コミットメッセージ本文に貼る。緑にならないコミットは作らない。
4. **ドキュメントは実装の後。** 動作確認できていないことを「完了」「CI 成功」と書かない。
5. **Free Pascal 3.2.2 で検証する。** `sudo apt-get install fp-compiler fp-units-fcl` 程度で導入できる。
   Lazarus/LCL が無い環境では `make gui` はスキップしてよいが、その旨を報告に書く。

# 実施ステップ

## Step A — ビルドを緑にする（最優先。これが終わるまで機能追加禁止）

A1. マージ残置の除去
   - 上記 6 つの .pas から重複ブロックを削除。特に:
     - `submissionqueue.pas`: `Submit` の 2 重 Accepted 判定、`ExtractFirst` の二重 if、`ProcessNext` の
       2 つ目の `begin`、`CancelPending` の二重 dispatch、`PendingCount` の二重代入、`Destroy` の二重解放
     - `completionqueue.pas`: `Destroy` の二重解放、`TryDispatch` 末尾の無条件 `FNotifier.NotifyCompletionAvailable`
     - `health.pas`: 2 つ目の `private` 節、`Report` / `ReportHealthy` の旧本体
     - `rttyreference.pas`: `Floor` 版 2 行
     - `rigctld.pas`: try-except の直後にある 2 回目の `FTransport.Execute`
     - `submissionworker.pas`: `Shutdown` の Assigned ガード無し版 2 行
   - `test_runner.lpr`: uses の重複行、`NotifyCompletionAvailable` の重複本体
   - `Makefile`: `.PHONY` を 1 行に、`test-runner` ルールを 1 つに

A2. 元からの欠落の修正
   - `recentqsos.pas` の uses に `Classes` を追加
   - `test_runner.lpr` の uses に `ZLog.Application.Ports` を追加
   - すべての `.lpr`（app/zlog.lpr、tests/unit、tests/benchmark 4 本、tests/fixtures）で
     `{$IFDEF UNIX}cthreads, cwstring,{$ENDIF}` とする。`zlog_gui.lpr` は LCL が manager を入れるので不要だが、
     統一のため付けても害はない
   - `CopyFilePrefix` を `if ALength > 0 then Destination.CopyFrom(Source, ALength);` にする
   - `zlog_gui.lpi` に `<RequiredPackages Count="1"><Item1><PackageName Value="LCL"/></Item1></RequiredPackages>` を追加

A3. 検証
   - `make clean test` → `PASS: 540 assertions`（前後で数が変わる場合は理由を記載）
   - `make run` を 2 回 → `make verify-demo` が `records=2` を返す
   - `make benchmark benchmark-memory benchmark-audio benchmark-rtty` がすべて JSON を出力する
   - `make test-tools` が OK

A4. ドキュメントの重複除去
   - README.md「現在の実装」節: 末尾の矛盾する旧段落（「OS 固有の process API…未実装」「現在の transport は fake contract」）
     を削除し、節全体を 10 行以内の箇条書きに圧縮する。詳細は IMPLEMENTATION_STATUS.md へ委ねる
   - QUALITY_REVIEW.md: 「最終更新」を 1 行に、「次の実装順序」の 4./5. 重複を 1 つに
   - IMPLEMENTATION_STATUS.md: 「## 4.」見出しの重複を 1 つに

## Step B — 再発防止（Step A と同じ PR に含める）

B1. CI を「マージゲート」にする
   - `.github/workflows/lazarus-core.yml` に `concurrency` を追加し、`pull_request` では Ubuntu だけを required にする
     （macOS / Windows は継続するが、まず 1 OS を確実に緑にする）
   - README に「Lazarus/ を変更する PR は Actions が緑でなければマージしない」と明記
B2. マージ残置の機械検出
   - `Lazarus/tools/check_duplicates.py` を追加: 各 .pas / .lpr について「同一の `procedure X.Y;` / `function X.Y` /
     `constructor` / `destructor` 実装見出しが 2 回出現」「`.PHONY` 複数行」「`最終更新:` 複数行」を検出して exit 1
   - `make lint` ターゲットと CI の最初のステップに組み込む
B3. テスト失敗時に全件表示
   - `AssertTrue` を「失敗をカウントして継続、最後に一覧表示して exit 1」に変更する（FPCUnit 移行は後回しでよい）
B4. 単一 OS での実行証跡
   - CI の Ubuntu job で `make test` の標準出力を `build/test-report.txt` に保存し artifact 化する

## Step C — Phase 2（Contest core）へ進む前の設計課題（実装は別 PR。ここでは ADR 案のみ）

`Lazarus/docs/adr/` に以下 3 件の ADR ドラフトを作成する。各 1 ページ以内、選択肢と却下理由を必ず書く。

C1. **QSO 訂正・削除の表現**: append-only journal に `Revision` / `Tombstone` record を追加する案 vs.
    snapshot + 差分ログ案。既存 v1 payload との互換（version byte）をどう扱うか
C2. **Contest rule engine の境界**: `ZLog.Domain.Contest.*` として dupe key、point、multiplier、serial を
    pure Pascal で置き、ALL JA を最初の versioned definition とする。Delphi 版 `.cfg` との golden 比較方法
C3. **QSO データモデル拡張**: band / operator / station / serial / points / multi の追加を payload v2 として行い、
    v1 を読めることをテストで固定する

# 禁止事項

- `git merge` / `git rebase` の結果を目視だけで確定しないこと。必ず `make clean test` を通す
- 既存のインターフェース名・ユニット名の一括リネーム
- LCL への Hamlib / CW / RTTY 直結（QUALITY_REVIEW.md §6 の方針どおり）
- 実行していない検証結果を docs に書くこと

# 成果物

1. Step A + B を含む 1 つの PR（コミットは論点ごとに分割。squash は PR 作成者が行う）
2. PR 本文に:
   - 変更ファイル一覧と、各ファイルで「新側を採用した理由」
   - `make clean test` / `make run ×2` / `make verify-demo` / 各 benchmark の実行ログ（抜粋可）
   - `make gui` を実行できたか否か
3. Step C の ADR ドラフト 3 件（同 PR に含めてよいが、実装コードは含めない）
4. 最後に、今回の作業で新たに見つかった問題があれば IMPLEMENTATION_STATUS.md §4 に追記する
````

---

## Part 3. 補足 — 検証手順（再現用）

```bash
# FPC 導入（Ubuntu）
sudo apt-get install -y fp-compiler fp-units-fcl fp-units-rtl

# 現状確認
cd Lazarus && make clean test        # → Duplicate identifier で失敗

# 特定 commit がビルド可能か
git worktree add /tmp/wt <sha> && (cd /tmp/wt/Lazarus && make clean test); git worktree remove --force /tmp/wt

# CI 履歴
curl -s "https://api.github.com/repos/ji1uui/LazLogger/actions/runs?per_page=100" \
  | python3 -c "import sys,json,collections;d=json.load(sys.stdin);print(collections.Counter(r['conclusion'] for r in d['workflow_runs']))"
```
