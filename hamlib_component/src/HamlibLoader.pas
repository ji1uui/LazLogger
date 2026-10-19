{
  HamlibLoader.pas

  Dynamic loader for the Hamlib shared library. Locates and loads
  libhamlib at runtime, resolves required and optional symbols, and
  provides a thin Pascal-friendly wrapper.

  Hamlib 共有ライブラリの動的ローダ。実行時に libhamlib を探索・
  ロードし、必須および任意シンボルを解決します。Pascal フレンドリな
  薄いラッパーを提供します。

  Layer:    L1 (dynamic loading / 動的ロード層)
  Depends:  HamlibInterfaces, HamlibErrors

  Note: Application code should NOT instantiate this directly.
  Use TRigServiceFactory which constructs the loader internally.

  注: アプリケーションコードはこれを直接インスタンス化してはいけません。
  TRigServiceFactory がローダを内部で構築します。
}
unit HamlibLoader;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, dynlibs, ctypes,
  HamlibInterfaces, HamlibErrors, HamlibLevelCodec;

type
  { ====================================================================
    Hamlib C API function pointer types
    Hamlib C API 関数ポインタ型
    ====================================================================
    These match the prototypes in include/hamlib/rig.h. Calling
    convention is cdecl (Hamlib is built with MinGW on Windows).

    これらは include/hamlib/rig.h のプロトタイプに一致します。
    呼び出し規約は cdecl です (Hamlib は Windows では MinGW でビルド)。 }

  { ------------------------------------------------------------------
    Exact C types, verified against Hamlib master (4.7.x) 2026-10-12:

      typedef uint32_t      rig_model_t;    (riglist.h)
      typedef unsigned int  vfo_t;
      typedef double        freq_t;
      typedef uint64_t      rmode_t;
      typedef signed long   shortfreq_t;
      typedef shortfreq_t   pbwidth_t;      <-- long, NOT int64
      typedef long          hamlib_token_t;
      typedef enum ...      ptt_t;          (int-sized enum)

    pbwidth_t is the one that bites: it is C `long`, which is 64-bit on
    Linux/macOS (LP64) but 32-bit on Windows (LLP64). Binding it as
    cint64 happens to work on Unix and corrupts the argument list on
    Win64. clong is the only portable spelling.

    正確な C 型 (2026-10-12 に Hamlib master 4.7.x と照合):
    pbwidth_t が要注意です。実体は C の long で、Linux/macOS (LP64) では
    64bit、Windows (LLP64) では 32bit です。cint64 で束縛すると Unix では
    たまたま動き、Win64 では引数列が壊れます。移植可能な綴りは clong だけです。
    ------------------------------------------------------------------ }

  hl_model_t   = cuint32;   { rig_model_t    }
  hl_vfo_t     = cuint;     { vfo_t          }
  hl_freq_t    = cdouble;   { freq_t         }

  { Pointers to the above, for the out-parameters of the Rev.6.0 calls.
    上記へのポインタ。Rev.6.0 で追加した呼び出しの out 引数用。 }
  Phl_vfo_t    = ^hl_vfo_t;
  Phl_freq_t   = ^hl_freq_t;
  hl_rmode_t   = cuint64;   { rmode_t        }
  hl_pbwidth_t = clong;     { pbwidth_t      }
  hl_token_t   = clong;     { hamlib_token_t }
  hl_ptt_t     = cint;      { ptt_t enum     }

  T_rig_init           = function (model: hl_model_t): Pointer; cdecl;
  T_rig_open           = function (rig: Pointer): cint; cdecl;
  T_rig_close          = function (rig: Pointer): cint; cdecl;
  T_rig_cleanup        = function (rig: Pointer): cint; cdecl;
  T_rig_set_freq       = function (rig: Pointer; vfo: hl_vfo_t;
                                    freq: hl_freq_t): cint; cdecl;
  T_rig_get_freq       = function (rig: Pointer; vfo: hl_vfo_t;
                                    out freq: hl_freq_t): cint; cdecl;
  T_rig_set_mode       = function (rig: Pointer; vfo: hl_vfo_t;
                                    mode: hl_rmode_t;
                                    width: hl_pbwidth_t): cint; cdecl;
  T_rig_get_mode       = function (rig: Pointer; vfo: hl_vfo_t;
                                    out mode: hl_rmode_t;
                                    out width: hl_pbwidth_t): cint; cdecl;
  T_rig_set_ptt        = function (rig: Pointer; vfo: hl_vfo_t;
                                    ptt: hl_ptt_t): cint; cdecl;
  T_rig_get_ptt        = function (rig: Pointer; vfo: hl_vfo_t;
                                    out ptt: hl_ptt_t): cint; cdecl;
  T_rigerror           = function (errnum: cint): PAnsiChar; cdecl;

  { rigerror2 — the single-line form. Hamlib's own header calls it
    "returns single-line message", and reading src/rig.c (4.5.5) shows
    why that matters: rigerror() appends the message to Hamlib's
    accumulated debug buffer and then returns THE WHOLE BUFFER, which
    can be 15 KB of protocol trace. Verified against the real library:
    a failed rig_set_ptt produced an "error message" containing dozens
    of rig_set_cache_mode trace lines.

    Optional, because it does not exist in every 4.x build; without it
    the loader keeps only the first line of rigerror()'s output, which
    is the message itself.

    rigerror2 — 1 行形式。Hamlib のヘッダ自身が
    "returns single-line message" と書いており、src/rig.c (4.5.5) を
    読むとその理由が分かります。rigerror() はメッセージを Hamlib の
    累積デバッグバッファに追記し、「バッファ全体」を返します。15 KB の
    プロトコルトレースになり得ます。実ライブラリで確認済み: 失敗した
    rig_set_ptt の「エラーメッセージ」に rig_set_cache_mode のトレースが
    数十行含まれていました。

    すべての 4.x ビルドに存在するとは限らないため任意です。無い場合は
    ローダが rigerror() の出力の 1 行目 (それがメッセージ本体) だけを
    残します。 }
  T_rigerror2          = function (errnum: cint): PAnsiChar; cdecl;

  { ====================================================================
    value_t — the C union rig_get_level and rig_set_level carry.
    value_t - rig_get_level / rig_set_level が運ぶ C の共用体。
    ====================================================================
      typedef union ... i: signed int; f: float; s: char*;
                        cs: const char*; b: struct ... l: int; d: uchar* ...

    A Pascal variant record is a union, and this one is laid out to
    match: the largest arm is b (int + pointer = 16 bytes on LP64/LLP64
    with 8-byte alignment), so sizeof(value_t) is 16 and it is passed in
    two integer registers on SysV AMD64 rather than on the stack.

    Getting this wrong does not fail to compile and does not crash: it
    silently reads the S-meter out of the wrong half of a register pair.
    demo2/FeatureMatrixTest.lpr therefore checks a known value through
    the real library rather than trusting the declaration.

    Pascal の可変レコードは共用体であり、これは一致するよう配置して
    います。最大のアームは b (int + ポインタ = LP64/LLP64 で 8 バイト
    境界に揃えて 16 バイト) なので sizeof(value_t) は 16 となり、
    SysV AMD64 ではスタックではなく整数レジスタ 2 本で渡されます。

    ここを誤ってもコンパイルは通り、クラッシュもしません。レジスタ対の
    誤った側から S メータを静かに読むだけです。したがって
    demo2/FeatureMatrixTest.lpr は、宣言を信用せず実ライブラリ経由で
    既知の値を検査します。 }
  hl_value_t = record
    case Integer of
      0: (i:  cint);
      1: (f:  cfloat);
      2: (s:  PAnsiChar);
      3: (b_l: cint; b_d: PByte);
  end;
  Phl_value_t = ^hl_value_t;

  hl_setting_t = cuint64;   { setting_t = uint64_t }

  { ---- the calls applications actually use, added in Rev.6.0 ----
    ---- アプリケーションが実際に使う呼び出し (Rev.6.0 で追加) ---- }
  T_rig_set_vfo        = function (rig: Pointer; vfo: hl_vfo_t): cint; cdecl;
  T_rig_get_vfo        = function (rig: Pointer; vfo: Phl_vfo_t): cint; cdecl;

  T_rig_set_split_vfo  = function (rig: Pointer; rx_vfo: hl_vfo_t;
                                    split: cint; tx_vfo: hl_vfo_t): cint; cdecl;
  T_rig_get_split_vfo  = function (rig: Pointer; rx_vfo: hl_vfo_t;
                                    split: pcint; tx_vfo: Phl_vfo_t): cint; cdecl;
  T_rig_set_split_freq = function (rig: Pointer; vfo: hl_vfo_t;
                                    tx_freq: hl_freq_t): cint; cdecl;
  T_rig_get_split_freq = function (rig: Pointer; vfo: hl_vfo_t;
                                    tx_freq: Phl_freq_t): cint; cdecl;

  T_rig_set_level      = function (rig: Pointer; vfo: hl_vfo_t;
                                    level: hl_setting_t;
                                    val: hl_value_t): cint; cdecl;
  T_rig_get_level      = function (rig: Pointer; vfo: hl_vfo_t;
                                    level: hl_setting_t;
                                    val: Phl_value_t): cint; cdecl;

  T_rig_set_func       = function (rig: Pointer; vfo: hl_vfo_t;
                                    func: hl_setting_t;
                                    status: cint): cint; cdecl;
  T_rig_get_func       = function (rig: Pointer; vfo: hl_vfo_t;
                                    func: hl_setting_t;
                                    status: pcint): cint; cdecl;

  T_rig_vfo_op         = function (rig: Pointer; vfo: hl_vfo_t;
                                    op: cint): cint; cdecl;

  T_rig_get_caps_int   = function (model: hl_model_t;
                                    caps: cint): clonglong; cdecl;
  T_rig_set_conf       = function (rig: Pointer; token: hl_token_t;
                                    val: PAnsiChar): cint; cdecl;
  T_rig_token_lookup   = function (rig: Pointer;
                                    name: PAnsiChar): hl_token_t; cdecl;
  T_rig_version        = function: PAnsiChar; cdecl;

  { Model verification. Present since Hamlib 4.5 (verified against the
    4.5.5, 4.6 and 4.7.2 headers), but resolved as OPTIONAL so an older
    or trimmed build still loads — it just cannot verify models.

    モデル検証用。Hamlib 4.5 以降に存在します (4.5.5 / 4.6 / 4.7.2 の
    ヘッダで確認済み) が、任意シンボルとして解決します。より古い、または
    機能を削ったビルドでもロードでき、モデル検証だけができなくなります。

      enum rig_caps_cptr_e ... =
        RIG_CAPS_VERSION_CPTR, RIG_CAPS_MFG_NAME_CPTR,
        RIG_CAPS_MODEL_NAME_CPTR, RIG_CAPS_STATUS_CPTR  }
  T_rig_check_backend   = function (model: hl_model_t): cint; cdecl;
  T_rig_get_caps_cptr   = function (model: hl_model_t;
                                     caps: cint): PAnsiChar; cdecl;
  T_rig_load_all_backends = function: cint; cdecl;

  { rig_set_debug(enum rig_debug_level_e). The enum is an ordinary C
    enum, so cint is the right width.

      RIG_DEBUG_NONE = 0, BUG, ERR, WARN, VERBOSE, TRACE, CACHE

    Hamlib writes its diagnostics to stderr, and some builds print
    backend registration lines to stdout as well. A library that
    chatters over an application's console is a packaging detail of the
    Hamlib build, not something the application chose, so the loader
    quiets it at load time and lets the application ask for more.

    rig_set_debug(enum rig_debug_level_e)。通常の C enum なので cint が
    正しい幅です。

    Hamlib は診断を stderr に書き、ビルドによってはバックエンド登録行を
    stdout にも印字します。ライブラリがアプリのコンソールを埋めるのは
    Hamlib ビルドの事情であってアプリが選んだことではないため、ローダは
    ロード時に静かにし、必要ならアプリが上げられるようにします。 }
  T_rig_set_debug = procedure (debug_level: cint); cdecl;

  { Callback invoked once per registered model by rig_list_foreach_model.
    Verified against Hamlib src/register.c (4.7.2): the iteration stops
    as soon as the callback returns 0, and continues on any non-zero
    value. Returning 1 therefore means "keep going".

    This is a C calling-convention callback, so it must be a plain
    function (not a method) and no Pascal exception may escape from it:
    unwinding through C frames would leave Hamlib's hash-table walk
    half-done. CollectModelCallback below guards against that.

    rig_list_foreach_model が登録済みモデルごとに 1 回呼ぶコールバック。
    Hamlib の src/register.c (4.7.2) で確認: コールバックが 0 を返すと
    即座に反復を終了し、0 以外なら継続します。したがって 1 は「続行」。

    C の呼び出し規約のコールバックであるため、メソッドではなく通常の
    関数でなければならず、Pascal 例外を外に漏らしてはなりません。C の
    フレームを巻き戻すと Hamlib のハッシュテーブル走査が中途半端な状態
    で残ります。下記 CollectModelCallback がそれを防ぎます。 }
  T_model_callback = function (model: hl_model_t;
                               data: Pointer): cint; cdecl;

  T_rig_list_foreach_model = function (cfunc: T_model_callback;
                                        data: Pointer): cint; cdecl;

  { ====================================================================
    THamlibLoader — concrete implementation of IHamlibLoader.
    THamlibLoader - IHamlibLoader の具象実装。
    ==================================================================== }
  THamlibLoader = class(TInterfacedObject, IHamlibLoader, IHamlibDiagnostics,
                        IHamlibCatalog, IHamlibRigControl)
  private
    FHandle:   TLibHandle;
    FLibPath:  string;
    FApiMajor: Integer;
    FApiMinor: Integer;

    { Required function pointers — Load fails if any is unresolved.
      必須関数ポインタ — いずれか未解決なら Load は失敗します。 }
    F_rig_init:     T_rig_init;
    F_rig_open:     T_rig_open;
    F_rig_close:    T_rig_close;
    F_rig_cleanup:  T_rig_cleanup;
    F_rig_set_freq: T_rig_set_freq;
    F_rig_get_freq: T_rig_get_freq;
    F_rig_set_mode: T_rig_set_mode;
    F_rig_get_mode: T_rig_get_mode;
    F_rig_set_ptt:  T_rig_set_ptt;
    F_rig_get_ptt:  T_rig_get_ptt;
    F_rigerror:     T_rigerror;
    F_rigerror2:    T_rigerror2;

    { Optional function pointers — nil if not present.
      任意関数ポインタ — 存在しない場合 nil。 }
    F_rig_set_conf:     T_rig_set_conf;
    F_rig_token_lookup: T_rig_token_lookup;
    F_rig_version:      T_rig_version;
    F_rig_check_backend:     T_rig_check_backend;
    F_rig_get_caps_cptr:     T_rig_get_caps_cptr;
    F_rig_load_all_backends: T_rig_load_all_backends;
    F_rig_list_foreach_model: T_rig_list_foreach_model;
    F_rig_set_debug:          T_rig_set_debug;

    { Rev.6.0 — all optional, because a trimmed or older build may not
      export them and the component must still drive frequency and mode.
      Rev.6.0 — すべて任意です。機能を削った、または古いビルドでは
      公開されていない可能性があり、それでも周波数とモードは動かせる
      必要があるためです。 }
    F_rig_set_vfo:        T_rig_set_vfo;
    F_rig_get_vfo:        T_rig_get_vfo;
    F_rig_set_split_vfo:  T_rig_set_split_vfo;
    F_rig_get_split_vfo:  T_rig_get_split_vfo;
    F_rig_set_split_freq: T_rig_set_split_freq;
    F_rig_get_split_freq: T_rig_get_split_freq;
    F_rig_set_level:      T_rig_set_level;
    F_rig_get_level:      T_rig_get_level;
    F_rig_set_func:       T_rig_set_func;
    F_rig_get_func:       T_rig_get_func;
    F_rig_vfo_op:         T_rig_vfo_op;
    F_rig_get_caps_int:   T_rig_get_caps_int;

    { Raw rig_version() text and whether the binding came from a file name
      that carries no soname.
      rig_version() の原文と、soname を含まないファイル名でバインドしたか。 }
    FVersionText:       string;
    FUnversioned:       Boolean;
    FBackendsLoaded:    Boolean;


    { Set of resolved symbol names for HasSymbol.
      HasSymbol 用の解決済みシンボル名集合。 }
    FResolvedSymbols: TStringList;

    { Hamlib registers its backends lazily. Three separate call sites
      need them loaded first, and before Rev.6.0 two of them carried a
      copy of this three-line dance.
      Hamlib はバックエンドを遅延登録します。3 箇所がロード済みを前提と
      しており、Rev.6.0 より前はそのうち 2 箇所がこの 3 行を複製して
      いました。 }
    procedure EnsureBackendsLoaded;

    { Try to load from a single candidate path. Returns True on success.
      単一候補パスからのロードを試行します。成功時 True。 }
    function  TryLoad(const APath: string): Boolean;

    { Look up a required symbol; raises EHamlibLoadError if missing.
      必須シンボルを検索します。見つからない場合 EHamlibLoadError を発生。 }
    function  ResolveRequired(const AName: string): Pointer;

    { Look up an optional symbol; returns nil if missing.
      任意シンボルを検索します。見つからない場合 nil を返します。 }
    function  ResolveOptional(const AName: string): Pointer;

    { Detect Hamlib version after symbols are resolved.
      シンボル解決後に Hamlib バージョンを検出します。 }
    procedure DetectVersion;
    procedure DetectUnversionedBinding;

    { Build the platform-specific list of library file candidates.
      プラットフォーム固有のライブラリファイル候補リストを構築します。 }
    function  GetCandidates(const AUserPath: string): TStringArray;
  public
    constructor Create;
    destructor  Destroy; override;

    { IHamlibLoader implementation }

    { Locate and load the Hamlib library. Returns True if a library
      was loaded and all required symbols resolved.
      Hamlib ライブラリを探索しロードします。ライブラリがロードされ
      必須シンボルがすべて解決された場合 True を返します。 }
    function  Load(const APath: string = ''): Boolean;

    procedure Unload;
    function  GetIsLoaded: Boolean;
    function  GetApiMajor: Integer;
    function  GetApiMinor: Integer;
    function  GetLibPath:  string;
    function  HasSymbol(const AName: string): Boolean;

    function  CallRigInit(AModel: Integer): Pointer;
    function  CallRigOpen(ARig: Pointer): Integer;
    function  CallRigClose(ARig: Pointer): Integer;
    function  CallRigCleanup(ARig: Pointer): Integer;
    function  CallRigSetFreq(ARig: Pointer; AVfo: Integer; AFreq: Double): Integer;
    function  CallRigGetFreq(ARig: Pointer; AVfo: Integer; out AFreq: Double): Integer;
    function  CallRigSetMode(ARig: Pointer; AVfo: Integer;
                             AMode: Int64; AWidth: Int64): Integer;
    function  CallRigGetMode(ARig: Pointer; AVfo: Integer;
                             out AMode: Int64; out AWidth: Int64): Integer;
    function  CallRigSetPtt(ARig: Pointer; AVfo: Integer; APtt: Integer): Integer;
    function  CallRigGetPtt(ARig: Pointer; AVfo: Integer; out APtt: Integer): Integer;
    function  CallRigError(ACode: Integer): string;
    function  SetConf(ARig: Pointer; const AName, AValue: string): Integer;
    function  SetSerialPort(ARig: Pointer; const APort: string): Integer;
    function  SetSerialBaud(ARig: Pointer; ABaud: Integer): Integer;

    { IHamlibDiagnostics implementation }
    function  GetVersionText: string;
    function  GetVersionVerdict: TRigVersionVerdict;
    function  GetSupportedRangeText: string;
    function  GetUnversionedBinding: Boolean;
    function  CheckModel(AModel: Integer;
                         out AMfg, AModelName: string;
                         out AAnswered: Boolean): Boolean;

    { IHamlibCatalog implementation }
    function  ListModels(out AList: TRigModelInfoArray): Boolean;

    { Set Hamlib's global debug level. 0 = none (the level the loader
      applies after a successful Load), 2 = errors, 3 = warnings,
      5 = tracing. Global to the library, not per-rig, because that is
      how Hamlib's own API is shaped.

      No-op when the running library does not export rig_set_debug.

      Hamlib のグローバルなデバッグレベルを設定します。0 = なし (Load
      成功後にローダが適用するレベル)、2 = エラー、3 = 警告、5 = トレース。
      Hamlib 自身の API がそうであるため、リグ単位ではなくライブラリ
      全体に効きます。

      実行中のライブラリが rig_set_debug を公開していない場合は何も
      しません。 }
    procedure SetDebugLevel(ALevel: Integer);

    { IHamlibRigControl implementation }
    function CallRigSetVfo(ARig: Pointer; AVfo: Integer): Integer;
    function CallRigGetVfo(ARig: Pointer; out AVfo: Integer): Integer;
    function CallRigSetSplitVfo(ARig: Pointer; ARxVfo: Integer;
                                ASplitOn: Boolean; ATxVfo: Integer): Integer;
    function CallRigGetSplitVfo(ARig: Pointer; ARxVfo: Integer;
                                out ASplitOn: Boolean;
                                out ATxVfo: Integer): Integer;
    function CallRigSetSplitFreq(ARig: Pointer; AVfo: Integer;
                                 ATxFreq: Double): Integer;
    function CallRigGetSplitFreq(ARig: Pointer; AVfo: Integer;
                                 out ATxFreq: Double): Integer;
    function CallRigSetLevelFloat(ARig: Pointer; AVfo: Integer;
                                  ALevelBit: Int64; AValue: Double): Integer;
    function CallRigSetLevelInt(ARig: Pointer; AVfo: Integer;
                                ALevelBit: Int64; AValue: Integer): Integer;
    function CallRigGetLevel(ARig: Pointer; AVfo: Integer; ALevelBit: Int64;
                             AAsFloat: Boolean;
                             out AFloatValue: Double;
                             out AIntValue: Integer): Integer;
    function CallRigSetFunc(ARig: Pointer; AVfo: Integer; AFuncBit: Int64;
                            AActive: Boolean): Integer;
    function CallRigGetFunc(ARig: Pointer; AVfo: Integer; AFuncBit: Int64;
                            out AActive: Boolean): Integer;
    function CallRigVfoOp(ARig: Pointer; AVfo: Integer; AOp: Integer): Integer;
    function QueryCapabilities(AModel: Integer;
                               out ACaps: TRigCapabilities): Boolean;
  end;

