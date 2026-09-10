# 交信モードと CW / RTTY 送受信エンジン方針

## 1. 結論

交信モードは QSO の分類値だけではなく、受信、復調／解読、送信文生成、変調／キーイング、無線機制御を
協調させる subsystem として実装します。初期対象は `CW`、`RTTY`、`SSB`（記録と CAT）とし、CW と RTTY は
**送受信の両方**を提供します。MMTTY や Windows 専用 DLL は中核依存にせず、新しい RTTY modem を
Free Pascal で実装します。

Hamlib は無線機制御の標準 backend とします。ただし Hamlib に modem、音声 I/O、CW decoder、ログ状態まで
担わせません。責務は次のように分けます。

```text
                       +--------------------+
User intent ---------->| Mode session       |<-------- QSO / macro / contest context
                       | coordinator        |
                       +--+----+----+-----+-+
                          |    |    |     |
                Hamlib CAT| Audio  DSP    |Keying/PTT
                          v    v    v     v
                        Rig  Device Modem Transport
                       port  port   port   port
```

この分離により、Hamlib の更新、sound device、DSP 実装、keyer を独立に交換・試験できます。

## 2. モードモデル

`TMode` 一つへ UI、ADIF、CAT の数値を詰め込まず、以下を別の value object とします。

* `TEmissionMode`: CW / RTTY / SSB。QSO と contest rule が参照する論理モード
* `TRigMode`: Hamlib が扱う rig mode、passband、data mode。機種差を含む
* `TModemProfile`: mark/space、shift、baud、polarity、stop bits、filter、AFC 等
* `TSignalPath`: radio、audio input/output、channel、PTT/keyer route
* `TModeCapabilities`: receive、transmit、decode、encode、CAT、hardware keying の可否

ADIF/Cabrillo/JARL の表記は export adapter で変換します。例えば AFSK と FSK が異なる信号経路でも、規約上
同じ RTTY なら QSO の論理モードは同じです。一方、後日の追跡用に `submode` と modem profile は session metadata
へ保存します。周波数、mode、PTT、送信先 radio の snapshot は QSO 確定時に同一 transaction へ含めます。

## 3. Hamlib を前提とする統合

### 境界

application 層には Hamlib 型を出さず、次の小さい port を置きます。

```pascal
IRigControl = interface
  function GetCapabilities: TRigCapabilities;
  function ReadState: TRigStateResult;
  function SetFrequency(const AHz: Int64): TRigCommandResult;
  function SetMode(const AMode: TRigMode; const APassbandHz: Integer): TRigCommandResult;
  function SetPtt(const AEnabled: Boolean): TRigCommandResult;
end;
```

本番 adapter は第一候補を **`rigctld` protocol client** とします。Hamlib を別 process に隔離でき、Windows/macOS
双方で Lazarus application と ABI、例外、blocking call の境界を切れるためです。直接 `libhamlib` を呼ぶ adapter は、
配布サイズや round-trip latency の計測で明確に有利な場合だけ追加します。両実装は同じ contract suite に合格させます。

### 実装規則

* Hamlib backend/model の選択、接続文字列、serial speed、DTR/RTS は typed configuration として保持する。
* `rigctld` の起動方法、接続先、version、model/capability を診断画面に表示する。
* 通信は専用 worker と bounded command queue を使い、UI thread から同期呼出ししない。
* poll は active/idle/PTT 中で周期を変え、手動 tune と送信 command を polling が上書きしないよう世代番号を付ける。
* timeout、切断、権限拒否、unsupported command、protocol error を別結果にする。
* PTT は lease と watchdog を持ち、process 終了、audio underrun、device loss、cancel で必ず解除を試みる。
* CI は fake rigctld、release lab は固定した Hamlib version と代表実機で contract/soak test を行う。

Hamlib が対応することと本製品が検証済みであることを混同しません。UI には「Hamlib reported」と
「zLog Lazarus verified」を分けた support matrix を表示します。

## 4. CW 送受信

### 送信

CW macro は contest context を token 展開して `TCwTransmission` を作り、送信 scheduler が文字、word gap、weight、
WPM を monotonic clock 上の event 列へ変換します。出力 adapter は次を同じ `ICwKeyingOutput` 契約で扱います。

