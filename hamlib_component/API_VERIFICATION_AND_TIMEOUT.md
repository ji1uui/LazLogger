# HamlibComponent Rev.4.2 — Hamlib API 照合と二段タイムアウト実装

**実施日**: 2026-10-12
**照合対象**: Hamlib master（4.7.x 系）の `include/hamlib/rig.h`、`include/hamlib/riglist.h`、`src/conf.c`、`src/serial_cfg_params.h`
**検証環境**: FPC 3.2.2 (x86_64-linux)、heaptrc、実行可能テスト 8 本

---

## サマリ

実ヘッダとの突き合わせで、**タイムアウト未実装以外に 4 系統の誤り**が見つかりました。
いずれも Fake ローダでは永久に検出できない種類のものです。

| # | 問題 | 影響 | 状態 |
|---|---|---|---|
| A-1 | モデル番号 11 個中 9 個が誤り | **別機種のバックエンドに接続** | 修正 |
| A-2 | `pbwidth_t` を `cint64` で束縛 | **Win64 で引数列が破綻** | 修正 |
| A-3 | `RIG_VFO_MAIN` / `SUB` のビット取り違え | **Sub 指定が Main に当たる** | 修正 |
| A-4 | エラーコードの符号と値が誤り | 誤った分岐・誤ったドキュメント | 修正 |
| T-1 | コマンドタイムアウト未実装 | **無応答リグで永久ハング** | 二段構えで実装 |

全テスト合格、リーク 0、Release / Debug 両構成で警告・Note 0 です。

---

## A-1: モデル番号（最も危険）

`riglist.h` の規則は次のとおりです。

```c
#define MAX_MODELS_PER_BACKEND 1000
#define RIG_MAKE_MODEL(a,b) (MAX_MODELS_PER_BACKEND*(a)+(b))
#define RIG_DUMMY 0 / RIG_YAESU 1 / RIG_KENWOOD 2 / RIG_ICOM 3
```

| 定数 | 旧（誤） | 新（正） | 旧値の実体 |
|---|---|---|---|
| `RIG_MODEL_IC7300` | 3085 | **3073** | IC-705 |
| `RIG_MODEL_IC705` | 3070 | **3085** | （未定義領域） |
| `RIG_MODEL_IC7610` | 3083 | **3078** | （未定義領域） |
| `RIG_MODEL_IC7600` | 3061 | **3063** | （別機種） |
| `RIG_MODEL_FT991A` | 122 | **`FT991` = 1035** | （未定義領域） |
| `RIG_MODEL_FTDX10` | 135 | **1042** | （未定義領域） |
| `RIG_MODEL_TS890S` | 1035 | **2041** | FT-991 |
| `RIG_MODEL_K3` | 2057 | **2029** | （別機種） |
| `RIG_MODEL_KX3` | 2070 | **2045** | （別機種） |

IC-7300 のつもりで IC-705 のバックエンドに繋がる状態でした。CI-V のコマンド体系は
近いので「一見つながるが一部の操作だけ失敗する」という最も厄介な壊れ方をします。

Hamlib に `FT991A` という独立項目は存在せず、FT-991/991A は同じ `RIG_MODEL_FT991`
で扱います。定数名も実体に合わせて改名し、`K3S` / `K4` を追加しました。

数値の由来を追えるよう、算出規則と照合日をヘッダコメントに残しています。

---

## A-2: `pbwidth_t` の ABI 不一致

```c
typedef signed long shortfreq_t;
typedef shortfreq_t pbwidth_t;
```

`pbwidth_t` は C の `long` です。Linux/macOS（LP64）では 8 バイトなので
`cint64` でも偶然一致しますが、**Windows（LLP64）では 4 バイト**です。
`rig_set_mode` / `rig_get_mode` の第 4 引数がずれ、スタック上の引数列が破綻します。

実ヘッダから抽出した型をすべて別名として明示し、綴りの揺れを封じました。

```pascal
hl_model_t   = cuint32;   { rig_model_t    }
hl_vfo_t     = cuint;     { vfo_t          }
hl_freq_t    = cdouble;   { freq_t         }
hl_rmode_t   = cuint64;   { rmode_t        }
hl_pbwidth_t = clong;     { pbwidth_t ← long であって int64 ではない }
hl_token_t   = clong;     { hamlib_token_t }
hl_ptt_t     = cint;      { ptt_t          }
```