implementation

{ ------------------------------------------------------------------
  rig_load_all_backends registers every backend Hamlib knows with a
  table inside the library. That table belongs to the LIBRARY IMAGE,
  not to this object, and Hamlib's registration is not idempotent: a
  second call allocates a fresh registration record per model and
  leaks the first set. There is no unregister-all to pair it with.

  Up to Rev.6.0 the "already loaded" flag was per THamlibLoader
  instance, and the factory builds one loader per IRigService. An
  application that created a service per connection therefore leaked
  one registration table per connection — measured at 283 blocks,
  4,528 bytes, every time, on Hamlib 4.5.5. Valgrind saw it; heaptrc
  could not, because the allocations are on the C side of the
  boundary.

  The flag therefore has to be as wide as the thing it describes: the
  process, for as long as the library is mapped into it.

  rig_load_all_backends は、Hamlib が知るすべてのバックエンドを
  ライブラリ内部の表に登録します。その表は本オブジェクトではなく
  「ライブラリイメージ」に属し、Hamlib の登録は冪等ではありません。
  2 回目の呼び出しは機種ごとに新しい登録レコードを確保し、1 回目の
  ぶんを漏らします。対になる一括解除は存在しません。

  Rev.6.0 まで「ロード済み」フラグは THamlibLoader インスタンスごとで
  あり、ファクトリは IRigService ごとにローダを 1 つ作ります。接続ごと
  にサービスを作るアプリケーションは、接続ごとに登録表を 1 つ漏らして
  いました。Hamlib 4.5.5 で毎回 283 ブロック・4,528 バイトと実測。
  Valgrind には見え、heaptrc には見えません。境界の C 側の確保だから
  です。

  したがってフラグは、それが記述する対象と同じ広さ、すなわちライブラリ
  がプロセスに写像されている限りのプロセス全体でなければなりません。
  ------------------------------------------------------------------ }
