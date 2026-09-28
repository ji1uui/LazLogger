# 機能・非機能要件台帳

改訂日: 2026-09-26。対象: zLog Lazarus Edition。これは要求と受入条件の改訂であり、実装完了の宣言ではない。

## 1. 目的・範囲・文書の役割

Windows/macOSで、コンテストの準備、交信、記録、訂正、提出、復旧までを安全に完走できる製品を作る。ログの正確性、キーボード操作速度、CW/RTTY送受信を維持する。既存Delphi/VCL画面の機械移植や全ダイアログ再現は目標にしない。

本書を要求・受入指標の正本、[開発実行計画](DEVELOPMENT_PLAN.md)を順序・依存・ゲートの正本、[ロードマップ](ROADMAP.md)を段階の要約とする。[実装進捗監査](IMPLEMENTATION_STATUS.md)は証拠付きの現状を記録する。設計詳細は[ARCHITECTURE](ARCHITECTURE.md)、[MODE_ENGINE](MODE_ENGINE.md)、背景は[MIGRATION_POLICY](MIGRATION_POLICY.md)に残す。既存文書の数値・優先度が競合するときは本書を適用し、安全性を黙って緩和しない。

以下のM0〜M8/G0〜G8は改訂計画の識別子で、旧Step/Gate番号とは異なる。

| 到達点 | 範囲・呼称 |
|---|---|
| M0〜M1 | 検証基盤と保存・復旧のwalking skeleton。製品MVPではない |
| M2〜M3 | ログ中核。ALL JAから開始し、国内4・国際2コンテスト、訂正、提出・復旧まで |
| M4〜M6 | 運用MVP。上記にCAT、CW/RTTY送受信、cluster/spot、運用dashboardを含む |
| M7 | 高度運用。multi-op、SO2R/2BSIQ、録音、live score、拡張 |
| M8 | 移行・正式リリース。署名配布、pilot、rollback、サポート |

CW/RTTYやclusterをMVPから削除しない。途中のログ中核をMVPと呼ばない。CQRLOG由来の地図、QSL/award、onlineサービス等は採用候補であり、必須要件と混同しない。候補はM8で採否と理由を確定し、採用したものだけ受入対象へ加える。

## 2. 利用者と主要シナリオ

初心者はsetup→練習→記録→提出、熟練者はkeyboard-onlyのCQ/S&P→訂正→継続入力、国内運用者はexchange/得点/提出の一致、SO2R利用者は送信先の確実な識別、multi-op利用者は切断中記録と競合復旧、保守担当は規約・機種変更の追跡を必要とする。

M0で初心者・熟練者・SO2R・multi-op・アクセシビリティ利用者を各3名以上対象とする観察計画、募集責任者、同意・匿名化方法を作る。利用者調査は計画完了と実施完了を別記録とし、各機能の受入前に該当群で検証する。初回QSO時間、キー数、誤入力率、復旧成功率を既存版と同一課題で比較する。UX閾値はD06で事前確定する。

## 3. 機能要件

「基盤あり」はソース・テストが存在する意味で、最新コミットでの合格を意味しない。Ownerは担当ロール。実担当者は着手時に割り当てる。

