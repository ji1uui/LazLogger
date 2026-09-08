# 実施ロードマップ

日付ありの納期ではなく、品質ゲートで次段階へ進みます。各フェーズは Windows/macOS を同時に通し、
macOS 対応を最後にまとめて行いません。

## Phase 0 — Discovery / 技術検証

* source inventory と `retain / redesign / replace / retire` 台帳を作る。
* 代表ログを匿名化し、既存版から dupe/point/multi/export の golden result を採取する。
* Lazarus/FPC/LCL、package/sign/notarize、serial、audio、network、DB を両 OS で spike する。
* 5 ペルソナの利用観察を実施し、MVP の優先順位と性能測定環境を確定する。
* ADR template、coding standard、CI matrix、issue taxonomy を用意する。

**Exit:** 未決技術に benchmark/PoC があり、MVP acceptance criteria、互換 fixture、リスク owner が承認済み。

## Phase 1 — Walking skeleton

* `app/src/tests/resources` と dependency rule check を作る。
* empty session の作成、1 QSO の validation/log/reload/display を end-to-end で通す。
* append-only journal、structured diagnostics、crash recovery の最小実装を作る。
* fake rig/cluster と demo contest を用意し、実機なしで CI と練習を可能にする。

**Exit:** 両 OS の package を clean machine で起動し、異常終了後も 1 QSO を復旧できる。

## Phase 2 — Contest core MVP

* QSO edit/history、dupe、score/multi、search、import/export を縦割りで追加する。
* 最優先の国内 4 コンテストと国際 2 コンテストを golden corpus で一致させる。
* keyboard-first main window、setup wizard、command palette、テーマ、アクセシビリティを整える。
* 100,000 QSO dataset の継続 benchmark と profiler budget を CI gate にする。

**Exit:** shadow operation で既存版との結果差がなく、performance/accessibility acceptance criteria を満たす。

## Phase 3 — Station integration

* CAT、CW keyer、voice、cluster、band map を port ごとに実装する。
* capability detection、permission onboarding、disconnect/reconnect、device simulator を提供する。
* hardware matrix と firmware/driver version を release report に残す。

**Exit:** サポート表の各構成で 24 時間 soak、通信断、sleep/resume、device replug を完走する。

## Phase 4 — Advanced operation

* multi-op sync、競合解決、SO2R state machine/interlock、recording/live score を追加する。
* 競技形式別の field test と failure injection を行う。
* extension SDK は最低 2 種の contest と rig を外部 package として実装してから公開する。

**Exit:** LAN partition/rejoin で QSO 欠落なし、誤 TX 防止 test 合格、外部 extension の互換性方針が成立。

## Phase 5 — 移行と正式リリース

* read-only dry run、backup、report、rollback を備える migration assistant を提供する。
* signed installer、macOS notarization、SBOM、release notes、support matrix を用意する。
* 1 contest season は既存版と並行提供し、重大問題時にデータを失わず戻せるようにする。

**Exit:** pilot cohort の完走、restore drill、support runbook、既知制限、旧版保守方針が公開済み。

## 優先順位の付け方

`(利用者価値 + リスク低減 + 学習価値) / (実装量 + 運用負担)` を基本にし、ログ消失・得点誤り・誤送信の
リスクは数値に関係なく先に処理します。issue は persona、contest scenario、acceptance metric、依存 port、
Windows/macOS 差、migration impact を必須項目とします。

## 主なリスクと対策

| リスク | 早期シグナル | 対策 |
|---|---|---|
| 全面 rewrite の長期化 | 動作する縦割りが 1 sprint 以上ない | walking skeleton、feature slice、scope gate |
| 規約の微妙な非互換 | golden の QSO 単位差分 | rule version と explanation、専門利用者 review |
| macOS の機器差 | stub/条件コンパイル増加 | Phase 0 実機 PoC、capability model、support matrix |
| 抽象化過多 | interface が実装一つで頻繁に変更 | 抽象化条件を architecture 文書で制限 |
| 高負荷で UI freeze | p95 budget の継続悪化 | benchmark gate、bounded worker、virtualized list |
| マルチオペのログ衝突 | 重複 ID、serial gap | event/revision model、partition test、監査 UI |
| 利用者が移行しない | setup 中断、shortcut 不満 | import dry-run、legacy keymap、pilot/shadow operation |

## 最初の backlog（実装順）

1. ADR-001 toolchain/widgetset と clean-machine build
2. legacy fixture のライセンス・匿名化ルール
3. domain dependency guard と FPCUnit test project
4. `TCallsign`, `TFrequencyHz`, `TQsoDraft`, validation result
5. `ILogQsoUseCase` + in-memory repository + deterministic clock/ID
6. journal durability spike（power-loss test を含む）
7. one-screen LCL shell + Presenter + keyboard traversal
8. legacy importer の最小 slice と差分 report
9. ALL JA の dupe/point/multi golden slice
10. Windows/macOS CI artifact と smoke checklist

この順序なら、UI の大量作成より先に、移植の最大リスクである正確性、保存、依存境界、両 OS 配布を検証できます。
