{
  DxMainForm.pas

  TDxForm — the DxPanel window. Implements IDxView and does nothing
  else: place controls, assign to them, forward events.

  TDxForm - DxPanel のウィンドウ。IDxView を実装し、それ以外は何もし
  ません。コントロールを配置し、代入し、イベントを転送します。

  The one thing this form does that the first sample's did not is paint:
  an S-meter is a picture, and there is no stock LCL control that draws
  one. Painting is still presentation — PaintMeter reads two fields the
  presenter gave it and draws them. It takes no decision about the rig.

  本フォームが最初のサンプルと違う唯一の点は「描画」です。S メータは
  図であり、それを描く標準の LCL コントロールはありません。描画も
  表示の仕事です。PaintMeter は presenter が与えた 2 つのフィールドを
  読んで描くだけで、リグについて何も判断しません。

  Layer:    demo2 (application, LCL)
  Depends:  LCL, HamlibInterfaces, HamlibVfoCodec, DxPanelView,
            DxPanelPresenter, DxSplitSequence
}
unit DxMainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Graphics, Spin,
  HamlibInterfaces, HamlibVfoCodec,
  DxPanelView, DxPanelPresenter, DxSplitSequence;

type
  TDxForm = class(TForm, IDxView)
  private
    { ---- connection row / 接続行 ---- }
    cmbRig:      TComboBox;
    edtModel:    TSpinEdit;
    cmbPort:     TComboBox;
    cmbPolicy:   TComboBox;
    btnConnect:  TButton;

    { ---- the split workflow / スプリット作業 ---- }
    edtRxMHz:    TEdit;
    edtTxMHz:    TEdit;
    btnSetup:    TButton;
    btnAbort:    TButton;
    btnClear:    TButton;
    barProgress: TProgressBar;
    lblProgress: TLabel;
    lblOutcome:  TLabel;

    { ---- displays / 表示 ---- }
    lblRxBig:    TLabel;
    lblTxBig:    TLabel;
    lblVfo:      TLabel;
    pbMeter:     TPaintBox;
    lblMeter:    TLabel;

    { ---- individual controls / 個別操作 ---- }
    btnToggle:   TButton;
    trkPower:    TTrackBar;
    lblPower:    TLabel;
    chkNb:       TCheckBox;

    { ---- diagnostics / 診断 ---- }
    memCaps:     TMemo;
    lblStatus:   TLabel;
    lblLibrary:  TLabel;
    lblQueue:    TLabel;

    tmrMeter:    TTimer;
    tmrState:    TTimer;

    FPresenter:  TDxPresenter;

    { What PaintMeter draws. Written only by ShowSignal.
      PaintMeter が描く内容。書き込むのは ShowSignal だけです。 }
    FMeterDb:    Integer;
    FMeterValid: Boolean;

    { A TForm's lifetime belongs to its owner, not to a reference
      count. Handing IDxView to the presenter must therefore not make
      the presenter an owner.
      TForm の寿命は参照カウントではなく所有者に属します。したがって
      IDxView を presenter に渡すことで presenter を所有者にしては
      なりません。 }
    function  _AddRef: LongInt; cdecl;
    function  _Release: LongInt; cdecl;

    procedure BuildControls;
    procedure FillStaticLists;
    function  ChosenModel: Integer;

    { ---- event forwarding, one line each / イベント転送、各 1 行 ---- }
    procedure ConnectClick(Sender: TObject);
    procedure SetupClick(Sender: TObject);
    procedure AbortClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    procedure ToggleClick(Sender: TObject);
    procedure PowerChange(Sender: TObject);
    procedure NbClick(Sender: TObject);
    procedure MeterTick(Sender: TObject);
    procedure StateTick(Sender: TObject);
    procedure PaintMeter(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;

    { Scripted start, for the screenshot script and as a smoke test:
        ./DxPanel --model=1 --port=
      自動起動。スクリーンショット取得とスモークテスト用。 }
    procedure AutoConnect(AModel: Integer; const APort: string);
    procedure AutoSetup(ARxMHz, ATxMHz: Double);

    { ---- IDxView ---- }
    procedure ShowRigList(const AItems: array of string;
                          AEnumerationAvailable: Boolean);
    procedure ShowRxFrequency(AHz: Double);
    procedure ShowTxFrequency(ASplitOn: Boolean; ATxVfo: TRigVfo;
                              AHz: Double);
    procedure ShowSelectedVfo(AVfo: TRigVfo; ARawVfo: Integer);
    procedure ShowSignal(ADb: Integer; AValid: Boolean);
    procedure ShowSequenceProgress(AStepIndex, AStepCount: Integer;
                                   const ACaption: string);
    procedure ShowSequenceOutcome(ASucceeded: Boolean;
                                  const AMessage: string);
    procedure ShowCapabilities(const ALines: array of string);
    procedure SetUiMode(AMode: TDxUiMode);
    procedure ShowNotice(ALevel: TDxNoticeLevel; const AText: string);
    procedure ShowLibraryInfo(const AText: string);
    procedure ShowQueueDepth(ADepth: Integer; ABreakerOpen: Boolean);
  end;

implementation

const
  { The S-meter's span, in dB relative to S9. Hamlib's
    RIG_LEVEL_STRENGTH is defined that way, so S9 is 0 and S1 is -48
    at the conventional 6 dB per S unit.

    S メータの範囲。S9 を基準とした dB です。Hamlib の
    RIG_LEVEL_STRENGTH がそう定義されているため、S9 が 0、慣例の
    1 S 単位 6 dB では S1 が -48 になります。 }
  METER_MIN_DB = -54;
  METER_MAX_DB =  60;

{ ------------------------------------------------------------------
  Construction / 構築
  ------------------------------------------------------------------ }

constructor TDxForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption      := 'DxPanel — split operation';
  Width        := 760;
  Height       := 640;
  Position     := poScreenCenter;
  BorderStyle  := bsSingle;
  FMeterValid  := False;

  BuildControls;
  FillStaticLists;

  FPresenter := TDxPresenter.Create(Self as IDxView);
  FPresenter.Initialise;
end;

destructor TDxForm.Destroy;
begin
  { The timers stop before the presenter goes, or a tick could call a
    freed object.
    presenter より先にタイマを止めます。さもないとティックが解放済み
    オブジェクトを呼びえます。 }
  if Assigned(tmrMeter) then tmrMeter.Enabled := False;
  if Assigned(tmrState) then tmrState.Enabled := False;
  FreeAndNil(FPresenter);
  inherited Destroy;
end;

function TDxForm._AddRef: LongInt; cdecl;
begin
  Result := -1;
end;

function TDxForm._Release: LongInt; cdecl;
begin
  Result := -1;
end;

{ ------------------------------------------------------------------
  Control placement. Tedious and uninteresting, which is the point:
  everything interesting is in the presenter.
  コントロール配置。退屈で面白みがありません。それが要点です。
  面白いものはすべて presenter にあります。
  ------------------------------------------------------------------ }

procedure TDxForm.BuildControls;

  function MakeLabel(const ACaption: string; L, T: Integer;
                     ABold: Boolean = False): TLabel;
  begin
    Result         := TLabel.Create(Self);
    Result.Parent  := Self;
    Result.Left    := L;
    Result.Top     := T;
    Result.Caption := ACaption;
    if ABold then
      Result.Font.Style := [fsBold];
  end;

begin
  { ---- connection ---- }
  MakeLabel('Rig', 12, 14);
  cmbRig        := TComboBox.Create(Self);
  cmbRig.Parent := Self;
  cmbRig.SetBounds(44, 10, 300, 24);
  cmbRig.Style  := csDropDownList;

  MakeLabel('or model #', 352, 14);
  edtModel        := TSpinEdit.Create(Self);
  edtModel.Parent := Self;
  edtModel.SetBounds(424, 10, 70, 24);
  edtModel.MinValue := 0;
  edtModel.MaxValue := 99999;
  edtModel.Value    := 1;

  MakeLabel('Port', 504, 14);
  cmbPort        := TComboBox.Create(Self);
  cmbPort.Parent := Self;
  cmbPort.SetBounds(536, 10, 120, 24);

  MakeLabel('Link', 12, 46);
  cmbPolicy        := TComboBox.Create(Self);
  cmbPolicy.Parent := Self;
  cmbPolicy.SetBounds(44, 42, 140, 24);
  cmbPolicy.Style  := csDropDownList;

  btnConnect        := TButton.Create(Self);
  btnConnect.Parent := Self;
  btnConnect.SetBounds(200, 42, 110, 26);
  btnConnect.Caption := 'Connect';
  btnConnect.OnClick := @ConnectClick;

  lblLibrary := MakeLabel('', 320, 48);
  lblLibrary.Font.Color := clGray;

  { ---- big display ---- }
  MakeLabel('RX', 12, 86, True);
  lblRxBig := MakeLabel('—', 44, 80);
  lblRxBig.Font.Size  := 20;
  lblRxBig.Font.Style := [fsBold];

  MakeLabel('TX', 300, 86, True);
  lblTxBig := MakeLabel('—', 332, 80);
  lblTxBig.Font.Size  := 20;
  lblTxBig.Font.Style := [fsBold];

  lblVfo := MakeLabel('VFO: —', 12, 122);
  lblVfo.Font.Color := clNavy;

  { ---- S-meter ---- }
  MakeLabel('S', 12, 150, True);
  pbMeter        := TPaintBox.Create(Self);
  pbMeter.Parent := Self;
  pbMeter.SetBounds(32, 146, 560, 28);
  pbMeter.OnPaint := @PaintMeter;

  lblMeter := MakeLabel('no reading', 604, 152);

  { ---- split workflow ---- }
  MakeLabel('Split setup', 12, 194, True);

  MakeLabel('RX MHz', 12, 222);
  edtRxMHz        := TEdit.Create(Self);
  edtRxMHz.Parent := Self;
  edtRxMHz.SetBounds(70, 218, 100, 24);
  edtRxMHz.Text   := '14.023';

  MakeLabel('TX MHz', 184, 222);
  edtTxMHz        := TEdit.Create(Self);
  edtTxMHz.Parent := Self;
  edtTxMHz.SetBounds(242, 218, 100, 24);
  edtTxMHz.Text   := '14.205';

  btnSetup        := TButton.Create(Self);
  btnSetup.Parent := Self;
  btnSetup.SetBounds(356, 217, 120, 26);
  btnSetup.Caption := 'Set up split';
  btnSetup.OnClick := @SetupClick;

  btnAbort        := TButton.Create(Self);
  btnAbort.Parent := Self;
  btnAbort.SetBounds(484, 217, 80, 26);
  btnAbort.Caption := 'Abort';
  btnAbort.OnClick := @AbortClick;

  btnClear        := TButton.Create(Self);
  btnClear.Parent := Self;
  btnClear.SetBounds(572, 217, 110, 26);
  btnClear.Caption := 'Split off';
  btnClear.OnClick := @ClearClick;

  barProgress        := TProgressBar.Create(Self);
  barProgress.Parent := Self;
  barProgress.SetBounds(12, 252, 300, 18);
  barProgress.Min    := 0;
  barProgress.Max    := TDxSplitSequence.StepCount;

  lblProgress := MakeLabel('idle', 320, 252);

  lblOutcome := MakeLabel('', 12, 278);
  lblOutcome.AutoSize := False;
  lblOutcome.SetBounds(12, 278, 710, 34);
  lblOutcome.WordWrap := True;

  { ---- individual controls ---- }
  MakeLabel('Controls', 12, 320, True);

  btnToggle        := TButton.Create(Self);
  btnToggle.Parent := Self;
  btnToggle.SetBounds(12, 342, 110, 26);
  btnToggle.Caption := 'VFO A/B';
  btnToggle.OnClick := @ToggleClick;

  MakeLabel('RF power', 136, 346);
  trkPower        := TTrackBar.Create(Self);
  trkPower.Parent := Self;
  trkPower.SetBounds(196, 340, 180, 30);
  trkPower.Min    := 0;
  trkPower.Max    := 100;
  trkPower.Position := 50;
  trkPower.Frequency := 10;
  trkPower.OnChange  := @PowerChange;

  lblPower := MakeLabel('50 %', 382, 346);

  chkNb        := TCheckBox.Create(Self);
  chkNb.Parent := Self;
  chkNb.SetBounds(440, 344, 160, 22);
  chkNb.Caption := 'Noise blanker';
  chkNb.OnClick := @NbClick;

  { ---- diagnostics ---- }
  MakeLabel('What the library will say about this model', 12, 382, True);
  memCaps        := TMemo.Create(Self);
  memCaps.Parent := Self;
  memCaps.SetBounds(12, 402, 710, 150);
  memCaps.ReadOnly   := True;
  memCaps.ScrollBars := ssAutoVertical;
  memCaps.Font.Name  := 'Monospace';
  memCaps.Font.Size  := 9;

  lblStatus := MakeLabel('', 12, 562);
  lblStatus.AutoSize := False;
  lblStatus.SetBounds(12, 562, 710, 34);
  lblStatus.WordWrap := True;

  lblQueue := MakeLabel('', 12, 600);
  lblQueue.Font.Color := clGray;

  tmrMeter          := TTimer.Create(Self);
  tmrMeter.Interval := 250;
  tmrMeter.Enabled  := False;
  tmrMeter.OnTimer  := @MeterTick;

  tmrState          := TTimer.Create(Self);
  tmrState.Interval := 500;
  tmrState.Enabled  := False;
  tmrState.OnTimer  := @StateTick;

  OnCloseQuery := @FormCloseQuery;
end;

procedure TDxForm.FillStaticLists;
begin
  cmbPort.Items.Add('');
  cmbPort.Items.Add('/dev/ttyUSB0');
  cmbPort.Items.Add('/dev/ttyACM0');
  cmbPort.Items.Add('COM3');
  cmbPort.ItemIndex := 0;

  cmbPolicy.Items.Add('default');
  cmbPolicy.Items.Add('fast');
  cmbPolicy.Items.Add('slow');
  cmbPolicy.Items.Add('veryslow');
  cmbPolicy.ItemIndex := 0;
end;

{ ------------------------------------------------------------------
  Painting the meter / メータの描画
  ------------------------------------------------------------------ }

procedure TDxForm.PaintMeter(Sender: TObject);
var
  C:        TCanvas;
  W, H, X:  Integer;
  Db:       Integer;
  S:        Integer;
  Tick:     Integer;
begin
  C := pbMeter.Canvas;
  W := pbMeter.Width;
  H := pbMeter.Height;

  C.Brush.Color := clBtnFace;
  C.FillRect(0, 0, W, H);
  C.Pen.Color := clGray;
  C.Rectangle(0, 0, W, H);

  { The scale: S1..S9 at 6 dB each, then +20/+40/+60 over S9. Drawn
    even with no reading, so the operator can see the panel is alive.
    目盛。S1〜S9 は各 6 dB、その上に S9+20/+40/+60。読み取りがなくても
    描きます。パネルが生きていることが分かるようにです。 }
  C.Font.Size  := 6;
  C.Font.Color := clBlack;
  for S := 1 to 9 do
  begin
    Db   := -54 + S * 6;
    Tick := Round((Db - METER_MIN_DB) / (METER_MAX_DB - METER_MIN_DB) * W);
    C.Pen.Color := clGray;
    C.Line(Tick, H - 6, Tick, H - 1);
    C.TextOut(Tick - 2, H - 16, IntToStr(S));
  end;
  for S := 20 to 60 do
    if S mod 20 = 0 then
    begin
      Tick := Round((S - METER_MIN_DB) / (METER_MAX_DB - METER_MIN_DB) * W);
      C.Pen.Color := clRed;
      C.Line(Tick, H - 6, Tick, H - 1);

      { The last label sits on the right edge, where a centred caption
        is half outside the control and reads as "+". Nudging it in is
        not a style preference: a clipped scale label is a scale the
        operator cannot read.
        最後のラベルは右端にあり、中央揃えでは半分が外へ出て「+」と
        しか読めません。内側へ寄せるのは好みの問題ではありません。
        切れた目盛ラベルは、オペレータが読めない目盛です。 }
      if Tick > W - 20 then
        C.TextOut(W - 20, H - 16, '+' + IntToStr(S))
      else
        C.TextOut(Tick - 6, H - 16, '+' + IntToStr(S));
    end;

  if not FMeterValid then
    Exit;

  { Clamp rather than discard: a rig that answers +70 dB is reporting a
    strong signal, not an error, and a bar drawn past the end of the
    control is a drawing bug rather than information.
    捨てずに切り詰めます。+70 dB と答えるリグは強い信号を報告している
    のであり誤りではありません。そしてコントロールの外まで描かれた棒は
    情報ではなく描画上の不具合です。 }
  Db := FMeterDb;
  if Db < METER_MIN_DB then Db := METER_MIN_DB;
  if Db > METER_MAX_DB then Db := METER_MAX_DB;

  X := Round((Db - METER_MIN_DB) / (METER_MAX_DB - METER_MIN_DB) * (W - 2));
  if FMeterDb > 0 then
    C.Brush.Color := clRed       { over S9 }
  else
    C.Brush.Color := clGreen;
  C.FillRect(1, 1, 1 + X, H - 17);
end;

{ ------------------------------------------------------------------
  Event forwarding / イベント転送
  ------------------------------------------------------------------ }

function TDxForm.ChosenModel: Integer;
var
  Info: TRigModelInfo;
begin
  if (cmbRig.ItemIndex >= 0)
     and FPresenter.TryGetModel(cmbRig.ItemIndex, Info) then
    Result := Info.ModelNumber
  else
    Result := edtModel.Value;
end;

procedure TDxForm.ConnectClick(Sender: TObject);
begin
  if btnConnect.Caption = 'Disconnect' then
  begin
    FPresenter.Disconnect;
    Exit;
  end;
  FPresenter.Connect(ChosenModel, cmbPort.Text, cmbPolicy.Text);
end;

procedure TDxForm.SetupClick(Sender: TObject);
begin
  FPresenter.StartSplitSetup(StrToFloatDef(edtRxMHz.Text, 0),
                             StrToFloatDef(edtTxMHz.Text, 0));
end;

procedure TDxForm.AbortClick(Sender: TObject);
begin
  FPresenter.AbortSplitSetup;
end;

procedure TDxForm.ClearClick(Sender: TObject);
begin
  FPresenter.ClearSplit;
end;

procedure TDxForm.ToggleClick(Sender: TObject);
begin
  FPresenter.ToggleVfo;
end;

procedure TDxForm.PowerChange(Sender: TObject);
begin
  lblPower.Caption := IntToStr(trkPower.Position) + ' %';
  FPresenter.SetRfPowerPercent(trkPower.Position);
end;

procedure TDxForm.NbClick(Sender: TObject);
begin
  FPresenter.SetNoiseBlanker(chkNb.Checked);
end;

procedure TDxForm.MeterTick(Sender: TObject);
begin
  FPresenter.MeterTick;
end;

procedure TDxForm.StateTick(Sender: TObject);
begin
  FPresenter.StateTick;
end;

procedure TDxForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  { Teardown happens here rather than in the destructor so that the
    component's Close runs while the LCL is still able to deliver the
    callbacks it queues.
    終了処理をデストラクタではなくここで行います。コンポーネントの
    Close が、LCL がまだキュー済みコールバックを配送できるうちに走る
    ようにするためです。 }
  tmrMeter.Enabled := False;
  tmrState.Enabled := False;
  FPresenter.Disconnect;
  CanClose := True;
end;

{ ------------------------------------------------------------------
  IDxView — assignments only / 代入のみ
  ------------------------------------------------------------------ }

procedure TDxForm.ShowRigList(const AItems: array of string;
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

  cmbRig.Enabled   := AEnumerationAvailable;
  edtModel.Enabled := not AEnumerationAvailable;
  if AEnumerationAvailable and (cmbRig.Items.Count > 0) then
    cmbRig.ItemIndex := 0;
end;

procedure TDxForm.ShowRxFrequency(AHz: Double);
begin
  if AHz <= 0 then
    lblRxBig.Caption := '—'
  else
    lblRxBig.Caption := FormatFloat('0.000000', AHz / 1E6);
end;

procedure TDxForm.ShowTxFrequency(ASplitOn: Boolean; ATxVfo: TRigVfo;
                                   AHz: Double);
begin
  if not ASplitOn then
  begin
    { Never a stale number here. "= RX" is the whole message: transmit
      follows receive.
      ここに古い数値を残しません。「= RX」がメッセージのすべてです。
      送信は受信に追従します。 }
    lblTxBig.Caption    := '= RX';
    lblTxBig.Font.Color := clWindowText;
    Exit;
  end;

  lblTxBig.Font.Color := clRed;
  if AHz <= 0 then
    lblTxBig.Caption := 'split (' + RigVfoToString(ATxVfo) + ')'
  else
    lblTxBig.Caption := FormatFloat('0.000000', AHz / 1E6);
end;

procedure TDxForm.ShowSelectedVfo(AVfo: TRigVfo; ARawVfo: Integer);
begin
  if ARawVfo = 0 then
    lblVfo.Caption := 'VFO: ' + RigVfoToString(AVfo)
  else
    lblVfo.Caption := Format('VFO: %s   (the rig answered vfo_t $%s)',
                             [RigVfoToString(AVfo), HexStr(ARawVfo, 8)]);
end;

procedure TDxForm.ShowSignal(ADb: Integer; AValid: Boolean);
begin
  FMeterDb    := ADb;
  FMeterValid := AValid;
  if AValid then
    lblMeter.Caption := Format('%d dB rel. S9', [ADb])
  else
    lblMeter.Caption := 'no reading';
  pbMeter.Invalidate;
end;

procedure TDxForm.ShowSequenceProgress(AStepIndex, AStepCount: Integer;
                                        const ACaption: string);
begin
  barProgress.Max      := AStepCount;
  barProgress.Position := AStepIndex;
  if AStepIndex = 0 then
    lblProgress.Caption := ACaption
  else
    lblProgress.Caption := Format('%d / %d  %s',
                                  [AStepIndex, AStepCount, ACaption]);
end;

procedure TDxForm.ShowSequenceOutcome(ASucceeded: Boolean;
                                       const AMessage: string);
begin
  lblOutcome.Caption := AMessage;
  if ASucceeded then
    lblOutcome.Font.Color := clGreen
  else
    lblOutcome.Font.Color := clRed;
  lblOutcome.Font.Style := [fsBold];
end;

procedure TDxForm.ShowCapabilities(const ALines: array of string);
var
  i: Integer;
begin
  memCaps.Lines.BeginUpdate;
  try
    memCaps.Lines.Clear;
    for i := Low(ALines) to High(ALines) do
      memCaps.Lines.Add(ALines[i]);
  finally
    memCaps.Lines.EndUpdate;
  end;
end;

procedure TDxForm.SetUiMode(AMode: TDxUiMode);
var
  Live:     Boolean;
  Selecting: Boolean;
begin
  Live      := AMode = duiConnected;
  Selecting := AMode = duiDisconnected;

  cmbRig.Enabled    := Selecting and (cmbRig.Items.Count > 0);
  edtModel.Enabled  := Selecting and (cmbRig.Items.Count = 0);
  cmbPort.Enabled   := Selecting;
  cmbPolicy.Enabled := Selecting;
  btnConnect.Enabled := AMode <> duiConnecting;

  case AMode of
    duiDisconnected:  btnConnect.Caption := 'Connect';
    duiConnecting:    btnConnect.Caption := 'Connecting...';
  else
    btnConnect.Caption := 'Disconnect';
  end;

  edtRxMHz.Enabled  := Live;
  edtTxMHz.Enabled  := Live;
  btnSetup.Enabled  := Live;
  btnClear.Enabled  := Live;
  btnToggle.Enabled := Live;
  trkPower.Enabled  := Live;
  chkNb.Enabled     := Live;

  { Abort is the one control that is live precisely when the others are
    not: it exists for the state the others are locked out of.
    Abort は、他が無効なときにこそ有効な唯一のコントロールです。他が
    締め出されている状態のために存在するからです。 }
  btnAbort.Enabled := AMode = duiSequenceRunning;

  tmrMeter.Enabled := AMode in [duiConnected, duiSequenceRunning];
  tmrState.Enabled := AMode in [duiConnected, duiSequenceRunning];
end;

procedure TDxForm.ShowNotice(ALevel: TDxNoticeLevel; const AText: string);
begin
  lblStatus.Caption := AText;
  case ALevel of
    dnlInfo:    lblStatus.Font.Color := clWindowText;
    dnlWarning: lblStatus.Font.Color := clOlive;
  else
    lblStatus.Font.Color := clRed;
  end;
end;

procedure TDxForm.ShowLibraryInfo(const AText: string);
begin
  lblLibrary.Caption := AText;
end;

procedure TDxForm.ShowQueueDepth(ADepth: Integer; ABreakerOpen: Boolean);
begin
  if ABreakerOpen then
    lblQueue.Caption := Format('queue %d — CIRCUIT BREAKER OPEN', [ADepth])
  else
    lblQueue.Caption := Format('queue %d', [ADepth]);
end;

{ ------------------------------------------------------------------
  Scripted start / 自動起動
  ------------------------------------------------------------------ }

procedure TDxForm.AutoConnect(AModel: Integer; const APort: string);
var
  i:    Integer;
  Info: TRigModelInfo;
begin
  edtModel.Value := AModel;
  cmbPort.Text   := APort;

  { Show the operator which catalogue entry this model number is, if
    the list has it. A panel that connects to model 1 while its rig
    selector shows nothing looks like the selector failed to load.
    一覧にあれば、その機種番号がどのカタログ項目かを表示します。
    モデル 1 に接続しながら機種選択が空のパネルは、選択肢の読み込みに
    失敗したように見えます。 }
  for i := 0 to cmbRig.Items.Count - 1 do
    if FPresenter.TryGetModel(i, Info) and (Info.ModelNumber = AModel) then
    begin
      cmbRig.ItemIndex := i;
      Break;
    end;

  FPresenter.Connect(AModel, APort, 'fast');
end;

procedure TDxForm.AutoSetup(ARxMHz, ATxMHz: Double);
begin
  edtRxMHz.Text := FormatFloat('0.000000', ARxMHz);
  edtTxMHz.Text := FormatFloat('0.000000', ATxMHz);
  FPresenter.StartSplitSetup(ARxMHz, ATxMHz);
end;

end.