| ID | 要件・受入シナリオ | 現状 | 到達点 / Owner |
|---|---|---|---|
| F01 | コンテスト、部門、局・operator情報を検証してsession作成。demo contestとsimulated rig/clusterで電波を出さず準備〜提出を練習できる | 最小画面のみ | M3 / Product・UX |
| F02 | callsign、Hz、UTC、mode、exchangeを検証しQSOを記録。保存確定後だけ成功表示。満杯・失敗では入力を保持し再試行可能。QSO IDで結果を照会できる | 基盤あり | M1 / Domain |
| F03 | journal再生、破損検出、backup/restore。ack済みQSO欠落0。未ackは保存済みの可能性を示してID照会し、盲目的再登録を防ぐ | 基盤あり | M1 / Platform |
| F04 | correction、void/restore、revision audit。操作者・時刻・理由・旧値を保持し、取消／復元後の再計算と一致 | 未実装 | M2 / Domain |
| F05 | 100,000 QSOの検索・filter・paging・scroll。全件をUIへ保持せず、集計はrevision時点を表示。更新中も新規記録可能 | recent queryのみ | M2 / UX・Domain |
| F06 | dupe、point、multi、serial、penalty、scoreの根拠とrule version。ALL JA後に国内4・国際2へ拡張しgolden一致。増分結果と全再計算が一致 | 未実装 | M3 / Domain |
| F07 | legacy読込、ADIF/Cabrillo/JARL E-Logのimport/export、事前検査。dry-run件数・警告・原本hash、文字コード/JST・UTC/単位の変換根拠を表示。非可逆項目は警告 | 未実装 | M3 / Domain |
| F08 | 設定・永続schemaのversion、upgrade/downgrade判定、backupとrollback。非対応版は原本を変更せず停止する | 未実装 | M3 / Platform |
| F09 | 接続・jobセンターで状態、capability、version、最終成功、latency、queue、再試行・取消・復旧手順を表示。worker障害もUIへ配送する | health基盤のみ | M1→M4 / Platform・UX |
| F10 | Hamlib CATの周波数・mode追従、poll世代、single-writer、timeout/cancel/reconnect。実rigctld・rig別support matrix。古いpollで操作を上書きせず、切断中も記録する | protocol/process/worker基盤 | M4 / Station |
| F11 | TX route、PTT lease/watchdog、half-duplex、ESC停止。device loss、crash、underrun、shutdown時に停止・解除を試み、解除未確認を成功表示しない。自動再送信・別deviceへの自動TX切替をしない | 未実装 | M4 / Station |
| F12 | CW macro/token、WPM変更、lead/tail、先読みkeying、sidetone。外部keyer/Hamlib/serial・USB/audio出力をcapabilityで区別し、各公開backendのtimingとcancelを測る | 未実装 | M5 / Station |
| F13 | CW RXのfilter・追従・timing・confidenceと候補選択。noise/QSB/手打ちcorpusで検証し、QSOを自動確定しない。独立に無効化可能 | 未実装 | M5 / Station |
| F14 | RTTY RX: resample/filter、AFC・timing recovery、start/data/stop、ITA2 FIGS/LTRS/USOS、normal/reverse、squelch。45.45 baud/170 Hzを標準にprofile化。WAV→文字round-tripと条件別BER | timing既知bit referenceのみ | M5 / Station |
| F15 | RTTY TX: ITA2/framing→phase-continuous AFSK、その後FSK。loopback→dummy-loadの順でPTT・cancel・underrunを検証 | 波形generatorのみ | M5 / Station |
| F16 | timestamp付きaudio、sample-rate変更、device identity、permission、sleep/resume/replug、bounded SPSC。RX text/TX buffer/waterfall/profile/送信先を同一workspaceで示し、各状態を色だけに依存させない | ringのみ | M5 / Station・UX |
| F17 | scalar正確性固定後にSSE/AVX/NEON runtime dispatchとscalar fallbackを検証。waterfall負荷がdecodeへ影響しない。GPUはCPU budget未達の実測とADRがある場合のみ | 未実装 | M5 / Station |
| F18 | DX cluster/spotのfragmentation、filter、aging、重複、異常入力、offline/reconnect。keyboardでspot→tune/転記し、規約・band・capability矛盾を抑止 | 未実装 | M6 / Platform |
| F19 | setup、QSO、訂正、提出をkeyboard-onlyで完走。再割当shortcut、IME/focus、固定入力位置、command palette、theme/high contrast/DPI、label。rate・残時間・score・接続状態dashboard | 最小入力画面 | M3→M6 / UX |
| F20 | multi-opのoffline記録、重複event排除、serial policy、partition/rejoin時の競合表示・監査。QSO欠落0 | 未実装 | M7 / Domain |
| F21 | SO2R/2BSIQのradio/audio/keyer/focusを統合したinterlock。禁止TX routeへ到達しない状態遷移と2台実機fault試験 | 未実装 | M7 / Station |
| F22 | 音声録音とQSO時刻索引、任意live score（同意・payload・停止表示）、署名付きcontest/rig拡張。SDK公開前に各2種の外部packageを検証 | 未実装 | M7 / Platform |
| F23 | migration assistant、signed package、notarization、SBOM、diagnostic bundle、clean install/upgrade/rollback、pilotと既存版並行運用1 season、support runbook | 未実装 | M8 / Platform・Product |
| C01 | 採用候補: callsign card/local history・DXCC・QSL情報・online lookup。source/時刻、TTL、rate limit、世代管理、同意、利用者が選んだ値だけ反映 | 提案 | M6採否→M8 / Product |
| C02 | 採用候補: grayline/地図/伝搬、QSL/award、統計drill-down、personal best、dock/layout preset。非表示時更新停止、集中mode、revision付き集計 | 提案 | M8 / Product・UX |
| C03 | 採用候補: Outbox online連携。再開・取消・preview/redaction・送信履歴、service別idempotency、HTTP 429/認証期限/不明結果の重複防止 | 提案 | M8 / Product・Platform |