あわせて `out` 引数を受ける一時変数も対応する C 型に揃え、呼び出し前にゼロ初期化
しています（Hamlib が失敗時に書き込まない場合でも未初期化値を読まないため）。

**注**: `rig.h` には `BUILTINFUNC` 定義時に `rig_set_freq` が引数 4 個になる分岐が
あります。これはデバッグビルド専用で、配布バイナリは 3 引数版です。現在の束縛は
後者に一致します。

---

## A-3: VFO ビットの取り違え

```c
#define RIG_VFO_SUB   RIG_VFO_N(25)
#define RIG_VFO_MAIN  RIG_VFO_N(26)
```

旧実装は `SUB = 1 shl 26` / `MAIN = 1 shl 27` で、**Sub を指定すると Main に当たり**、
Main を指定するとどの VFO にも該当しないビットになっていました。デュアル受信機では
エラーにならず静かに別の受信機を操作します。隣接ビットなので再発しやすく、
コメントで警告を明記しました。

---

## A-4: エラーコードの符号

`RIG_E*` は**正の enum 値**で、関数は**その符号を反転した値**を返します。

| 定数 | 値 | 関数の戻り値 |
|---|---|---|
| `RIG_ETIMEOUT` | 5 | -5 |
| `RIG_EIO` | 6 | -6 |
| `RIG_ENAVAIL` | 11 | -11 |
| `RIG_EPOWER` | 20 | -20（電源 OFF） |
| `RIG_EACCESS` | 22 | -22（ポート使用中） |

マニュアルに書いた「-3 = RIG_EIO」は誤りでした（-3 は `ENOMEM`）。
全 23 個の定数を `HamlibTypes.pas` に追加し、符号の扱いをコメントで明記しています。

この照合の副産物として **`RIG_ETIMEOUT` の存在**が確認でき、Hamlib 自身が報告する
タイムアウトを `rcsTimeout` に写せるようになりました（下記 T-1 の第 1 段）。

---

## T-1: 二段構えのコマンドタイムアウト

### 設計

```
┌─ 第 1 段: Hamlib 自身の timeout / retry conf ───────────────┐
│  ConnectInternal で rig_set_conf('timeout', …) を適用        │
│  対象: リグは繋がっているが無応答                            │
│  → Hamlib が自分で -RIG_ETIMEOUT を返す。追加スレッド不要    │
└──────────────────────────────────────────────────────────────┘
┌─ 第 2 段: TRigWatchdog 監視スレッド ─────────────────────────┐
│  Worker が Hamlib に入る前に Arm、出たら Disarm              │
│  対象: read() がそもそも期限切れにならない場合               │
│        (USB 変換器の活線抜去、ドライバのカーネル内ブロック)  │
│  → 期限超過で rig_close を叩き、ブロック中の I/O を失敗させる│
└──────────────────────────────────────────────────────────────┘
```

第 1 段だけでは不十分な理由は、Hamlib の `timeout` が **`read()` ごと**に効くためです。
固まったデバイスからはその `read()` 自体が戻らないことがあり、そうなると Worker
スレッドは永久に帰らず、キューは流れず、エラーも届きません。

### 第 1 段の実装

`conf.c` と `serial_cfg_params.h` で確認したトークン名を使います。

```pascal
procedure TRigWorker.ApplyHamlibTimeouts;
begin
  Budget  := CommandBudgetMs;
  Retries := 1;
  PerRead := Budget div (Retries + 1);   { 最悪 = PerRead × (retry+1) }
  if PerRead < 100 then PerRead := 100;
  FLoader.SetConf(FRig, 'timeout', IntToStr(PerRead));
  FLoader.SetConf(FRig, 'retry',   IntToStr(Retries));
end;
```

1 回の Hamlib 呼び出しの最悪ブロック時間が概ね `timeout × (retry + 1)` になるため、
`CommandTimeoutMs` をそのまま渡すのではなく逆算しています。
汎用の `IHamlibLoader.SetConf` を追加し、`SetSerialPort` / `SetSerialBaud` も
これを使う形に統一しました。