var
  GRegistryLock:       TRTLCriticalSection;
  GBackendsRegistered: Boolean = False;
  GLoadedInstances:    Integer = 0;


const
  { Hamlib RIG_OK. Declared locally so this unit does not depend on
    HamlibTypes (which depends on HamlibInterfaces only).
    Hamlib の RIG_OK。本ユニットが HamlibTypes に依存しないよう局所宣言。 }
  RIG_OK_CODE = 0;

  { enum rig_debug_level_e: RIG_DEBUG_NONE = 0.
    enum rig_debug_level_e の RIG_DEBUG_NONE = 0。 }
  RIG_DEBUG_NONE_LEVEL = 0;

  { RIG_ENAVAIL is enum ordinal 11; functions return its negation.
    Used when a symbol this build needs is simply not exported.
    RIG_ENAVAIL は enum 序数 11。関数はその符号反転を返します。本ビルドに
    必要なシンボルが公開されていない場合に使います。 }
  RIG_ENAVAIL_CODE = 11;

  { enum rig_caps_int_e, rig.h: TARGETABLE_VFO, RIG_MODEL, PORT_TYPE,
    PTT_TYPE, HAS_GET_LEVEL.
    enum rig_caps_int_e (rig.h)。 }
  RIG_CAPS_TARGETABLE_VFO = 0;
  RIG_CAPS_PTT_TYPE       = 3;
  RIG_CAPS_HAS_GET_LEVEL  = 4;

  { ptt_type_t RIG_PTT_NONE = 0 — the rig has no PTT line configured.
    ptt_type_t の RIG_PTT_NONE = 0。PTT 線が設定されていないリグ。 }
  RIG_PTT_NONE_TYPE = 0;

  { ------------------------------------------------------------------
    The verified Hamlib range — this component's declared contract.
    検証済み Hamlib 範囲 — 本コンポーネントが宣言する契約。
    ------------------------------------------------------------------
    Every ABI-relevant value in this component (VFO bits, mode bits, type
    widths, error codes, model numbers) was read from the Hamlib headers
    for these versions on the date below. Outside this range the component
    refuses to run by default, because symbol resolution succeeding tells
    us nothing about argument widths.

    本コンポーネントの ABI 関連の値 (VFO ビット、モードビット、型幅、
    エラーコード、モデル番号) はすべて、下記の日付に下記バージョンの
    Hamlib ヘッダから読み取ったものです。この範囲外では既定で実行を拒否
    します。シンボルが解決できることは引数幅について何も保証しないためです。

    Widening this range is a deliberate act: re-run tools/check_abi.py
    against the new headers, then edit these three constants.

    範囲の拡大は意図的な作業です。新しいヘッダに対して tools/check_abi.py
    を再実行し、その後にこの 3 定数を編集してください。 }
  VERIFIED_MAJOR     = 4;
  VERIFIED_MIN_MINOR = 5;
  VERIFIED_MAX_MINOR = 7;
  VERIFIED_ON        = '2026-10-12';

  { rig_caps_cptr_e ordinals, from include/hamlib/rig.h.
    include/hamlib/rig.h の rig_caps_cptr_e の序数。 }
  RIG_CAPS_VERSION_CPTR    = 0;
  RIG_CAPS_MFG_NAME_CPTR   = 1;
  RIG_CAPS_MODEL_NAME_CPTR = 2;
  RIG_CAPS_STATUS_CPTR     = 3;

  { File names that carry no soname / version. Binding through one of
    these works today but may silently resolve to a different ABI after a
    system upgrade, so it is reported as a risk signal.

    soname / バージョンを含まないファイル名。現在は動作しますが、システム
    更新後に別の ABI へ静かに解決され得るため、危険信号として報告します。 }
  UNVERSIONED_NAMES: array[0..2] of string =
    ('hamlib.dll', 'libhamlib.dylib', 'libhamlib.so');