## 4. 非機能要件

Hは不変条件（例外承認で緩和不可）。Bは既存文書の初期budget（G0で測定条件を固定）。Tは今回具体化した提案値（指定ゲート前にADRで確定）。未確定Tを合格扱いしない。

| ID | 条件・判定値 | 検証・証拠 | Gate / Owner |
|---|---|---|---|
| N01 | H: ack済みQSO欠落0、silent corruption・二重登録0。flush失敗でackしない。復旧前に破損原本を保全 | byte切断に加え外部process kill、disk full/read-only/flush failure、再起動・独立parser照合。実電源断は媒体別試験 | G1 / Platform |
| N02 | H: UI外部I/O・workerからLCL操作0。起動復旧/終了待ちも対象。B: event-to-paint p95≤50 ms、heartbeat gap>100 msが0、UI適用1回≤5 ms | W1〜W4で入力・paint・heartbeat・drain時間trace。fake worker 10秒停止、queue飽和、遅いobserver | G1 / UX・Quality |
| N03 | B: Enter/command受理からdurable flush完了までp95≤20 ms。queue待ち込み。UI成功表示までの時間も別記録 | W1〜W3、1,000回以上、各5試行。同期repository単体値で代用しない | G1 / Quality |
| N04 | B: 100kで候補/dupe p95≤50 ms、scroll/filter frame p95≤16 ms、全再集計≤2 s（進捗/取消）、warm起動入力可能≤2 s | W2でUIを含む計測。cold起動・recoveryは別分布。機能未実装時はNOT VERIFIED | G2〜G3 / Quality |
| N05 | H: queue/worker/cache上限、backpressure/drop/coalesce方針を明記。24hで継続的資源増加0。T: warm-up後RSS増加≤max(10 MiB,5%)、停止後handle/thread基準値へ復帰 | queue high-water、RSS/heap/handle/thread時系列。入力量に比例する正当なログ増加とleakを分離 | G1短期、G5/G6 24h / Platform |
| N06 | H: Running→Stopping→Stoppedで新規受付を閉じ、in-flight/通知の所有権を確定。Submit/Shutdown競合を明示契約化。T:通常shutdown≤2 s、障害時5 s以内に継続待機/復旧可能終了の状態提示 | barrierで競合を固定、disk stall/遅延callback/worker例外。timeout後に生きたthreadの参照を解放しない。OS I/O強制終了不能を隠さない | G1 / Platform |
| N07 | H: CAT/network/modem停止時もlogging継続。versioned IPC、request ID/generation/deadline/cancel、crash loop遮断、未完結果の明示 | 10秒hang、kill、out-of-order、malformed、再起動、sleep/replug、W3/W4 | G4〜G6 / Platform |
| N08 | H: 禁止TX・PTT stuck 0（公開support構成）。B: ESC event→PTT release command p99≤50 ms、TX command→開始p95≤100 ms | command発行と物理PTT解除を別測定。logic analyzer/loopback。物理解除上限はD04で機種別確定、解除不能時は障害表示と手動手順 | G4〜G5 / Station |
| N09 | H: audio callback allocation/lock/blocking I/O 0、24h deadline miss 0。SPSCは1 producer/1 consumerを固定 | callback instrumentation、別実threadのsequence/checksum stress、device loss、W4。単一thread往復benchmarkでは不可 | G5 / Station |
| N10 | B: RX frame完了→候補表示p95≤150 ms。RTTY 1 decoder+waterfallのCPU≤1 reference coreの20%。H: clean文字round-trip一致、固定corpus非回帰 | corpus別BER/文字誤り率・遅延・CPU。AWGN、offset/drift、clock error、隣接/impulse/fading、許諾済み実録音。SIMDはscalar比較 | G5 / Station・Quality |
| N11 | H: 規約golden100%一致、増分=全再計算。仕様変更はrule version/差分/根拠をレビューして新goldenを別版保存 | QSO別dupe/point/multi/score/export、境界時刻/portable/forced/correctionのtable/property試験 | G3 / Domain |
| N12 | H: import原本hash不変、silent data loss 0。Unicode/UTF-8、Hz、UTC、schema/API/ABI versionを境界で定義 | round-trip、巨大/壊れた/未知version fixture、fuzz、upgrade/downgrade、backup restore | G3/G8 / Platform |
| N13 | Windows x64とmacOS ARM64を初期必須検証案としG0でOS最低版/widgetset/FPC/Lazarusを固定。macOS x64/Windows ARM64は未検証と明示、対応表なしに対応をうたわない | 同一SHAのcore/GUI/package/clean-machine smoke。Linux CI成功は両OS成功の代替にならない | G0/G1/G8 / Platform |
| N14 | H: domain/applicationにLCL・OS I/O依存なし。deterministic clock/ID、scalar reference、小さなportと所有権契約 | dependency guard、契約test、範囲/overflow検査build、変更adapterのfault test。FPCUnit移行は既存assertionを維持 | G0以降 / Domain |
| N15 | H: credentialはOS store、未信頼入力は長さ/範囲/version検査。外部送信はservice別同意・preview・停止。secretはlog/bundleに出さない | credential/redaction/IPC入力試験、local IPC権限、依存license・version・署名検査。更新/拡張は署名・互換・rollback成立前に有効化しない | G4/G6/G8 / Platform |
| N16 | H: 診断はbounded、PII最小化。component/code/severity、queue lag、最後の完了、drop、retryを記録。heartbeatだけで健全判定しない | fault→UI状態→復旧の照合、bundle preview/redaction、diagnostic sink例外隔離 | G1以降 / Platform |
| N17 | keyboard/IME/focus、DPI/contrast/label、cancel/error recoveryを主要scenarioで検証。自動補正は根拠・Reject/Undo/Raw復元、QSO自動確定なし | 該当群のtask成功率/時間/キー数/誤操作と既存版比較。TX先を色以外でも識別。数値はD06 | G3/G5/G6 / UX |
| N18 | H: releaseに署名/hash/SBOM/既知制限/support matrix/rollbackと24・48h rehearsal、blocker 0 | clean install/upgrade/restore/pilot結果を同一release SHAへ結合。未検証構成は公開対応範囲外 | G8 / Product・Quality |

