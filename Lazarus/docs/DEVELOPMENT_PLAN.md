# 開発実行計画（2026-09-26改訂）

## 1. 現状と進め方

要求・指標の正本は[要件台帳](REQUIREMENTS.md)。本計画は対象OSで完走したscenarioと証拠で進捗を判定する。

対象はPR #29の f9a02bce751be9b6956d2a9062e5fc6b4cf7608d。[CI run 36203748416](https://github.com/ji1uui/LazLogger/actions/runs/36203748416)ではPython 5件が3 OSで成功、Linux/macOSはRecentQsosのEInvalidOperation未解決でcompile失敗、WindowsはFPC取得504で未build。benchmark artifactは0。保存・worker・ring・RTTY referenceのコードはあるがG0/G1は未合格。この文書改訂はコードやCIを修復したという意味ではない。

各incrementを「要求ID→正常/失敗scenario→契約test→最小実装→両OS実行→計測→レビュー→証拠登録」の順で完成させる。1 iterationは1〜2週間の計画単位で納期保証ではない。現在はM0/M1の復旧を優先し、後続feature拡大を止める。CAT/audio/RTTY spikeは保持し、製品完了と区別する。

## 2. ゲートと依存

| 段階 | 依存・対象要件 | 実装・成果物 | Exit（全条件必須） |
|---|---|---|---|
| M0 検証基盤 / G0 | なし。N13/N14、D01/D02 | compile修復、Windows toolchain取得の失敗検知・再現性、3 OS coreとWindows/macOS GUI、toolchain ADR、fixture/匿名化、測定schema、dependency/range/overflow checks、利用者調査計画 | 同一SHAのcore成功・両OS GUI成功、reference/測定手順固定、純JSON結果。環境障害とコード失敗を分類 |
| M1 保存・復旧 / G1 | G0。F02/F03/F09、N01〜N03/N05/N06/N16 | 非同期起動復旧、worker lifecycle/active operation/deadline、completion時間budget、heartbeat、保存ID結果照会、最小job/health、package | 両OS clean-machineで保存→kill→復旧→再保存、ack欠落0。10秒停止/保存stallでもUI継続、late callbackなし。W1性能、終了・競合、baseline |
| M2 Logbook / G2 | G1。F04/F05、N04/N05/N12/N17 | correction/void/restore/revision、virtualized grid/search/filter、index/snapshot再構築 | 1/1k/100k state transitionとreplay一致。W2表示・保存・資源上限、keyboard編集・復元 |
| M3 ログ中核 / G3 | G2、D03/D07。F01/F06〜F08/F19、N04/N11/N12/N17 | ALL JA→国内4/国際2、score/serial、setup/demo、legacy dry-run、3形式import/export、backup/migration、keyboard/dashboard | 6 contestのQSO別golden100%一致、増分=全再計算、export validator、原本hash不変、restore/rollback、100k性能と利用者試験 |
| M4 CAT・TX安全 / G4 | G3、D04。F09〜F11、N07/N08/N15/N16 | 実rigctld/capability、poll generation、接続センター、supervisor/IPC、PTT lease/watchdog、route/cancel | fake+公開予定実機でtimeout/replug/sleep/crashとlogging継続。ESC command latencyと物理解除を別測定。合格前に実TXを公開しない |
| M5 CW/RTTY・audio / G5 | G4、D05。F12〜F17、N05/N08〜N10/N17 | CW TX→RX、RTTY framing/WAV→audio RX→AFSK→FSK、profile/waterfall、scalar後SIMD | 下記G5a〜d、両OS support構成の24h、BER/文字・latency/CPU、安全/device loss合格 |
| M6 運用MVP / G6 | G5。F18/F19、N02〜N05/N07/N15/N17、C01採否 | cluster/spot/filter/aging、band map操作、network supervisor、offline、dashboard・focus統合 | W3/W4 budgetと資源上限。6 contest+CAT+CW/RTTY+clusterで準備〜提出を両OS完走。experimental表示とsupport範囲を明示 |
| M7 高度運用 / G7 | G6。F20〜F22、N01/N07/N08/N12/N15 | multi-op conflict/serial、SO2R/2BSIQ interlock、録音、任意live score、署名拡張 | partition/rejoin/重複/clock skew/node crashで欠落0、禁止TX0。2台実機、外部contest/rig各2種、同意・停止・互換 |
| M8 移行・正式release / G8 | G7。F23/N18、採用済C01〜C03 | migration assistant、installer/sign/notarize/SBOM、bundle、onboarding/help/support、採用post-contest機能、旧版並行運用 | clean install/upgrade/downgrade/backup/rollback、24/48h rehearsal、pilot完走、blocker0、対応表・既知制限、1 season並行運用の結果 |

M3はログ中核であり運用MVPではない。限定pilotはG6後に可能だが署名・backup・rollback・supportは省略しない。M7完了前の正式版はscope変更として別途意思決定し、本計画の完了と混同しない。

### M5内部の順序

* G5a: ITA2/start/data/stop、profile、WAV round-trip、timing recovery/AFCと条件別corpus固定。CW timingはfake monotonic clock。
* G5b: audio adapter、timestamp、別thread SPSC、callback instrumentation、RX latency。CW decoderはoperator選択式。
* G5c: CW TX・RTTY AFSK loopback→FSK dummy-loadでcancel/underrun/PTT物理解除。公開する全backendで試験。
* G5d: scalar/SIMD decision/BER/許容差、waterfall on/off、24h deadline miss/PTT stuck/継続的資源増加ゼロ。

