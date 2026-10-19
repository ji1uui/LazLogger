{
  HamlibInterfaces.pas

  Public interfaces and types for the Hamlib wrapper component.
  This is the only unit that application code typically needs to know
  about. All other units are implementation details.

  Hamlib ラッパーコンポーネントの公開インターフェースと型定義です。
  アプリケーションコードは通常、このユニットだけを意識すればよく、
  他のユニットはすべて実装詳細です。

  Layer:    Cross-cutting (used by all layers / 全層から参照される)
  Depends:  SysUtils only / SysUtils のみ
}
unit HamlibInterfaces;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils;

type
  { ====================================================================
    Basic enumerations and constants
    基本列挙型と定数
    ==================================================================== }

  { TRigVfo - identifies a VFO (Variable Frequency Oscillator) on the rig.
    rvfoCurr means "whichever VFO is currently active".

    TRigVfo - リグ上の VFO (周波数調整用発振器) を識別します。
    rvfoCurr は「現在アクティブな VFO」を意味します。 }
  TRigVfo = (
    rvfoCurr,   { Current / 現在の VFO }
    rvfoA,      { VFO A   / 主 VFO }
    rvfoB,      { VFO B   / 副 VFO }
    rvfoMain,   { Main    / メイン受信機 (デュアル受信機) }
    rvfoSub     { Sub     / サブ受信機 (デュアル受信機) }
  );

  { TRigPttState - PTT (Push-To-Talk) transmission state.
    TRigPttState - PTT (送信ボタン) の状態。 }
  TRigPttState = (
    rpttOff,        { RX           / 受信中 }
    rpttOn,         { TX (default) / 送信中 (既定) }
    rpttOnMic,      { TX via mic   / マイク経由送信 }
    rpttOnData      { TX via data  / データ経由送信 }
  );

  { TRigCommandStatus - completion status of an asynchronous command.
    TRigCommandStatus - 非同期コマンドの完了ステータス。 }
  TRigCommandStatus = (
    rcsSuccess,     { Completed normally / 正常完了 }
    rcsError,       { Hamlib returned an error / Hamlib がエラーを返した }
    rcsCancelled,   { Cancelled by ICancellationToken or CancelAllPending
                      / ICancellationToken または CancelAllPending によりキャンセル }
    rcsTimeout,     { Did not complete within CommandTimeoutMs
                      / CommandTimeoutMs 以内に完了しなかった }
    rcsRejected     { Circuit Breaker is open
                      / Circuit Breaker が遮断中 }
  );

  { ====================================================================
    TRigMode — operating mode as a domain value, not a Hamlib bitmask.
    TRigMode - Hamlib のビットマスクではなくドメイン値としての動作モード。
    ====================================================================
    Hamlib represents a mode as one bit of a 64-bit rmode_t. Exposing
    that bitmask would force every application to know which bit means
    USB, i.e. to encode a constant that lives in another project's
    header. This enum carries the same information as a name, and
    THamlibModeCodec is the only place that knows the bit numbers.

    Hamlib はモードを 64bit rmode_t の 1 ビットで表します。そのビット
    マスクを公開すると、どのビットが USB なのかを全アプリケーションが
    知る必要が生じます。つまり別プロジェクトのヘッダに属する定数を
    自分のコードに埋め込むことになります。本列挙型は同じ情報を名前で
    運び、ビット番号を知るのは THamlibModeCodec だけです。

    rmUnknown means "the rig reported something this binding has no name
    for" — a newer Hamlib mode, or a mask with more than one bit set.
    The raw value is still available in TRigModeResult.RawMode, so an
    application is never cut off from information it needs.

    rmUnknown は「本バインディングに名前が無い値をリグが報告した」こと
    を意味します (より新しい Hamlib のモード、または複数ビットが立った
    マスク)。生値は TRigModeResult.RawMode で引き続き取得できるため、
    必要な情報から隔離されることはありません。

    Verified against Hamlib 4.5.5 and 4.7.2 rig.h on 2026-10-13. Across
    those versions Hamlib only ever filled previously reserved bits
    (RIG_MODE_BIT40..46 became USBD1..3, LSBD1..3, WFMS); no existing
    mode was renumbered. tools/check_abi.py enforces this.

    2026-10-13 に Hamlib 4.5.5 と 4.7.2 の rig.h で照合済み。両版の間で
    Hamlib は予約ビットを埋めただけ (RIG_MODE_BIT40..46 が USBD1..3,
    LSBD1..3, WFMS になった) で、既存モードの採番変更はありません。
    tools/check_abi.py がこれを強制します。 }
  TRigMode = (
    rmUnknown,    { Unnamed or composite value / 名前の無い値、または複合値 }

    { --- the modes an amateur station uses daily / 日常的に使うモード --- }
    rmAM,         { AM }
    rmCW,         { CW, normal sideband / CW 正サイドバンド }
    rmUSB,        { Upper sideband / 上側波帯 }
    rmLSB,        { Lower sideband / 下側波帯 }
    rmRTTY,       { Radio teletype / ラジオテレタイプ }
    rmFM,         { Narrow-band FM / 狭帯域 FM }
    rmWFM,        { Broadcast wide FM / 放送用広帯域 FM }
    rmCWR,        { CW, reverse sideband / CW 逆サイドバンド }
    rmRTTYR,      { RTTY, reverse sideband / RTTY 逆サイドバンド }
    rmAMS,        { AM synchronous / 同期検波 AM }
    rmPktLSB,     { Packet/digital on LSB / LSB でのパケット・デジタル }
    rmPktUSB,     { Packet/digital on USB — FT8 etc. / USB でのパケット (FT8 等) }
    rmPktFM,      { Packet/digital on FM / FM でのパケット }
    rmEcssUSB,    { Exalted carrier SSB, upper / 搬送波強調 SSB 上側 }
    rmEcssLSB,    { Exalted carrier SSB, lower / 搬送波強調 SSB 下側 }
    rmFax,        { Facsimile / ファクシミリ }

    { --- less common, but defined by Hamlib / 使用頻度は低いが Hamlib 定義あり --- }
    rmSAM,        { Synchronous AM, double sideband / 同期 AM 両側波帯 }
    rmSAL,        { Synchronous AM, lower sideband / 同期 AM 下側波帯 }
    rmSAH,        { Synchronous AM, upper sideband / 同期 AM 上側波帯 }
    rmDSB,        { Double sideband, suppressed carrier / 両側波帯 搬送波抑圧 }
    rmFMN,        { Narrow FM (Kenwood TS-990S) / 狭帯域 FM }
    rmPktAM,      { Packet/digital on AM / AM でのパケット }
    rmP25,        { APCO/P25 digital / APCO/P25 デジタル }
    rmDStar,      { D-STAR digital / D-STAR デジタル }
    rmDPMR,       { dPMR digital / dPMR デジタル }
    rmNxdnVN,     { NXDN-VN digital / NXDN-VN デジタル }
    rmNxdnN,      { NXDN-N digital / NXDN-N デジタル }
    rmDCR,        { DCR digital / DCR デジタル }
    rmAMN,        { Narrow AM / 狭帯域 AM }
    rmPSK,        { PSK / PSK }
    rmPSKR,       { PSK reverse / PSK 逆 }
    rmDD,         { DD mode (IC-9700) / DD モード }
    rmC4FM,       { Yaesu C4FM / ヤエス C4FM }
    rmPktFMN,     { Yaesu DATA-FM-N / ヤエス DATA-FM-N }
    rmSpec,       { Unfiltered / 無フィルタ }
    rmCWN,        { Narrow CW (FT-736R) / 狭帯域 CW }
    rmIQ,         { I/Q output / I/Q 出力 }
    rmIsbUSB,     { ISB monitoring USB / ISB USB 監視 }
    rmIsbLSB,     { ISB monitoring LSB / ISB LSB 監視 }

    { --- added in Hamlib 4.6+ / Hamlib 4.6 以降で追加 --- }
    rmUsbD1,      { USB-D1 }
    rmUsbD2,      { USB-D2 }
    rmUsbD3,      { USB-D3 }
    rmLsbD1,      { LSB-D1 }
    rmLsbD2,      { LSB-D2 }
    rmLsbD3,      { LSB-D3 }
    rmWfmS        { Wide FM stereo / 広帯域 FM ステレオ }
  );

  { A set of modes — what a rig reports as "supported".
    モードの集合 — リグが「対応」と報告する内容。 }
  TRigModeSet = set of TRigMode;

  { ====================================================================
    TRigLevel — a rig setting or meter reading, by name.
    TRigLevel - 名前で表したリグの設定値・メータ読み値。
    ====================================================================
    Hamlib carries these as one bit of a 64-bit setting_t plus a value_t
    UNION whose int or float member is the right one depending on the
    level. Both halves of that are things an application must not have
    to know, so both live in THamlibLevelCodec.

    The ones an application reaches for first:
      rlvStrength   the S-meter, in dB relative to S9 (S9 = 0, S7 = -12)
      rlvRfPower    transmit power, 0.0 .. 1.0
      rlvSwr        SWR, read-only
      rlvAf/rlvRf   volume and RF gain, 0.0 .. 1.0
      rlvSql        squelch threshold, 0.0 .. 1.0

    Hamlib はこれらを 64bit setting_t の 1 ビットと、レベルに応じて int と
    float のどちらが正しいかが決まる value_t「共用体」で運びます。どちらも
    アプリケーションが知らされるべきでない事柄なので、両方とも
    THamlibLevelCodec に置いています。

    This list is deliberately not exhaustive: it covers the levels that
    real applications use (checked against WSJT-X, rigctl and grig),
    and a level with no name here can still be reached by its raw bit
    through the diagnostics interface.

    本一覧は意図的に網羅的ではありません。実アプリケーションが使うレベル
    (WSJT-X、rigctl、grig で確認) を対象にしています。ここに名前の無い
    レベルも、診断インターフェース経由で生ビットで到達できます。 }
  TRigLevel = (
    rlvNone,
    rlvPreamp,          { dB, int / dB, int }
    rlvAtt,             { dB, int / dB, int }
    rlvVoxDelay,        { tenths of a second, int / 0.1 秒単位, int }
    rlvAf,              { volume 0..1, float / 音量 }
    rlvRf,              { RF gain 0..1, float / RF ゲイン }
    rlvSql,             { squelch 0..1, float / スケルチ }
    rlvIfShift,         { Hz, int }
    rlvApf,             { audio peak filter 0..1, float }
    rlvNr,              { noise reduction 0..1, float }
    rlvPbtIn,           { float }
    rlvPbtOut,          { float }
    rlvCwPitch,         { Hz, int }
    rlvRfPower,         { TX power 0..1, float / 送信出力 }
    rlvMicGain,         { 0..1, float }
    rlvKeySpeed,        { WPM, int / WPM, int }
    rlvNotchF,          { Hz, int }
    rlvComp,            { 0..1, float }
    rlvAgc,             { int }
    rlvBkInDelay,       { int }
    rlvBalance,         { float }
    rlvMeter,           { int }
    rlvVoxGain,         { 0..1, float }
    rlvAntiVox,         { 0..1, float }
    rlvSlopeLow,        { Hz, int }
    rlvSlopeHigh,       { Hz, int }
    rlvBkInDelayMs,     { ms, int }
    rlvRawStrength,     { raw A/D, int, read-only / 生 A/D 値、読み取り専用 }
    rlvSwr,             { float, read-only / 読み取り専用 }
    rlvAlc,             { float, read-only / 読み取り専用 }
    rlvStrength,        { S-meter, dB relative to S9, int, read-only
                          / S メータ、S9 基準の dB、int、読み取り専用 }
    rlvRfPowerMeter,    { 0..1, float, read-only }
    rlvCompMeter,       { float, read-only }
    rlvVdMeter,         { float, read-only }
    rlvIdMeter,         { float, read-only }
    rlvMonitorGain,     { 0..1, float }
    rlvNb,              { noise blanker level 0..1, float }
    rlvRfPowerMeterWatts { watts, float, read-only / ワット、読み取り専用 }
  );

  TRigLevelSet = set of TRigLevel;

  { ====================================================================
    TRigFunc — an on/off function of the rig.
    TRigFunc - リグのオン・オフ機能。
    ====================================================================
    Same shape as TRigLevel but the value is simply a Boolean. Again a
    chosen subset: the functions that appear in real applications and
    on real front panels.

    TRigLevel と同じ形ですが、値は単なる Boolean です。こちらも選別した
    部分集合で、実アプリケーションと実機のフロントパネルに現れる機能を
    対象にしています。 }
  TRigFunc = (
    rfnNone,
    rfnFastAgc,
    rfnNoiseBlanker,
    rfnCompression,
    rfnVox,
    rfnTone,            { CTCSS encode / CTCSS 送出 }
    rfnToneSql,         { CTCSS decode / CTCSS 検出 }
    rfnSemiBreakIn,
    rfnFullBreakIn,
    rfnAutoNotch,
    rfnNoiseReduction,
    rfnMonitor,
    rfnManualNotch,
    rfnLock,
    rfnMute,
    rfnReverse,         { reverse split / リバーススプリット }
    rfnSquelch,
    rfnRit,
    rfnAfc,
    rfnSatMode,
    rfnTuner,           { antenna tuner / アンテナチューナ }
    rfnXit
  );

  TRigFuncSet = set of TRigFunc;

  { ====================================================================
    TRigVfoOp — a one-shot VFO operation.
    TRigVfoOp - 一回限りの VFO 操作。
    ====================================================================
    WSJT-X uses rvoToggle and rvoCopy to implement split on rigs that
    have no split command of their own ("fake it" mode), which is why
    these are here rather than in a list of conveniences.

    WSJT-X は、独自のスプリットコマンドを持たないリグでスプリットを
    実現するため (いわゆる "fake it" モード) に rvoToggle と rvoCopy を
    使います。これらが「あると便利な機能」ではなくここにある理由です。 }
  TRigVfoOp = (
    rvoNone,
    rvoCopy,            { RIG_OP_CPY   — VFO A -> B / VFO A から B へ複写 }
    rvoExchange,        { RIG_OP_XCHG  — swap A and B / A と B を交換 }
    rvoFromVfo,         { RIG_OP_FROM_VFO — VFO -> memory / VFO からメモリ }
    rvoToVfo,           { RIG_OP_TO_VFO   — memory -> VFO / メモリから VFO }
    rvoMemClear,        { RIG_OP_MCL }
    rvoUp,              { RIG_OP_UP }
    rvoDown,            { RIG_OP_DOWN }
    rvoBandUp,          { RIG_OP_BAND_UP }
    rvoBandDown,        { RIG_OP_BAND_DOWN }
    rvoLeft,            { RIG_OP_LEFT }
    rvoRight,           { RIG_OP_RIGHT }
    rvoTune,            { RIG_OP_TUNE — start the antenna tuner
                          / アンテナチューナ始動 }
    rvoToggle           { RIG_OP_TOGGLE — toggle VFO A/B
                          / VFO A/B のトグル }
  );

  { ====================================================================
    TRigCapabilities — what this rig can actually do.
    TRigCapabilities - このリグが実際にできること。
    ====================================================================
    Read once after Open. An application uses it to disable controls
    the rig cannot honour, which is better than offering a button that
    always returns "function not available on this rig".

    Hamlib exposes only part of struct rig_caps through its public API
    (rig_get_caps_int, five fields), so the level and function masks are
    filled from the rig's own has_get_level / has_set_level when the
    running library offers them, and left empty otherwise. Empty means
    "not known", NOT "the rig supports nothing" — an application should
    treat an empty set as "offer everything and let the rig refuse".

    Open 後に 1 度読みます。アプリケーションはこれを使って、リグが
    応えられない操作のコントロールを無効化します。押すたびに「この機種
    では利用できません」と返るボタンを出すよりましです。

    Hamlib が公開 API 経由で見せる struct rig_caps は一部だけです
    (rig_get_caps_int の 5 フィールド)。そのためレベル・ファンクションの
    マスクは、実行中のライブラリが提供する場合に限りリグ自身の
    has_get_level / has_set_level から埋め、それ以外は空のままにします。
    空は「不明」であって「リグが何も対応していない」ではありません。
    アプリケーションは空集合を「全部提示してリグに断らせる」と解釈して
    ください。 }
  TRigCapabilities = record
    Known:            Boolean;    { False when the library could not answer
                                    / ライブラリが答えられなかったとき False }
    TargetableVfo:    Boolean;    { can address a VFO without selecting it
                                    / VFO を選択せずに指定できる }
    { The MODEL's default PTT type from struct rig_caps, NOT the type in
      force for this connection. Hamlib's rig_get_caps_int reads the
      static capability table, so a ptt_type conf token the application
      passed does not change it — measured: ptt_type stays 0 for the
      dummy rig after AddConfToken('ptt_type', 'RIG').

      HasPtt therefore means "this rig can key, as configured": it is
      True when the model's own caps say so OR when the application
      supplied a ptt_type conf token naming a real line. That is the
      question a UI is actually asking when it decides whether to enable
      a TX button.

      struct rig_caps 由来の「機種既定」の PTT 種別であり、この接続で
      有効な種別ではありません。Hamlib の rig_get_caps_int は静的な能力
      表を読むため、アプリケーションが渡した ptt_type の設定トークンでは
      変化しません (実測: ダミーリグで AddConfToken('ptt_type','RIG')
      後も ptt_type は 0 のまま)。

      したがって HasPtt は「設定された状態でこのリグが送信できるか」を
      意味します。機種自身の caps がそう言っているか、またはアプリが
      実在の線を指す ptt_type トークンを与えた場合に True です。TX
      ボタンを有効にするか決めるとき UI が実際に問うているのはこちら
      です。 }
    PttType:          Integer;    { Hamlib ptt_type_t; 0 = RIG_PTT_NONE }
    HasPtt:           Boolean;
    GetLevels:        TRigLevelSet;
    SetLevels:        TRigLevelSet;
    GetFuncs:         TRigFuncSet;
    SetFuncs:         TRigFuncSet;
    VfoOps:           set of TRigVfoOp;
  end;

  { ====================================================================
    TRigErrorKind — what went wrong, as a decidable value.
    TRigErrorKind - 何が起きたかを判定可能な値として表現。
    ====================================================================
    Hamlib returns negated enum ordinals (-5 for a timeout, -6 for I/O).
    An application that branches on those numbers has hard-coded another
    project's enum ordering; worse, the sign convention invites the
    mistake of comparing against the positive RIG_E* value. This enum
    removes both hazards. The original number stays available as
    NativeCode for logs and bug reports.

    Hamlib は enum の序数を符号反転して返します (タイムアウトは -5、
    I/O エラーは -6)。その数値で分岐するアプリケーションは、他プロジェクト
    の enum の並び順をハードコードしていることになります。さらに符号の
    慣習が「正の RIG_E* と比較する」という誤りを誘発します。本列挙型は
    その両方を取り除きます。元の数値はログやバグ報告のために NativeCode
    として残ります。 }
  TRigErrorKind = (
    rekNone,              { No error / エラーなし }
    rekInvalidArgument,   { RIG_EINVAL / 無効な引数 }
    rekConfiguration,     { RIG_ECONF / 設定が不正 }
    rekOutOfMemory,       { RIG_ENOMEM / メモリ不足 }
    rekNotImplemented,    { RIG_ENIMPL / 未実装 }
    rekTimeout,           { RIG_ETIMEOUT / 通信タイムアウト }
    rekIo,                { RIG_EIO - includes "port could not be opened"
                            / I/O エラー (ポートを開けない場合を含む) }
    rekInternal,          { RIG_EINTERNAL / Hamlib 内部エラー }
    rekProtocol,          { RIG_EPROTO / プロトコルエラー }
    rekRigRejected,       { RIG_ERJCTED - the rig refused the command
                            / リグがコマンドを拒否 }
    rekTruncated,         { RIG_ETRUNC / 引数が切り詰められた }
    rekNotAvailable,      { RIG_ENAVAIL - this rig lacks the function
                            / この機種に当該機能が無い }
    rekVfoNotTargetable,  { RIG_ENTARGET / VFO を直接指定できない }
    rekBusError,          { RIG_BUSERROR / バス通信エラー }
    rekBusBusy,           { RIG_BUSBUSY / バス衝突 }
    rekInvalidHandle,     { RIG_EARG / NULL ハンドル等 }
    rekInvalidVfo,        { RIG_EVFO / 無効な VFO }
    rekOutOfDomain,       { RIG_EDOM / 引数が定義域外 }
    rekDeprecated,        { RIG_EDEPRECATED / 非推奨の関数 }
    rekSecurity,          { RIG_ESECURITY / セキュリティエラー }
    rekPowerOff,          { RIG_EPOWER - the rig is not powered on
                            / リグの電源が入っていない }
    rekLimitExceeded,     { RIG_ELIMIT / 上限超過 }
    rekAccessDenied,      { RIG_EACCESS - e.g. the port is already in use
                            / アクセス拒否 (例: ポート使用中) }
    rekUnrecognised,      { A code this binding has no name for; see
                            NativeCode. A newer Hamlib may add codes.
                            / 本バインディングに名前が無いコード。
                              NativeCode を参照。新しい Hamlib は
                              コードを追加し得ます。 }

    { ----------------------------------------------------------------
      Conditions this component raises itself. They have no Hamlib
      return code, so NativeCode is 0 for all three. Keeping them in the
      same enum means an application has exactly one thing to switch on;
      inventing plausible-looking Hamlib codes for them (the previous
      design reported "-1" for a tripped breaker) would have been a lie
      about where the failure came from.

      本コンポーネント自身が発生させる状態です。対応する Hamlib 戻り値が
      無いため、3 つとも NativeCode は 0 です。同じ列挙型に入れることで
      アプリケーションが分岐する対象は 1 つだけになります。これらに
      もっともらしい Hamlib コードを捏造すること (旧設計では遮断を "-1"
      として報告していました) は、障害の出所についての虚偽になります。
      ---------------------------------------------------------------- }
    rekConnectFailed,     { Open could not establish a connection
                            / Open が接続を確立できなかった }
    rekCircuitOpen,       { Circuit Breaker refused the command
                            / Circuit Breaker がコマンドを拒否した }
    rekNotConnected,      { No live handle: rig off, cable out, port taken
                            / 有効なハンドルが無い (電源オフ、ケーブル
                              抜け、ポート占有) }
    rekComponentFault     { An exception inside this component, not a
                            Hamlib return code. Report these as bugs.
                            / Hamlib の戻り値ではなく、本コンポーネント
                              内部の例外。バグとして報告してください。 }
  );

  { ====================================================================
    TRigModelInfo — one entry of the rig catalogue.
    TRigModelInfo - リグカタログの 1 項目。
    ====================================================================
    Obtained from the loaded library at run time (see IRigModelCatalog),
    never hard-coded. ModelNumber is the value Open expects; the two
    name fields are what a user should see in a combo box.

    ロードされたライブラリから実行時に取得します (IRigModelCatalog 参照)。
    ハードコードはしません。ModelNumber は Open が期待する値、2 つの
    名前フィールドはコンボボックスでユーザに見せる内容です。 }
  TRigModelInfo = record
    ModelNumber:  Integer;   { value to pass to Open / Open に渡す値 }
    Manufacturer: string;    { e.g. "Icom" / 例: "Icom" }
    ModelName:    string;    { e.g. "IC-7300" / 例: "IC-7300" }
    BackendStatus: string;   { Hamlib's own maturity label: Alpha, Beta,
                               Stable, Untested
                               / Hamlib 自身の成熟度ラベル }
  end;

  TRigModelInfoArray = array of TRigModelInfo;

  { ====================================================================
    Result records — all callbacks receive these as value-type parameters.
    結果レコード — すべてのコールバックは値型パラメータとして受け取ります。
    Value-type design eliminates Use-After-Free even after Service is freed.
    値型設計により Service 破棄後でも Use-After-Free が起きません。
    ==================================================================== }

  { Generic result for "set" operations and errors.
    「set」系操作とエラー用の汎用結果。 }
  TRigResult = record
    Status:     TRigCommandStatus;
    Error:      TRigErrorKind;    { Branch on this, not on NativeCode
                                    / 分岐はこちらで行う (NativeCode ではなく) }
    NativeCode: Integer;          { Raw negated Hamlib code, 0 if success.
                                    For logs and bug reports only.
                                    / 生の負の Hamlib コード、成功時 0。
                                      ログとバグ報告のためだけに使う。 }
    ErrorMsg:   string;           { Human-readable error message
                                    / 人間可読のエラーメッセージ }
  end;

  { Result for frequency get operations.
    周波数取得操作の結果。 }
  TRigFreqResult = record
    Status:     TRigCommandStatus;
    Freq:       Double;          { Frequency in Hz / 周波数 [Hz] }
    Error:      TRigErrorKind;   { Branch on this / 分岐はこちら }
    NativeCode: Integer;         { Raw Hamlib code, diagnostics only
                                   / 生の Hamlib コード、診断用のみ }
    ErrorMsg:   string;
  end;

  { Result for mode get operations.
    モード取得操作の結果。 }
  TRigModeResult = record
    Status:     TRigCommandStatus;
    Mode:       TRigMode;        { Named mode; rmUnknown if unrecognised
                                   / 名前付きモード。未知なら rmUnknown }
    Passband:   Integer;         { Passband width in Hz, 0 = rig default
                                   / 通過帯域幅 [Hz]、0 = リグ既定 }
    RawMode:    Int64;           { The rmode_t value as reported, kept so a
                                   newer mode is never simply lost
                                   / 報告された rmode_t 値。新しいモードが
                                     単に失われないよう保持する }
    Error:      TRigErrorKind;   { Branch on this / 分岐はこちら }
    NativeCode: Integer;         { Raw Hamlib code, diagnostics only
                                   / 生の Hamlib コード、診断用のみ }
    ErrorMsg:   string;
  end;

  { Result for PTT state get operations. Deliberately minimal: a PTT
    query either answers or does not, and Status already says which.
    PTT 状態取得操作の結果。意図的に最小構成です。PTT 問い合わせは
    答えるか答えないかのいずれかで、Status がそれを示します。 }
  TRigPttResult = record
    Status: TRigCommandStatus;
    Active: Boolean;             { True if transmitting / 送信中なら True }
  end;

  { ====================================================================
    Results for the operations added in Rev.6.0.
    Rev.6.0 で追加した操作の結果。
    ==================================================================== }

  { A level reading. Levels are int or float depending on which level
    was asked for; both are filled, so an application that knows it
    asked for the S-meter can read IntValue without a conversion and
    one that just wants to draw a bar can read FloatValue.

    レベルの読み値。レベルによって int か float かが決まりますが両方を
    埋めます。S メータを要求したと分かっているアプリは変換なしで
    IntValue を読め、バーを描きたいだけのアプリは FloatValue を読めます。 }
  TRigLevelResult = record
    Status:     TRigCommandStatus;
    Level:      TRigLevel;
    IsFloat:    Boolean;         { which member Hamlib filled
                                   / Hamlib が埋めたメンバ }
    FloatValue: Double;
    IntValue:   Integer;
    Error:      TRigErrorKind;
    NativeCode: Integer;
    ErrorMsg:   string;
  end;

  { An on/off function reading. オン・オフ機能の読み値。 }
  TRigFuncResult = record
    Status:     TRigCommandStatus;
    Func:       TRigFunc;
    Active:     Boolean;
    Error:      TRigErrorKind;
    NativeCode: Integer;
    ErrorMsg:   string;
  end;

  { Split state: whether the rig is in split, and which VFO transmits.
    スプリット状態。スプリット中か否かと、送信に使う VFO。 }
  TRigSplitResult = record
    Status:     TRigCommandStatus;
    SplitOn:    Boolean;
    TxVfo:      TRigVfo;
    TxFreq:     Double;          { 0 when not read / 未取得時は 0 }
    Error:      TRigErrorKind;
    NativeCode: Integer;
    ErrorMsg:   string;
  end;

  { The currently selected VFO.

    Do not compare Vfo to what you asked for with "=". Measured against
    real Hamlib 4.5.5: after rig_set_vfo(RIG_VFO_B) the library answers
    RIG_VFO_SUB, and after RIG_VFO_A it answers RIG_VFO_MAIN. Hamlib
    normalises the pair, so the honest report is what the rig said, and
    RigVfoSelectionMatches in HamlibVfoCodec is how to ask "did my
    selection take effect?".

    現在選択されている VFO。

    要求した VFO と "=" で比較しないでください。実 Hamlib 4.5.5 で実測:
    rig_set_vfo(RIG_VFO_B) の後、ライブラリは RIG_VFO_SUB と答え、
    RIG_VFO_A の後は RIG_VFO_MAIN と答えます。Hamlib が対を正規化する
    ためで、正直な報告はリグが言ったとおりの値です。「選択が効いたか」を
    尋ねるには HamlibVfoCodec の RigVfoSelectionMatches を使います。 }
  TRigVfoResult = record
    Status:     TRigCommandStatus;
    Vfo:        TRigVfo;
    RawVfo:     Integer;         { the vfo_t as reported, kept for the
                                   same reason as TRigModeResult.RawMode
                                   / 報告された vfo_t。TRigModeResult の
                                     RawMode と同じ理由で保持 }
    Error:      TRigErrorKind;
    NativeCode: Integer;
    ErrorMsg:   string;
  end;


  { ====================================================================
    Callback procedure types
    コールバック手続き型
    ====================================================================
    All callbacks are invoked on the UI thread via TThread.Queue.
    Application code may freely access UI controls in callbacks.
    すべてのコールバックは TThread.Queue により UI スレッドから呼ばれます。
    アプリケーションコードはコールバック内で UI コントロールに自由にアクセスできます。 }

  TRigCommandCallback = procedure(const AResult: TRigResult)      of object;
  TRigFreqCallback    = procedure(const AResult: TRigFreqResult)  of object;
  TRigModeCallback    = procedure(const AResult: TRigModeResult)  of object;
  TRigPttCallback     = procedure(const AResult: TRigPttResult)   of object;
  TRigLevelCallback   = procedure(const AResult: TRigLevelResult) of object;
  TRigFuncCallback    = procedure(const AResult: TRigFuncResult)  of object;
  TRigSplitCallback   = procedure(const AResult: TRigSplitResult) of object;
  TRigVfoCallback     = procedure(const AResult: TRigVfoResult)   of object;

  { Event handlers (Push model) — also invoked on the UI thread.
    イベントハンドラ (Push モデル) — UI スレッドから呼ばれます。 }
  TRigFreqChangedEvent = procedure(Sender: TObject; AFreq: Double)         of object;
  TRigConnectEvent     = procedure(Sender: TObject; AConnected: Boolean)    of object;
  { AKind is what application logic should switch on; ANativeCode is the
    raw Hamlib number, carried for logs.
    分岐に使うのは AKind です。ANativeCode は生の Hamlib 数値で、
    ログのために同行します。 }
  TRigErrorEvent       = procedure(Sender: TObject; AKind: TRigErrorKind;
                                   ANativeCode: Integer;
                                   const AMsg: string)                       of object;

  { ====================================================================
    ICancellationToken — RAII-style cancellation handle
    ICancellationToken - RAII 形式のキャンセルハンドル
    ====================================================================
    Returned from every async API. Caller may keep it for individual
    cancellation, or simply discard it (CancelAllPending in Service.Destroy
    handles cleanup). Reference-counted lifetime.
    各非同期 API の戻り値です。呼び出し元は個別キャンセルのために保持しても
    よく、破棄してもよい (Service.Destroy 内の CancelAllPending が後始末)。
    参照カウントで生存期間を管理します。 }
  { A thing a queued delivery must keep alive until it has run.

    The component's rule is that anything a TThread.Queue entry will
    touch must either outlive every possible delivery or be held by
    reference count — a raw method pointer gives neither. IRigStateHolder
    was already held this way by the dispatch objects; this interface
    generalises that so the poller's result handler can be too.

    It carries no methods on purpose. Its whole job is to be referenced.

    キューに積まれた配送が、実行されるまで生かしておかねばならないもの。

    本コンポーネントの規則は、TThread.Queue の項目が触れるものはすべて、
    あらゆる配送より長生きするか、参照カウントで保持されるかのいずれかで
    なければならない、というものです。生のメソッドポインタはそのどちらも
    与えません。IRigStateHolder は既に配送オブジェクトがこの形で保持して
    いました。本インターフェースはそれを一般化し、ポーラの結果ハンドラも
    同じ形で保持できるようにします。

    メソッドを持たないのは意図的です。参照されることだけが役割です。 }
  IRigDeliveryKeepAlive = interface
    ['{7B5C1E49-0A62-4D38-9F17-6E3C84B20D5A}']
  end;

  ICancellationToken = interface
    ['{B1A2C3D4-1122-3344-5566-778899AABBCC}']

    { Cancel the associated command. If already executing, the result will
      arrive as rcsCancelled. Safe to call multiple times.
      関連コマンドをキャンセルします。すでに実行中の場合は結果が
      rcsCancelled で届きます。複数回呼び出しても安全です。 }
    procedure Cancel;

    { Returns True after Cancel has been called.
      Cancel が呼ばれた後 True を返します。 }
    function IsCancelled: Boolean;
  end;

  { ====================================================================
    TRigState — atomic state snapshot (Pull model)
    TRigState - アトミックな状態スナップショット (Pull モデル)
    ====================================================================
    Updated by the internal poller thread. Read via IRigService.CurrentState
    using a critical section, so application code may read it from any thread
    safely. Timestamp = 0 means "no data has been collected yet".
    内部ポーラースレッドが更新します。IRigService.CurrentState から
    クリティカルセクション経由で読み出すため、任意のスレッドから安全に
    読めます。Timestamp = 0 は「まだデータ未収集」を意味します。 }
  TRigState = record
    Connected:  Boolean;

    { The frequency of whichever VFO the rig currently has selected.
      This is what the poller fills, because polling asks the rig for
      "the frequency" (RIG_VFO_CURR) and the rig answers for the VFO
      it has selected — which the operator can change from the rig's
      own front panel at any moment.

      Up to Rev.5.1 this value was filed in VfoAFreq, on the
      assumption that the selected VFO is VFO A. That assumption holds
      for a single-VFO panel and fails the moment split operation is
      used: with VFO B selected, the snapshot reported VFO B's
      frequency as VFO A's, so an application displaying "VFO A"
      showed the frequency it was transmitting on while claiming it
      was the one it was listening to. The second sample application
      is what surfaced this; see REV6_REPORT.md.

      リグが現在選択している VFO の周波数。ポーラが埋めるのはこの値
      です。ポーリングはリグに「周波数」(RIG_VFO_CURR) を尋ね、リグは
      自身が選択している VFO について答えるからです。そしてその選択は、
      オペレータがリグ本体の操作でいつでも変えられます。

      Rev.5.1 まで、この値は「選択中の VFO は VFO A である」という前提
      のもとに VfoAFreq へ格納していました。この前提は単一 VFO の
      パネルでは成り立ち、スプリット運用を使った瞬間に破綻します。
      VFO B を選択していると、スナップショットは VFO B の周波数を
      VFO A のものとして報告し、「VFO A」を表示するアプリケーションは
      送信周波数を受信周波数と偽って表示していました。これを表面化
      させたのは 2 つ目のサンプルアプリケーションです
      (REV6_REPORT.md 参照)。 }
    CurrentFreq: Double;         { Hz, 0 = not yet acquired / Hz、0 = 未取得 }

    { These two are filled ONLY by a read that named the VFO
      explicitly — GetFrequencyAsync(rvfoA) or (rvfoB). Polling never
      writes them, because polling does not know which VFO it got.
      0 therefore means "nobody has asked for that VFO", which is not
      the same as "that VFO is unused".

      この 2 つは、VFO を明示した読み取り
      — GetFrequencyAsync(rvfoA) または (rvfoB) — によってのみ埋まり
      ます。ポーリングは書きません。どの VFO の値かを知らないから
      です。したがって 0 は「誰もその VFO を尋ねていない」であり、
      「その VFO は使われていない」ではありません。 }
    VfoAFreq:   Double;          { Hz, 0 = not asked / Hz、0 = 未問い合わせ }
    VfoBFreq:   Double;          { Hz, 0 = not asked / Hz、0 = 未問い合わせ }
    Mode:       TRigMode;        { Named mode / 名前付きモード }
    Passband:   Integer;         { Hz, 0 = rig default / Hz、0 = リグ既定 }
    RawMode:    Int64;           { rmode_t as reported / 報告された rmode_t }
    PttActive:  Boolean;
    SplitOn:    Boolean;
    TxVfo:      TRigVfo;         { which VFO transmits in split
                                   / スプリット時に送信する VFO }
    TxFreq:     Double;          { Hz, 0 = not acquired / Hz、0 = 未取得 }
    { The rig's selected VFO, as last reported by GetVfoAsync. The
      poller does not refresh it: asking rig_get_vfo on every poll
      would double the traffic on a serial link for a value that
      changes rarely. rvfoCurr means "not asked yet" — it is the one
      value that names no particular VFO, so it cannot be mistaken for
      an answer.

      リグの選択中 VFO。最後に GetVfoAsync が報告した値です。ポーラは
      更新しません。めったに変わらない値のために、ポーリングのたび
      rig_get_vfo を呼べばシリアル回線の通信量が倍になるからです。
      rvfoCurr は「まだ尋ねていない」を意味します。特定の VFO を指さ
      ない唯一の値なので、答えと取り違えられません。 }
    SelectedVfo: TRigVfo;

    { S-meter in dB relative to S9: 0 = S9, -54 = S0, +20 = S9+20dB.
      HasStrength says whether a reading has arrived; without it a
      display cannot tell "S9" from "never polled".

      S9 基準の dB による S メータ。0 = S9、-54 = S0、+20 = S9+20dB。
      HasStrength は読み値が届いたかを示します。これが無いと表示側は
      「S9」と「一度も取得していない」を区別できません。 }
    StrengthDb:   Integer;
    HasStrength:  Boolean;
    Timestamp:  QWord;           { GetTickCount64 value, 0 = never updated
                                   / GetTickCount64 の値、0 = 一度も更新なし }
  end;

  { ====================================================================
    TRigTimeoutPolicy — hardware-specific timeout configuration
    TRigTimeoutPolicy - ハードウェア固有のタイムアウト設定
    ====================================================================
    Captures all timing-related parameters that vary per rig family.
    Use predefined profiles (RigPolicy_FastUsb, RigPolicy_SlowCat etc.) or
    construct your own. Apply at runtime via IRigService.ApplyTimeoutPolicy.
    機種ごとに異なるタイミング関連パラメータをまとめます。定義済みプロファイル
    (RigPolicy_FastUsb / RigPolicy_SlowCat 等) を使うか自作してください。
    IRigService.ApplyTimeoutPolicy でランタイム適用できます。 }

  { Circuit Breaker strategy: fixed threshold or adaptive failure rate.
    Circuit Breaker 戦略: 固定閾値または適応的失敗率。 }
  TCircuitBreakerStrategy = (
    cbsFixed,       { Open after N consecutive failures
                      / N 回連続失敗で開く }
    cbsAdaptive     { Open when failure rate exceeds threshold over a window
                      / ウィンドウ内の失敗率が閾値を超えたら開く }
  );

  TRigTimeoutPolicy = record
    CommandTimeoutMs:       Cardinal;  { Per-command timeout / コマンドごとのタイムアウト }
    ConnectTimeoutMs:       Cardinal;  { Connection timeout / 接続タイムアウト }

    CbStrategy:             TCircuitBreakerStrategy;
    CbFixedThreshold:       Integer;   { For cbsFixed: consecutive failures
                                         / cbsFixed 用: 連続失敗回数 }
    CbAdaptiveWindowSize:   Integer;   { For cbsAdaptive: window size in commands
                                         / cbsAdaptive 用: ウィンドウサイズ (コマンド数) }
    CbAdaptiveFailureRate:  Double;    { For cbsAdaptive: 0.0..1.0
                                         / cbsAdaptive 用: 0.0〜1.0 }
    CbRecoveryMs:           Cardinal;  { Time before half-open retry
                                         / Half-Open 試行までの時間 }

    PollIntervalMs:         Cardinal;  { Poller interval / ポーラー間隔 }
    FreqChangeThresholdHz:  Double;    { Min change to fire FreqChanged event
                                         / FreqChanged 発火の最小変化量 }
  end;

  { ====================================================================
    Library and model verification (forward compatibility)
    ライブラリとモデルの検証（上位互換）
    ====================================================================
    Resolving every symbol does not prove the ABI matches. These types let
    the component state which Hamlib range it was verified against, report
    what it actually loaded, and let the application decide the policy.

    全シンボルが解決できても ABI が一致している証明にはなりません。これらの型
    により、コンポーネントは「検証済み範囲」を宣言し、実際にロードしたものを
    報告し、方針の決定はアプリケーションに委ねます。 }

  TRigVersionVerdict = (
    rvvVerified,   { Inside the verified range / 検証済み範囲内 }
    rvvUntested,   { Readable version, outside the range
                     / バージョンは読めたが範囲外 }
    rvvUnknown     { Version could not be determined at all
                     / バージョンを特定できなかった }
  );

  { What the component actually loaded and connected to. Read via
    IRigService.LibraryStatus; useful in an about box, a log header, and a
    bug report.

    コンポーネントが実際にロード・接続した対象。IRigService.LibraryStatus で
    読み出します。バージョン情報画面、ログヘッダ、不具合報告に有用です。 }
  TRigLibraryStatus = record
    LibPath:         string;              { Resolved library path / 解決されたパス }
    VersionText:     string;              { rig_version() verbatim / rig_version() の原文 }
    ApiMajor:        Integer;
    ApiMinor:        Integer;
    Verdict:         TRigVersionVerdict;
    SupportedRange:  string;              { e.g. '4.5 .. 4.7' }

    { True when the library was found through a candidate that carries no
      soname / version in its file name (libhamlib.so, hamlib.dll). Such a
      name may resolve to a different ABI after the next system upgrade.

      ファイル名に soname / バージョンを含まない候補 (libhamlib.so,
      hamlib.dll) 経由で見つかった場合 True。次のシステム更新で別の ABI に
      解決され得る名前です。 }
    UnversionedBinding: Boolean;

    { Filled by Open when the loaded Hamlib can be queried for model info.
      ロードした Hamlib にモデル情報を問い合わせられた場合に Open が埋めます。 }
    ModelNumber:     Integer;
    ModelMfg:        string;
    ModelName:       string;
    ModelValidated:  Boolean;
  end;

  { Non-fatal compatibility warning. Fired on the UI thread.
    致命的でない互換性警告。UI スレッドで発火します。 }
  TRigLibraryWarningEvent = procedure(Sender: TObject;
                                      const AStatus: TRigLibraryStatus;
                                      const AMessage: string) of object;

  { ====================================================================
    IHamlibLoader — abstraction over the Hamlib dynamic library
    IHamlibLoader - Hamlib 動的ライブラリの抽象化
    ====================================================================
    Application code does NOT typically use this interface directly;
    it is consumed by TRigService internally. Test code may implement
    a fake loader (TFakeHamlibLoader) to test the entire stack
    without an actual Hamlib library.
    アプリケーションコードは通常このインターフェースを直接使いません。
    TRigService が内部で利用します。テストコードでは Fake ローダ
    (TFakeHamlibLoader) を実装して、実際の Hamlib ライブラリなしで
    全層をテストできます。 }
  IHamlibLoader = interface
    ['{C3A1B2D4-E5F6-4890-ABCD-EF0123456789}']

    { Load the Hamlib library. Returns True on success.
      If APath is empty, the loader searches platform-specific candidates.
      Hamlib ライブラリをロードします。成功時 True。
      APath が空文字の場合、プラットフォーム別の候補を探索します。 }
    function  Load(const APath: string = ''): Boolean;

    { Unload the library. Safe to call multiple times.
      ライブラリをアンロードします。複数回呼んでも安全です。 }
    procedure Unload;

    { Status accessors. ステータスアクセサ。 }
    function  GetIsLoaded: Boolean;
    function  GetApiMajor: Integer;
    function  GetApiMinor: Integer;
    function  GetLibPath:  string;

    { Check whether a specific Hamlib API symbol was resolved.
      Use this to detect whether the loaded version supports a feature.
      特定の Hamlib API シンボルが解決されたかを確認します。
      ロードされたバージョンが特定機能をサポートするかの検出に使います。 }
    function  HasSymbol(const AName: string): Boolean;

    { ----------------------------------------------------------------
      Function pointer wrappers — called from L3 (Worker thread only).
      関数ポインタラッパー — L3 (Worker スレッド) からのみ呼び出されます。
      ---------------------------------------------------------------- }

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
    { Set any Hamlib configuration token by name (see src/conf.c and
      src/serial_cfg_params.h for the full list). Returns the Hamlib
      return code, or RIG_OK when the running library predates
      rig_set_conf / rig_token_lookup.

      Hamlib の設定トークンを名前で設定します (一覧は src/conf.c と
      src/serial_cfg_params.h)。Hamlib の戻り値を返します。実行中の
      ライブラリに rig_set_conf / rig_token_lookup が無い場合は RIG_OK。 }
    function  SetConf(ARig: Pointer; const AName, AValue: string): Integer;

    function  SetSerialPort(ARig: Pointer; const APort: string): Integer;
    function  SetSerialBaud(ARig: Pointer; ABaud: Integer): Integer;

    property IsLoaded: Boolean read GetIsLoaded;
    property ApiMajor: Integer read GetApiMajor;
    property ApiMinor: Integer read GetApiMinor;
    property LibPath:  string  read GetLibPath;
  end;

  { ====================================================================
    IHamlibDiagnostics — optional role interface on the loader
    IHamlibDiagnostics - ローダの任意 role interface
    ====================================================================
    Deliberately NOT part of IHamlibLoader. IHamlibLoader already has 21
    methods, and every addition to it forces every test fake to be
    rewritten — adding one method in Rev.4.2 broke four test files. These
    verification concerns have a different set of callers (the factory and
    Open, not the command classes), so they get their own narrow contract.

    意図的に IHamlibLoader には入れていません。IHamlibLoader はすでに 21
    メソッドあり、1 本追加するたびに全テストフェイクの書き換えを強制します
    (Rev.4.2 で 1 本足してテスト 4 ファイルが壊れました)。これらの検証用の
    関心事は呼び出し側の集合が異なる (ファクトリと Open であり、コマンド
    クラスではない) ため、独立した細い契約に分けます。

    A loader that does not implement this interface simply skips
    verification: Supports() returns False and the component degrades to
    Rev.4.2 behaviour. Test fakes therefore need no changes.

    本インターフェースを実装しないローダは検証を省略します。Supports() が
    False を返し、コンポーネントは Rev.4.2 相当の挙動に退行します。
    したがってテストフェイクの変更は不要です。 }
  IHamlibDiagnostics = interface
    ['{5E9C7A21-3F48-4D6B-8A05-1C7B9E42D830}']

    { rig_version() verbatim, or '' when unavailable.
      rig_version() の原文。取得不能なら ''。 }
    function GetVersionText: string;

    { Compare the loaded version against the verified range.
      ロードしたバージョンを検証済み範囲と照合します。 }
    function GetVersionVerdict: TRigVersionVerdict;

    { Human-readable verified range, e.g. '4.5 .. 4.7'.
      人間可読の検証済み範囲。例: '4.5 .. 4.7'。 }
    function GetSupportedRangeText: string;

    { True when bound through a file name without soname / version.
      soname / バージョンを含まないファイル名経由でバインドした場合 True。 }
    function GetUnversionedBinding: Boolean;

    { Ask the loaded Hamlib whether it knows this model, and what it calls
      it. Returns False when the model is unknown OR when the running
      library is too old to answer; AAnswered distinguishes the two so a
      missing API is never reported as a bad model number.

      ロードした Hamlib がこのモデルを知っているか、何と呼んでいるかを
      問い合わせます。モデルが未知の場合と、実行中のライブラリが古くて
      回答できない場合の双方で False を返します。AAnswered が両者を区別し、
      API 欠落を「不正なモデル番号」と誤報しないようにします。 }
    function CheckModel(AModel: Integer;
                        out AMfg, AModelName: string;
                        out AAnswered: Boolean): Boolean;
  end;

  { ====================================================================
    IHamlibCatalog — optional role interface: enumerate the backends
    IHamlibCatalog - 任意 role interface: バックエンドの列挙
    ====================================================================
    Like IHamlibDiagnostics, kept out of IHamlibLoader so that adding
    enumeration breaks no existing fake. The loader implements it by
    calling rig_load_all_backends + rig_list_foreach_model +
    rig_get_caps_cptr; a library missing any of those makes ListModels
    return False, and the component carries on without a catalogue.

    IHamlibDiagnostics と同様、既存フェイクを壊さないよう IHamlibLoader
    には入れません。ローダは rig_load_all_backends +
    rig_list_foreach_model + rig_get_caps_cptr で実装します。いずれかを
    欠くライブラリでは ListModels が False を返し、コンポーネントは
    カタログ無しで動作を続けます。 }
  IHamlibCatalog = interface
    ['{7C4D8E13-6A2B-4F59-9D80-3E5A1B6C7D42}']

    { Enumerate every model the loaded library can drive. Returns False
      when the running Hamlib lacks the enumeration API; AList is then
      empty. Takes tens of milliseconds, because it forces every backend
      to be loaded — call it once and keep the result.

      ロードされたライブラリが扱える全機種を列挙します。実行中の Hamlib
      に列挙 API が無い場合は False を返し、AList は空になります。全
      バックエンドのロードを強制するため数十ミリ秒かかります。1 回だけ
      呼び、結果を保持してください。 }
    function ListModels(out AList: TRigModelInfoArray): Boolean;
  end;

  { ====================================================================
    IHamlibRigControl — optional role interface: everything past
    frequency, mode and PTT.
    IHamlibRigControl - 任意 role interface: 周波数・モード・PTT から
    先のすべて。
    ====================================================================
    The third role interface, and for the same reason as the first two:
    IHamlibLoader has 22 methods and every addition to it rewrites every
    test fake in the project. Twelve more would have rewritten six of
    them.

    A loader that does not implement this interface simply cannot do
    these operations, and the commands report rekNotAvailable — which is
    also the honest answer for a Hamlib build that does not export the
    symbols.

    3 つ目の role interface です。理由は最初の 2 つと同じで、
    IHamlibLoader は 22 メソッドあり、1 本追加するたびにプロジェクト内の
    全テストフェイクを書き換えることになります。12 本追加すれば 6 個の
    フェイクを書き換えることになっていました。

    本インターフェースを実装しないローダはこれらの操作ができず、コマンドは
    rekNotAvailable を報告します。シンボルを公開していない Hamlib ビルドに
    対しても、それが正直な答えです。 }
  IHamlibRigControl = interface
    ['{4A7E2D96-1C83-4B50-9E6F-2D8A5C140B73}']

    { Each returns the Hamlib code, or -RIG_ENAVAIL (-11) when the
      running library does not export that symbol.
      各メソッドは Hamlib の戻り値を返します。実行中のライブラリが当該
      シンボルを公開していない場合は -RIG_ENAVAIL (-11) です。 }
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

    { The value_t union is resolved here: the caller says which member
      it means, and the loader does the rest.
      value_t 共用体はここで解決します。呼び出し側がどのメンバを意味
      するかを伝え、残りはローダが行います。 }
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

    { Capability query. Returns False when the library cannot answer.
      能力問い合わせ。ライブラリが答えられない場合 False。 }
    function QueryCapabilities(AModel: Integer;
                               out ACaps: TRigCapabilities): Boolean;
  end;

  { ====================================================================
    IRigModelCatalog — the rig list, for the application's UI
    IRigModelCatalog - アプリの UI 向けリグ一覧
    ====================================================================
    Replaces hard-coded RIG_MODEL_* constants. Build one from the
    factory, bind it to a combo box, and pass the selected entry's
    ModelNumber to Open. Because the list comes from the library that
    will actually drive the rig, a Hamlib upgrade adds new rigs to the
    application without recompiling it.

    ハードコードされた RIG_MODEL_* 定数を置き換えます。ファクトリから
    生成してコンボボックスに流し込み、選択項目の ModelNumber を Open に
    渡してください。一覧は実際にリグを動かすライブラリ自身から来るため、
    Hamlib を更新すればアプリを再コンパイルせずに新機種が増えます。

    Reference-counted; hold it as an IRigModelCatalog field and it is
    released automatically.
    参照カウント管理です。IRigModelCatalog 型のフィールドで保持すれば
    自動的に解放されます。 }
  IRigModelCatalog = interface
    ['{2B6F9A04-8D71-4C3E-A52F-9B8C0D1E2F35}']

    { False when the loaded library could not be enumerated. Every other
      method then behaves as an empty list.
      ロードされたライブラリを列挙できなかった場合 False。その場合、
      他のメソッドは空リストとして振る舞います。 }
    function GetIsAvailable: Boolean;

    { Number of models, sorted by manufacturer then model name.
      機種数。メーカー名→機種名の順にソートされています。 }
    function GetCount: Integer;

    { Entry by index. AIndex outside 0..Count-1 raises EArgumentException.
      添字による項目取得。0..Count-1 の範囲外は EArgumentException。 }
    function GetItem(AIndex: Integer): TRigModelInfo;

    { Look up by the number Open takes. False when not present.
      Open が取る番号で検索します。存在しなければ False。 }
    function FindByNumber(AModelNumber: Integer;
                          out AInfo: TRigModelInfo): Boolean;

    { Look up by names, case-insensitively — useful for restoring a
      saved setting without storing a number that a Hamlib upgrade might
      reassign.
      名前で大文字小文字を無視して検索します。保存済み設定の復元に有用
      です。Hamlib の更新で再割り当てされ得る番号を保存せずに済みます。 }
    function FindByName(const AManufacturer, AModelName: string;
                        out AInfo: TRigModelInfo): Boolean;

    property IsAvailable: Boolean read GetIsAvailable;
    property Count:       Integer read GetCount;
    property Items[AIndex: Integer]: TRigModelInfo read GetItem;
  end;

  { ====================================================================
    IRigService — main facade for application code
    IRigService - アプリケーションコード向けの主 Facade
    ====================================================================
    This is the ONLY interface application code needs to use directly.
    All async APIs return ICancellationToken and may be called with
    callback = nil to enable error fallback to OnError.

    アプリケーションコードが直接使う唯一のインターフェースです。
    すべての非同期 API は ICancellationToken を返します。callback = nil で
    呼ぶと、エラーは OnError へフォールバックルーティングされます。 }
  IRigService = interface
    ['{A9B8C7D6-E5F4-4321-8765-ABCDEF012345}']

    { ------------------------------------------------------------
      Connection management
      接続管理
      ------------------------------------------------------------ }

    { Open a connection to the specified rig. Returns immediately; the
      connection itself is made on the Worker thread, and its outcome
      arrives through OnConnectionChanged and OnError.

      AModel is a Hamlib model number. Take it from
      IRigModelCatalog.Items[i].ModelNumber rather than writing a
      constant: this interface documented "3085 for IC-7300" until
      Rev.5.0, and 3085 is in fact the IC-705 — the kind of mistake the
      catalogue exists to make impossible.

      APort is platform-specific (COM5, /dev/ttyUSB0,
      /dev/cu.usbserial-*). Leave it EMPTY for a backend that owns no
      serial device — Hamlib's built-in dummy rig (model 1), or a
      network backend whose address is set through a conf token. Do not
      pass 'none': Hamlib resolves that as a host name and the open
      fails with -RIG_ECONF.

      指定されたリグへの接続を開きます。即座に戻り、接続自体は Worker
      スレッドで行われ、結果は OnConnectionChanged と OnError で届きます。

      AModel は Hamlib モデル番号です。定数を書くのではなく
      IRigModelCatalog.Items[i].ModelNumber から取ってください。本
      インターフェースは Rev.5.0 まで「IC-7300 なら 3085」と書いていま
      したが、3085 は実際には IC-705 です。カタログはまさにこの種の
      誤りを不可能にするために存在します。

      APort はプラットフォーム依存です (COM5, /dev/ttyUSB0,
      /dev/cu.usbserial-*)。シリアルデバイスを持たないバックエンド
      (Hamlib 内蔵ダミーリグ = モデル 1、またはアドレスを conf トークン
      で設定するネットワークバックエンド) では「空」にしてください。
      'none' を渡してはいけません。Hamlib はそれをホスト名として解決し、
      open は -RIG_ECONF で失敗します。 }
    procedure Open(AModel: Integer; const APort: string);

    { Close the connection. Cancels all pending commands.
      接続を閉じます。保留中のすべてのコマンドをキャンセルします。 }
    procedure Close;

    function GetIsOpen: Boolean;

    { ------------------------------------------------------------
      Polling control — poller is hidden inside the service.
      ポーリング制御 — ポーラーはサービス内部に隠蔽されています。
      ------------------------------------------------------------ }

    { Start periodic polling of frequency/state. The OnFrequencyChanged
      event will fire whenever the frequency changes by more than
      FreqChangeThresholdHz (set via the timeout policy).

      周波数・状態の周期ポーリングを開始します。周波数が
      FreqChangeThresholdHz (タイムアウトポリシーで設定) を超えて
      変化するたびに OnFrequencyChanged イベントが発火します。 }
    procedure EnablePolling(AIntervalMs: Cardinal = 200);

    { Stop polling. Safe to call when polling is not active.
      ポーリングを停止します。停止中に呼んでも安全です。 }
    procedure DisablePolling;

    { ------------------------------------------------------------
      Asynchronous APIs (all return ICancellationToken)
      非同期 API (すべて ICancellationToken を返す)

      Default arguments minimize boilerplate. Pass nil callback to
      route errors to OnError automatically.
      デフォルト引数で記述量を最小化。callback=nil でエラーは
      OnError へ自動ルーティング。
      ------------------------------------------------------------ }

    { Set frequency on a VFO. Frequency is in Hz.
      VFO の周波数を設定します。周波数は Hz 単位。 }
    function SetFrequencyAsync(AFreq: Double;
                               AVfo: TRigVfo = rvfoCurr;
                               ACallback: TRigCommandCallback = nil): ICancellationToken;

    { Get frequency from a VFO. Result delivered via callback.
      VFO から周波数を取得します。結果はコールバックで届きます。 }
    function GetFrequencyAsync(AVfo: TRigVfo = rvfoCurr;
                               ACallback: TRigFreqCallback = nil): ICancellationToken;

    { Set operating mode. APassbandHz=0 means "rig default for this mode",
      which is what you want unless the operator picked a filter width.
      Passing rmUnknown raises EArgumentException: there is no sensible
      rmode_t to send for "unknown".

      動作モードを設定します。APassbandHz=0 は「このモードのリグ既定」で、
      オペレータがフィルタ幅を指定した場合を除き通常はこれを使います。
      rmUnknown を渡すと EArgumentException を発生させます。「未知」に
      対して送るべき rmode_t は存在しないためです。 }
    function SetModeAsync(AMode: TRigMode;
                          APassbandHz: Integer = 0;
                          AVfo: TRigVfo = rvfoCurr;
                          ACallback: TRigCommandCallback = nil): ICancellationToken;

    { Get operating mode from a VFO. モードを VFO から取得します。 }
    function GetModeAsync(AVfo: TRigVfo = rvfoCurr;
                          ACallback: TRigModeCallback = nil): ICancellationToken;

    { Set PTT (transmit) state. PTT (送信) 状態を設定します。 }
    function SetPttAsync(AState: TRigPttState;
                         ACallback: TRigCommandCallback = nil): ICancellationToken;

    { ------------------------------------------------------------
      Levels, functions, split and VFO — Rev.6.0
      レベル・ファンクション・スプリット・VFO — Rev.6.0
      ------------------------------------------------------------
      Added after surveying what applications actually ask Hamlib for.
      WSJT-X alone uses set_split_vfo, get_split_vfo, set_split_freq,
      set_split_mode, set_vfo, get_vfo and vfo_op; an S-meter needs
      get_level(STRENGTH). Up to Rev.5.1 this component offered
      frequency, mode and PTT, which is not enough to build those
      applications on.

      アプリケーションが実際に Hamlib へ何を要求しているかを調査した
      結果として追加しました。WSJT-X だけでも set_split_vfo、
      get_split_vfo、set_split_freq、set_split_mode、set_vfo、get_vfo、
      vfo_op を使い、S メータには get_level(STRENGTH) が要ります。
      Rev.5.1 までの本コンポーネントは周波数・モード・PTT のみで、
      それらのアプリを載せるには足りませんでした。 }

    { Read a level. The S-meter is GetLevelAsync(rlvStrength, ...).
      A level the rig does not have returns rcsError with
      rekNotAvailable — ask the capabilities first to avoid that.

      レベルを読みます。S メータは GetLevelAsync(rlvStrength, ...)。
      リグが持たないレベルは rekNotAvailable 付きの rcsError になります。
      事前に能力を問い合わせれば避けられます。 }
    function GetLevelAsync(ALevel: TRigLevel;
                           ACallback: TRigLevelCallback = nil;
                           AVfo: TRigVfo = rvfoCurr): ICancellationToken;

    { Set a float-valued level, 0.0 .. 1.0 for the gain-like ones.
      Passing a read-only level (a meter) raises EArgumentException:
      that is a programming error, not a rig limitation.

      float 値のレベルを設定します。ゲイン系は 0.0〜1.0。読み取り専用の
      レベル (メータ類) を渡すと EArgumentException です。リグの制限では
      なくプログラミングの誤りだからです。 }
    function SetLevelFloatAsync(ALevel: TRigLevel; AValue: Double;
                                ACallback: TRigCommandCallback = nil;
                                AVfo: TRigVfo = rvfoCurr): ICancellationToken;

    { Set an int-valued level (preamp dB, keyer WPM, CW pitch Hz ...).
      int 値のレベルを設定します (プリアンプ dB、キーヤ WPM、CW ピッチ Hz 等)。 }
    function SetLevelIntAsync(ALevel: TRigLevel; AValue: Integer;
                              ACallback: TRigCommandCallback = nil;
                              AVfo: TRigVfo = rvfoCurr): ICancellationToken;

    { Read and write an on/off function (tuner, VOX, noise blanker...).
      オン・オフ機能の読み書き (チューナ、VOX、ノイズブランカ等)。 }
    function GetFuncAsync(AFunc: TRigFunc;
                          ACallback: TRigFuncCallback = nil;
                          AVfo: TRigVfo = rvfoCurr): ICancellationToken;
    function SetFuncAsync(AFunc: TRigFunc; AActive: Boolean;
                          ACallback: TRigCommandCallback = nil;
                          AVfo: TRigVfo = rvfoCurr): ICancellationToken;

    { Turn split operation on or off, naming the transmit VFO.
      ATxVfo = rvfoCurr lets Hamlib choose the usual partner of the
      current VFO, which is what an application normally wants.

      スプリット運用の入切。送信 VFO を指定します。ATxVfo = rvfoCurr に
      すると現在 VFO の通常の相方を Hamlib が選びます。通常はこれで十分
      です。 }
    function SetSplitAsync(AEnabled: Boolean;
                           ATxVfo: TRigVfo = rvfoCurr;
                           ACallback: TRigCommandCallback = nil): ICancellationToken;

    { Read the split state and, when split is on, the transmit
      frequency. One command, because an application that asks "am I
      split?" always wants to know "split to where?".

      スプリット状態と、スプリット時の送信周波数を読みます。1 コマンドに
      まとめているのは、「スプリット中か」を尋ねるアプリは必ず
      「どこへのスプリットか」も知りたいからです。 }
    function GetSplitAsync(ACallback: TRigSplitCallback = nil): ICancellationToken;

    { Set the transmit frequency used while split is on.
      スプリット中に使う送信周波数を設定します。 }
    function SetSplitFreqAsync(AFreq: Double;
                               ACallback: TRigCommandCallback = nil): ICancellationToken;

    { Select the VFO the rig's front panel acts on, and read it back.
      リグのフロントパネルが作用する VFO を選択し、読み戻します。 }
    function SetVfoAsync(AVfo: TRigVfo;
                         ACallback: TRigCommandCallback = nil): ICancellationToken;
    function GetVfoAsync(ACallback: TRigVfoCallback = nil): ICancellationToken;

    { One-shot VFO operation: swap A/B, copy A to B, start the tuner.
      一回限りの VFO 操作: A/B 交換、A から B への複写、チューナ始動。 }
    function VfoOpAsync(AOp: TRigVfoOp;
                        ACallback: TRigCommandCallback = nil;
                        AVfo: TRigVfo = rvfoCurr): ICancellationToken;

    { What this rig can do, as reported by the loaded library. Valid
      after Open; Known = False when the library cannot answer.
      本機ができること。ロードされたライブラリの報告に基づきます。
      Open 後に有効で、ライブラリが答えられない場合 Known = False。 }
    function GetCapabilities: TRigCapabilities;

    { Push a Hamlib configuration token straight at the rig, for the
      settings this component has no opinion about: ptt_type, rts_state,
      data_bits, stop_bits, serial_handshake and the rest of conf.c.

      Must be called BEFORE Open — Hamlib applies most of these while
      opening the port, and several cannot be changed afterwards. The
      component applies them in the order given, right after rig_init.

      This is deliberately a raw string pair rather than a typed API.
      The token list belongs to Hamlib and grows with it; wrapping it
      would mean re-publishing this component every time Hamlib adds a
      setting, and leaving it out means a rig that needs ptt_type=RIG
      cannot transmit at all.

      Hamlib の設定トークンをそのままリグへ渡します。本コンポーネントが
      見解を持たない設定 (ptt_type、rts_state、data_bits、stop_bits、
      serial_handshake など conf.c の全項目) のためのものです。

      Open より前に呼ぶ必要があります。Hamlib はこれらの多くをポート
      オープン時に適用し、いくつかは後から変更できません。コンポーネントは
      rig_init の直後に、指定された順序で適用します。

      型付き API ではなく意図的に生の文字列対にしています。トークン一覧は
      Hamlib のものであり Hamlib とともに増えます。ラップすれば Hamlib が
      設定を追加するたびに本コンポーネントを再公開することになり、省けば
      ptt_type=RIG を要するリグが送信すらできません。 }
    procedure AddConfToken(const AName, AValue: string);

    { ------------------------------------------------------------
      Bulk cancellation
      一括キャンセル
      ------------------------------------------------------------ }

    { Cancel all pending and currently executing commands. Use this in
      the destructor of an owning Presenter to prevent dangling callbacks.
      The Service destructor also calls this automatically as a fail-safe.

      保留中・実行中のすべてのコマンドをキャンセルします。所有元の
      Presenter のデストラクタで呼ぶことで、Dangling Callback を防ぎます。
      Service のデストラクタもフェイルセーフとして自動的にこれを呼びます。 }
    procedure CancelAllPending;

    { ------------------------------------------------------------
      Hardware policy
      ハードウェアポリシー
      ------------------------------------------------------------ }

    { Apply a new timeout policy at runtime. Does not require reconnection.
      Throws EArgumentException if the policy fails validation.

      タイムアウトポリシーをランタイムで適用します。再接続不要です。
      ポリシーがバリデーションに失敗した場合 EArgumentException を発生。 }
    procedure ApplyTimeoutPolicy(const APolicy: TRigTimeoutPolicy);

    function GetCurrentPolicy: TRigTimeoutPolicy;

    { ------------------------------------------------------------
      Event handlers (Push model)
      イベントハンドラ (Push モデル)
      ------------------------------------------------------------ }

    procedure SetOnConnectionChanged(AHandler: TRigConnectEvent);
    procedure SetOnFrequencyChanged(AHandler: TRigFreqChangedEvent);
    procedure SetOnError(AHandler: TRigErrorEvent);

    { Non-fatal compatibility warnings: an untested Hamlib version that the
      factory was told to allow, a library bound without a soname, or a
      model number the library could not confirm. The application decides
      whether to show a banner, log it, or ignore it.

      致命的でない互換性警告。ファクトリが許可した未検証バージョン、soname
      なしでバインドされたライブラリ、ライブラリが確認できなかったモデル番号
      などです。バナー表示・ログ・無視のいずれにするかはアプリが決めます。 }
    procedure SetOnLibraryWarning(AHandler: TRigLibraryWarningEvent);

    { ------------------------------------------------------------
      Library and model verification
      ライブラリとモデルの検証
      ------------------------------------------------------------ }

    { What was actually loaded and connected to. Valid after Create for the
      library fields, and after Open for the model fields.

      実際にロード・接続した対象。ライブラリ系フィールドは Create 後、
      モデル系フィールドは Open 後に有効です。 }
    function GetLibraryStatus: TRigLibraryStatus;

    { ------------------------------------------------------------
      State snapshot (Pull model)
      状態スナップショット (Pull モデル)
      ------------------------------------------------------------ }

    { Return the latest known state. Thread-safe; may be called from
      any thread. If polling has not run yet, Timestamp=0.

      最新の既知状態を返します。スレッドセーフで任意のスレッドから
      呼べます。ポーリング未実行時は Timestamp=0。 }
    function GetCurrentState: TRigState;

    { ------------------------------------------------------------
      Diagnostics
      診断
      ------------------------------------------------------------ }

    function GetQueueDepth: Integer;
    function GetCircuitBreakerOpen: Boolean;

    property IsOpen:             Boolean           read GetIsOpen;
    property CurrentState:       TRigState         read GetCurrentState;
    property LibraryStatus:      TRigLibraryStatus read GetLibraryStatus;
    property QueueDepth:         Integer           read GetQueueDepth;
    property CircuitBreakerOpen: Boolean           read GetCircuitBreakerOpen;
  end;

  { ====================================================================
    IRigServiceFactory — dependency injection root
    IRigServiceFactory - 依存性注入のルート
    ====================================================================
    Use this to obtain an IRigService instance. The factory hides all
    L1..L5 wiring complexity from application code.

    IRigService インスタンスの取得にこれを使います。ファクトリは
    L1〜L5 の結線の複雑さをアプリケーションコードから隠蔽します。 }
  IRigServiceFactory = interface
    ['{F1E2D3C4-B5A6-9788-1234-567890ABCDEF}']

    { Create a Service with default policy.
      デフォルトポリシーで Service を生成します。 }
    function CreateService: IRigService;

    { Create a Service with a specific hardware policy.
      Use this when you know the rig family in advance.
      特定のハードウェアポリシーで Service を生成します。
      機種ファミリが事前にわかっている場合に使います。 }
    function CreateServiceWithPolicy(const APolicy: TRigTimeoutPolicy): IRigService;

    { Create a mock service for testing (no real DLL load).
      テスト用のモックサービスを生成します (実 DLL ロードなし)。 }
    function CreateMockService: IRigService;

    { Load Hamlib and ask it which rigs it can drive. Use the returned
      catalogue to populate the rig selector instead of hard-coding
      RIG_MODEL_* constants, then pass the chosen entry's ModelNumber
      to IRigService.Open.

      The version gate applies here too, so this raises
      EHamlibUnsupportedVersion on an unverified Hamlib unless
      AllowUntestedVersion is set — the catalogue comes from the same
      library the Service will use, so it must pass the same check.

      An old or trimmed Hamlib that cannot enumerate yields a catalogue
      whose IsAvailable is False rather than an exception: the
      application should then fall back to asking the operator for a
      model number.

      Hamlib をロードし、扱えるリグを問い合わせます。RIG_MODEL_* 定数を
      ハードコードする代わりに、返されたカタログで機種選択 UI を構成し、
      選ばれた項目の ModelNumber を IRigService.Open に渡してください。

      バージョンゲートはここにも適用されます。したがって
      AllowUntestedVersion を設定していない場合、未検証の Hamlib では
      EHamlibUnsupportedVersion を発生させます。カタログは Service が
      使うのと同じライブラリから来るため、同じ検査を通る必要があります。

      列挙できない古い・機能を削った Hamlib では、例外ではなく
      IsAvailable が False のカタログを返します。その場合アプリケーション
      はオペレータにモデル番号の入力を求めるフォールバックを用意して
      ください。 }
    function CreateModelCatalog: IRigModelCatalog;

    { ------------------------------------------------------------
      Compatibility policy — the application's decision
      互換性の方針 — アプリケーションが決めること
      ------------------------------------------------------------
      False (default): a Hamlib outside the verified range is refused with
      EHamlibUnsupportedVersion, so an ABI change becomes a visible failure
      at startup instead of silent corruption later.

      True: the Service is created anyway and the mismatch is reported
      through IRigService.OnLibraryWarning. Set this only after verifying
      the newer Hamlib yourself.

      False (既定): 検証済み範囲外の Hamlib は EHamlibUnsupportedVersion で
      拒否します。ABI 変更が、後の静かな破損ではなく起動時の明確な失敗に
      なります。

      True: それでも Service を生成し、不一致は
      IRigService.OnLibraryWarning で報告します。新しい Hamlib を自分で
      検証した場合にのみ設定してください。 }
    function  GetAllowUntestedVersion: Boolean;
    procedure SetAllowUntestedVersion(AValue: Boolean);

    property AllowUntestedVersion: Boolean
      read GetAllowUntestedVersion write SetAllowUntestedVersion;
  end;

implementation
end.