障害注入で意図的に停止した保存装置にはN03の20 ms成功保存を要求しない。その条件ではN01（虚偽ackなし）、N02（UI継続）、N06（終了状態提示）を要求する。正常系の失敗sampleを除いて性能合格にすることは禁止する。

## 5. 測定契約

W1: 空/1,000 QSOで保存と再起動。W2: 固定hashの100,000 QSOで入力、候補、scroll/filter、export、index/score再構築を同時実行。W3: W2にCAT 10秒hang、network offline/flood、保存遅延を個別・組合せ注入。W4: CW/RTTY/audio/waterfallと記録を24h、RCは48hで実施する。

W1/W2の自動負荷はTとして継続10 QSO/s、burst100件、networkは測定した想定peakの10倍を提案し、G0のD02で固定する。人の入力試験は別に行う。生成seed、dataset、queue容量、audio block/sample rate、corpus/SNR、再集計条件をmanifestへ保存する。

referenceはWindowsのIntel N150相当＋SSDを最低候補、MacはApple Silicon最低候補とし、RAM/OS/電源mode/媒体/filesystemをD02で固定する。異なるCPU/OS/runnerの数値を混ぜない。CPU%は「使用CPU時間÷wall時間÷1 core」で計算し、総CPU、RSS、wakeups・可能な範囲の電力を同じworkloadで併記する。

