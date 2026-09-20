# 実装品質レビュー

最終更新: 2026-09-13

## 1. レビュー範囲と判断基準

対象は現在の walking skeleton の domain、application、infrastructure、presentation、
LCL composition root、テスト、CI である。評価軸は次のとおり。

- 正しさ: ドメイン不変条件、永続化の一貫性、エラー時の振る舞い
- 堅牢性: クラッシュ復旧、入力上限、例外安全、スレッド安全、終了処理
- 効率性: UI スレッドの待ち時間、計算量、メモリ使用量、バックプレッシャー
- 保守性: SOLID、依存方向、所有権、型による契約、テスト容易性
- 移植性: Free Pascal/LCL、Windows/macOS、バイトオーダーと文字コード

## 2. 結論

アーキテクチャの骨格は計画に適合している。ドメインと LCL は分離され、永続化 I/O は
単一 worker へ隔離され、submission/completion の両 queue には上限がある。また journal は
明示的な little-endian 形式、version、CRC、flush 後 ack、未完 tail 回復を備える。

一方、プロダクション品質には未到達である。今回、直近一覧を worker の書き込みと並行して
安全に参照できなかった問題と、1 MiB を超える payload を書ける一方で再起動時には読めない
問題を **Critical** と判定し修正した。残課題は下表のゲートを通過するまでリリース対象に
含めない。

## 3. 指摘と対応

|重要度|領域|指摘|状態 / 方針|
|---|---|---|---|
|Critical|並行性|memory repository の一覧・索引へ worker と UI が同時アクセスできた|修正済み。全公開操作を critical section で保護し、clone/snapshot も lock 内で生成する|
|Critical|永続化|writer に payload 上限がなく、reader が拒否する journal を生成できた|修正済み。serialize 後、書き込み前に 1 MiB 上限を検証する|
|High|永続化|OS/process crash を模した kill 試験がなく、`FileFlush` の媒体保証は OS 依存|一部対応。append各段階のfault injectionと全tail切断位置を検証済み。Windows/macOS実機の強制終了・電源断相当試験は未完|
|High|エラー処理|repository例外が単一の内部エラーへ集約され、原因分類がなかった|対応済み。利用者には再試行可能なstorage分類、診断にはboundedな例外classとcomponent/codeを渡す|
|High|ライフサイクル|worker service の `Submit` と `Shutdown` を複数 thread から同時実行する契約がない|制約を維持。当面 UI owner のみが呼ぶ。CAT/network producer 導入前に状態 machine と同期を追加する|
|High|データモデル|contest、band、operator、station、serial、dupe/multiplier 情報が QSO にない|計画済み。contest rule model 確定後に versioned migration として追加する|
|Medium|入力|exchange 長、ID 長、timestamp 範囲の domain 制約がない|未完。contest ごとの制約と journal 全体の安全上限を分ける|
|Medium|性能|journal 起動時は全 record を object として再生するため、大規模 log で起動時間と RAM が線形増加する|未完。測定後に snapshot/checkpoint または SQLite read model を選定する|
|Medium|queue|FIFO 先頭削除に `TList.Delete(0)` を使い、queue 長に対して O(n)|容量 32/64 では許容。CAT/decoder event queue には ring buffer を使う|
|Medium|UI|LCL 画面は入力フォームのみで Recent QSO read model が未接続|対応済み。永続化済み snapshot の最新50件を grid へ表示する|
|Medium|アクセシビリティ|キーボード操作、screen reader 名、配色、DPI の検証がない|LCL UI 受入試験へ追加する|
|Low|テスト構造|単一 test runner が肥大化している|FPCUnit 導入時に domain/application/infrastructure contract suite へ分割する|

## 4. 確認できた良い設計

1. **依存性逆転**: use case は repository、clock、ID generator の interface へ依存し、LCL や
   ファイル API を参照しない。
2. **Interface Segregation**: query は `IQsoReadRepository` だけを要求し、書き込み能力を
   持たない。
3. **所有権**: repository は QSO を clone して保持し、検索結果も clone または値 snapshot で返す。
4. **非同期境界**: submit は bounded queue へ積むだけで、journal I/O と flush は worker が行う。
5. **バックプレッシャー**: submission と completion の双方が bounded であり、UI 停止時にも
   無制限にメモリを消費しない。
6. **決定的テスト**: clock と ID generator を注入し、時刻や乱数に依存しない検証が可能。
7. **独立検証**: journal を Python 実装でも検査し、writer/reader が同じ誤りを共有するリスクを
   下げている。

## 5. 性能・堅牢性ゲート

次の機能へ進む際は平均値だけでなく p95/p99/max と失敗数を保存する。

|ゲート|データ量 / 条件|合格条件|
|---|---|---|
|ID 検索|100,000 QSO、10,000 lookup|結果正答、平均 1 ms 未満を目標、退行 20% 超で失敗|
|Recent 取得|100,000 QSO、50 件を 1,000 回|順序正答、UI frame budget を圧迫しない|
|durable append|200 回、各 OS|p95 50 ms を暫定目標、全 ack record を再読可能|
|tail recovery|header/payload を各 byte 位置で切断|完全 record を保持し、未完 tail だけを除去|
|corruption|magic、length、CRC、UTF-8、version を変異|silent acceptance せず型付き corruption となる|
|queue stress|連続 submit、completion 停止、shutdown 競合|上限維持、二重 callback なし、deadlock なし|
|長時間運転|24 時間、CAT 更新 + QSO + decoder 負荷|UI stall なし、handle/thread/RAM の継続増加なし|

benchmark の閾値はハードウェア差が大きいため、まず CI artifact を baseline として保存し、
同一 runner 系列での相対退行を判定する。単発の絶対値だけで合否を決めない。

## 6. 次の実装順序

1. thread-safe read model を利用した Recent QSO presenter と LCL grid を追加する。（完了）
2. journal fault injection を導入し、write/flush 失敗と全 tail 切断位置を自動検証する。（完了）
3. structured diagnostics、health state、利用者が再試行可能なエラー分類を追加する。（完了）
4. Hamlib adapter は別 process 境界を基本とし、timeout、再接続、最新値優先 queue を実装する。（protocol clientとfake transport完了、OS別process transportは未完）
5. CW/RTTY engine は audio/device thread と DSP worker を UI から分離し、固定長 buffer pool と
   lock-free または bounded ring buffer を技術検証してから統合する。

Hamlib/CW/RTTY を先に GUI へ直結すると、device 停止が UI 停止へ波及する。したがって、上記の
fault injection と health model を先に確立することを次 phase への必須条件とする。
