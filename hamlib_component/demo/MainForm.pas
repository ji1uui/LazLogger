{
  MainForm.pas

  TMainForm — the RigPanel window. It implements IRigView and does
  nothing else: assign to controls, forward events to the presenter.

  TMainForm - RigPanel のウィンドウ。IRigView を実装し、それ以外は何も
  しません。コントロールへの代入と、presenter へのイベント転送だけです。

  The rule this unit follows / 本ユニットが守る規則
  ------------------------------------------------------------------
  No decision is taken here. There is no `if Connected then` and no
  frequency arithmetic beyond the Hz/MHz formatting that is purely a
  presentation concern. Every handler is one line that calls the
  presenter, and every IRigView method is a few assignments.

  ここでは判断を行いません。`if Connected then` もなく、周波数の計算も
  Hz/MHz の整形（純粋に表示上の関心事）以外にはありません。各イベント
  ハンドラは presenter を呼ぶ 1 行であり、各 IRigView メソッドは数行の
  代入です。

  If you find yourself wanting to add logic to this unit, it belongs in
  RigPanelPresenter — where it can be tested without a screen.
  本ユニットにロジックを足したくなったら、それは RigPanelPresenter に
  属します。そこでなら画面なしにテストできます。

  Layer:    demo (application, LCL)
  Depends:  LCL, HamlibInterfaces, HamlibModeCodec, RigPanelView,
            RigPanelPresenter
}
unit MainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Graphics, Spin,
  HamlibInterfaces, HamlibModeCodec,
  RigPanelView, RigPanelPresenter;

type
  TMainForm = class(TForm, IRigView)
    { ---- controls, created in code so this unit needs no .lfm at
           build time and the demo stays readable as source ----
      ---- コントロールはコードで生成します。ビルド時に .lfm を必要と
           せず、デモがソースとして読めるままになります ---- }
  private
    cmbRig:      TComboBox;
    edtModel:    TSpinEdit;
    cmbPort:     TComboBox;
    cmbPolicy:   TComboBox;
    btnConnect:  TButton;

    lblFreqBig:  TLabel;
    lblModeBig:  TLabel;
    shpPtt:      TShape;
    lblPttText:  TLabel;

    edtFreqMHz:  TEdit;
    btnQsy:      TButton;
    cmbMode:     TComboBox;
    edtPassband: TSpinEdit;
    btnSetMode:  TButton;
    btnPttOn:    TButton;
    btnPttOff:   TButton;
    btnRead:     TButton;
    btnCancel:   TButton;

    lblStatus:   TLabel;
    lblLibrary:  TLabel;
    lblQueue:    TLabel;
    tmrRefresh:  TTimer;

    FPresenter:  TRigPresenter;

    { The presenter is a plain object, but the view it is given is an
      interface. The form must therefore hand out a reference that does
      NOT own it: a TForm is destroyed by its owner, not by a reference
      count. _AddRef/_Release below are overridden to make that
      explicit.

      presenter は通常のオブジェクトですが、渡される view はインター
      フェースです。したがってフォームは「所有しない」参照を渡さなければ
      なりません。TForm は参照カウントではなく所有者によって破棄される
      からです。下記の _AddRef/_Release でそれを明示します。 }
    function  _AddRef: LongInt; cdecl;
    function  _Release: LongInt; cdecl;

    procedure BuildControls;
    procedure FillStaticLists;

    { ---- event forwarding, one line each / イベント転送、各 1 行 ---- }
    procedure ConnectClick(Sender: TObject);
    procedure QsyClick(Sender: TObject);
    procedure SetModeClick(Sender: TObject);
    procedure PttOnClick(Sender: TObject);
    procedure PttOffClick(Sender: TObject);
    procedure ReadClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure RefreshTick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;

    { Connect without the operator clicking, for a scripted
      demonstration or a smoke test:

          ./RigPanel --model=1 --port=

      Model 1 is Hamlib's built-in dummy rig, which needs no hardware
      and no port. Still just event forwarding: the presenter does the
      work, exactly as it would from the button.

      オペレータのクリックなしで接続します。デモの自動実行や
      スモークテスト用です。モデル 1 は Hamlib 内蔵のダミーリグで、
      ハードウェアもポートも不要です。これもイベント転送にすぎません。
      ボタンから呼ぶ場合とまったく同じく、処理は presenter が行います。 }
    procedure AutoConnect(AModel: Integer; const APort: string);

    { ---- IRigView ---- }
    procedure ShowRigList(const AItems: array of string;
                          AEnumerationAvailable: Boolean);
    procedure ShowFrequency(AHz: Double);
    procedure ShowMode(AMode: TRigMode; APassbandHz: Integer);
    procedure ShowPtt(AActive: Boolean);
    procedure SetUiMode(AMode: TRigUiMode);
    procedure ShowNotice(ALevel: TRigNoticeLevel; const AText: string);
    procedure ShowLibraryInfo(const AText: string);
    procedure ShowQueueDepth(ADepth: Integer; ABreakerOpen: Boolean);
  end;

