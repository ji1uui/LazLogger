{
  HamlibFactory.pas

  Dependency injection factory for IRigService. Application code uses
  this to obtain an IRigService without knowing about IHamlibLoader,
  TRigWorker, TRigPollerThread, etc.

  IRigService 用の依存性注入ファクトリ。アプリケーションコードはこれを
  使って、IHamlibLoader、TRigWorker、TRigPollerThread 等を意識せずに
  IRigService を取得します。

  Layer:    L4
  Depends:  HamlibInterfaces, HamlibErrors, HamlibTimeoutPolicy,
            HamlibLoader, HamlibService, HamlibCatalog

  Typical usage:
    var
      Factory: IRigServiceFactory;
      Service: IRigService;
    begin
      Factory := TRigServiceFactory.Create;
      Service := Factory.CreateServiceWithPolicy(RigPolicy_FastUsb);
      Service.Open(RIG_MODEL_IC7300, 'COM5');
      ...
    end;

  典型的な使用例:
    var
      Factory: IRigServiceFactory;
      Service: IRigService;
    begin
      Factory := TRigServiceFactory.Create;
      Service := Factory.CreateServiceWithPolicy(RigPolicy_FastUsb);
      Service.Open(RIG_MODEL_IC7300, 'COM5');
      ...
    end;
}
unit HamlibFactory;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  HamlibInterfaces, HamlibErrors, HamlibTimeoutPolicy,
  HamlibLoader, HamlibService, HamlibCatalog;

type
  { ====================================================================
    TRigServiceFactory — concrete implementation of IRigServiceFactory
    TRigServiceFactory - IRigServiceFactory の具象実装
    ==================================================================== }
  TRigServiceFactory = class(TInterfacedObject, IRigServiceFactory)
  private
    FLibPath:              string;
    FAllowUntestedVersion: Boolean;

    { One loader, reused for every Service this factory makes.

      Each loader dlopens the library; when the last one lets go, the
      library leaves the process. A factory that built a fresh loader
      per Service therefore ran a load / register-backends / unload
      cycle per Service — and Hamlib's rig_load_all_backends() begins
      with memset(rig_hash_table, 0, ...) and then calloc()s a fresh
      node for each of the 283 backends, abandoning the previous ones.
      dlclose does not reclaim them. So every Service created cost
      4,528 bytes that nothing would ever free, inside libhamlib.

      Measured with valgrind over 123 Service lifecycles: 34,809 lost
      blocks, exactly 123 x 283, every one of them traced to
      EnsureBackendsLoaded.

      Sharing the loader also stops the backend registry — a single
      process-global table inside the library — being torn down and
      rebuilt while other code may be reading it.

      本ファクトリが作るすべての Service で再利用する単一のローダ。

      各ローダはライブラリを dlopen します。最後の 1 つが手放すと
      ライブラリはプロセスから外れます。したがって Service ごとに新しい
      ローダを作るファクトリは、Service ごとに ロード / バックエンド登録
      / アンロード のサイクルを回していました。そして Hamlib の
      rig_load_all_backends() は memset(rig_hash_table, 0, ...) から始まり、
      283 個のバックエンドそれぞれに新しいノードを calloc して、以前の
      ものを放棄します。dlclose はそれらを回収しません。つまり Service を
      1 つ作るごとに、libhamlib 内部で誰も解放しない 4,528 バイトを
      支払っていました。

      valgrind で Service のライフサイクル 123 回を測定: 喪失ブロック
      34,809 個、ちょうど 123 × 283 であり、そのすべてが
      EnsureBackendsLoaded に由来していました。

      ローダの共有は、ライブラリ内部の単一のプロセス全体バックエンド表が、
      他のコードが読んでいるかもしれない最中に破棄・再構築されることも
      止めます。 }
    FSharedLoader:         IHamlibLoader;

    { Returns the shared loader, creating it on first use. }
    function AcquireLoader: IHamlibLoader;

    { Apply the version gate. Mechanism lives in the loader
      (IHamlibDiagnostics); the policy decision lives here.
      バージョンゲートを適用します。機構はローダ側 (IHamlibDiagnostics)、
      方針の決定はここにあります。 }
    procedure EnforceVersionGate(ALoader: IHamlibLoader);
  public
    { Construct with an optional explicit Hamlib library path. If empty,
      the loader uses platform-specific search candidates.
      明示的な Hamlib ライブラリパスを指定 (任意)。空の場合はローダが
      プラットフォーム固有の探索候補を使用します。 }
    constructor Create(const ALibPath: string = '');

    { ----------- IRigServiceFactory implementation ----------- }

    { Create a Service with the default timeout policy.
      デフォルトタイムアウトポリシーで Service を生成します。 }
    function CreateService: IRigService;

    { Create a Service with a specific hardware policy. Use this when
      the rig family is known in advance (recommended for production).
      特定のハードウェアポリシーで Service を生成します。機種ファミリが
      事前にわかる場合に使用 (本番環境推奨)。 }
    function CreateServiceWithPolicy(const APolicy: TRigTimeoutPolicy): IRigService;

    { Create a mock service for unit tests. Returns nil in this base
      implementation; subclasses or test factories should override.
      The base TRigServiceFactory does not depend on test units, so
      this method is a placeholder.

      ユニットテスト用のモックサービスを生成します。本基本実装では nil を
      返します。サブクラスまたはテスト用ファクトリが override してください。
      基底 TRigServiceFactory はテストユニットに依存しないため、本メソッドは
      プレースホルダです。 }
    function CreateMockService: IRigService;

    { Load Hamlib and build the rig catalogue from it. See
      IRigServiceFactory.CreateModelCatalog for the contract.
      Hamlib をロードしてリグカタログを構築します。契約は
      IRigServiceFactory.CreateModelCatalog を参照。 }
    function CreateModelCatalog: IRigModelCatalog;

    function  GetAllowUntestedVersion: Boolean;
    procedure SetAllowUntestedVersion(AValue: Boolean);

    property AllowUntestedVersion: Boolean
      read GetAllowUntestedVersion write SetAllowUntestedVersion;
  end;

