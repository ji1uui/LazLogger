# マルチスレッド安全性監査

最終更新: 2026-09-21

## 結論

現状は **UIを通常のQSO保存I/Oから分離するwalking skeletonとしては妥当** だが、
「マルチスレッド対応が十分に完成した」とは判定しない。QSO保存、completion配送、Hamlib処理には
専用workerとbounded queueがあり、LCL widgetはmain threadだけから更新される。一方、公開APIの一部は
single-owner契約であり、任意のthreadから同時に`Submit`/`Shutdown`できるサービスではない。

## 実装済みの安全境界

|境界|現状|保証|
|---|---|---|
|LCL UI|main thread|workerはwidgetを操作せず、completionをmain threadでdrainする|
|QSO永続化|単一worker|file I/OとflushをUI threadから分離する|
|submission/completion|critical section付きbounded queue|無制限なメモリ増加を防ぎ、pending/in-flightを容量へ含める|
|completion競合|結果保持と通知再試行|永続化済みQSOを再実行せず、exactly-once callbackを維持する|
|UI終了|disable → worker join → async call再除去|破棄後のnotifierを指す遅延callbackを残さない|
|予期しないpump例外|worker内で隔離|workerを存続させ、health monitorへcritical diagnosticを通知する|
|repository/read model|critical section|workerの追加とUIのrecent queryを直列化する|
|Hamlib|専用worker/process|timeoutとbackoffによりUI threadへdevice I/Oを持ち込まない|
|audio ring|lock-free SPSC|事前確保した固定容量を、1 producer / 1 consumerに限って使用する|

## 未達・制約

1. `TSubmissionWorkerService`と`TRigWorkerService`のlifecycle APIはUI ownerから直列に呼ぶ契約で、
   `Submit`/`RequestFrequency`と`Shutdown`の同時実行は保証していない。
2. `StopAndJoin`には終了deadlineがない。filesystem、driver、child processがOS内部で停止した場合、
   application終了が待ち続ける可能性がある。
3. audio ringはSPSC専用である。複数producer、複数consumer、producer/consumerの途中交換には使えない。
   またWindows/macOSを含むCPU memory-orderingの長時間実測は未完である。
4. RTTYはscalar referenceとbenchmarkだけで、audio callback、DSP worker、decode event queueを接続した
   concurrent pipelineではない。
5. completion observerが遅い場合はmain threadを消費する。1回のdrain上限はあるが、callback時間budget、
   heartbeat、event-to-paintの自動監視はない。
6. ThreadSanitizer相当、同時submit/shutdown、device loss、disk stall、24時間soakの証跡がない。
7. CI定義はあるが、対象commitのWindows/macOS実行結果と性能artifactはrepository内に保存されていない。

## 次の受入ゲート

- lifecycleを明示的なstate machineにし、active operationを追跡してconcurrent shutdownを決定的に試験する。
- worker停止にdeadlineと強制切断可能なadapter契約を追加し、UI終了時間の上限を定める。
- producer/consumerを実threadで動かすaudio stressを追加し、overrun、破損、CPU、RSSを継続測定する。
- UI heartbeatを記録し、QSO burst、journal stall、CAT timeout、RTTY負荷時の最大stallを測定する。
- Windows/macOS実機で強制終了、audio device loss、rigctld停止・再起動、sleep/wakeを試験する。

上記ゲートを通過するまでは、現在の実装を「UI非ブロッキング設計の基礎」と表現し、
一般的なmulti-thread safetyや24時間contest運用の保証とは扱わない。