implementation

const
  { The modes offered in the mode box. A real application would narrow
    this to what the selected rig supports; the component can decode a
    capability mask (THamlibModeCodec.SetFromHamlib) but does not yet
    expose the rig's own mode list, so this is a fixed common set.

    モード欄に出すモード。実アプリでは選択機種が対応するものに絞ります。
    コンポーネントは能力マスクを展開できますが
    (THamlibModeCodec.SetFromHamlib)、リグ自身のモード一覧を取得する
    API はまだ無いため、ここでは一般的な固定集合にしています。 }
  OFFERED_MODES: array[0..7] of TRigMode = (
    rmUSB, rmLSB, rmCW, rmCWR, rmFM, rmAM, rmPktUSB, rmRTTY
  );

{ ------------------------------------------------------------------
  Lifetime / 生存期間
  ------------------------------------------------------------------ }

constructor TMainForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption     := 'RigPanel — Hamlib component demo';
  Width       := 560;
  Height      := 430;
  Position    := poScreenCenter;
  BorderStyle := bsSingle;
  OnCloseQuery := @FormCloseQuery;

  BuildControls;
  FillStaticLists;

  { Self is passed as IRigView. _AddRef/_Release are no-ops, so the
    presenter cannot keep the form alive and cannot free it either.
    Self を IRigView として渡します。_AddRef/_Release は何もしないため、
    presenter がフォームを延命することも解放することもありません。 }
  FPresenter := TRigPresenter.Create(Self as IRigView);
  FPresenter.Initialise;
end;

destructor TMainForm.Destroy;
begin
  { Stop the timer before the presenter goes: a tick arriving after the
    presenter is freed would call into freed memory.
    presenter より先にタイマを止めます。presenter 解放後にティックが
    届くと解放済みメモリを呼ぶことになります。 }
  if Assigned(tmrRefresh) then tmrRefresh.Enabled := False;
  FreeAndNil(FPresenter);
  inherited Destroy;
end;

function TMainForm._AddRef: LongInt; cdecl;
begin
  { A form's lifetime is owned by its owner, never by an interface
    reference count. Returning a constant keeps the form from being
    freed under the LCL's feet when the last interface reference goes.
    フォームの生存期間は所有者が持ち、インターフェースの参照カウントは
    決して持ちません。定数を返すことで、最後の参照が消えたときに LCL の
    足元でフォームが解放されるのを防ぎます。 }
  Result := 1;
end;

function TMainForm._Release: LongInt; cdecl;
begin
  Result := 1;
end;

procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  { Nothing to ask: the presenter's destructor cancels in-flight
    commands and closes the rig, and the component's own destructor
    repeats that as a fail-safe.
    尋ねることはありません。presenter のデストラクタが実行中コマンドを
    キャンセルしてリグを閉じ、コンポーネント側のデストラクタもフェイル
    セーフとして同じことを行います。 }
  CanClose := True;
end;

{ ------------------------------------------------------------------
  Control construction — layout only
  コントロール構築 — レイアウトのみ
  ------------------------------------------------------------------ }