1. 外部 keyer（WinKeyer 等。timing 品質の第一候補）
2. Hamlib/rig command が提供する CW keying
3. serial DTR/RTS または対応 USB keying device
4. sidetone/audio CW（練習および対応機向け）

OS scheduler で dot ごとに `Sleep` する実装は禁止します。十分な先読み queue を device へ渡し、停止、速度変更、
PTT lead/tail、送信完了を明示的な state machine にします。送信中も ESC は最優先の bounded latency で停止します。

### 受信

CW decoder は補助機能として提供し、確定 QSO を自動生成しません。audio preprocessing（DC block/AGC）、狭帯域 filter、
tone tracking、envelope、adaptive threshold、timing classifier、Morse decoder の段階へ分け、各段の観測値を waterfall と
confidence に利用します。複数 speed、QSB、noise、手打ちの揺らぎを corpus 化し、operator が候補を選択して入力欄へ
取り込む Human-in-the-loop を既定とします。

## 5. RTTY modem（MMTTY 非依存）

### RX pipeline

```text
Audio capture -> resample -> DC/AGC -> channel filter
              -> dual tone detector / complex demodulator
              -> AFC + timing recovery -> bit slicer
              -> async frame decoder -> ITA2 state -> text/confidence
```

標準 profile は 45.45 baud / 170 Hz shift を提供し、値を固定したアルゴリズムにはしません。normal/reverse、mark/space、
stop bits、USOS、FIGS/LTRS、unshift-on-space、AFC、squelch は `TModemProfile` で管理します。decode 結果は文字だけでなく、
timestamp、confidence、raw symbol decision を ring buffer に保持し、再 decode と障害解析を可能にします。

検波器は最初に小ブロック FFT または Goertzel の双方を benchmark して選びます。弱信号用の complex mixer + FIR と
matched filtering は同じ `IRttyDemodulator` 契約の別実装にし、golden IQ/audio corpus で BER と CPU 使用率を比較します。

### TX pipeline

macro/token 展開 -> ITA2 encoder -> start/data/stop symbol scheduler -> AFSK waveform または FSK keying の順に処理します。

* **AFSK:** phase-continuous DDS、click-free ramp、sample clock に基づく fractional symbol accumulator を用いる。
* **FSK:** 対応する Hamlib rig control または専用 keying adapter へ symbol event を先読み送信する。
* TX buffer が安全閾値を下回った場合は文字化けを継続せず、送信停止、PTT 解放、明確な underrun 通知を行う。
* RX/TX 切替は half-duplex state machine とし、PTT lead/tail、sound device latency、rig settle time を profile 化する。

受信文字列を自動で callsign/exchange 候補へ解析しても、重複判定と QSO 確定は既存の use case を通します。
modem が contest rule や QSO repository を直接参照することはありません。

## 6. モダンなハードウェア資源の活用

「GPU 使用」自体を目的にせず、deadline、BER、消費電力、配布容易性を測定して backend を選びます。

* capture/render と DSP の間は preallocated lock-free SPSC ring buffer とし、real-time callback で allocation、lock、file I/O をしない。
* sample は連続する `Single` 配列（SoA）とし、FPC の vectorization と platform SIMD library を利用できる kernel 境界を設ける。
* CPU SIMD（x86-64 SSE/AVX、Apple Silicon NEON）を最初の accelerated backend とする。
* 多チャネル waterfall、大規模 FFT、複数 decoder では macOS Metal と Windows の利用可能な compute backend を PoC する。
* 単一 45.45-baud decoder は GPU 転送遅延の方が大きい可能性があるため、benchmark なしに GPU を必須化しない。
* 全 accelerated backend に scalar reference implementation を用意し、同一入力で許容誤差、symbol decision、BER を比較する。
* backend は起動時 benchmark ではなく capability と保存済み profile で選択し、deadline miss 時は安全に低負荷構成へ degrade する。

UI waterfall は decode pipeline と queue を共有せず、描画低下や非表示が復調性能へ影響しない構成にします。

## 7. Audio とリアルタイム設計

