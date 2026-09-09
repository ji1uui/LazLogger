# zLog Lazarus Edition 開発実行計画

## 1. 計画の使い方

この計画は日付を先に固定する工程表ではなく、動作する小さな機能を一つずつ完成させ、測定結果を確認してから
次へ進む **品質ゲート方式**です。1 iteration は1〜2週間を目安としますが、未達の品質を日程理由で持ち越しません。

各stepは必ず次の順で実施します。

1. 利用scenario、失敗scenario、受入指標をissueへ記載する。
2. domain/APIと契約testを先に作る。
3. 最小の縦割り実装をWindows/macOSで動かす。
4. 正確性、応答性、資源効率、障害復旧を測定する。
5. baselineとの差分とprofileをreviewし、必要な箇所だけ最適化する。
6. document、migration、診断情報を整え、demoで受入確認する。
7. gate合格後にrelease可能なincrementとしてmainへ統合する。

一度に複数の大機能を着手しません。各時点で「最後に合格したincrement」が起動・保存・復旧できる状態を維持します。

## 2. 成果物と責任境界

小規模チームでも役割を省略せず、一人が複数を兼務する場合はreview時に帽子を切り替えます。

| 役割 | 主な責務 | 承認対象 |
|---|---|---|
| Product owner | contest scenario、優先順位、非目標 | acceptance scenario |
| Domain owner | QSO、contest rule、互換性 | golden差分、rule version |
| Platform owner | Lazarus/LCL、OS、配布 | Windows/macOS artifact |
| Station owner | Hamlib、audio、CW/RTTY、PTT安全 | hardware/support matrix |
| Quality owner | CI、benchmark、fault injection | quality gate report |
| UX reviewer | keyboard、accessibility、情報設計 | usability checklist |

重大な得点差、QSO欠落、PTT stuck、credential漏洩はProduct判断で許容できないrelease blockerとします。

## 3. Step-by-step実装計画

### Step 0 — Baselineと意思決定基盤

**実装**

* Lazarus/FPCの採用候補をWindows/macOSのclean machineでbuildするspikeを作る。
* ADR template、coding standard、dependency rule、structured logging schemaを用意する。
* 匿名化した小・中・大ログ、壊れたログ、代表contestのgolden corpusを作る。
* benchmark runnerがOS、CPU、compiler、commit、datasetをJSONへ記録するようにする。

**検証**

* 同じcommitを両OSで再現buildできる。
* 現行zLogからQSO件数、dupe、point、multi、最終score、exportを採取できる。
* benchmarkを5回実行し、中央値とばらつきを保存できる。

**Gate 0:** toolchain ADR、CI matrix、fixture利用条件、性能測定手順がreview済み。機能コードはこのgate後に開始する。

### Step 1 — Walking skeleton：1件を記録して復旧

**実装**

* `TCallsign`、`TFrequencyHz`、`TQsoDraft`とvalidation resultをpure Pascalで実装する。
* `ILogQsoUseCase`、deterministic clock/ID、in-memory repositoryを実装する。
* 最小LCL画面から1 QSOを入力し、append-only journalへ保存して再表示する。
* process supervisor、main-thread dispatcher、UI heartbeatの骨格を用意する。

**検証**

* value objectとuse caseのunit test、repository contract testを実行する。
* journal writeの各byte位置でprocess killを注入し、最後にacknowledgeされたQSOを復旧する。
* fake workerを10秒停止しても入力とwindow操作が継続することを確認する。
* cold/warm起動、QSO受付、UI heartbeat gap、memoryをbaseline化する。

**Gate 1:** Windows/macOS packageで1 QSOを保存・復旧でき、UI threadに外部I/Oがなく、acknowledged QSO欠落が0。

### Step 2 — QSO lifecycleとLogbook

**実装**

* QSO correction、void/restore、revision audit、search/pagingを追加する。
* virtualized grid、filter chip、undo可能な編集previewを実装する。
* legacy log importerをread-only dry-runから実装する。

**検証**