procedure TMainForm.BuildControls;

  function MakeLabel(const AText: string; ALeft, ATop: Integer): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent  := Self;
    Result.Left    := ALeft;
    Result.Top     := ATop;
    Result.Caption := AText;
  end;

  function MakeButton(const AText: string; ALeft, ATop, AWidth: Integer;
                      AHandler: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent  := Self;
    Result.Left    := ALeft;
    Result.Top     := ATop;
    Result.Width   := AWidth;
    Result.Caption := AText;
    Result.OnClick := AHandler;
  end;

begin
  { ---- connection row / 接続行 ---- }
  MakeLabel('Rig', 16, 16);
  cmbRig := TComboBox.Create(Self);
  cmbRig.Parent := Self;
  cmbRig.SetBounds(16, 34, 250, 24);
  cmbRig.Style  := csDropDownList;

  MakeLabel('or model #', 276, 16);
  edtModel := TSpinEdit.Create(Self);
  edtModel.Parent  := Self;
  edtModel.SetBounds(276, 34, 80, 24);
  edtModel.MinValue := 1;
  edtModel.MaxValue := 99999;
  edtModel.Value    := 1;

  MakeLabel('Port', 366, 16);
  cmbPort := TComboBox.Create(Self);
  cmbPort.Parent := Self;
  cmbPort.SetBounds(366, 34, 170, 24);

  MakeLabel('Timing', 16, 68);
  cmbPolicy := TComboBox.Create(Self);
  cmbPolicy.Parent := Self;
  cmbPolicy.SetBounds(16, 86, 140, 24);
  cmbPolicy.Style  := csDropDownList;

  btnConnect := MakeButton('Connect', 170, 86, 110, @ConnectClick);

  { ---- readout / 表示部 ---- }
  lblFreqBig := MakeLabel('—', 16, 126);
  lblFreqBig.Font.Height := -34;
  lblFreqBig.Font.Style  := [fsBold];

  lblModeBig := MakeLabel('—', 300, 136);
  lblModeBig.Font.Height := -22;

  shpPtt := TShape.Create(Self);
  shpPtt.Parent := Self;
  shpPtt.SetBounds(460, 134, 26, 26);
  shpPtt.Shape  := stCircle;
  shpPtt.Brush.Color := clGray;
  lblPttText := MakeLabel('RX', 492, 140);

  { ---- controls / 操作部 ---- }
  MakeLabel('MHz', 16, 190);
  edtFreqMHz := TEdit.Create(Self);
  edtFreqMHz.Parent := Self;
  edtFreqMHz.SetBounds(16, 208, 110, 24);
  edtFreqMHz.Text   := '14.074000';
  btnQsy := MakeButton('QSY', 132, 208, 70, @QsyClick);

  MakeLabel('Mode', 216, 190);
  cmbMode := TComboBox.Create(Self);
  cmbMode.Parent := Self;
  cmbMode.SetBounds(216, 208, 100, 24);
  cmbMode.Style  := csDropDownList;

  MakeLabel('Width Hz (0=auto)', 326, 190);
  edtPassband := TSpinEdit.Create(Self);
  edtPassband.Parent   := Self;
  edtPassband.SetBounds(326, 208, 90, 24);
  edtPassband.MinValue := 0;
  edtPassband.MaxValue := 30000;
  edtPassband.Value    := 0;
  btnSetMode := MakeButton('Set', 422, 208, 60, @SetModeClick);

  btnPttOn  := MakeButton('TX', 16, 248, 70, @PttOnClick);
  btnPttOff := MakeButton('RX', 92, 248, 70, @PttOffClick);
  btnRead   := MakeButton('Read now', 180, 248, 100, @ReadClick);
  btnCancel := MakeButton('Cancel read', 286, 248, 110, @CancelClick);

  { ---- status / ステータス ---- }
  lblStatus := MakeLabel('Starting...', 16, 296);
  lblStatus.Width := 520;

  lblQueue := MakeLabel('', 16, 320);
  lblQueue.Width := 520;

  lblLibrary := MakeLabel('', 16, 344);
  lblLibrary.Width := 520;
  lblLibrary.Font.Height := -11;
  lblLibrary.Font.Color  := clGrayText;

  { ---- periodic refresh / 定期更新 ---- }
  tmrRefresh := TTimer.Create(Self);
  tmrRefresh.Interval := 300;
  tmrRefresh.OnTimer  := @RefreshTick;
  tmrRefresh.Enabled  := True;
end;

procedure TMainForm.FillStaticLists;
var
  i: Integer;
begin
  cmbPolicy.Items.Add('Default');
  cmbPolicy.Items.Add('Fast USB');
  cmbPolicy.Items.Add('Slow CAT');
  cmbPolicy.Items.Add('Very slow CAT');
  cmbPolicy.ItemIndex := 1;

  {$IFDEF WINDOWS}
  for i := 1 to 16 do cmbPort.Items.Add(Format('COM%d', [i]));
  {$ELSE}
  for i := 0 to 3 do cmbPort.Items.Add(Format('/dev/ttyUSB%d', [i]));
  for i := 0 to 3 do cmbPort.Items.Add(Format('/dev/ttyACM%d', [i]));
  {$ENDIF}
  cmbPort.Items.Add('none');
  cmbPort.ItemIndex := 0;

  for i := Low(OFFERED_MODES) to High(OFFERED_MODES) do
    cmbMode.Items.Add(THamlibModeCodec.ToDisplayString(OFFERED_MODES[i]));
  cmbMode.ItemIndex := 0;
end;

{ ------------------------------------------------------------------
  Event forwarding / イベント転送
  ------------------------------------------------------------------ }

procedure TMainForm.AutoConnect(AModel: Integer; const APort: string);
begin
  edtModel.Value := AModel;
  cmbPort.Text   := APort;
  FPresenter.Connect(AModel, APort, 'default');
end;

procedure TMainForm.ConnectClick(Sender: TObject);
const
  POLICY_NAMES: array[0..3] of string = ('default', 'fast', 'slow', 'veryslow');
var
  Info:   TRigModelInfo;
  Number: Integer;
begin
  if btnConnect.Caption = 'Disconnect' then
  begin
    FPresenter.Disconnect;
    Exit;
  end;

  { The catalogue selection wins when there is one; otherwise the
    number the operator typed. Which of the two is in play is decided by
    SetUiMode/ShowRigList, not here.
    カタログの選択があればそれを、無ければオペレータが入力した番号を
    使います。どちらが有効かは SetUiMode/ShowRigList が決めます。 }
  if FPresenter.TryGetModel(cmbRig.ItemIndex, Info) then
    Number := Info.ModelNumber
  else
    Number := edtModel.Value;

  FPresenter.Connect(Number, cmbPort.Text,
                     POLICY_NAMES[cmbPolicy.ItemIndex]);
end;

procedure TMainForm.QsyClick(Sender: TObject);
var
  MHz: Double;
begin
  { TryStrToFloat, not StrToFloat: a typo must not raise out of an
    OnClick. Everything beyond "is it a number" is the presenter's and
    the component's business.
    StrToFloat ではなく TryStrToFloat です。打ち間違いが OnClick から
    例外を出してはなりません。「数値か否か」を超える判断は presenter と
    コンポーネントの仕事です。 }
  if not TryStrToFloat(Trim(edtFreqMHz.Text), MHz) then
  begin
    ShowNotice(rnlError, 'Enter a frequency in MHz, for example 14.074');
    Exit;
  end;
  FPresenter.SetFrequency(MHz * 1.0e6);
end;

procedure TMainForm.SetModeClick(Sender: TObject);
begin
  FPresenter.SetMode(OFFERED_MODES[cmbMode.ItemIndex], edtPassband.Value);
end;

procedure TMainForm.PttOnClick(Sender: TObject);
begin
  FPresenter.SetPtt(True);
end;

procedure TMainForm.PttOffClick(Sender: TObject);
begin
  FPresenter.SetPtt(False);
end;

procedure TMainForm.ReadClick(Sender: TObject);
begin
  FPresenter.RequestFrequency;
  FPresenter.RequestMode;
end;

procedure TMainForm.CancelClick(Sender: TObject);
begin
  FPresenter.CancelPendingRead;
end;

procedure TMainForm.RefreshTick(Sender: TObject);
begin
  FPresenter.RefreshFromSnapshot;
end;

{ ------------------------------------------------------------------
  IRigView — display only
  IRigView - 表示のみ
  ------------------------------------------------------------------ }

procedure TMainForm.ShowRigList(const AItems: array of string;
                                 AEnumerationAvailable: Boolean);
var
  i: Integer;
begin
  cmbRig.Items.BeginUpdate;
  try
    cmbRig.Items.Clear;
    for i := Low(AItems) to High(AItems) do
      cmbRig.Items.Add(AItems[i]);
  finally
    cmbRig.Items.EndUpdate;
  end;

  if AEnumerationAvailable and (cmbRig.Items.Count > 0) then
    cmbRig.ItemIndex := 0;

  { Exactly one of the two selectors is usable, so the operator is not
    offered a choice that will be ignored.
    2 つの選択手段のうち使えるのは常に片方だけにし、無視される選択を
    オペレータに提示しません。 }
  cmbRig.Enabled   := AEnumerationAvailable;
  edtModel.Enabled := not AEnumerationAvailable;
end;

procedure TMainForm.ShowFrequency(AHz: Double);
begin
  if AHz <= 0 then
    lblFreqBig.Caption := '—'
  else
    lblFreqBig.Caption := FormatFloat('#,##0.000000', AHz / 1.0e6);
end;

procedure TMainForm.ShowMode(AMode: TRigMode; APassbandHz: Integer);
begin
  if APassbandHz > 0 then
    lblModeBig.Caption := Format('%s / %d Hz',
      [THamlibModeCodec.ToDisplayString(AMode), APassbandHz])
  else
    lblModeBig.Caption := THamlibModeCodec.ToDisplayString(AMode);
end;

procedure TMainForm.ShowPtt(AActive: Boolean);
begin
  if AActive then
  begin
    shpPtt.Brush.Color := clRed;
    lblPttText.Caption := 'TX';
  end
  else
  begin
    shpPtt.Brush.Color := clGray;
    lblPttText.Caption := 'RX';
  end;
end;

procedure TMainForm.SetUiMode(AMode: TRigUiMode);
var
  Live: Boolean;
begin
  Live := (AMode = ruiConnected);

  { Selectors are locked while a link exists, so the operator cannot
    change the rig under a running connection.
    リンクがある間は選択をロックし、接続中にオペレータが機種を変えられ
    ないようにします。 }
  cmbPort.Enabled   := (AMode = ruiDisconnected);
  cmbPolicy.Enabled := (AMode = ruiDisconnected);
  cmbRig.Enabled    := (AMode = ruiDisconnected) and (cmbRig.Items.Count > 0);
  edtModel.Enabled  := (AMode = ruiDisconnected) and (cmbRig.Items.Count = 0);

  btnConnect.Enabled := (AMode <> ruiConnecting);
  if Live then
    btnConnect.Caption := 'Disconnect'
  else
    btnConnect.Caption := 'Connect';

  btnQsy.Enabled      := Live;
  btnSetMode.Enabled  := Live;
  btnPttOn.Enabled    := Live;
  btnPttOff.Enabled   := Live;
  btnRead.Enabled     := Live;
  btnCancel.Enabled   := Live;
  edtFreqMHz.Enabled  := Live;
  cmbMode.Enabled     := Live;
  edtPassband.Enabled := Live;
end;

procedure TMainForm.ShowNotice(ALevel: TRigNoticeLevel; const AText: string);
begin
  lblStatus.Caption := AText;
  case ALevel of
    rnlInfo:    lblStatus.Font.Color := clWindowText;
    rnlWarning: lblStatus.Font.Color := clOlive;
    rnlError:   lblStatus.Font.Color := clRed;
  end;
end;

procedure TMainForm.ShowLibraryInfo(const AText: string);
begin
  lblLibrary.Caption := AText;
end;

procedure TMainForm.ShowQueueDepth(ADepth: Integer; ABreakerOpen: Boolean);
begin
  if ABreakerOpen then
    lblQueue.Caption := Format('queue %d — paused after repeated failures',
                               [ADepth])
  else
    lblQueue.Caption := Format('queue %d', [ADepth]);
end;

end.