constructor THamlibLoader.Create;
begin
  inherited Create;
  FHandle          := NilHandle;
  FResolvedSymbols := TStringList.Create;
  FResolvedSymbols.Sorted     := True;
  FResolvedSymbols.Duplicates := dupIgnore;
end;

destructor THamlibLoader.Destroy;
begin
  Unload;
  FResolvedSymbols.Free;
  inherited;
end;

function THamlibLoader.GetCandidates(const AUserPath: string): TStringArray;
var
  EnvPath: string;
  ExeDir:  string;

  { Helper: append a single string to Result.
    ヘルパー: Result に文字列を1件追加。 }
  procedure AddCandidate(const APath: string);
  var
    L: Integer;
  begin
    L := Length(Result);
    SetLength(Result, L + 1);
    Result[L] := APath;
  end;

begin
  Result := nil;

  { 1) Explicit user-provided path always wins.
       利用者指定パスが常に最優先。 }
  if AUserPath <> '' then
    AddCandidate(AUserPath);

  { 2) Environment variable override.
       環境変数によるオーバーライド。 }
  EnvPath := GetEnvironmentVariable('VELA_HAMLIB_PATH');
  if EnvPath <> '' then
    AddCandidate(EnvPath);

  { 3) Platform-specific defaults.
       プラットフォーム別デフォルト。 }
  ExeDir := ExtractFilePath(ParamStr(0));

  {$IFDEF WINDOWS}
  AddCandidate(ExeDir + 'hamlib\libhamlib-4.dll');
  AddCandidate(ExeDir + 'libhamlib-4.dll');
  AddCandidate('libhamlib-4.dll');
  AddCandidate('libhamlib-2.dll');
  AddCandidate('hamlib.dll');
  {$ENDIF}

  {$IFDEF DARWIN}
  AddCandidate(ExeDir + '../Frameworks/libhamlib.4.dylib');
  AddCandidate('/opt/homebrew/lib/libhamlib.4.dylib');
  AddCandidate('/usr/local/lib/libhamlib.4.dylib');
  AddCandidate('libhamlib.4.dylib');
  AddCandidate('libhamlib.dylib');
  {$ENDIF}

  {$IF defined(LINUX) or defined(BSD)}
  { Bundled copy next to the executable first, so a self-contained
    AppImage/tarball build works without a system-wide install.
    まず実行ファイル隣接の同梱コピーを探し、システム全体への
    インストールなしで AppImage/tarball 配布が動くようにします。 }
  AddCandidate(ExeDir + 'lib/libhamlib.so.4');
  AddCandidate(ExeDir + 'libhamlib.so.4');
  AddCandidate('libhamlib.so.4');
  AddCandidate('libhamlib.so.2');
  AddCandidate('libhamlib.so');
  {$ENDIF}
end;

function THamlibLoader.TryLoad(const APath: string): Boolean;
begin
  FHandle := LoadLibrary(APath);
  Result  := FHandle <> NilHandle;
  if Result then
    FLibPath := APath;
end;

function THamlibLoader.ResolveRequired(const AName: string): Pointer;
begin
  Result := GetProcedureAddress(FHandle, AName);
  if Result = nil then
    raise EHamlibLoadError.CreateFmt(
      'Required Hamlib symbol "%s" not found in %s', [AName, FLibPath]);
  FResolvedSymbols.Add(AName);
end;

function THamlibLoader.ResolveOptional(const AName: string): Pointer;
begin
  Result := GetProcedureAddress(FHandle, AName);
  if Result <> nil then
    FResolvedSymbols.Add(AName);
end;

procedure THamlibLoader.DetectVersion;
var
  VerStr: string;
  P:      PAnsiChar;
  i:      Integer;
  sMajor: string;
  sMinor: string;