implementation

constructor TRigServiceFactory.Create(const ALibPath: string);
begin
  inherited Create;
  FLibPath              := ALibPath;
  FAllowUntestedVersion := False;   { refuse by default / 既定は拒否 }
end;

function TRigServiceFactory.GetAllowUntestedVersion: Boolean;
begin
  Result := FAllowUntestedVersion;
end;

procedure TRigServiceFactory.SetAllowUntestedVersion(AValue: Boolean);
begin
  FAllowUntestedVersion := AValue;
end;

procedure TRigServiceFactory.EnforceVersionGate(ALoader: IHamlibLoader);
var
  Diag: IHamlibDiagnostics;
begin
  { A loader without diagnostics cannot be gated; that is the test-fake
    path and it is intentionally permitted.
    診断を持たないローダはゲートできません。これはテストフェイクの経路で、
    意図的に許可します。 }
  if not Supports(ALoader, IHamlibDiagnostics, Diag) then Exit;

  if Diag.GetVersionVerdict = rvvVerified then Exit;
  if FAllowUntestedVersion then Exit;   { caller took responsibility
                                          / 呼び出し元が責任を引き受けた }

  case Diag.GetVersionVerdict of
    rvvUntested:
      raise EHamlibUnsupportedVersion.CreateFmt(
        'Hamlib %s is outside the verified range %s. Symbol resolution ' +
        'does not prove ABI compatibility, so startup was refused. ' +
        'Set TRigServiceFactory.AllowUntestedVersion := True to override ' +
        'after verifying this version yourself.',
        [Diag.GetVersionText, Diag.GetSupportedRangeText]);
    rvvUnknown:
      raise EHamlibUnsupportedVersion.CreateFmt(
        'The Hamlib version at %s could not be determined, so it cannot ' +
        'be checked against the verified range %s. Set ' +
        'TRigServiceFactory.AllowUntestedVersion := True to proceed anyway.',
        [ALoader.LibPath, Diag.GetSupportedRangeText]);
  end;
end;

function TRigServiceFactory.CreateService: IRigService;
begin
  Result := CreateServiceWithPolicy(RigPolicy_Default);
end;

function TRigServiceFactory.AcquireLoader: IHamlibLoader;
var
  Loader: IHamlibLoader;