`IAudioInput` / `IAudioOutput` は timestamp 付き frame を扱い、Windows/macOS の具体 API を platform adapter に隔離します。
device の sample rate へ内部 DSP を依存させず、品質と latency を選べる resampler を境界に置きます。

thread の優先順位は audio callback > modem DSP > rig polling > UI visualization とします。queue には上限と
high-water mark を持たせ、欠落 sample、overrun、underrun、clock drift、processing p95/p99 を診断可能にします。
device unplug、sleep/resume、sample-rate change では自動再接続を試みますが、勝手に別の送信 device へ切り替えません。

## 8. 性能・品質の受入基準

Phase 0 で reference machine、audio interface、corpus、SNR/channel model を固定した後、数値を ADR で確定します。
初期 engineering budget は次の通りです。

| 項目 | 初期目標 |
|---|---|
| audio callback | allocation/lock 0、deadline miss 0（24時間 soak） |
| RX audio から文字候補表示 | p95 150 ms 以下（frame 完了後） |
| CW/RTTY 送信開始 | command から p95 100 ms 以下（設定済み device） |
| ESC emergency stop | key event から PTT release command まで p99 50 ms 以下 |
| RTTY CPU | 1 decoder + waterfall で reference core の 20% 以下 |
| RTTY 正確性 | synthetic AWGN/fading corpus の BER を release ごとに非回帰 |
| 長時間動作 | 24時間で unbounded memory growth、queue overflow、PTT stuck 0 |

BER は MMTTY との主観比較だけで判定しません。clean tone、frequency offset/drift、clock error、adjacent signal、impulse noise、
selective fading と、利用許諾を得た実交信 audio を versioned corpus にします。他実装との比較は同じ audio、同じ出力単位、
同じ CPU 制約で行います。

## 9. UI / UX

* mode workspace に RX text、TX buffer、waterfall/tuning indicator、macro、rig/PTT/audio 状態を集約する。
* callsign/exchange 候補は confidence と根拠範囲を示し、single key で入力欄へ移す。
* focus が RX text に移っても function key、ESC、log shortcut の意味を変えない。
* TX 中は対象 radio、送信文字位置、残り buffer、AFSK/FSK、PTT を色だけでなく文字と形で示す。
* beginner preset、contest preset、advanced DSP panel を分け、競技中の誤操作を減らす。
* monitor level と waterfall は自動調整可能にするが、AFC/polarity/profile の自動変更は履歴と undo を持たせる。

## 10. テストと段階導入

1. pure Pascal scalar DSP、synthetic signal generator、WAV golden corpus を先に作る。
2. file input/output で RTTY round-trip と BER test を通し、sound device より先に modem を確定する。
3. fake Hamlib server で command order、timeout、reconnect、capability contract を検証する。
4. loopback audio/PTT で送受信 state machine、cancel、underrun を fault injection する。
5. CPU SIMD backend を追加し scalar と bit/symbol 単位で比較する。
6. 実機・dummy load と録音で CW/RTTY を shadow operation し、送信安全性を確認する。
7. GPU backend は CPU budget を満たさない use case が確認された場合だけ release 対象にする。

CW decoder と RTTY decoder は当初 `experimental` と表示し、送信機能、ログ記録、export の安定性とは別に有効化できます。
RTTY 送信は AFSK loopback、その後 FSK dummy-load の順で gate を開きます。

## 11. 追加 ADR

* ADR-MODE-001: Hamlib version、`rigctld` 配布／外部接続、protocol compatibility
* ADR-MODE-002: Windows/macOS audio API と device identity
* ADR-MODE-003: DSP sample rate、block size、resampler、numeric precision
* ADR-MODE-004: CW keying backend の timing / cancellation contract
* ADR-MODE-005: RTTY detector と timing recovery の benchmark 結果
* ADR-MODE-006: SIMD/GPU backend、runtime dispatch、scalar fallback
* ADR-MODE-007: PTT safety state machine と watchdog

## 12. 外部仕様の確認先

実装時は二次記事ではなく、Hamlib 公式リポジトリ／公式文書、各無線機メーカーの CAT command reference、
Microsoft と Apple の audio/compute API 文書を version と取得日付きで ADR に記録します。Hamlib の対応機種一覧は
変化するため repository に転記せず、release ごとに採用版から生成します。