begin
  FApiMajor := 0;
  FApiMinor := 0;
  if not Assigned(F_rig_version) then Exit;

  P := F_rig_version();
  if P = nil then Exit;

  VerStr       := AnsiString(P);
  FVersionText := VerStr;
  { Parse "Hamlib 4.5.5" or similar.
    "Hamlib 4.5.5" 等をパース。 }
  if Pos('.', VerStr) <= 0 then Exit;

  { Find first digit, then parse major.minor.
    最初の数字を見つけ major.minor をパース。 }
  for i := 1 to Length(VerStr) do
    if (VerStr[i] >= '0') and (VerStr[i] <= '9') then
    begin
      VerStr := Copy(VerStr, i, MaxInt);
      Break;
    end;

  if Pos('.', VerStr) <= 0 then Exit;

  sMajor    := Copy(VerStr, 1, Pos('.', VerStr) - 1);
  FApiMajor := StrToIntDef(sMajor, 0);
  VerStr    := Copy(VerStr, Pos('.', VerStr) + 1, MaxInt);
  if Pos('.', VerStr) > 0 then
    sMinor := Copy(VerStr, 1, Pos('.', VerStr) - 1)
  else
    sMinor := VerStr;
  FApiMinor := StrToIntDef(sMinor, 0);
end;

function THamlibLoader.Load(const APath: string): Boolean;
var
  Candidate: string;
begin
  Result := False;
  if FHandle <> NilHandle then
    Exit(True);

  for Candidate in GetCandidates(APath) do
    if TryLoad(Candidate) then Break;

  if FHandle = NilHandle then
    Exit(False);

  EnterCriticalSection(GRegistryLock);
  try
    Inc(GLoadedInstances);
  finally
    LeaveCriticalSection(GRegistryLock);
  end;

  try
    { Resolve required symbols. 必須シンボルを解決。 }
    F_rig_init     := T_rig_init    (ResolveRequired('rig_init'));
    F_rig_open     := T_rig_open    (ResolveRequired('rig_open'));
    F_rig_close    := T_rig_close   (ResolveRequired('rig_close'));
    F_rig_cleanup  := T_rig_cleanup (ResolveRequired('rig_cleanup'));
    F_rig_set_freq := T_rig_set_freq(ResolveRequired('rig_set_freq'));
    F_rig_get_freq := T_rig_get_freq(ResolveRequired('rig_get_freq'));
    F_rig_set_mode := T_rig_set_mode(ResolveRequired('rig_set_mode'));
    F_rig_get_mode := T_rig_get_mode(ResolveRequired('rig_get_mode'));
    F_rig_set_ptt  := T_rig_set_ptt (ResolveRequired('rig_set_ptt'));
    F_rig_get_ptt  := T_rig_get_ptt (ResolveRequired('rig_get_ptt'));
    F_rigerror     := T_rigerror    (ResolveRequired('rigerror'));

    { Resolve optional symbols. 任意シンボルを解決。 }
    F_rig_set_conf     := T_rig_set_conf    (ResolveOptional('rig_set_conf'));
    F_rig_token_lookup := T_rig_token_lookup(ResolveOptional('rig_token_lookup'));
    F_rig_version      := T_rig_version     (ResolveOptional('rig_version'));
    F_rigerror2        := T_rigerror2       (ResolveOptional('rigerror2'));

    F_rig_check_backend     := T_rig_check_backend
                                 (ResolveOptional('rig_check_backend'));
    F_rig_get_caps_cptr     := T_rig_get_caps_cptr
                                 (ResolveOptional('rig_get_caps_cptr'));
    F_rig_load_all_backends := T_rig_load_all_backends
                                 (ResolveOptional('rig_load_all_backends'));
    F_rig_list_foreach_model := T_rig_list_foreach_model
                                 (ResolveOptional('rig_list_foreach_model'));
    F_rig_set_debug         := T_rig_set_debug
                                 (ResolveOptional('rig_set_debug'));

    F_rig_set_vfo        := T_rig_set_vfo       (ResolveOptional('rig_set_vfo'));
    F_rig_get_vfo        := T_rig_get_vfo       (ResolveOptional('rig_get_vfo'));
    F_rig_set_split_vfo  := T_rig_set_split_vfo (ResolveOptional('rig_set_split_vfo'));
    F_rig_get_split_vfo  := T_rig_get_split_vfo (ResolveOptional('rig_get_split_vfo'));
    F_rig_set_split_freq := T_rig_set_split_freq(ResolveOptional('rig_set_split_freq'));
    F_rig_get_split_freq := T_rig_get_split_freq(ResolveOptional('rig_get_split_freq'));
    F_rig_set_level      := T_rig_set_level     (ResolveOptional('rig_set_level'));
    F_rig_get_level      := T_rig_get_level     (ResolveOptional('rig_get_level'));
    F_rig_set_func       := T_rig_set_func      (ResolveOptional('rig_set_func'));
    F_rig_get_func       := T_rig_get_func      (ResolveOptional('rig_get_func'));
    F_rig_vfo_op         := T_rig_vfo_op        (ResolveOptional('rig_vfo_op'));
    F_rig_get_caps_int   := T_rig_get_caps_int  (ResolveOptional('rig_get_caps_int'));

    DetectVersion;
    DetectUnversionedBinding;

    { Silence the library before anything else uses it. Verified
      against real Hamlib 4.5.5: without this, loading the backends
      prints dozens of registration lines and every rig_open prints a
      full protocol trace — on stdout as well as stderr in the Debian
      build, which corrupts the output of any console program and can
      pop a console window on Windows.

      An application that wants Hamlib's diagnostics calls
      SetDebugLevel again with a higher level; the component never
      lowers it afterwards.

      他のどこかが使う前にライブラリを静かにします。実 Hamlib 4.5.5 で
      確認済み: これを行わないと、バックエンドのロードで数十行の登録
      メッセージが、rig_open ごとに完全なプロトコルトレースが印字され
      ます。Debian ビルドでは stderr だけでなく stdout にも出るため、
      コンソールプログラムの出力を壊し、Windows ではコンソール
      ウィンドウを開かせ得ます。

      Hamlib の診断が欲しいアプリケーションは SetDebugLevel をより高い
      レベルで呼び直します。コンポーネントがその後下げることはありません。 }
    SetDebugLevel(RIG_DEBUG_NONE_LEVEL);

    Result := True;
  except
    Unload;
    raise;
  end;
end;

procedure THamlibLoader.Unload;
begin
  if FHandle <> NilHandle then
  begin
    UnloadLibrary(FHandle);
    FHandle := NilHandle;

    { When the last loader lets go, the library may leave the process
      and a later dlopen gets a fresh, empty backend table. Clearing
      the flag here is what makes that case correct: left set, a
      reloaded library would never have its backends registered and
      every model lookup would fail.
      最後のローダが手放すとライブラリはプロセスから外れうるため、後の
      dlopen は新しい空のバックエンド表を得ます。ここでフラグをクリア
      することがその場合を正しくします。立てたままなら、再ロードされた
      ライブラリはバックエンド未登録のままとなり、すべての機種検索が
      失敗します。 }
    EnterCriticalSection(GRegistryLock);
    try
      if GLoadedInstances > 0 then
        Dec(GLoadedInstances);
      if GLoadedInstances = 0 then
        GBackendsRegistered := False;
    finally
      LeaveCriticalSection(GRegistryLock);
    end;
  end;
  FBackendsLoaded := False;
  FResolvedSymbols.Clear;
  FLibPath  := '';
  FApiMajor := 0;
  FApiMinor := 0;
end;

function THamlibLoader.GetIsLoaded: Boolean;
begin
  Result := FHandle <> NilHandle;
end;

function THamlibLoader.GetApiMajor: Integer;
begin
  Result := FApiMajor;
end;

function THamlibLoader.GetApiMinor: Integer;
begin
  Result := FApiMinor;
end;

function THamlibLoader.GetLibPath: string;
begin
  Result := FLibPath;
end;

function THamlibLoader.HasSymbol(const AName: string): Boolean;
var
  Idx: Integer;
begin
  Result := FResolvedSymbols.Find(AName, Idx);
end;

{ ----------------------------------------------------------------
  Function pointer wrappers — straight-through calls to the C API.
  関数ポインタラッパー — C API へのストレート呼び出し。
  ---------------------------------------------------------------- }

function THamlibLoader.CallRigInit(AModel: Integer): Pointer;
begin
  Assert(Assigned(F_rig_init), 'rig_init not loaded');
  Result := F_rig_init(hl_model_t(AModel));
end;

function THamlibLoader.CallRigOpen(ARig: Pointer): Integer;
begin
  Assert(Assigned(F_rig_open), 'rig_open not loaded');
  Result := F_rig_open(ARig);
