# 0008: 無線機ポートと HamlibComponent アダプター

- 状態：提案（この ADR を含む PR のマージで決定）
- 日付：2026-10-19
- 関連：M0 タスク T8（[05_DEVELOPMENT_PROCESS.md](../05_DEVELOPMENT_PROCESS.md) 第 13 節）、[00_DEVELOPMENT_POLICY.md](../00_DEVELOPMENT_POLICY.md) 決定事項 D3・D12・D20、旧未決事項 Q10、[04_ARCHITECTURE.md](../04_ARCHITECTURE.md) 第 4 節

## 背景

無線機制御には HamlibComponent を使う（D3）。コンポーネントは同じリポジトリの [`hamlib_component/`](../../../hamlib_component/)（Rev.6.1）にある。
T8 では、次の 5 点を決める必要がある。

- 中核が依存する無線機の窓口（ポート）の形
- コールバックがどのスレッドで、何回届くか
- ADIF のモードと無線機のモードの対応
- Hamlib のライブラリの読み込みと、CI での用意
- 旧未決事項 Q10（PTT の送信時間の監視、CW 送信、読み込み先の API 指定、GUI なしでのコールバック、複数の無線機）の答え

## 選択肢

### コンポーネントの取り込み方

| 選択肢 | 長所 | 短所 |
|---|---|---|
| **ソースのユニットを `-Fu` で参照する** | LCL に依存しない部分だけを使える。CLI とテストでも同じ。FPC だけでビルドできる | パッケージの依存関係を自分で書く |
| Lazarus パッケージ（`HamlibComponent.lpk`）を使う | Lazarus の IDE で扱いやすい | `lazbuild` が必要。LCL 用の登録ユニットも含まれる |
| コードを MuninnLog にコピーする | 独立する | 二重の保守になる |

### 中核から見た窓口

| 選択肢 | 長所 | 短所 |
|---|---|---|
| **中核に `IRadioPort` を置き、アダプターが `IRigService` を包む** | 中核は HamlibComponent の型を知らない。テストで差し替えられる。周波数・モードを中核の型（`TFrequencyHz`、`TMode`）で扱える | アダプターの分のコードが増える |
| 中核が `IRigService` を直接使う | コードが少ない | 中核が外部コンポーネントに依存する（AGENTS.md 第 2 節に違反） |

## 決定

1. **取り込み方**
   - MuninnLog は `hamlib_component/src` のユニットを `-Fu` で参照する。コードはコピーしない。
   - テストは `hamlib_component/test/FakeHamlibLoader.pas`（ライブラリを使わない模擬ローダー）も参照する。製品のビルドには含めない。
2. **無線機ポート**（`Muninn.Core.Radio`）
   - `IRadioPort`：`Connect`、`Disconnect`、`IsConnected`、`SetFrequency`、`GetFrequency`、`SetMode`、`GetMode`、`SetTransmit`、接続・周波数・エラーのイベント。
   - 接続設定は `TRadioConnection`：機種番号、機種名、ポート、conf トークン、ポーリング間隔。
   - 結果は `TRadioResult`。エラーの種類は `TRadioError` の 9 種類（未接続、接続失敗、ポート使用中、タイムアウト、非対応、一時的に使えない、取り消し、失敗、なし）で、UI の表示（[04](../04_ARCHITECTURE.md) 4.2 節）に対応する。
3. **アダプター**（`Muninn.Integrations.Hamlib` の `THamlibRadio`）
   - `IRigService` を 1 つ受け取る。`TRigServiceFactory` はプロセスに 1 つ作り、無線機ごとに `CreateService` する。
   - 中核の型と HamlibComponent の型の変換だけを行う。HamlibComponent の型は、このユニットの外に出さない。
   - 周波数は Hamlib の `Double` を四捨五入して整数 Hz にし、`TFrequencyHz` の範囲外なら失敗として報告する。
4. **スレッドとコールバック**
   - ポートは UI スレッド（メインスレッド）からだけ呼ぶ。
   - 結果は HamlibComponent が `TThread.Queue` でメインスレッドに渡す。LCL のアプリでは自動で届く。LCL を使わないプログラム（CLI、テスト）は `CheckSynchronize` を呼ぶ。
   - コールバックは 1 回の呼び出しにつき必ず 1 回呼ばれる。未接続や対応の無いモードは、メソッドから戻る前に呼ばれる。`Disconnect` は待っている呼び出しを取り消し（`reCancelled`）、そのコールバックは `Disconnect` の中で呼ばれることがある。
   - ポートを解放すると、待っている呼び出しの結果は捨てる（コールバックを呼ばない）。解放済みの画面などに結果が届かないようにするため。