GPU/map専用processは実測未達とADRがある場合だけ追加。modemのprocess隔離・PTT保護はD04で固定し、in-process試作を障害隔離の証明にしない。

## 3. 直近backlog

| ID | 作業 / Owner | 依存 | 完了証拠 |
|---|---|---|---|
| B01 | RecentQsos compile修復 / Domain | なし | 差分とLinux/macOS core成功。assertionを弱めない |
| B02 | Windows FPC取得504対策、version固定・再試行/失敗検知、両OS LCL / Platform | なし | Windows core、両OS GUI、toolchain記録 |
| B03 | D01/D02、dataset、純JSON/時計、5試行・10%比較gate / Quality | B01/B02 | schema検証baseline、退行検出fixture、build log分離、永続artifact |
| B04 | journal起動復旧の非同期化、入力可能state / Platform | G0 | cold/warm/recovery trace、原本保全、UI外部I/O0 |
| B05 | shutdown/active operation/deadline/late callback/pump例外 / Platform | G0 | barrier競合、disk stall、遅いobserver、停止後参照なし、未ack照会 |
| B06 | heartbeat/event-to-paint/drain、障害通知とjob state / UX | B04/B05 | 10秒hang/飽和trace、N02/N03/N06判定 |
| B07 | process kill/disk full/flush失敗/package復旧 / Quality | B04〜B06 | 両OS clean-machine ack照合、package hash/run log |
| B08 | G1受入review / Product・Quality | B03〜B07 | 要件別結果manifest、blocker0、M2開始判断 |

B01/B02は担当・環境が確保できたときのみ並行可能。担当未定のまま後続を大量着手しない。

## 4. 最初の3 iteration

1. A: B01/B02、D01、fixture許諾、調査募集、B03測定定義とG0判定。toolchain障害は取得経路を検証して解消する。
2. B: G0後にB04/B05。起動・shutdown・durabilityの正常/失敗scenarioとW1測定。
3. C: B06/B07、5試行baseline、利用者入力/復旧確認、B08。G1未達ならhardeningを継続しM2へ進まない。

後続工数はG1で実績と実機確保状況を見て再見積もりする。taskにはowner、要求ID、依存、正常/失敗、OS差、migration影響、証拠保存先を必須とする。

## 5. 検証cadenceと証拠

PR: unit・変更adapter contract・小golden・dependency・range/overflow・3 OS headless・両OS GUI、1k microbenchmark。既存の make test-tools / make clean test / make gui / make run（2回）/ make verify-demo / make benchmark / make benchmark-memory / make benchmark-audio / make benchmark-rtty を出発点とする。UI/fault/soak runnerは未実装分を追加する。コマンドの存在を成功と混同しない。

Nightly: 100k W2、全golden、import fuzz、timeout/crash/saturation、UI・memory/handle/thread。Milestone: 固定reference5試行、実機matrix、8〜24h、sleep/replug、DPI/keyboard/accessibility、restore。RC: 24/48h、partition/disk full/process kill/電源断相当、署名package・pilot。

証拠索引は docs/evidence/<commit>/<gate>/manifest.json。run URL、artifact hash/保存先、OS、要求ID、scenario、期待値/実測、PASS/FAIL/NOT VERIFIED、担当・日時を保持する。生データは期限切れしないrelease/evidence保管へ保存し、CI artifactだけに依存しない。

build logと純JSONを分離しschema検証後upload。失敗時も診断log回収。baseline比10%超またはbudget超過は停止。H違反は例外不可、B/T変更は要件台帳のADR手順に従う。

## 6. 状態・責任・リスク

進行: Proposed→Ready→Implementing→Measuring→Hardening→Accepted。検証は別軸でPASS/FAIL/NOT VERIFIED/BLOCKED。コードあり・CI失敗はAcceptedにしない。source変更後は影響する旧合格を再検証する。

Productはscope、Domainは規約/互換、PlatformはOS/永続/配布、Stationは機器/DSP/PTT、UXは操作、Qualityは測定/証拠。兼務でもreview記録を分ける。週次dashboardは最後の合格gate、OS別SHA、FAIL/NOT VERIFIED、flaky、資源/BER trend、次のblockerを示す。

| リスク | 対処・停止条件 |
|---|---|
| toolchain/runner変化 | version/image記録、取得検証。環境失敗をtest成功へ置換しない |
| 実機/利用者不足 | support構成と調査確保を先行。fake成功で実機/UX gateを開かない |
| spike先行・scope拡大 | G1前は後続拡大停止、候補は採否記録後に着手 |
| 指標の取り違え | queue込み保存、UI paint、物理PTT、実threadを測る |
| 終了期限とdata safety | 生threadを強制破棄しない。cancel/process隔離/復旧状態を定義、未解決ならG1/G4停止 |
| golden/legacy権利不明 | 許諾・匿名化・hash・version固定、未確定ならG3停止 |

## 7. 旧計画との対応

旧Step 0→M0、1→M1、2→M2、3/4→M3、5→M4、7/8/9→M5、6→M6、10→M7、11→M8。旧Phase 0/1→M0/M1、2→M2/M3、3→M4〜M6、4→M7、5→M8。

CI失敗を最優先にし、要求IDで証拠を結び、ログ中核と運用MVPを区別する。退行規則は20%から10%へ統一。CW/RTTY両方向、国内4/国際2、multi-op/SO2R、移行scopeは維持する。
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