* create/correct/void/recoverのstate transitionをproperty/table testする。
* 1、1,000、100,000 QSOで検索、scroll、edit、起動時間とpeak memoryを測る。
* malformed/途中切断/異常文字コードのimportをfuzzし、原本hashが変わらないことを確認する。
* index rebuild中にも新規QSOをdurableに受付できることをload testする。

**Gate 2:** 100,000 QSOでUI frame p95 16 ms、新規QSO受付p95 20 msを初期目標とし、未達時はprofileと承認済み改善計画を必須とする。

### Step 3 — Contest rule vertical slice

**実装**

* dupe key、point、multiplier、serial、score explanationを共通rule engineへ実装する。
* 最初のcontestとしてALL JAを一つのversioned definitionで完成させる。
* score/multi viewをdomain eventによる差分更新で表示する。

**検証**

* 境界時刻、band/mode変更、portable call、forced QSO、訂正をtable testする。
* golden corpusをQSO単位で比較し、差をrule-id付きで出力する。
* incremental resultと全再計算結果をrandom operation sequenceで比較する。
* 100,000 QSO全再計算と1 QSO追加時のCPU/latencyを測る。

**Gate 3:** golden結果100%一致。意図した仕様変更だけは専門review、理由、旧新結果、rule versionを記録して例外承認する。

### Step 4 — 提出とデータ交換

**実装**

* ADIF、Cabrillo、JARL E-Logを独立adapterとして追加する。
* import/export preview、validation report、文字コード／時刻／単位変換を実装する。
* backup/restoreとschema migrationを提供する。

**検証**

* parse/serialize round-trip、golden file、malformed input、巨大fileをtestする。
* disk full、read-only、rename失敗、途中終了をfault injectionする。
* downgrade/upgradeを含むmigration matrixとrestore drillを実行する。

**Gate 4:** 原本変更なし、silent data lossなし、全警告がQSO位置と修復方法を提示し、提出fixtureがvalidatorに合格する。

### Step 5 — Hamlib CATと接続センター

**実装**

* `IRigControl` contract、fake `rigctld`、本番`rigctld` clientを実装する。
* radioごとのsingle-writer queue、poll generation、timeout/cancel/reconnectを実装する。
* capability、version、latency、last success、queue depthを接続センターへ表示する。

**検証**

* delayed/out-of-order/malformed response、切断、crash loopをfakeで再現する。
* `rigctld`を10秒hang/killしてもQSO記録が継続することを確認する。
* release labで代表rigのfrequency/mode/PTT、sleep/resume、USB replugをsoak testする。

**Gate 5:** UI freezeなし、誤radio commandなし、切断中QSO欠落0、PTT watchdogが全failure scenarioで解除を試みる。

### Step 6 — DX cluster、Band Map、Callsign Card

**実装**

* `zlog-netd`とversioned IPC、cluster state machine、spot model/filter/agingを実装する。
* non-blocking callsign card、local cache、TTL/rate limit/privacy consentを実装する。
* keyboard操作可能なband mapとstale result抑止を追加する。

**検証**

* DNS timeout、packet fragmentation、invalid UTF、spot flood、再接続をsimulationする。
* callsignを高速変更しても以前のlookup結果が混入しないことをgeneration testする。
* 10倍想定peak trafficでqueue上限、drop/coalesce、CPU、memoryを測る。

**Gate 6:** network offline/flood時も入力budgetを維持し、unbounded queueなし、外部送信は同意済みdataだけ。

### Step 7 — CW送信、次にCW受信

**実装**

* macro/token、monotonic scheduler、`ICwKeyingOutput`、外部keyer/Hamlib adapterを実装する。
* stop、WPM変更、PTT lead/tailを明示的state machineにする。
* 送信が安定した後、confidence付きCW decoderを補助機能として追加する。

**検証**

* fake clockでdot/dash/gap、macro、速度変更を決定的にtestする。
* logic analyzer/audio loopbackでtiming jitterとESC停止p99を測る。
* worker crash、device loss、queue underrunでPTT stuckがないことを確認する。
* noise/QSB/速度変化corpusでdecoder accuracyを非回帰比較する。

**Gate 7:** 送信安全試験を先に合格し、受信decoderはQSOを自動確定しない。decoderは独立して無効化可能。

### Step 8 — RTTY scalar modem、Audio、AFSK送信

