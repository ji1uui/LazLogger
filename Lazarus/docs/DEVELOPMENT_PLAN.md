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