end;

function THamlibLoader.CallRigClose(ARig: Pointer): Integer;
begin
  Assert(Assigned(F_rig_close), 'rig_close not loaded');
  Result := F_rig_close(ARig);
end;

function THamlibLoader.CallRigCleanup(ARig: Pointer): Integer;
begin
  Assert(Assigned(F_rig_cleanup), 'rig_cleanup not loaded');
  Result := F_rig_cleanup(ARig);
end;

function THamlibLoader.CallRigSetFreq(ARig: Pointer; AVfo: Integer;
                                       AFreq: Double): Integer;
begin
  Assert(Assigned(F_rig_set_freq), 'rig_set_freq not loaded');
  Result := F_rig_set_freq(ARig, hl_vfo_t(AVfo), AFreq);
end;

function THamlibLoader.CallRigGetFreq(ARig: Pointer; AVfo: Integer;
                                       out AFreq: Double): Integer;
var
  CFreq: hl_freq_t;
begin
  Assert(Assigned(F_rig_get_freq), 'rig_get_freq not loaded');
  CFreq  := 0;
  Result := F_rig_get_freq(ARig, hl_vfo_t(AVfo), CFreq);
  AFreq  := CFreq;
end;

function THamlibLoader.CallRigSetMode(ARig: Pointer; AVfo: Integer;
                                       AMode: Int64; AWidth: Int64): Integer;
begin
  Assert(Assigned(F_rig_set_mode), 'rig_set_mode not loaded');
  { AWidth narrows to C long here; on Win64 that is 32-bit, which is
    ample for a passband in Hz.
    AWidth はここで C の long に縮小されます。Win64 では 32bit ですが、
    Hz 単位の通過帯域幅には十分です。 }
  Result := F_rig_set_mode(ARig, hl_vfo_t(AVfo),
                           hl_rmode_t(AMode), hl_pbwidth_t(AWidth));
end;

function THamlibLoader.CallRigGetMode(ARig: Pointer; AVfo: Integer;
                                       out AMode: Int64;
                                       out AWidth: Int64): Integer;
var
  CMode:  hl_rmode_t;
  CWidth: hl_pbwidth_t;
begin
  Assert(Assigned(F_rig_get_mode), 'rig_get_mode not loaded');
  CMode  := 0;
  CWidth := 0;
  Result := F_rig_get_mode(ARig, hl_vfo_t(AVfo), CMode, CWidth);
  AMode  := Int64(CMode);
  AWidth := Int64(CWidth);
end;

function THamlibLoader.CallRigSetPtt(ARig: Pointer; AVfo: Integer;
                                      APtt: Integer): Integer;
begin
  Assert(Assigned(F_rig_set_ptt), 'rig_set_ptt not loaded');
  Result := F_rig_set_ptt(ARig, hl_vfo_t(AVfo), hl_ptt_t(APtt));
end;

function THamlibLoader.CallRigGetPtt(ARig: Pointer; AVfo: Integer;
                                      out APtt: Integer): Integer;
var
  CPtt: hl_ptt_t;
begin
  Assert(Assigned(F_rig_get_ptt), 'rig_get_ptt not loaded');
  CPtt   := 0;
  Result := F_rig_get_ptt(ARig, hl_vfo_t(AVfo), CPtt);
  APtt   := CPtt;
end;

function THamlibLoader.CallRigError(ACode: Integer): string;
var
  P:   PAnsiChar;
  Eol: Integer;