**実装**

* synthetic generator、resampler、filter、tone detector、timing recovery、ITA2 codecをscalar実装する。
* `zlog-modemd`、timestamp付きaudio frame、bounded SPSC ring、telemetryを実装する。
* phase-continuous DDSによるAFSK TXとhalf-duplex/PTT state machineを追加する。

**検証**

* WAV file入出力でclean signalのencode/decode round-tripをbit単位で確認する。
* AWGN、offset/drift、clock error、隣接信号、impulse、fading corpusでBER curveを保存する。
* callback allocation/lockをinstrumentし、overrun/underrunと24時間memory growthを監視する。
* audio loopbackでRX latency、TX開始、cancel、PTT releaseを測る。

**Gate 8:** scalar referenceの正確性を固定し、24時間deadline miss/PTT stuck 0。ここまでは高速化を目的とした近似を入れない。

### Step 9 — RTTY SIMD、FSK、Waterfall

**実装**

* x86-64 SSE/AVXとApple Silicon NEON backendをruntime dispatchで追加する。
* FSK keying adapterと先読みsymbol queueを実装する。
* decoderとは別の低優先度consumerとしてwaterfall/tuning UIを実装する。

**検証**

* scalar/SIMDを同一corpusでsymbol decision、許容誤差、BERまで比較する。
* profilerでhotspot、speed-up、CPU、電力、queue lagを測る。
* waterfallを表示／非表示／高負荷にしてdecode BERとaudio deadlineへ影響しないことを確認する。
* dummy loadでFSK timing、cancel、device loss、PTT watchdogを検証する。

**Gate 9:** scalar非回帰、RTTY 1 decoder + waterfallがreference core 20%以下という初期budgetを満たす。GPUは実測上の未達がある場合だけADRを開始する。

### Step 10 — Multi-op、SO2Rと高度な運用

**実装**

* multi-op event sync、offline記録、conflict UI、serial policyを実装する。
* radio/audio/keyer routeを一つのSO2R state machineで管理しinterlockを実装する。
* Run/S&P/Digital layout presetと送信先の非色覚依存表示を完成させる。

**検証**

* LAN partition/rejoin、重複event、遅延、clock skew、node crashをsimulationする。
* random state transitionで禁止TX routeに到達しないことをproperty testする。
* 2台のrigを用いたfault injectionとoperator usability sessionを行う。

**Gate 10:** QSO欠落0、競合は監査可能、誤TX route 0。安全stateが不明な場合は送信しない。

### Step 11 — Post-contest UXとRelease Candidate

**実装**

* Outbox、online upload、QSL/award view、grayline/map/statisticsを追加する。
* signed package、macOS notarization、SBOM、diagnostic bundle、migration assistantを完成させる。
* beginner onboarding、keyboard reference、support matrixを公開する。

**検証**

* HTTP timeout/429/重複送信、credential expiry、child process crashをtestする。
* map/statistics/upload負荷中のQSO入力性能を確認する。
* clean install、upgrade、rollback、backup restore、24/48時間contest rehearsalを両OSで行う。

**Gate 11:** pilot利用者が一連のcontestを完走し、blocker 0、rollback可能、support runbook完成で正式release候補とする。

## 4. 継続的な検証プロセス

### Pull Requestごと（数分）

* format/lint、全unit test、dependency rule、変更adapterのcontract test
* 小golden corpus、sanitizer相当のrange/overflow/check build
* 1,000 QSO microbenchmark。baselineから10%超悪化したら理由とprofileを要求する
* Windows/macOS compileとheadless test

### Nightly（30〜90分）

* 全golden contest、100,000 QSO benchmark、import fuzz corpus
* fake Hamlib/network/modemのtimeout、切断、crash、queue saturation
* UI responsiveness scenarioとmemory/handle/thread leak検査
* 性能値を時系列保存し、単発閾値と連続悪化trendの両方を通知する

### Weekly／Milestone

* 実機hardware matrix、8〜24時間soak、sleep/resume、device replug
* backup/restore drill、schema migration、package clean install
* keyboard-only/high-DPI/dark/high-contrast/accessibility walkthrough
* golden差分、flaky test、技術的負債、未使用feature flagをtriageする

