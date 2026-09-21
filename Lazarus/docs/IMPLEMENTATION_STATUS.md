# 実装進捗監査

最終更新: 2026-09-21

## 1. 判定方法

進捗はファイル数や実装行数ではなく、次の4状態で判定する。

- **Accepted**: 実装、automated test、対象OSの実行証跡、受入値が揃っている
- **Implemented**: 実装とtestはあるが、対象OSまたは実機の証跡が未確認
- **Partial**: 最小sliceだけ実装され、仕様上必要な機能が残る
- **Not started**: executableな縦割りがない

PR本文や過去の説明に「CI成功」と書かれていても、repository内にrun URLや結果artifactがなく、この作業環境でも
Free Pascalを実行できない場合はAcceptedと判定しない。

## 2. フェーズ判定

|Phase|状態|実装済み|Exit条件に対する不足|
|---|---|---|---|
|Phase 0 Discovery|Partial|設計文書、CI定義、journal/repository/audio/RTTY benchmark runner、fake rigctld|toolchain ADR、CQRLOG参照revision、実測baseline、Windows/macOS実機PoC、persona検証が未完|
|Phase 1 Walking skeleton|Implemented|QSO validation、durable journal、非同期保存、Recent QSO UI、diagnostics、fake rig/process|両OS packageのclean-machine起動、署名、異常終了後の実行証跡、versioned IPCが未完|
|Phase 2 Contest core MVP|Not started|汎用QSO記録のみ|QSO edit/history、dupe、score、multiplier、contest rule、search、import/export、golden corpusが未実装|
|Phase 3 Station integration|Partial|rigctld protocol/process/worker、audio ring、RTTY synthetic scalar reference|実rig matrix、audio device、PTT safety、CW、ITA2、timing recovery/AFC、WAV corpus、24h soakが未完|
|Phase 4 Advanced operation|Not started|なし|multi-op、SO2R interlock、network sync、band map、live scoreが未実装|
|Phase 5 Migration/release|Not started|journal verifierのみ|legacy importer、dry-run/report/rollback、installer、notarization、SBOM、pilot運用が未実装|

## 3. 実装と証跡

|領域|状態|確認できる証跡|監査結果|
|---|---|---|---|
|Domain value objects / Log QSO|Implemented|deterministic unit scenarios|基本validationのみ。contest固有不変条件はない|
|Journal durability|Implemented|CRC、version、全tail切断、fault injection、独立Python parser|process kill、disk-full、実電源断、媒体flush保証は未検証|
|Repository query|Implemented|100k insert/lookup/recent benchmark runner|CI数値と退行閾値がrepositoryに固定されていない|
|UI responsiveness|Partial|bounded submission/completion、worker、最大16 callback drain|heartbeat/event-to-paint計測、keyboard/DPI/accessibility試験がない|
|Hamlib|Partial|fake protocol、実child-process fixture、timeout/backoff、dedicated worker|実rigctld version、radio model、PTT、capability、permission、replug試験がない|
|Audio transport|Partial|preallocated lock-free SPSC ring、overflow telemetry、benchmark runner|audio API adapter、real-time priority、concurrent soak、device lossが未実装|
|RTTY|Partial|45.45-baud synthetic AFSK、scalar correlator、clean BER benchmark|ITA2、start/stop framing、clock recovery、AFC、filter、AWGN/fading/WAV corpus、TX/PTTが未実装|
|CW|Not started|設計文書のみ|keying、sidetone、decoder、latency/PTT safety testがない|
|Contest logging|Not started|なし|dupe/point/multi/serial/score/export互換がない|

## 4. コード監査で修正した事項

scalar RTTY generatorはbit境界を `ceil(bit * sample_rate / baud)` で切り替える。一方、decoderは従来
`floor`を使っていたため、fractional baudでは各window先頭へ直前bitのsampleを1個含める場合があった。
clean signalでは相関利得に隠れていたが、低SNRや短いsymbolではBER悪化要因になる。この境界をgeneratorと同じ
`ceil`へ統一した。

submission worker は completion queue の空きを確認してから永続化していたが、確認と投入は
atomic ではない。別 producer が間へ投入すると、QSO は永続化済みなのに completion を失い、
UI が `submitting` のまま残る可能性があった。さらに単純な再試行は QSO を二重登録する。
永続化結果を submission queue 内に保持し、completion 投入だけを再試行する状態へ変更した。
保持中の completion と worker が取り出した in-flight item も queue 容量と `PendingCount` に含め、
取り出し直後に新規 submit が割り込んでも bounded queue 契約を維持する。

completion notifier は queue 投入後に UI wake-up を行う。notifier の例外が worker まで伝播すると、
completion 自体は queue にあるにもかかわらず worker が異常終了し得たため、wake-up を best-effort
境界とし、投入済み completion の所有権を変えないようにした。

## 5. 性能に関する結論

benchmark runnerとJSON artifact upload定義は存在するが、このrepositoryの現在のcommitには測定artifact、runner仕様、
比較baseline、許容退行率が保存されていない。したがって「性能が計画値を満たした」とはまだ判定できない。

次に固定すべき値は次のとおり。

1. journal append p50/p95/p99/maxとfilesystem/runner情報
2. 100,000 QSO lookup/recent queryのp95とpeak RSS
3. audio ring block latency、concurrent SPSC 24時間overrun、CPU/wakeup
4. RTTY corpus別BER、decode real-time factor、frequency offset限界
5. LCL event-to-paint heartbeat gapとcompletion drain時間

## 6. 次の優先順位

機能追加より先に、次の検証基盤を完成させる。

1. CI結果からbenchmarkをbaselineとしてversion管理し、同一runner系列で20%超の退行を検出する。
2. lock-free audio ringのproducer/consumer concurrent stressとThreadSanitizer相当の検証を追加する。
3. RTTYへdeterministic AWGN/frequency-offset corpusを追加し、BER曲線をscalar referenceで固定する。
4. ITA2 encoder/decoderとstart/data/stop framingを追加して文字列round-tripを成立させる。
5. 実`rigctld` support matrixとPTT watchdogを実装してからLCLへCAT操作を接続する。

Contest coreが未着手のため、現在の成果物を「zLog代替」やMVPとは扱わない。現状はPhase 1のwalking skeletonと
Phase 3向け技術spikeが並行して存在する状態である。
