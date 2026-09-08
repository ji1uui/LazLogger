# アーキテクチャ方針

## 1. 採用する形

Clean Architecture / Ports and Adapters を過度に抽象化せず適用します。

```text
LCL View -> Presenter/ViewModel -> Use case -> Domain
                                  |    ^
                                  v    |
                              Port interfaces
                                  ^
                                  |
             DB / File / CAT / Keyer / Cluster / Clock adapters
```

内側は外側を参照しません。`domain` と `application` のテストは LCL、実機、network、wall clock なしで実行します。
依存性注入は composition root の constructor injection を基本とし、service locator と writable global を禁止します。

## 2. 境界と責務

### Domain

* Entities: `TQso`, `TStation`, `TContestSession`, `TOperator`
* Value objects: `TCallsign`, `TFrequencyHz`, `TBand`, `TMode`, `TExchange`, `TQsoId`
* Services: rule evaluation、dupe policy、score/multiplier、serial allocation
* Domain events: `TQsoLogged`, `TQsoCorrected`, `TRigChanged`, `TMultiplierWorked`

domain 型は表示用文字列や LCL の `TColor` を持ちません。単位を型名に含め、UTC instant と local display を分けます。
validation error は例外で通常制御せず、field、code、message parameters を持つ result として返します。

### Application

`ILogQsoUseCase`、`ICorrectQsoUseCase`、`IChangeRadioUseCase` 等の利用者意図を表す API を提供します。
repository、transaction、clock、radio、keyer、cluster、notification は小さな port interface とします。
一つの巨大な manager interface にせず、Interface Segregation を守ります。

### Infrastructure / Platform

* 永続化: journal、snapshot、query index、backup
* file formats: legacy、ADIF、Cabrillo、JARL E-Log
* networking: telnet cluster、multi-op transport、online services
* Windows: serial/HID/credential/audio と必要な legacy bridge
* macOS: IOKit/CoreAudio/Keychain 等を用いる adapter（技術検証後に確定）

platform unit だけが OS conditional を持ち、呼出側は `TRigCapabilities` で能力を問い合わせます。
「未接続」「非対応」「権限拒否」「一時障害」を別状態にし、UI へ actionable な復旧手順を返します。

### Presentation

Form/Frame は state を描画して user intent を Presenter へ通知します。得点計算、file I/O、sleep、socket 操作をしません。
ViewModel は immutable snapshot とし、一方向 data flow で focus loop と event cascade を防ぎます。
テーマは semantic token（`status.connected`, `qso.dupe` 等）から LCL 色へ変換します。

## 3. SOLID を判断可能なルールにする

* **SRP:** unit 名に `And` が必要なら分割を検討。変更理由を PR に一文で書けない class は分割する。
* **OCP:** 新 contest/rig を既存 use case の case 文編集だけで追加しない。registry + interface で発見する。
* **LSP:** adapter の mock と実装に共通 contract suite を実行し、timeout/cancel/error semantics を一致させる。
* **ISP:** UI は巨大な `IGlobalServices` を受け取らず、必要な query/command port のみ受け取る。
* **DIP:** clock、ID generator、filesystem、network、device はすべて port 経由。domain が OS API を参照したら CI で失敗させる。

抽象化は「置換する実装がある」「決定性のため fake が必要」「外部境界」のいずれかを満たす場合に限ります。

## 4. 状態、並行処理、性能

* UI state は main thread のみで更新する。
* CAT/cluster/network/file parsing は worker task、結果は typed message で main thread へ marshal する。
* cancellation token、bounded queue、timeout を全 long-running port に含める。
* radio command は順序付き single-writer queue とし、polling と利用者 command の競合を policy で解決する。
* QSO commit は journal append → acknowledgement → 非同期 index/snapshot 更新とする。
* score と dupe は event ごとの差分更新を通常経路、全再計算を検証・復旧経路にする。

イベント bus を global object の代用品にしません。message schema、producer、consumer、thread、ordering を表にしてから追加します。

## 5. データ設計

`TQso` の識別子は内容や PC 名から算出せず、衝突耐性のある ID generator port から得ます。修正は同一 ID の
revision event とし、元データと operator/time/reason を保持します。周波数は integer Hz、時刻は UTC、表示時だけ
locale/timezone を適用します。

永続 schema は versioned migration を持ちます。アプリの downgrade、途中で電源断、disk full、破損を integration test します。
SQLite 等の具体技術は concurrent durability benchmark と macOS 配布条件を Phase 0 で比較して ADR で決めます。

## 6. Contest rule model

共通 engine と contest definition を分けます。

* engine: eligibility、dupe key、point、multiplier、penalty、total、explanation
* definition: bands/modes、exchange grammar、serial policy、期間、カテゴリ、export mapping
* extension: 複雑な規約だけが versioned `IContestRule` 実装を提供

結果は点数だけでなく `rule-id` と説明要素を返し、UI と提出前検査で根拠を示します。規約の有効年を明記し、
過去ログを開いても当時の rule version で再計算できるようにします。

## 7. テスト戦略

* unit: value object、exchange parser、dupe、score、state machine（table/property based cases）
* contract: 全 repository、rig、cluster、clock adapter に同じ期待動作
* golden: 匿名化した既存ログについて QSO ごとの dupe/point/multi と最終結果を比較
* integration: import/export round-trip、network reconnect、journal recovery、schema migration
* UI: keyboard traversal、shortcut、high DPI、dark/high contrast、screen reader label の smoke test
* hardware-in-loop: CI 外の release lab で代表 CAT/keyer/SO2R 構成を matrix 実行

テストのため production code に条件分岐を入れず、clock/device ports を fake に置換します。

## 8. ADR が必要な未決事項

1. Lazarus/FPC の最低・推奨バージョンと CPU target
2. 永続化方式と暗号化／backup strategy
3. task/thread abstraction と main-thread dispatcher
4. serial/HID/audio のクロスプラットフォーム library
5. packaging、code signing、notarization、auto-update
6. plugin sandbox と署名方式
7. localization resource format

PoC、代替案、判断基準、rollback を記録するまで、これらを application/domain API へ漏らしません。