### 第 2 段の実装

```pascal
FWatchdog.Arm(CommandBudgetMs);
try
  ACmd.Execute(FLoader, FRig);
  TimedOut := FWatchdog.Disarm;
  if TimedOut then … rcsTimeout … else … rcsSuccess …
except
  on E: ERigError do
  begin
    TimedOut := FWatchdog.Disarm;
    { どちらの段で検出しても rcsTimeout にする }
    if TimedOut or (E.Code = -RIG_ETIMEOUT_CODE) then
      R.Status := rcsTimeout
    else
      R.Status := rcsError;
  end;
```

`Disarm` は「この呼び出しの最中に watchdog が発火したか」を返します。発火していれば
Hamlib が最終的に何を返したかに関わらず `rcsTimeout` として報告します。

中断処理（`AbortStuckCall`）と通常の切断（`DisconnectInternal`）は `FAbortLock` で
直列化し、同じハンドルを二重に閉じないようにしています。Worker 破棄時は watchdog を
先に停止し、実行中の中断が解放済みハンドルに触れないようにしました。

### 実測

```
Tier 1 — configuration pushed into Hamlib:
    timeout = 500 ms      ← CommandTimeoutMs 1000 から逆算
    retry   = 1

Tier 2 — I/O が 8000 ms ブロック、予算 1000 ms:
    callback fired : TRUE
    elapsed        : 1015 ms
    status         : 3  (3 = rcsTimeout)
    rig_close called          : TRUE
    ...from a different thread: TRUE
RESULT: OK (aborted and reported as rcsTimeout)
```

同じテストを修正前のコードに当てた結果:

```
    callback fired : FALSE
    elapsed        : 6116 ms
    rig_close called          : FALSE
RESULT: *** FAIL - command never completed (still hung) ***
```

6 秒待ってもコールバックすら返らないハング状態でした。

---

## 正直に申し上げる限界

**第 2 段は Hamlib が安全と保証していない操作です。** Worker が Hamlib 呼び出しの
中にいる間に別スレッドから `rig_close` を呼びます。これは最後の手段であり、代替案は
「二度と回復しないアプリケーション」です。中断は期限を過ぎて初めて発火し、その時点で
セッションは破棄前提なので、Worker は必ずゼロから再接続しハンドルを再利用しません。
それでも、バックエンドによっては `rig_close` 自体がブロックする可能性は残ります。

**第 1 段は実機でしか検証できていません。** テストの `SetConf` は値を記録するだけで、
実際に Hamlib のシリアル読み取りが設定どおりの時間で諦めるかは未確認です。
`timeout × (retry + 1)` という最悪値の見積もりもバックエンド依存で、
CI-V バスのようにバックエンドが内部で追加の待ちを入れる実装では超過し得ます。

**実機検証は依然として未実施です。** 今回の照合でヘッダとの整合は取れましたが、
`rigctld`（`RIG_MODEL_NETRIGCTL` = 2）経由か実機での疎通確認は別途必要です。
特に A-1 の修正値は算出規則から導いたもので、実際に IC-7300 に繋いで確認したもの
ではありません。

---

## 検証資材

| ファイル | 検証内容 |
|---|---|
| `test/TimeoutTest.lpr` | **新規** 二段タイムアウト（第 1 段の設定適用、第 2 段の中断） |
| `test/ConnectFailTest.lpr` | 接続失敗時の nil PRIG 安全性 |
| `test/LifecycleTest.lpr` | Open/Close/破棄の 3 パターン |
| `test/MisuseTest.lpr` | Open 前 API 呼び出し |
| `test/DanglingTest.lpr` | 破棄済みオブジェクトへのコールバック |
| `test/LeakTest.lpr` / `LeakTest2.lpr` | heaptrc によるリーク検査 |
| `test/PerfTest.lpr` | キュー性能 |

```bash
cd test
fpc -Mobjfpc -Sh -Sa -Criot -gh -gl -B -Fu../src -FE. TimeoutTest.lpr && ./TimeoutTest
```

結果: 全 8 本合格、リーク 0、Release / Debug とも警告・Note 0。

---

*API Verification & Timeout Report / 2026-10-12 — Hamlib master (4.7.x) 照合、FPC 3.2.2 実測*