5. **モードの対応**

   | ADIF の MODE / SUBMODE | 無線機のモード |
   |---|---|
   | SSB / USB、SSB / LSB | USB、LSB |
   | SSB（サブモード無し） | 非対応（USB か LSB かが決まらない） |
   | CW、AM、FM、RTTY | CW、AM、FM、RTTY |
   | DIGITALVOICE / C4FM、DIGITALVOICE / DSTAR | C4FM、D-STAR |
   | DIGITALVOICE / FREEDV、その他の ADIF のモード（FT8、PSK、SSTV など） | PKT-USB（データ通信用の USB） |
   | ATV、その他の DIGITALVOICE、ADIF に無いモード | 非対応 |

   - 無線機から読んだモードは、無線機の表示名（`RadioText`）と、ADIF のモード（分かる場合だけ）で返す。
   - PKT-USB などのデータ用のモードからは ADIF のモードが決まらない（FT8 か RTTY かを無線機は知らない）。この場合、QSO のモードは利用者の選択やデジタルモードのアプリから決める。
6. **ライブラリの読み込み**
   - HamlibComponent の探索に従う。`TRigServiceFactory.Create(<パス>)` で読み込み先を API で指定できる。環境変数 `VELA_HAMLIB_PATH` は候補を 1 つ追加する。
   - 検証済みの版は Hamlib 4.5〜4.7。範囲外の版は起動時に拒否される（`EHamlibUnsupportedVersion`）。
7. **テスト**
   - 模擬ローダーで、アダプターの動作（接続、設定、周波数・モード・PTT、失敗、ポーリング、解放後の結果の破棄）を試験する。
   - 実際の Hamlib の**ダミー機種（機種番号 1、ポートは空）**で、周波数とモードの設定と取得を試験する。
   - ライブラリが無い環境では、ダミー機種のテストを「無視（Ignore）」にする。環境変数 `MUNINN_REQUIRE_HAMLIB=1` のときは失敗にする。CI は 3 OS ともこれを指定する。
   - CI でのライブラリの用意：Linux は apt の `libhamlib4t64`（Ubuntu 24.04 は 4.5.5）、macOS は Homebrew の `hamlib`、Windows は Hamlib の公式リリース `hamlib-w64-4.6.5.zip`（SHA-256 を固定）。

## 旧未決事項 Q10 への答え

| 確認したい点 | 答え | MuninnLog の対応 |
|---|---|---|
| PTT の送信時間の監視 | コンポーネントには無い。二段タイムアウトは I/O の保護 | MuninnLog が送信時間の上限を監視して PTT を解除する（送信の機能を作るときに実装する） |
| CW 送信 | コンポーネントに `rig_send_morse` 相当は無い | WinKeyer または HuginnEngine で行う。必要になったらコンポーネントへの追加を検討する |
| 読み込み先の API 指定 | `TRigServiceFactory.Create(<パス>)` で指定できる | 配布物に同梱したライブラリのパスを渡す |
| GUI なしでのコールバック | `TThread.Queue` でメインスレッドに届く。GUI なしでは `CheckSynchronize` が必要 | テストで確認した。CLI で無線機を使うときも同じ |
| 複数の無線機 | 1 つのファクトリから複数の `IRigService` を作れる（ローダーを共有する設計） | SO2R は無線機ごとに `THamlibRadio` を作る。複数台の同時動作は SO2R の作業で試験する |

## 結果

- HamlibComponent の更新は同じリポジトリの変更として扱い、CI の無線機テストで確認する（[05](../05_DEVELOPMENT_PROCESS.md) 第 9 節の「取り込み方」を更新した）。
- 中核は `IRadioPort` だけに依存し、HamlibComponent の変更の影響はアダプターに閉じる。
- `scripts/test.sh` は結合テストのビルドに `src/integrations`、`hamlib_component/src`、`hamlib_component/test` を加える。
- CI は `hamlib_component/src` と模擬ローダーの変更でも実行する。
- 配布物には Hamlib のライブラリの同梱が必要（配布の作業で扱う。Hamlib は LGPL）。
- `GetPtt` はコンポーネントに無いため、ポートにも送信状態の取得を置かない。ポーリングは周波数だけを取得する。

**見直す条件：**

- HamlibComponent の API が変わったとき（Rev.7 など）
- 検証済みの範囲の外の Hamlib を使う必要が出たとき
- スプリット、VFO、レベルなどをポートに加えるとき（M1 の Hamlib 連動）