### Release Candidate

* 24/48時間rehearsal、network partition、disk full、process kill、power-loss相当test
* signed artifactとhash、SBOM、Hamlib/device support matrix、既知制限を固定する
* pilot cohortでshadow operationし、現行zLogとのscore/export差分を確認する
* release/rollback判定とincident連絡経路を記録する

## 5. 性能・堅牢性・効率性の共通指標

| 観点 | 指標 | 初期budget / 判定 |
|---|---|---|
| UI応答 | event-to-paint p50/p95/p99、heartbeat gap | p95 50 ms、100 ms超gap 0を目標 |
| Log安全 | acknowledge後の欠落、recovery時間 | 欠落0、破損は検出して原本保持 |
| QSO受付 | command-to-durable journal | p95 20 ms |
| 大規模表示 | 100,000 QSO scroll/filter | frame p95 16 ms、全件UI保持禁止 |
| CPU | idle、logging、RTTY、再集計 | scenario別baselineから10%超をreview |
| Memory | peak、24時間growth、queue depth | unbounded growth/queue 0 |
| I/O | journal fsync、DB query、network bytes | batch効果とtail latencyを併記 |
| 障害隔離 | child crash時の入力可否、再起動時間 | logging継続、crash loopを遮断 |
| 送信安全 | ESC-to-PTT release、PTT stuck | p99 50 ms目標、stuck 0 |
| DSP品質 | BER、decode latency、deadline miss | corpus非回帰、deadline miss 0 |
| 電力効率 | CPU package/GPU利用、wakeups | 高速化前後で同じworkloadを比較 |

固定値はPhase 0のreference machine測定後にADRで確定します。平均だけで合否を決めず、tail latencyと最悪queue depthを記録します。

## 6. 最適化の手順

1. 再現可能なworkloadと利用者影響を示す。
2. profiler、trace、queue telemetryでbottleneckを特定する。
3. algorithm/data structure/I/O回数を先に改善する。
4. allocation削減、batching、cache、SIMDを順に検討する。
5. GPU/process追加は転送・IPC・配布・電力を含む総費用で比較する。
6. scalar/reference結果とgoldenを保ち、変更前後のp50/p95/p99をPRへ添付する。
7. 改善しない、複雑性が過大、堅牢性が落ちる変更はrevertする。

測定のためのtelemetryが本番性能を損なわないようsamplingとring bufferを使い、利用者dataは既定で外部送信しません。

## 7. 進捗の可視化

各stepは次の状態だけを取ります。

`Proposed -> Ready -> Implementing -> Measuring -> Hardening -> Accepted`

進捗率をファイル数や画面数で示さず、合格したscenarioで示します。週次dashboardには以下を掲載します。

* step/gateとblocker、次の検証
* Windows/macOSの最新成功artifact
* unit/contract/golden/fault testの件数とflaky率
* UI、QSO受付、memory、CPU、BERのbaseline trend
* unresolved golden差分、crash、data-loss、PTT safety issue
* ユーザー検証で判明した仮説、採用／棄却理由

二つのstepが同時に`Implementing`となるのは、依存せず担当とtest environmentが分かれる場合だけです。未完機能はfeature flagで
通常利用から隔離し、flagにはowner、削除条件、期限を設定します。

## 8. 最初の3 iteration

### Iteration 1

* toolchain候補を両OSでbuildしADR-001を作成する。
* CI skeleton、FPCUnit、dependency checkを作る。
* corpusの匿名化・ライセンス規則と最小fixtureを確定する。

### Iteration 2

* value objects、validation result、`ILogQsoUseCase`をtest-firstで実装する。
* in-memory repository、deterministic clock/IDで1 QSOを通す。
* 小benchmark runnerとJSON artifactをCIへ追加する。

### Iteration 3

* 最小LCL QSO entryとPresenterを接続する。
* journal append/recoveryとkill-point testを実装する。
* fake worker hangに対するUI heartbeat testを通し、Gate 1 reviewを行う。

Iteration 3終了時点でGate 1に未達なら、Step 2へ進まず原因を解消します。これが段階実装と品質維持の最初の実証になります。