begin
  if Assigned(FSharedLoader) and FSharedLoader.IsLoaded then
    Exit(FSharedLoader);

  Loader := THamlibLoader.Create;
  if not Loader.Load(FLibPath) then
    raise EHamlibLoadError.Create('Hamlib library could not be loaded. ' +
      'Ensure libhamlib is installed and accessible.');
  FSharedLoader := Loader;
  Result        := FSharedLoader;
end;

function TRigServiceFactory.CreateServiceWithPolicy(
  const APolicy: TRigTimeoutPolicy): IRigService;
var
  Loader:  IHamlibLoader;
  Service: TRigService;
  ErrMsg:  string;
begin
  { Validate the policy before doing any expensive work.
    時間のかかる処理を行う前にポリシーをバリデート。 }
  if not ValidatePolicy(APolicy, ErrMsg) then
    raise EArgumentException.Create('Invalid policy: ' + ErrMsg);

  { Step 1: Obtain the loader. Shared across every Service this factory
    makes — see FSharedLoader for why that matters.
    ステップ 1: ローダを取得します。本ファクトリが作る全 Service で共有
    します。その理由は FSharedLoader を参照してください。 }
  Loader := AcquireLoader;

  { Step 1b: refuse an unverified ABI before anything is built on top.
    ステップ 1b: 上に何も積む前に、未検証の ABI を拒否します。 }
  EnforceVersionGate(Loader);

  { Step 2: Construct the Service. The Service takes an IHamlibLoader
    reference; the Service's lifetime owns the loader (via reference
    counting) until the IRigService itself is released.

    ステップ 2: Service を構築。Service は IHamlibLoader 参照を取り、
    IRigService 自体が解放されるまで参照カウントによりローダを所有します。 }
  Service := TRigService.Create(Loader);
  Service.ApplyTimeoutPolicy(APolicy);
  Result := Service;
end;

function TRigServiceFactory.CreateModelCatalog: IRigModelCatalog;
var
  Loader: IHamlibLoader;
begin
  { The same three steps as CreateServiceWithPolicy, minus the Service:
    load, gate, then ask. The gate is not skipped for a read-only
    query, because an ABI mismatch would corrupt the model numbers this
    returns just as readily as it would corrupt a frequency.

    CreateServiceWithPolicy と同じ 3 段階から Service を除いたもの、
    すなわち「ロード → ゲート → 問い合わせ」です。読み取り専用の
    問い合わせでもゲートは省きません。ABI 不一致は周波数と同じくらい
    容易に、ここで返すモデル番号を壊すためです。 }
  Loader := THamlibLoader.Create;
  if not Loader.Load(FLibPath) then
    raise EHamlibLoadError.Create('Hamlib library could not be loaded. ' +
      'Ensure libhamlib is installed and accessible.');

  EnforceVersionGate(Loader);

  Result := TRigModelCatalog.Create(Loader);
end;

function TRigServiceFactory.CreateMockService: IRigService;
begin
  { Returning nil from a function whose contract promises an object turns
    the caller's first method call into an access violation. Raising names
    the problem instead. Test code should construct TRigService directly
    with its own IHamlibLoader fake.

    オブジェクトを返すと約束した関数から nil を返すと、呼び出し元の最初の
    メソッド呼び出しがアクセス違反になります。例外にすれば問題が名指しされ
    ます。テストコードは独自の IHamlibLoader フェイクで TRigService を
    直接構築してください。 }
  raise ENotSupportedException.Create(
    'CreateMockService is not implemented in the production factory. ' +
    'Construct TRigService with a test IHamlibLoader instead.');
  { In production builds, no test/mock units are linked, so this
    returns nil. Test code uses a separate factory class
    (TMockRigServiceFactory) defined in the test module that overrides
    this and returns a service backed by TFakeHamlibLoader.

    本番ビルドではテスト/モックユニットがリンクされないため nil を返します。
    テストコードはテストモジュールで定義された別ファクトリクラス
    (TMockRigServiceFactory) を使い、これを override して
    TFakeHamlibLoader を裏に持つサービスを返します。 }
  Result := nil;
end;

end.
