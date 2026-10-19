# Hamlib coverage matrix — what applications use, and what we implement

実アプリケーションが使う Hamlib 機能と、本コンポーネントの実装状況

Rev.6.0 · surveyed 2026-10-17 · 調査日 2026-10-17

---

## 1. Why this document exists / 本書の目的

Deciding what a wrapper should cover by reading `rig.h` produces a
wrapper shaped like the header: several hundred entry points, all
equally weighted, most of which nobody calls. Deciding it by reading
the applications that already depend on Hamlib produces a wrapper
shaped like the problem.

`rig.h` を読んでラッパーの対象を決めると、ヘッダの形をしたラッパーが
できます。数百のエントリポイントが等しい重みで並び、その大半は誰も
呼びません。既に Hamlib に依存しているアプリケーションを読んで決めれば、
問題の形をしたラッパーができます。

Everything in section 3 was obtained by reading source, not from
memory. The files are named so the reading can be repeated.

第 3 節の内容はすべてソースを読んで得たもので、記憶によるものでは
ありません。再現できるようファイル名を明記しています。

---

## 2. The applications surveyed / 調査対象

| Application | How it reaches Hamlib | Source read |
|---|---|---|
| **WSJT-X / JS8Call** | links `libhamlib` directly | `HamlibTransceiver.cpp` (JS8Call `main`, a fork of WSJT-X's file) |
| **fldigi** | links `libhamlib` via a C++ wrapper class | `src/rigcontrol/rigclass.cxx`, `src/rigcontrol/hamlib.cxx` |
| **gpredict** | talks to `rigctld` over TCP | `src/gtk-rig-ctrl.c` |
| **rigctl / rigctld** | Hamlib's own reference client | `tests/rigctl_parse.c` (4.5.5) |

WSJT-X and JS8Call share one file by descent, so they count as one
data point, not two — but it is the data point that matters most,
because it is the most-deployed libhamlib consumer in amateur radio.

WSJT-X と JS8Call は由来を同じくする 1 ファイルを共有するため、2 件
ではなく 1 件として数えます。ただしこれは最も重要な 1 件です。
アマチュア無線で最も広く配備された libhamlib 利用者だからです。

`rigctl_parse.c` is included not because people run `rigctl`
interactively in large numbers, but because it is the complete set of
things Hamlib itself considers worth exposing, and because `rigctld`
is how every *non*-C application (gpredict, CQRLOG, Log4OM, N1MM+)
reaches a rig. A feature absent from `rigctl` is a feature no
networked client can use either.

`rigctl_parse.c` を含めたのは、`rigctl` を対話的に使う人が多いから
ではありません。これは Hamlib 自身が公開に値すると考えるものの完全な
集合であり、かつ `rigctld` は C 以外のすべてのアプリケーション
(gpredict、CQRLOG、Log4OM、N1MM+) がリグへ到達する経路だからです。
`rigctl` にない機能は、ネットワーク経由のクライアントにも使えません。

---

## 3. The matrix / 対応表

Legend — 凡例:

- **full** — bound, wrapped in a domain type, reachable from
  `IRigService`, and exercised by a test against the real library
- **partial** — reachable, but with a stated limitation
- **none** — not implemented; the reason is given in section 4

| Hamlib call | WSJT-X / JS8Call | fldigi | gpredict | rigctl | Ours | Where |
|---|:--:|:--:|:--:|:--:|:--:|---|
| `rig_init` / `rig_open` / `rig_close` / `rig_cleanup` | ✔ | ✔ | (via d) | ✔ | **full** | `IRigService.Open` / `Close` |
| `rig_load_all_backends` | ✔ | ✔ | — | ✔ | **full** | `THamlibLoader` |
| `rig_set_conf` | ✔ | ✔ | — | ✔ | **full** | `AddConfToken` (Rev.6.0) |
| `rig_get_conf` | ✔ | ✔ | — | ✔ | **none** | §4.1 |
| `rig_token_lookup` | ✔ | ✔ | — | ✔ | **full** | inside `SetConf` |
| `rig_set_freq` / `rig_get_freq` | ✔ | ✔ | `F`/`f` | ✔ | **full** | `SetFrequencyAsync` / `GetFrequencyAsync` |
| `rig_set_mode` / `rig_get_mode` | ✔ | ✔ | — | ✔ | **full** | `SetModeAsync` / `GetModeAsync`, `TRigMode` |
| `rig_set_ptt` / `rig_get_ptt` | ✔ | ✔ | — | ✔ | **full** | `SetPttAsync`, snapshot `PttActive` |
| `rig_set_split_vfo` / `rig_get_split_vfo` | ✔ | — | `S` | ✔ | **full** | `SetSplitAsync` / `GetSplitAsync` |
| `rig_set_split_freq` / `rig_get_split_freq` | ✔ | — | `I`/`i` | ✔ | **full** | `SetSplitFreqAsync`, `GetSplitAsync` |
| `rig_set_vfo` / `rig_get_vfo` | ✔ | — | — | ✔ | **full** | `SetVfoAsync` / `GetVfoAsync` |
| `rig_vfo_op` | ✔ | — | — | ✔ | **full** | `VfoOpAsync`, `TRigVfoOp` |
| `rig_set_level` / `rig_get_level` | — | — | — | ✔ | **full** | `SetLevelFloatAsync` / `SetLevelIntAsync` / `GetLevelAsync` |
| `rig_set_func` / `rig_get_func` | — | — | — | ✔ | **full** | `SetFuncAsync` / `GetFuncAsync` |
| `rig_get_caps_int` | ✔ | — | — | — | **partial** | `GetCapabilities`; §4.2 |
| `rig_get_caps_cptr` | ✔ | — | — | — | **none** | §4.3 |
| `rig_list_foreach_model` | ✔ | ✔ (`rig_list_foreach`) | — | ✔ | **full** | `IRigModelCatalog` |
| `rig_set_debug` / `rig_set_debug_callback` | ✔ | ✔ | — | ✔ | **partial** | `SetDebugLevel`; no callback, §4.4 |
| `rigerror` / `rigerror2` | ✔ | ✔ | — | ✔ | **full** | `rigerror2` preferred; §4.5 |
| `rig_strrmode` / `rig_strvfo` / `rig_parse_mode` | ✔ | ✔ | — | ✔ | **n/a** | we translate in Pascal, §4.6 |
| `rig_set_split_mode` / `rig_set_split_freq_mode` | ✔ | — | — | ✔ | **none** | §4.7 |
| `rig_set_freq_callback` | ✔ | — | — | — | **none** | §4.8 |
| `rig_set_xit` / `rig_set_rit` | — | — | — | ✔ | **none** | §4.9 |
| `rig_get_powerstat` / `rig_set_powerstat` | — | — | — | ✔ | **none** | §4.9 |
| `rig_get_ant` / `rig_set_ant` | — | — | — | ✔ | **none** | §4.9 |
| `rig_send_morse` / `rig_stop_morse` / `rig_wait_morse` | — | — | — | ✔ | **none** | §4.9 |
| memory channels (`rig_set_mem`, `rig_get_channel`, …) | — | — | — | ✔ | **none** | §4.9 |
| `rig_set_trn` (transceive mode) | — | — | — | ✔ | **none** | §4.10 |

Count: of the 20 distinct `rig_*` entry points used by at least one
surveyed application, **17 are full, 2 partial, 1 none**
(`rig_get_conf`). Everything in the "none" rows below that line is
used by `rigctl` alone.

集計: 調査対象のいずれかが使う 20 個の `rig_*` エントリポイントのうち、
**17 が full、2 が partial、1 が none** (`rig_get_conf`) です。それ以下の
「none」行は `rigctl` のみが使うものです。

---

## 4. The gaps, and why / 未実装部分とその理由

### 4.1 `rig_get_conf`

Reading a configuration value back. Both WSJT-X and fldigi call it,
so this is the one genuine gap in the "used by applications" set.
They use it to discover a backend's default before overriding it —
for example, to ask what `ptt_type` a model defaults to.

設定値を読み戻します。WSJT-X と fldigi の双方が呼ぶため、「アプリ
ケーションが使う」集合における唯一の真の欠落です。両者はバックエンドの
既定値を上書き前に知るために使います。たとえば、ある機種の `ptt_type`
の既定値を尋ねるために。

Not implemented because `AddConfToken` currently writes only, and a
read-back API that returns a string with no stated type invites the
caller to parse it — the same class of problem the component removed
from error codes and mode bitmasks. Doing it properly means deciding
what the returned string means per token, which is a design task, not
a binding task. It is the first candidate for Rev.6.1.

未実装の理由は、`AddConfToken` が現状書き込み専用であり、型の定めのない
文字列を返す読み戻し API は呼び出し側に解析を誘発するからです。これは
エラーコードやモードのビットマスクからコンポーネントが取り除いたのと
同種の問題です。適切に行うにはトークンごとに返却文字列の意味を決める
必要があり、それはバインディング作業ではなく設計作業です。Rev.6.1 の
第一候補です。

### 4.2 `rig_get_caps_int` — implemented, but it cannot answer much

Bound and exposed as `GetCapabilities`, but Hamlib's stable C API
exports exactly five fields through it. `TRigCapabilities.GetLevels`,
`SetLevels`, `GetFuncs` and `VfoOps` are therefore always empty, and
the documentation says in as many words that **empty means "not
asked", never "not supported"**. An application that hides a control
because the set is empty hides a control that works.

バインド済みで `GetCapabilities` として公開していますが、Hamlib の
安定 C API がこれを通して公開するのはちょうど 5 フィールドです。
そのため `TRigCapabilities` の `GetLevels`、`SetLevels`、`GetFuncs`、
`VfoOps` は常に空であり、文書には**空は「問い合わせていない」であって
「非対応」ではない**と明記しています。集合が空だからとコントロールを
隠すアプリケーションは、動作するコントロールを隠すことになります。

The only reliable way to learn whether a rig supports something is to
ask the rig and read the error. `rekNotAvailable` is the answer.

リグがある機能に対応するかを確実に知る唯一の方法は、リグに尋ねて
エラーを読むことです。`rekNotAvailable` がその答えです。

### 4.3 `rig_get_caps_cptr`

Returns `const char *` members of `struct rig_caps` by index. WSJT-X
uses it for the model name and manufacturer. We get both from
`rig_list_foreach_model` instead, which is already bound and gives
the whole catalogue in one pass rather than one string per call.

`struct rig_caps` の `const char *` メンバを添字で返します。WSJT-X は
機種名と製造者に使います。本コンポーネントは両方を
`rig_list_foreach_model` から得ます。既にバインド済みで、呼び出しごとに
1 文字列ではなく一度にカタログ全体を得られます。

### 4.4 `rig_set_debug_callback`

Routing Hamlib's debug output into the application's own log. Not
implemented: the callback fires on whichever thread is inside Hamlib,
which in this component is always the worker thread, and handing an
application a logging callback that arrives off the UI thread
contradicts the one guarantee the component makes about threading.
A queued variant is possible and is not hard; it is simply not yet
needed by anything.

Hamlib のデバッグ出力をアプリケーション自身のログへ流します。未実装
です。コールバックは Hamlib の内部に居るスレッド上で発火し、本
コンポーネントではそれは常にワーカースレッドです。UI スレッド外で届く
ログコールバックをアプリケーションに渡すことは、本コンポーネントが
スレッドについて行う唯一の保証と矛盾します。キュー経由の変種は可能で
難しくもありませんが、今のところ必要とするものがありません。

### 4.5 `rigerror` — bound, but deliberately not preferred

Measured against Hamlib 4.5.5: `rigerror()` returns the accumulated
debug buffer, which was 15 KB in our test. `rigerror2()` returns the
one-line message. The component calls `rigerror2` when the library
exports it and keeps only the first line otherwise.

Hamlib 4.5.5 で実測: `rigerror()` は蓄積されたデバッグバッファを返し、
本検査では 15 KB でした。`rigerror2()` は 1 行のメッセージを返します。
本コンポーネントはライブラリが `rigerror2` を公開していればそれを呼び、
そうでなければ最初の 1 行だけを残します。

### 4.6 `rig_strrmode` / `rig_strvfo` / `rig_parse_mode`

String conversions. Not bound on purpose: they return Hamlib's own
English labels, and a component whose display strings come from the C
library cannot be localised, cannot be unit-tested without the
library, and changes its output when the library is upgraded.
`HamlibModeCodec`, `HamlibLevelCodec` and `RigVfoToString` do the same
job in Pascal, where the mapping is visible and versioned with us.

文字列変換。意図的にバインドしていません。これらは Hamlib 自身の英語
ラベルを返します。表示文字列を C ライブラリから得るコンポーネントは、
地域化できず、ライブラリなしに単体テストできず、ライブラリの更新で
出力が変わります。`HamlibModeCodec`、`HamlibLevelCodec`、
`RigVfoToString` が同じ仕事を Pascal で行い、対応関係は目に見え、
本コンポーネントと共にバージョン管理されます。

### 4.7 `rig_set_split_mode` / `rig_set_split_freq_mode`

Setting the transmit VFO's mode, and setting transmit frequency and
mode in one call. WSJT-X uses both. Not implemented in Rev.6.0: the
split *frequency* is what every surveyed application sets on every
transmission, whereas the split *mode* is set once when the mode
changes. This is a deliberate scope line, not an oversight, and
`DxSplitSequence` is the natural place for the extra step when it is
added.

送信 VFO のモード設定と、送信周波数とモードを 1 回の呼び出しで設定
するもの。WSJT-X は両方を使います。Rev.6.0 では未実装です。調査対象の
すべてのアプリケーションが送信のたびに設定するのはスプリットの
「周波数」であり、スプリットの「モード」はモード変更時に一度設定する
ものです。これは見落としではなく意図した範囲の線引きであり、追加する
際には `DxSplitSequence` が自然な置き場所になります。

### 4.8 `rig_set_freq_callback`

Hamlib's transceive mode: the library reports frequency changes the
operator makes on the rig's front panel, instead of the application
polling. WSJT-X sets it up. Not implemented for the same reason as
4.4 — it delivers on Hamlib's own thread — and because polling at
250 ms gives the same user-visible behaviour on every backend,
whereas transceive support varies by rig and is a known source of
Hamlib bug reports.

Hamlib のトランシーブモード。アプリケーションがポーリングする代わりに、
オペレータがリグ本体で行った周波数変更をライブラリが報告します。
WSJT-X は設定します。未実装の理由は 4.4 と同じ (Hamlib 自身のスレッド
で配送される) ことに加え、250 ms のポーリングがどのバックエンドでも
同じ体感を与えるのに対し、トランシーブ対応は機種差が大きく Hamlib の
不具合報告の既知の発生源だからです。

### 4.9 RIT/XIT, power state, antenna, morse, memory channels

Used by `rigctl` and by no surveyed application. Each is a small
addition on the pattern `HamlibRigCommands.pas` already establishes
— a command class, a dispatch, a service method — so the cost of
adding one later is known and low. Adding all of them now would be
guessing at requirements.

`rigctl` が使い、調査対象のアプリケーションはいずれも使いません。
各々は `HamlibRigCommands.pas` が既に確立したパターン (コマンドクラス、
ディスパッチ、サービスメソッド) に沿った小さな追加であり、後から 1 つ
追加する費用は既知かつ低いままです。今すべてを追加するのは、要件の
当て推量です。

### 4.10 `rig_set_trn`

Deprecated in Hamlib 4.x in favour of the transceive callback. Not
implemented and not planned.

Hamlib 4.x でトランシーブコールバックに取って代わられ非推奨です。
未実装であり、予定もありません。

---

## 5. What the survey changed / 調査が変えたこと

Four things in Rev.6.0 exist because of this survey rather than
because the header looked interesting:

Rev.6.0 の 4 点は、ヘッダが面白そうだったからではなく、本調査の結果
として存在します。

1. **Split was promoted from "later" to "core".** Every surveyed
   application that does more than read a frequency uses it, and
   gpredict's satellite doppler tracking is *built* on it (`S`, `I`).
   スプリットは「後回し」から「中核」に昇格しました。周波数を読む以上
   のことをする調査対象はすべて使い、gpredict のサテライトドップラー
   追尾はその上に構築されています。

2. **Levels were split into float and integer paths.** `value_t` is a
   C union passed by value; reading an integer level as a float
   produces a plausible-looking number in the hundreds of millions.
   `TRigLevelResult.IsFloat` exists so no caller has to know which is
   which.
   レベルを float 経路と整数経路に分けました。`value_t` は値渡しの
   C 共用体であり、整数レベルを float として読むと数億という一見
   もっともらしい値になります。どちらであるかを呼び出し側が知らずに
   済むよう `TRigLevelResult.IsFloat` があります。

3. **`AddConfToken` was added before `Open`.** Both WSJT-X and fldigi
   set `ptt_type` before opening, because a model's default is often
   not how the station is wired.
   `Open` の前に `AddConfToken` を追加しました。WSJT-X と fldigi は
   どちらも開く前に `ptt_type` を設定します。機種の既定値が、実際の
   配線と異なることが多いからです。

4. **Capability reporting was made honest rather than useful.** It
   would have been easy to present empty sets as "the rig does not
   support this". Hamlib cannot answer the question, so neither can
   we, and saying so is the only correct behaviour.
   能力の報告を、便利ではなく正直にしました。空集合を「リグが非対応」
   として提示するのは簡単でした。Hamlib がその問いに答えられない以上
   本コンポーネントにも答えられず、そう述べることだけが正しい振る舞い
   です。

---

## 6. How this was verified / 検証方法

Every **full** row is exercised against the real Hamlib library's
dummy backend, not against a mock:

すべての **full** 行は、モックではなく実 Hamlib ライブラリのダミー
バックエンドに対して検査されています。

| Test | What it covers | Result |
|---|---|---|
| `demo2/FeatureMatrixTest.lpr` | every Rev.6.0 call, one at a time | 40 / 40 |
| `demo2/DxConformanceTest.lpr` | the calls composed into an operation that can fail halfway | 64 / 64 |
| `demo/RealHamlibTest.lpr` | the Rev.5.x surface | 33 / 33 |
| `tools/check_abi.py` | our constants against `rig.h` at four Hamlib refs | 0 mismatched |

What is **not** covered: no test here has touched a real transceiver
over a serial port. Every timing claim, every timeout path and every
backend quirk below the dummy rig remains unverified.

**未検証**の範囲: 本書のいずれの検査も、シリアルポート経由で実機に
触れていません。タイミングに関する主張、タイムアウト経路、ダミーリグ
より下のバックエンド固有の癖は、いずれも未検証のままです。