begin
  { Prefer the single-line call. See the comment on T_rigerror2 for why
    rigerror() cannot be used as-is.
    1 行形式を優先します。rigerror() をそのまま使えない理由は
    T_rigerror2 のコメントを参照してください。 }
  P := nil;
  if Assigned(F_rigerror2) then
    P := F_rigerror2(ACode)
  else if Assigned(F_rigerror) then
    P := F_rigerror(ACode);

  if P = nil then
  begin
    Result := Format('Hamlib error %d', [ACode]);
    Exit;
  end;

  Result := AnsiString(P);

  { Keep the first line only. With rigerror2 there is just one line and
    a trailing LF; with rigerror the first line is the message and the
    rest is trace.
    1 行目だけを残します。rigerror2 なら 1 行と末尾 LF のみ、rigerror
    なら 1 行目がメッセージで残りはトレースです。 }
  Eol := Pos(#10, Result);
  if Eol > 0 then
    Result := Copy(Result, 1, Eol - 1);
  Result := TrimRight(Result);

  { A code Hamlib does not know gives an empty or useless string; name
    the number instead of handing the application a blank message.
    Hamlib が知らないコードでは空または無意味な文字列になります。空の
    メッセージを渡すのではなく番号を示します。 }
  if Result = '' then
    Result := Format('Hamlib error %d', [ACode]);
end;

procedure THamlibLoader.DetectUnversionedBinding;
var
  Base: string;
  i:    Integer;
begin
  FUnversioned := False;
  Base := LowerCase(ExtractFileName(FLibPath));
  for i := Low(UNVERSIONED_NAMES) to High(UNVERSIONED_NAMES) do
    if Base = LowerCase(UNVERSIONED_NAMES[i]) then
    begin
      FUnversioned := True;
      Exit;
    end;
end;

{ ----------------- IHamlibDiagnostics ----------------- }

function THamlibLoader.GetVersionText: string;
begin
  Result := FVersionText;
end;

function THamlibLoader.GetSupportedRangeText: string;
begin
  Result := Format('%d.%d .. %d.%d (verified %s)',
    [VERIFIED_MAJOR, VERIFIED_MIN_MINOR,
     VERIFIED_MAJOR, VERIFIED_MAX_MINOR, VERIFIED_ON]);
end;

function THamlibLoader.GetUnversionedBinding: Boolean;
begin
  Result := FUnversioned;
end;

function THamlibLoader.GetVersionVerdict: TRigVersionVerdict;
begin
  { DetectVersion leaves both at 0 when rig_version is absent or
    unparseable. Treat that as unknown rather than as a mismatch: an
    unreadable version is a different situation from a wrong one.

    rig_version が無い、または解析できない場合 DetectVersion は両方を 0 の
    まま残します。これは不一致ではなく「不明」として扱います。読めない
    バージョンと誤ったバージョンは別の状況です。 }
  if (FApiMajor = 0) and (FApiMinor = 0) then
    Exit(rvvUnknown);

  if (FApiMajor = VERIFIED_MAJOR)
     and (FApiMinor >= VERIFIED_MIN_MINOR)
     and (FApiMinor <= VERIFIED_MAX_MINOR) then
    Result := rvvVerified
  else
    Result := rvvUntested;
end;

function THamlibLoader.CheckModel(AModel: Integer;
                                   out AMfg, AModelName: string;
                                   out AAnswered: Boolean): Boolean;
var
  P: PAnsiChar;
begin
  AMfg       := '';
  AModelName := '';
  AAnswered  := False;
  Result     := False;

  if (not Assigned(F_rig_check_backend))
     or (not Assigned(F_rig_get_caps_cptr)) then
    Exit;   { too old to answer / 古くて回答できない }

  { Backends are registered lazily; without this the first query for a
    model whose backend has not been touched yet reports it as unknown.
    バックエンドは遅延登録されます。これを呼ばないと、まだ触れていない
    バックエンドのモデルが「未知」と報告されます。 }
  EnsureBackendsLoaded;

  AAnswered := True;
  if F_rig_check_backend(hl_model_t(AModel)) <> RIG_OK_CODE then
    Exit;   { answered, and the answer is "unknown model"
              / 回答あり。内容は「未知のモデル」 }

  P := F_rig_get_caps_cptr(hl_model_t(AModel), RIG_CAPS_MFG_NAME_CPTR);
  if P <> nil then AMfg := AnsiString(P);

  P := F_rig_get_caps_cptr(hl_model_t(AModel), RIG_CAPS_MODEL_NAME_CPTR);
  if P <> nil then AModelName := AnsiString(P);

  Result := True;
end;

{ ====================================================================
  Model enumeration (IHamlibCatalog)
  モデル列挙 (IHamlibCatalog)
  ==================================================================== }

type
  { Growable list of model numbers, filled from the C callback. A plain
    record is used rather than a class so the callback touches nothing
    that could raise on allocation beyond SetLength.

    C コールバックから埋める可変長のモデル番号リスト。SetLength 以外で
    例外を発生させ得るものにコールバックが触れないよう、クラスではなく
    レコードを使います。 }
  TModelNumberList = record
    Count: Integer;
    Items: array of Integer;
    Failed: Boolean;
  end;
  PModelNumberList = ^TModelNumberList;

{ Grows in blocks so a few hundred backends do not cause a few hundred
  reallocations inside a C iteration.
  C の反復の内側で数百回の再確保が起きないよう、ブロック単位で伸ばします。 }
const
  MODEL_LIST_GROW = 64;

function CollectModelCallback(model: hl_model_t; data: Pointer): cint; cdecl;
var
  L: PModelNumberList;
begin
  { Never let an exception cross back into C. On failure, mark the list
    and return 0 to stop the walk cleanly rather than keep failing for
    every remaining backend.

    例外を C 側に戻してはなりません。失敗時はリストに印を付け、残りの
    全バックエンドで失敗を繰り返すのではなく 0 を返して走査を正常に
    終了させます。 }
  Result := 1;
  try
    L := PModelNumberList(data);
    if L = nil then
    begin
      Result := 0;
      Exit;
    end;
    if L^.Count >= Length(L^.Items) then
      SetLength(L^.Items, Length(L^.Items) + MODEL_LIST_GROW);
    L^.Items[L^.Count] := Integer(model);
    Inc(L^.Count);
  except
    if data <> nil then
      PModelNumberList(data)^.Failed := True;
    Result := 0;
  end;
end;

function THamlibLoader.ListModels(out AList: TRigModelInfoArray): Boolean;
var
  Numbers: TModelNumberList;
  i:       Integer;
  P:       PAnsiChar;
begin
  SetLength(AList, 0);
  Result := False;

  { Enumeration needs the iterator to walk the backends and
    rig_get_caps_cptr to name them. Without both, there is nothing
    useful to return and the caller falls back to a plain number entry.

    列挙にはバックエンドを走査する反復関数と、名前を得る
    rig_get_caps_cptr の両方が必要です。両方が無ければ返せる有用な情報が
    なく、呼び出し側は番号入力にフォールバックします。 }
  if (not Assigned(F_rig_list_foreach_model))
     or (not Assigned(F_rig_get_caps_cptr)) then
    Exit;

  { Nothing is in the hash table until the backends register themselves.
    バックエンドが自己登録するまでハッシュテーブルは空です。 }
  EnsureBackendsLoaded;

  Numbers.Count  := 0;
  Numbers.Failed := False;
  SetLength(Numbers.Items, MODEL_LIST_GROW);

  F_rig_list_foreach_model(@CollectModelCallback, @Numbers);

  if Numbers.Failed or (Numbers.Count = 0) then Exit;

  SetLength(AList, Numbers.Count);
  for i := 0 to Numbers.Count - 1 do
  begin
    AList[i].ModelNumber   := Numbers.Items[i];
    AList[i].Manufacturer  := '';
    AList[i].ModelName     := '';
    AList[i].BackendStatus := '';

    P := F_rig_get_caps_cptr(hl_model_t(Numbers.Items[i]),
                             RIG_CAPS_MFG_NAME_CPTR);
    if P <> nil then AList[i].Manufacturer := AnsiString(P);

    P := F_rig_get_caps_cptr(hl_model_t(Numbers.Items[i]),
                             RIG_CAPS_MODEL_NAME_CPTR);
    if P <> nil then AList[i].ModelName := AnsiString(P);

    P := F_rig_get_caps_cptr(hl_model_t(Numbers.Items[i]),
                             RIG_CAPS_STATUS_CPTR);
    if P <> nil then AList[i].BackendStatus := AnsiString(P);
  end;

  Result := True;
end;

procedure THamlibLoader.SetDebugLevel(ALevel: Integer);
begin
  if Assigned(F_rig_set_debug) then
    F_rig_set_debug(cint(ALevel));
end;

procedure THamlibLoader.EnsureBackendsLoaded;
begin
  if FBackendsLoaded then Exit;
  if not Assigned(F_rig_load_all_backends) then Exit;

  EnterCriticalSection(GRegistryLock);
  try
    if not GBackendsRegistered then
    begin
      F_rig_load_all_backends();
      GBackendsRegistered := True;
    end;
  finally
    LeaveCriticalSection(GRegistryLock);
  end;

  { The per-instance flag is a fast path only; the module-level one
    above is the authoritative answer.
    インスタンス側のフラグは高速経路にすぎません。正式な答えは上の
    モジュール全体のフラグです。 }
  FBackendsLoaded := True;
end;

{ ====================================================================
  IHamlibRigControl — the operations added in Rev.6.0
  IHamlibRigControl - Rev.6.0 で追加した操作
  ====================================================================
  Every one follows the same shape: refuse with -RIG_ENAVAIL when the
  symbol is missing, otherwise forward and return Hamlib's own code.
  Reporting "not available on this rig" for a missing symbol is exactly
  what an application needs to hear; inventing a different error would
  make a trimmed library look like a broken rig.

  いずれも同じ形です。シンボルが無ければ -RIG_ENAVAIL で拒否し、あれば
  転送して Hamlib の戻り値をそのまま返します。シンボル欠落に対して「この
  機種では利用できません」と報告するのは、アプリケーションが聞くべき内容
  そのものです。別のエラーを捏造すると、機能を削ったライブラリが壊れた
  リグのように見えてしまいます。 }

function THamlibLoader.CallRigSetVfo(ARig: Pointer; AVfo: Integer): Integer;
begin
  if not Assigned(F_rig_set_vfo) then Exit(-RIG_ENAVAIL_CODE);
  Result := F_rig_set_vfo(ARig, hl_vfo_t(AVfo));
end;

function THamlibLoader.CallRigGetVfo(ARig: Pointer; out AVfo: Integer): Integer;
var
  V: hl_vfo_t;
begin
  AVfo := 0;
  if not Assigned(F_rig_get_vfo) then Exit(-RIG_ENAVAIL_CODE);
  V      := 0;
  Result := F_rig_get_vfo(ARig, @V);
  if Result >= 0 then AVfo := Integer(V);
end;

function THamlibLoader.CallRigSetSplitVfo(ARig: Pointer; ARxVfo: Integer;
                                           ASplitOn: Boolean;
                                           ATxVfo: Integer): Integer;
var
  Split: cint;
begin
  if not Assigned(F_rig_set_split_vfo) then Exit(-RIG_ENAVAIL_CODE);
  { split_t is a C enum: RIG_SPLIT_OFF = 0, RIG_SPLIT_ON = 1.
    split_t は C の enum。RIG_SPLIT_OFF = 0、RIG_SPLIT_ON = 1。 }
  if ASplitOn then Split := 1 else Split := 0;
  Result := F_rig_set_split_vfo(ARig, hl_vfo_t(ARxVfo), Split,
                                hl_vfo_t(ATxVfo));
end;

function THamlibLoader.CallRigGetSplitVfo(ARig: Pointer; ARxVfo: Integer;
                                           out ASplitOn: Boolean;
                                           out ATxVfo: Integer): Integer;
var
  Split: cint;
  TxV:   hl_vfo_t;
begin
  ASplitOn := False;
  ATxVfo   := 0;
  if not Assigned(F_rig_get_split_vfo) then Exit(-RIG_ENAVAIL_CODE);
  Split  := 0;
  TxV    := 0;
  Result := F_rig_get_split_vfo(ARig, hl_vfo_t(ARxVfo), @Split, @TxV);
  if Result >= 0 then
  begin
    ASplitOn := Split <> 0;
    ATxVfo   := Integer(TxV);
  end;
end;

function THamlibLoader.CallRigSetSplitFreq(ARig: Pointer; AVfo: Integer;
                                            ATxFreq: Double): Integer;
begin
  if not Assigned(F_rig_set_split_freq) then Exit(-RIG_ENAVAIL_CODE);
  Result := F_rig_set_split_freq(ARig, hl_vfo_t(AVfo), hl_freq_t(ATxFreq));
end;

function THamlibLoader.CallRigGetSplitFreq(ARig: Pointer; AVfo: Integer;
                                            out ATxFreq: Double): Integer;
var
  F: hl_freq_t;
begin
  ATxFreq := 0;
  if not Assigned(F_rig_get_split_freq) then Exit(-RIG_ENAVAIL_CODE);
  F      := 0;
  Result := F_rig_get_split_freq(ARig, hl_vfo_t(AVfo), @F);
  if Result >= 0 then ATxFreq := Double(F);
end;

function THamlibLoader.CallRigSetLevelFloat(ARig: Pointer; AVfo: Integer;
                                             ALevelBit: Int64;
                                             AValue: Double): Integer;
var
  V: hl_value_t;
begin
  if not Assigned(F_rig_set_level) then Exit(-RIG_ENAVAIL_CODE);
  { Zero the whole union first. value_t is 16 bytes and only 4 of them
    are the float; leaving the rest as stack garbage would pass
    uninitialised bytes into C, which is harmless today and the kind of
    thing that stops being harmless when a library starts reading .b.

    まず共用体全体をゼロ化します。value_t は 16 バイトで、float はその
    うち 4 バイトだけです。残りをスタックのゴミのままにすると未初期化
    バイトを C に渡すことになります。今日は無害ですが、ライブラリが .b を
    読み始めた途端に無害でなくなる類の話です。 }
  FillChar(V, SizeOf(V), 0);
  V.f    := cfloat(AValue);
  Result := F_rig_set_level(ARig, hl_vfo_t(AVfo), hl_setting_t(ALevelBit), V);
end;

function THamlibLoader.CallRigSetLevelInt(ARig: Pointer; AVfo: Integer;
                                           ALevelBit: Int64;
                                           AValue: Integer): Integer;
var
  V: hl_value_t;
begin
  if not Assigned(F_rig_set_level) then Exit(-RIG_ENAVAIL_CODE);
  FillChar(V, SizeOf(V), 0);
  V.i    := cint(AValue);
  Result := F_rig_set_level(ARig, hl_vfo_t(AVfo), hl_setting_t(ALevelBit), V);
end;

function THamlibLoader.CallRigGetLevel(ARig: Pointer; AVfo: Integer;
                                        ALevelBit: Int64; AAsFloat: Boolean;
                                        out AFloatValue: Double;
                                        out AIntValue: Integer): Integer;
var
  V: hl_value_t;
begin
  AFloatValue := 0;
  AIntValue   := 0;
  if not Assigned(F_rig_get_level) then Exit(-RIG_ENAVAIL_CODE);

  FillChar(V, SizeOf(V), 0);
  Result := F_rig_get_level(ARig, hl_vfo_t(AVfo), hl_setting_t(ALevelBit), @V);
  if Result < 0 then Exit;

  { Which member holds the answer is fixed per level by Hamlib, and the
    caller has already looked it up. Both are filled so a display can
    use whichever it finds convenient, but only one of them is real.

    どちらのメンバに答えが入るかはレベルごとに Hamlib が決めており、
    呼び出し側は既にそれを調べています。表示側が都合のよい方を使える
    よう両方を埋めますが、実体はどちらか一方だけです。 }
  if AAsFloat then
  begin
    AFloatValue := V.f;
    AIntValue   := Round(V.f);
  end
  else
  begin
    AIntValue   := V.i;
    AFloatValue := V.i;
  end;
end;

function THamlibLoader.CallRigSetFunc(ARig: Pointer; AVfo: Integer;
                                       AFuncBit: Int64;
                                       AActive: Boolean): Integer;
var
  Status: cint;
begin
  if not Assigned(F_rig_set_func) then Exit(-RIG_ENAVAIL_CODE);
  if AActive then Status := 1 else Status := 0;
  Result := F_rig_set_func(ARig, hl_vfo_t(AVfo), hl_setting_t(AFuncBit),
                           Status);
end;

function THamlibLoader.CallRigGetFunc(ARig: Pointer; AVfo: Integer;
                                       AFuncBit: Int64;
                                       out AActive: Boolean): Integer;
var
  Status: cint;
begin
  AActive := False;
  if not Assigned(F_rig_get_func) then Exit(-RIG_ENAVAIL_CODE);
  Status := 0;
  Result := F_rig_get_func(ARig, hl_vfo_t(AVfo), hl_setting_t(AFuncBit),
                           @Status);
  if Result >= 0 then AActive := Status <> 0;
end;

function THamlibLoader.CallRigVfoOp(ARig: Pointer; AVfo: Integer;
                                     AOp: Integer): Integer;
begin
  if not Assigned(F_rig_vfo_op) then Exit(-RIG_ENAVAIL_CODE);
  Result := F_rig_vfo_op(ARig, hl_vfo_t(AVfo), cint(AOp));
end;

function THamlibLoader.QueryCapabilities(AModel: Integer;
                                          out ACaps: TRigCapabilities): Boolean;
var
  V: clonglong;
begin
  ACaps.Known         := False;
  ACaps.TargetableVfo := False;
  ACaps.PttType       := 0;
  ACaps.HasPtt        := False;
  ACaps.GetLevels     := [];
  ACaps.SetLevels     := [];
  ACaps.GetFuncs      := [];
  ACaps.SetFuncs      := [];
  ACaps.VfoOps        := [];
  Result := False;

  if not Assigned(F_rig_get_caps_int) then Exit;

  EnsureBackendsLoaded;

  { Hamlib publishes only five fields of struct rig_caps through its
    public API (enum rig_caps_int_e). has_set_level, has_get_func,
    has_set_func and vfo_ops are NOT among them, so the corresponding
    sets stay empty and the application must treat empty as "unknown".
    Pretending otherwise — for instance by copying has_get_level into
    SetLevels — would make a UI disable controls that work.

    Hamlib が公開 API 経由で見せる struct rig_caps は 5 フィールドだけ
    です (enum rig_caps_int_e)。has_set_level、has_get_func、
    has_set_func、vfo_ops は含まれないため、対応する集合は空のままに
    し、アプリケーションは空を「不明」と解釈する必要があります。
    たとえば has_get_level を SetLevels に流用するなどしてごまかすと、
    実際には動くコントロールを UI が無効化してしまいます。 }
  V := F_rig_get_caps_int(hl_model_t(AModel), RIG_CAPS_TARGETABLE_VFO);
  ACaps.TargetableVfo := V <> 0;

  V := F_rig_get_caps_int(hl_model_t(AModel), RIG_CAPS_PTT_TYPE);
  ACaps.PttType := Integer(V);
  ACaps.HasPtt  := Integer(V) <> RIG_PTT_NONE_TYPE;

  V := F_rig_get_caps_int(hl_model_t(AModel), RIG_CAPS_HAS_GET_LEVEL);
  ACaps.GetLevels := THamlibLevelCodec.SetFromHamlib(Int64(V));

  ACaps.Known := True;
  Result      := True;
end;

function THamlibLoader.SetConf(ARig: Pointer;
                                const AName, AValue: string): Integer;
var
  Token: hl_token_t;
begin
  { Both symbols are optional; a very old Hamlib without them simply
    keeps its defaults rather than failing the connection.
    どちらのシンボルも任意です。これらを持たない古い Hamlib では接続を
    失敗させず、既定値のままにします。 }
  if (not Assigned(F_rig_set_conf)) or (not Assigned(F_rig_token_lookup)) then
    Exit(RIG_OK_CODE);

  Token := F_rig_token_lookup(ARig, PAnsiChar(AnsiString(AName)));
  if Token = 0 then
    Exit(RIG_OK_CODE);   { unknown token on this build / このビルドに無いトークン }

  Result := F_rig_set_conf(ARig, Token, PAnsiChar(AnsiString(AValue)));
end;

function THamlibLoader.SetSerialPort(ARig: Pointer; const APort: string): Integer;
begin
  Result := SetConf(ARig, 'rig_pathname', APort);
end;

function THamlibLoader.SetSerialBaud(ARig: Pointer; ABaud: Integer): Integer;
begin
  Result := SetConf(ARig, 'serial_speed', IntToStr(ABaud));
end;

initialization
  InitCriticalSection(GRegistryLock);

finalization
  DoneCriticalSection(GRegistryLock);

end.
