{
  HamlibTimeoutPolicy.pas

  Predefined hardware timeout policies and validation helpers.
  Application code typically uses one of the predefined profiles
  (RigPolicy_Default, RigPolicy_FastUsb, RigPolicy_SlowCat,
  RigPolicy_VerySlowCat) and passes it to the factory or
  IRigService.ApplyTimeoutPolicy.

  ハードウェアタイムアウトの定義済みプロファイルとバリデーションヘルパー。
  アプリケーションコードは通常、定義済みプロファイル (RigPolicy_Default、
  RigPolicy_FastUsb、RigPolicy_SlowCat、RigPolicy_VerySlowCat) のいずれかを
  使い、ファクトリまたは IRigService.ApplyTimeoutPolicy に渡します。

  Layer:    L2
  Depends:  HamlibInterfaces
}
unit HamlibTimeoutPolicy;

{$mode objfpc}{$H+}

interface

uses
  HamlibInterfaces;

{ ====================================================================
  Predefined profiles
  定義済みプロファイル
  ==================================================================== }

{ Default policy — generic safe values. Suitable for most modern
  USB-CDC and reasonably fast RS-232 rigs.
  デフォルトポリシー — 一般的に安全な値です。多くの現代的な USB-CDC
  リグおよび適度に速い RS-232 リグに適しています。 }
function RigPolicy_Default: TRigTimeoutPolicy;

{ Fast USB policy — for IC-7300, FT-991A, TS-890S, etc.
  Aggressive timeouts for snappy UI response.
  高速 USB ポリシー — IC-7300、FT-991A、TS-890S 等向け。
  キビキビした UI 応答のための積極的なタイムアウト。 }
function RigPolicy_FastUsb: TRigTimeoutPolicy;

{ Slow CAT policy — for FT-817, TS-570D, and similar 9600bps RS-232
  rigs. More forgiving timeouts.
  低速 CAT ポリシー — FT-817、TS-570D 等の 9600bps RS-232 リグ向け。
  寛容なタイムアウト。 }
function RigPolicy_SlowCat: TRigTimeoutPolicy;

{ Very slow CAT policy — for IC-706 family on a CI-V bus, 4800bps
  rigs, or any setup with multiple devices on a shared CAT bus.
  Uses adaptive Circuit Breaker to avoid false trips on intermittent
  delays.
  非常に低速な CAT ポリシー — IC-706 系列の CI-V バス、4800bps リグ、
  または共有 CAT バスに複数機器がある環境向け。間欠的遅延での誤 Trip を
  避けるため適応的 Circuit Breaker を使用。 }
function RigPolicy_VerySlowCat: TRigTimeoutPolicy;

{ ====================================================================
  Validation
  バリデーション
  ==================================================================== }

{ Validate a policy. Returns False and sets AErrorMsg if any field
  is out of acceptable range.
  ポリシーをバリデートします。フィールドが許容範囲外の場合 False を
  返し AErrorMsg にメッセージを設定します。 }
function ValidatePolicy(const APolicy: TRigTimeoutPolicy;
                         out AErrorMsg: string): Boolean;

implementation

uses
  SysUtils;

function RigPolicy_Default: TRigTimeoutPolicy;
begin
  Result.CommandTimeoutMs       := 2000;
  Result.ConnectTimeoutMs       := 5000;
  Result.CbStrategy             := cbsFixed;
  Result.CbFixedThreshold       := 5;
  Result.CbAdaptiveWindowSize   := 0;
  Result.CbAdaptiveFailureRate  := 0;
  Result.CbRecoveryMs           := 10000;
  Result.PollIntervalMs         := 200;
  Result.FreqChangeThresholdHz  := 1.0;
end;

function RigPolicy_FastUsb: TRigTimeoutPolicy;
begin
  Result := RigPolicy_Default;
  Result.CommandTimeoutMs      := 800;
  Result.ConnectTimeoutMs      := 3000;
  Result.CbFixedThreshold      := 3;
  Result.CbRecoveryMs          := 5000;
  Result.PollIntervalMs        := 150;
  Result.FreqChangeThresholdHz := 1.0;
end;

function RigPolicy_SlowCat: TRigTimeoutPolicy;
begin
  Result := RigPolicy_Default;
  Result.CommandTimeoutMs      := 3000;
  Result.ConnectTimeoutMs      := 8000;
  Result.CbFixedThreshold      := 5;
  Result.CbRecoveryMs          := 15000;
  Result.PollIntervalMs        := 350;
  Result.FreqChangeThresholdHz := 5.0;
end;

function RigPolicy_VerySlowCat: TRigTimeoutPolicy;
begin
  Result := RigPolicy_Default;
  Result.CommandTimeoutMs       := 4000;
  Result.ConnectTimeoutMs       := 15000;
  Result.CbStrategy             := cbsAdaptive;
  Result.CbAdaptiveWindowSize   := 10;
  Result.CbAdaptiveFailureRate  := 0.7;
  Result.CbRecoveryMs           := 30000;
  Result.PollIntervalMs         := 800;
  Result.FreqChangeThresholdHz  := 10.0;
end;

function ValidatePolicy(const APolicy: TRigTimeoutPolicy;
                         out AErrorMsg: string): Boolean;
begin
  Result    := False;
  AErrorMsg := '';

  if APolicy.CommandTimeoutMs < 200 then
  begin
    AErrorMsg := 'CommandTimeoutMs must be at least 200ms';
    Exit;
  end;

  if APolicy.CommandTimeoutMs > 60000 then
  begin
    AErrorMsg := 'CommandTimeoutMs must not exceed 60000ms';
    Exit;
  end;

  if APolicy.ConnectTimeoutMs < 1000 then
  begin
    AErrorMsg := 'ConnectTimeoutMs must be at least 1000ms';
    Exit;
  end;

  if APolicy.PollIntervalMs < 50 then
  begin
    AErrorMsg := 'PollIntervalMs must be at least 50ms';
    Exit;
  end;

  if APolicy.CbStrategy = cbsFixed then
  begin
    if APolicy.CbFixedThreshold < 1 then
    begin
      AErrorMsg := 'CbFixedThreshold must be at least 1';
      Exit;
    end;
  end
  else if APolicy.CbStrategy = cbsAdaptive then
  begin
    if APolicy.CbAdaptiveWindowSize < 3 then
    begin
      AErrorMsg := 'CbAdaptiveWindowSize must be at least 3';
      Exit;
    end;
    if (APolicy.CbAdaptiveFailureRate <= 0)
       or (APolicy.CbAdaptiveFailureRate > 1.0) then
    begin
      AErrorMsg := 'CbAdaptiveFailureRate must be in (0.0, 1.0]';
      Exit;
    end;
  end;

  if APolicy.CbRecoveryMs < 1000 then
  begin
    AErrorMsg := 'CbRecoveryMs must be at least 1000ms';
    Exit;
  end;

  if APolicy.FreqChangeThresholdHz < 0 then
  begin
    AErrorMsg := 'FreqChangeThresholdHz must be non-negative';
    Exit;
  end;

  Result := True;
end;

end.