monotonic高分解能時計で開始/終了点を定義し、正常・失敗・timeoutを全件記録。latencyは各試行p50/p95/p99/max、sample数、失敗数を出す。5試行の中央値と範囲を併記し、試行中央値だけでtail違反を隠さない。24h試験は短時間5試行で代用しない。

測定JSONにはschema_version、commit、OS/CPU/RAM、compiler/widgetset、dependency、dataset/corpus hash、scenario/seed、build flags、時計、試行、metric/unit、閾値、baseline commit、失敗数を含める。stdoutは純JSON、build logは別ファイルとしschema検証する。

退行は同一環境・同一scenarioの承認済みbaseline比10%超でレビュー停止（20%規則を廃止）。初期budget超過も停止。hosted CIは傾向監視、正式合否は固定referenceの反復測定で判定する。雑音時は同条件再測定し、黙ってskipやbaseline更新をしない。0付近の指標はD02で絶対許容差を事前設定する。安全・正確性H違反は例外不可。B/T変更は理由・利用者影響・profile・期限・ownerをADRに残し、ProductとQualityの両方がレビューする。

## 6. 未決事項と決定期限

| ID | 決めること | Owner / 期限 | 未決時の扱い |
|---|---|---|---|
| D01 | FPC/Lazarus/OS最低版、widgetset、CPU対応tier、package再現手順 | Platform / G0 | G0不可 |
| D02 | reference構成、fixture許諾・匿名化、負荷、baseline、startup/recovery/RSS/終了のT値、測定schemaと絶対許容差 | Quality / G0（機器固有分G4前） | 対象性能はNOT VERIFIED |
| D03 | ALL JAの規約年度、残り国内3・国際2の名称/年度、golden採取元、専門review担当 | Product・Domain / M3着手前 | G3不可、候補を勝手に選ばない |
| D04 | 実rig/keyer/audio/Hamlib版、PTT物理解除上限・解除不能時手順、IPC/process isolation、lease/kill policy | Station / G4 | 実TX非公開 |
| D05 | RTTY検波/timing/resampler、CW速度・揺らぎ、SNR別BER/文字誤り上限、SIMD許容差、audio block/deadline | Station・Quality / M5 corpus固定前 | G5不可、clean bit一致で代用しない |
| D06 | 利用者調査結果、keyboard互換、UX数値、C01〜C03採否・外部service規約/同意 | Product・UX / 該当機能着手前、候補最終G8 | 未採用候補を必須化しない |
| D07 | schema/backup・暗号化方針、更新/拡張署名、license、旧版保守・移行support | Platform・Product / G3、公開分G8 | 対象公開不可 |

参照実装の観察事実と提案は区別する。CQRLOGはrevision、source path、実動作とlicenseを調査してから採用判断し、未調査の互換性を主張しない。
