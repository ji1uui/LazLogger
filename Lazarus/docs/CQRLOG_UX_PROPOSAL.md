# CQRLOG を参考にした機能・UI・非同期実行の提案

## 1. 調査範囲と扱い

参照元は [ok2cqr/cqrlog](https://github.com/ok2cqr/cqrlog) とします。CQRLOG の画面やコードをコピーするのではなく、
局情報参照、DX cluster、無線機連携、online service、award/QSL 管理などの一連の運用を参考に、コンテスト中の
即応性を重視した zLog 向け experience に組み替えます。

この文書の項目は採用決定ではなく、ユーザー検証にかける提案です。参照 repository の revision、対象 source path、
動作確認結果を Phase 0 の `CQRLOG_REVIEW` 台帳へ記録し、`Observed / Inferred / Proposed` を区別します。
外部サービスの仕様、CQRLOG の現行実装、ライセンス適合性を確認する前に互換性をうたわず、コードや画像を転載しません。

## 2. 提案する experience

### A. 一つの「運用ワークスペース」

QSO entry を常に中央へ固定し、周囲へ次の dockable panel を配置します。

```text
+---------------------------------------------------------------------+
| Contest / UTC / Rate / Score       Rig A [RX]  Rig B [TX]  Network |
+-------------------+--------------------------------+----------------+
| DX cluster &      | Callsign / Sent / Received     | Station detail |
| band map          | suggestion / validation        | DXCC / bearing |
|                   +--------------------------------+ propagation    |
|                   | Recent QSO (virtualized grid)  | notes/history  |
+-------------------+--------------------------------+----------------+
| Activity & jobs: CAT OK | upload queued | lookup cached | errors 0  |
+---------------------------------------------------------------------+
```

* panel は show/hide、dock、別 monitor、layout preset をサポートする。
* `Run`, `S&P`, `Digital`, `Post-contest`, `Beginner` preset を提供する。
* callsign entry の位置、Enter/Esc/function key の意味は preset を変えても不変とする。
* status bar は「接続あり」だけでなく、最終成功時刻、queue 件数、再試行、停止理由を表示する。
* 全機能は command palette から検索可能にし、menu 階層を覚えなくても使えるようにする。

### B. Callsign Intelligence Card

callsign 入力を debounce し、ローカル履歴、DXCC/entity、worked-before、QSL/award 状況、方位・距離、任意の online lookup を
一枚の card に統合します。情報源と取得時刻を各値に示し、値が食い違う場合は上書きせず並べます。

* local 判定は即時、network lookup は後着で表示し、QSO入力を待たせない。
* operator が採用した値だけを QSO draft へ反映し、remote response だけで既存値を変更しない。
* negative cache、TTL、rate limit、offline mode を設ける。
* callsign、locator、座標を外部へ送る前に service ごとの同意と privacy 表示を行う。

### C. DX cluster と band map

cluster console、filter、spot detail、band map を同じ spot model から構成します。

* source、spotter、受信時刻、age、mode、信頼度、worked/dupe/new multiplier を表示する。
* keyboard で前後 spot、tune、QSY、ignore、callsign entry への転記を行える。
* local band plan、contest rule、rig capability と矛盾する操作は理由付きで抑止する。
* self spot、重複 spot、古い spot、異常周波数を filter pipeline で扱う。
* cluster 切断中も logging と band map 閲覧を継続し、再接続で差分を反映する。

### D. Grayline・伝搬・地理情報

世界地図、grayline、short/long path、方位、日の出・日の入りを station card と連携させます。地図は常時描画せず、
低頻度 snapshot とし、最小化・非表示中は更新を止めます。外部予報値は「参考情報」として取得元・更新時刻を明示し、
contest score や QSO validation の必須入力にはしません。

楽しさを高める表示として、初 band/entity、personal best rate、時間帯別 worked map を控えめに提示します。
集中モードでは地図、animation、milestoneを一括非表示にできます。

### E. QSL・award・online log の「送信箱」

CQRLOG 型の post-QSO workflow を参考に、ADIF export、紙QSL対象抽出、LoTW/eQSL等のonline service連携を
contest core から分離した `Outbox` にまとめます。

* QSO commit はlocal保存で完了し、upload完了を待たない。
* service別に `Queued / Running / Succeeded / Retry / Needs attention` を表示する。
* idempotency key と送信履歴により二重uploadを防ぐ。
* contest中は自動送信を停止し、終了後にまとめて確認・送信できる。
* credential はOS credential store、upload payload は送信前preview/redactionを提供する。
* award進捗はmaterialized viewとして非同期更新し、QSOログの正本にしない。

### F. Logbook・検索・統計

検索条件を文章として読める filter chip にし、頻用検索を保存します。QSO grid はvirtualized pagingとし、全件をUI controlへ
読み込みません。集計はband/mode/operator/time/entity別のdrill-downを提供し、chartのpointから該当QSO一覧へ戻れます。

変更、merge、削除、importにはpreview、件数、validation error、undo可能なrevisionを必須にします。重い再集計中でも
QSO entryと保存を優先し、表示される統計には「QSO revision N時点」を付けます。

### G. 接続センターと診断

Hamlib、keyer、audio、cluster、multi-op、online serviceを一つの接続センターで管理します。

* device/serviceごとにcapability、version、endpoint、権限、最終応答、latencyを表示する。
* `Test` は実運用stateを変更しないdry-runを基本とし、PTTを伴うtestはdummy load確認を要求する。
* 「失敗」のみでなく、権限付与、port競合、rate limit、認証期限等の次の操作を示す。
* support bundleはqueue depth、thread heartbeat、child process stderr、Hamlib command traceを含め、秘密情報をredactする。

## 3. UIを停止させない実行モデル

### 絶対ルール

LCL main thread が行うのは、event取得、短いvalidation、immutable ViewModelの適用、描画要求だけです。main threadでは
socket/audio/device/file/database接続、DNS、外部process待機、全件検索、得点全再計算、画像生成、`Sleep`を禁止します。
「通常は速い」処理でも外部I/Oなら非同期portを通します。

UIへ返す一回の適用処理は5 msをbudgetとし、100件を超える結果はpagingまたはframe単位に分割します。workerからLCL
componentへ直接アクセスせず、main-thread dispatcherへimmutable messageを渡します。

### process分離

| Process | 責務 | 障害時の扱い |
|---|---|---|
| `zlog-ui` | LCL UI、Presenter、application command受付 | session journalから再起動・復旧 |
| `rigctld` | Hamlib backendとserial/USB CAT | supervisorがbackoff再起動、logging継続 |
| `zlog-modemd` | CW/RTTY DSP、audio stream、送信scheduler | PTT watchdog解除、UIへdegraded通知 |
| `zlog-netd` | cluster、lookup、upload、update | outbox保持、offlineへ移行 |
| `zlog-mapd`（必要時） | map tile/cache、grayline、重い描画用data | panelを停止しQSO入力は継続 |

最初から全processを必須にせず、`IRigControl`、`IModemSession`、`INetworkJobs`のin-process adapterでも同じprotocol contractを
実行できるようにします。ただしHamlibとmodemは送信安全性・native library障害・real-time優先度のためprocess分離を既定とします。
map processはprofileで計測し、UI GPU driverや大きなtile decodeが停止原因となる場合に有効化します。

### process間protocol

* local IPCはversioned、length-prefixed messageとし、request ID、deadline、cancellation、capability negotiationを持たせる。
* UIはchild processの同期responseを待たず、command受付後に`Pending` stateを表示する。
* heartbeatを「健全性」と誤認せず、queue lag、last completed command、audio deadline missも監視する。
* crash loopは無限再起動せずcircuit breakerを開き、原因と手動再開をUIへ示す。
* process終了時に未完了requestを明示的な失敗にし、古いresponseをgeneration IDで破棄する。
* IPC入力は外部入力と同様に検証し、child processへcredentialや全QSOを不必要に渡さない。

### thread分離

各process内では目的ごとにownerが一つのqueueを持ちます。

* UI: main thread + dispatcher。repository query worker poolは上限付き。
* modem: real-time audio callback、DSP worker、TX scheduler、telemetry。UI用waterfallは低優先度の別consumer。
* Hamlib client: radioごとのsingle-writer command worker。poll commandとoperator commandに優先度とgenerationを持たせる。
* network: connectionごとのstate machine。DNS/connect/read/retryをcancel可能にする。
* persistence: journal single writer。query index、backup、award/score view更新は別worker。

unbounded queue、workerごとのglobal state、thread termination、busy waitを禁止します。shutdownは`Stop accepting -> Cancel -> Drain/flush
within deadline -> Force close -> Report recovery state`の順にします。

## 4. 非同期UXパターン

* 100 ms未満は状態変更のみ、100 ms超はinline progress、1秒超はjob centerへ表示する。
* modal progress dialogは使わず、QSO entryを継続できるbackground jobとする。
* cancelはbutton表示だけでなく、port、worker、IPC、外部processまで伝播させる。
* stale resultにはquery generationを付け、callsignを変更した後に前のlookup結果を表示しない。
* optimistic updateは復元可能な設定に限定し、QSO durable commitとPTTには用いない。
* failure toastは一度だけ表示し、継続的な状態は接続センター／job centerへ集約する。
* backpressure時は「遅い」だけでなくqueue数と停止できる処理を示し、loggingのpriorityを上げる。

## 5. 優先順位

| 優先 | 提案 | 理由 | 成功指標 |
|---|---|---|---|
| P0 | 接続センター、job center、UI heartbeat | 全機能の障害を可視化しfreezeを早期検出 | 入力p95、heartbeat gap、復旧時間 |
| P0 | 非同期callsign cardとlocal cache | 入力を止めず判断材料を集約 | keystroke-to-local-result、stale表示0 |
| P0 | Hamlib/CAT process supervisor | device障害をUIから隔離 | disconnect中QSO欠落0、復旧成功率 |
| P0 | virtualized log grid | 大規模logでも一定応答 | 100,000 QSOでframe budget達成 |
| P1 | cluster + band map統合 | S&Pの操作数を削減 | spot-to-tune時間、誤band率 |
| P1 | Outbox型online連携 | upload障害を競技運用から隔離 | commit待ち0、二重送信0 |
| P1 | grayline/方位/station detail | DX判断と運用の楽しさ | panel利用率、lookup採用率 |
| P2 | award/QSL workflow | contest後の継続利用 | export/upload完了率、再作業時間 |
| P2 | map/統計のprocess分離 | 高負荷表示の影響を限定 | 表示負荷中も入力p95維持 |

## 6. 応答性の受入試験

* fake Hamlibを10秒hangさせても文字入力、QSO commit、画面移動のp95がbudget内である。
* DNS timeout、cluster flood、HTTP 429、offlineを同時発生させてもqueueが上限を超えない。
* RTTY decodeとwaterfallを24時間動かし、UI heartbeat gap 100 ms超、audio deadline miss、PTT stuckがない。
* 100,000 QSOのfilter/export/score rebuild中に、新規QSOを20 msのdurable受付budget内で保存できる。
* map childを強制終了してもUIは操作可能で、panelだけがdegradedとなり再起動できる。
* shutdown中のupload、CAT command、audio TXをfault injectionし、journal整合性とPTT解除を確認する。
* Windows/macOS双方でsleep/resume、device replug、child crash loopを自動scenarioとして実行する。

結果は平均値でなくp50/p95/p99、最大queue depth、dropped/coalesced message数とともにrelease artifactへ保存します。

## 7. CQRLOGレビューで確認する項目

Phase 0では参照revisionを固定し、少なくとも次をsourceと実動作の両方で確認します。

1. QSO entryからcallsign情報、過去QSO、地図へ至る情報の流れ
2. Hamlib/`rigctld`の起動、監視、timeout、再接続、複数radioの扱い
3. DX cluster filter、band map、spot agingとkeyboard操作
4. digital mode外部連携とQSO fieldへの転記境界
5. online lookup、LoTW/eQSL等のupload、失敗時の再試行とcredential保存
6. QSL、award、statistics、graylineが共有するquery model
7. database accessと長時間処理がUI threadへ与える影響
8. import/export、backup/restore、configuration migration

見つかった機能をそのままbacklogへ入れず、「contest中の意思決定時間を減らす」「post-contest作業を再開可能にする」など
zLog側のjobと測定可能な指標へ翻訳してから採否を決めます。
