#!/usr/bin/env python3
"""
run_transport_tests.py — drive TransportTest over real transports with
faults injected on purpose.

実トランスポート上で TransportTest を駆動し、意図的に障害を注入します。

What each scenario is for / 各シナリオの目的
------------------------------------------------------------------
Everything else in this project talks to Hamlib's in-process dummy
backend, which answers in microseconds and never fails. These
scenarios put a real transport underneath and then break it:

  serial-normal   a Kenwood TS-2000 over a PTY pair — proves the
                  serial path and a real backend's protocol code are
                  reached at all
  serial-silent   the rig accepts commands and never answers — the
                  tier-1 (Hamlib's own) timeout, which a dummy rig
                  cannot exercise
  serial-slow     answers, but later than the policy allows
  serial-partial  a reply that starts and never finishes, as a
                  marginal cable produces
  serial-garbage  bytes that are not a valid CAT reply
  serial-dies     answers for a while, then the link goes quiet
                  mid-session
  net-normal      model 2 (NET rigctl) over TCP to rigctld
  net-killed      rigctld is killed mid-session

The assertion every scenario shares is the one that matters most:
**the program must finish**. A component that hangs on a dead rig is
worse than one that reports an error, because the operator has no way
to tell it apart from a slow rig. Each run is given a hard wall-clock
budget and a scenario fails if it is exceeded.

すべてのシナリオに共通し、かつ最も重要な表明はこれです。
**プログラムは必ず終了しなければならない**。死んだリグに対して停止
するコンポーネントは、エラーを報告するものより悪いものです。オペレータ
には遅いリグとの区別がつかないからです。各実行には実時間の上限を与え、
超過したシナリオは失敗とします。

Usage:
    python3 tools/run_transport_tests.py --exe PATH/TO/TransportTest
                                         [--only NAME] [--keep-logs]
"""

import argparse
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
RIGSIM = os.path.join(HERE, "rigsim.py")

MODEL_TS2000 = 2014
MODEL_NETRIGCTL = 2


class Scenario:
    def __init__(self, name, why, setup, args, expect, budget=60):
        self.name = name
        self.why = why
        self.setup = setup      # callable(workdir) -> (port, cleanup)
        self.args = args        # extra TransportTest arguments
        self.expect = expect    # callable(dict) -> list of failures
        self.budget = budget


# ------------------------------------------------------------------
# Transport setup helpers / トランスポート準備
# ------------------------------------------------------------------

def start_pty_pair(workdir):
    """A socat PTY pair: one end for the component, one for the
    simulator.
    socat の PTY 対。片方はコンポーネント、片方はシミュレータ用。"""
    rig = os.path.join(workdir, "ttyRIG")
    sim = os.path.join(workdir, "ttySIM")
    log = open(os.path.join(workdir, "socat.log"), "w")
    proc = subprocess.Popen(
        ["socat", "-d", "-d",
         f"pty,raw,echo=0,link={rig}",
         f"pty,raw,echo=0,link={sim}"],
        stdout=log, stderr=log)
    deadline = time.time() + 10
    while time.time() < deadline:
        if os.path.exists(rig) and os.path.exists(sim):
            return rig, sim, proc, log
        time.sleep(0.1)
    proc.kill()
    raise RuntimeError("socat did not create the PTY pair")


def serial_setup(mode, **simargs):
    def setup(workdir):
        rig, sim, socat_proc, socat_log = start_pty_pair(workdir)
        cmd = [sys.executable, "-I", RIGSIM, "--pty", sim,
               "--mode", mode,
               "--log", os.path.join(workdir, "rigsim.log"),
               "--duration", "120"]
        for k, v in simargs.items():
            cmd += ["--" + k.replace("_", "-"), str(v)]
        simproc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL)
        time.sleep(0.5)

        def cleanup():
            for p in (simproc, socat_proc):
                try:
                    p.terminate()
                    p.wait(timeout=5)
                except Exception:
                    p.kill()
            socat_log.close()

        return rig, cleanup, None
    return setup


def net_setup(kill_after=None):
    def setup(workdir):
        port = 4532
        log = open(os.path.join(workdir, "rigctld.log"), "w")
        proc = subprocess.Popen(
            ["rigctld", "-m", "1", "-t", str(port)],
            stdout=log, stderr=log)
        time.sleep(1.0)
        if proc.poll() is not None:
            log.close()
            raise RuntimeError("rigctld exited immediately")

        killer = None
        if kill_after is not None:
            def kill_it():
                time.sleep(kill_after)
                try:
                    proc.send_signal(signal.SIGKILL)
                except Exception:
                    pass
            import threading
            killer = threading.Thread(target=kill_it, daemon=True)
            killer.start()

        def cleanup():
            try:
                proc.kill()
                proc.wait(timeout=5)
            except Exception:
                pass
            log.close()

        return f"localhost:{port}", cleanup, None
    return setup


# ------------------------------------------------------------------
# Expectations / 期待される結果
#
# Written as functions rather than literal strings because what a real
# backend answers is not fully predictable — RIG_ENAVAIL for a level a
# model does not have is a correct answer, not a failure. What IS
# predictable, and is what each check asserts, is the SHAPE of the
# outcome: did it finish, did it report rather than hang, is the error
# kind in the set that this fault can legitimately produce.
#
# 文字列リテラルではなく関数で書きます。実バックエンドが何を答えるかは
# 完全には予測できないからです (機種が持たないレベルへの RIG_ENAVAIL は
# 失敗ではなく正しい答えです)。予測可能で、各検査が表明するのは結果の
# 「形」です。終了したか、停止せず報告したか、エラー種別がその障害から
# 正当に生じうる集合に入っているか。
# ------------------------------------------------------------------

def kind_of(value):
    """The error-kind name, which contains spaces ("not connected",
    "communication timed out"). The first version of this matched
    \S+ and reported every one of them as 'not', which made six
    scenarios fail for a reason that was in the test.

    エラー種別名。空白を含みます ("not connected" 等)。本関数の初版は
    \S+ で照合し、すべてを 'not' として報告しました。そのため 6 つの
    シナリオが、テスト側にある理由で失敗しました。 """
    m = re.search(r"kind=(.*?)(?:\s+native=|$)", value or "")
    return m.group(1).strip() if m else None


def events_of(out):
    """connects / disconnects / errors as integers."""
    text = out.get("EVENTS") or out.get("CONNECT_EVENT") or ""
    def num(name):
        m = re.search(name + r"=(\d+)", text)
        return int(m.group(1)) if m else 0
    return num("connects"), num("disconnects"), num("errors")


def expect_working(out):
    """A healthy link: open, read, write, read back the written value.
    健全な回線。接続し、読み、書き、書いた値を読み戻せること。"""
    bad = []
    if out.get("OPEN") != "ok":
        bad.append(f"OPEN should have succeeded, got {out.get('OPEN')!r}")
        return bad

    connects, disconnects, _ = events_of(out)
    if connects < 1:
        bad.append("no connection event arrived on a healthy link")
    if disconnects:
        bad.append(f"{disconnects} disconnection event(s) on a healthy link")
    if not (out.get("GETFREQ1", "").startswith("ok")):
        bad.append(f"GETFREQ1 should have succeeded, got "
                   f"{out.get('GETFREQ1')!r}")
    if out.get("SETFREQ") != "ok":
        bad.append(f"SETFREQ should have succeeded, got "
                   f"{out.get('SETFREQ')!r}")
    rb = out.get("READBACK", "")
    if not rb.startswith("ok"):
        bad.append(f"READBACK should have succeeded, got {rb!r}")
    else:
        value = float(rb.split("value=")[1])
        if abs(value - 18100000) > 1:
            bad.append(f"the frequency written did not come back: "
                       f"{value:.0f}")
    if out.get("BREAKER_FINAL") != "closed":
        bad.append("the circuit breaker opened on a healthy link")
    if out.get("CLOSE") != "ok":
        bad.append(f"CLOSE should have succeeded, got {out.get('CLOSE')!r}")
    bad.extend(typed_shapes_ok(out))
    return bad


# The error kinds a broken link may legitimately produce. The point of
# listing them is that the set is SMALL: a transport failure must not
# surface as rekInternal or rekComponentFault, which would mean the
# component blamed itself for the cable.
#
# 壊れた回線が正当に生じうるエラー種別。列挙する意義は、その集合が
# 「小さい」ことにあります。トランスポート障害が rekInternal や
# rekComponentFault として現れてはなりません。それはコンポーネントが
# ケーブルの不具合を自分のせいにしたことを意味します。
TRANSPORT_KINDS = {
    "communication timed out",
    "I/O error",
    "protocol error",
    "argument truncated",
    "bus error",
    "bus busy",
    "could not open the rig",
    "rejected by the rig",
    "function not available on this rig",
    "invalid configuration",
}

# Kinds that are a correct *consequence* of a transport fault rather
# than a description of one. They may appear, but never as the only
# thing the application was ever told, or the operator is left with
# "not connected" and no idea why.
#
# トランスポート障害の記述ではなく、その正しい「帰結」である種別。
# 現れてもよいが、アプリケーションが知らされた唯一のものであっては
# なりません。さもないとオペレータには「未接続」だけが残り、理由が
# 分かりません。
CONSEQUENCE_KINDS = {
    "not connected",
    "paused after repeated failures",
}

# The kinds that would mean the component blamed itself for the cable.
# ケーブルの不具合をコンポーネントが自分のせいにしたことを意味する種別。
SELF_BLAME_KINDS = {
    "internal component error",
    "internal Hamlib error",
    "invalid argument",
    "invalid handle",
    "out of memory",
}


def typed_shapes_ok(out):
    """Each of the four Rev.6.0 result shapes reported exactly once.
    Zero means an application waiting on that call waits forever; more
    than one means it double-counts.
    Rev.6.0 の 4 つの結果の形が、それぞれちょうど 1 回報告したか。0 は
    その呼び出しを待つアプリが永久に待つことを、2 以上は二重計上を
    意味します。"""
    text = out.get("TYPED_SHAPES")
    if text is None:
        return []           # the link never opened; nothing to check
    bad = []
    for name in ("level", "func", "split", "vfo"):
        m = re.search(name + r"=(\d+)", text)
        n = int(m.group(1)) if m else 0
        if n != 1:
            bad.append(f"the {name} result reported {n} times, not once "
                       f"({text})")
    return bad


def all_kinds(out):
    """Every error kind the application was told about, from any
    source: the connection event, a command callback, or Open.
    アプリケーションが知らされたすべてのエラー種別。接続イベント、
    コマンドのコールバック、Open のいずれからでも。"""
    seen = set()
    for key, value in out.items():
        if key in ("FIRST_ERROR", "OPEN") or key.startswith("GETFREQ") \
                or key in ("SETFREQ", "READBACK", "SETMODE", "SETSPLIT",
                           "CLEARSPLIT"):
            k = kind_of(value)
            if k:
                seen.add(k)
    return seen


def expect_reported_not_hung(out, require_failure=True):
    """The link is broken. The component must say so, name a cause the
    operator can act on, and finish.

    Three earlier versions of this checker were wrong before the
    component was. It judged Open by its return value, which is
    documented not to wait for the connection attempt; it parsed the
    error kind with \\S+ and saw every multi-word kind as "not"; and it
    compared against invented kind names instead of the ones
    RigErrorKindToString actually produces. Each time, the component
    was right and the test was not — which is the normal case for a
    new test and the reason to read a failure before believing it.

    回線が壊れています。コンポーネントはそう述べ、オペレータが行動
    できる原因を挙げ、終了しなければなりません。

    本検査は、コンポーネントより先に 3 度誤っていました。待たないと
    文書化されている Open を戻り値で判定し、エラー種別を \\S+ で解析して
    複数語の種別をすべて "not" と見て、RigErrorKindToString が実際に
    生成する名前ではなく捏造した名前と比較していました。いずれも
    コンポーネントが正しく、テストが誤っていました。新しいテストでは
    それが通常であり、失敗を信じる前に読むべき理由です。 """
    bad = []
    if out.get("VERDICT") != "completed":
        bad.append("the program did not finish")
        return bad

    connects, disconnects, errors = events_of(out)
    kinds = all_kinds(out)

    outcomes = [v for k, v in out.items() if k.startswith("GETFREQ")]
    failed = [o for o in outcomes if not o.startswith("ok")]

    # Did anything notice? Either the connection attempt was reported
    # as failed, or a command failed.
    # 何かが気づいたか。接続試行が失敗と報告されたか、コマンドが失敗
    # したか。
    noticed = (disconnects > 0) or bool(failed) or out.get("OPEN") != "ok"
    if require_failure and not noticed:
        bad.append("nothing reported a problem against a rig that was "
                   "supposed to be broken — the fault injection did not "
                   "take")
        return bad

    if any(o == "nocallback" for o in outcomes):
        bad.append("a command never produced a callback at all — the "
                   "application would wait forever")

    if noticed:
        # The cause must have reached the application somewhere.
        # Consequence kinds alone are not enough.
        # 原因はどこかでアプリケーションに届いていなければなりません。
        # 帰結の種別だけでは足りません。
        causes = kinds & TRANSPORT_KINDS
        if not causes:
            bad.append(f"the link broke and the application was never "
                       f"told a cause it could act on; it saw only "
                       f"{sorted(kinds) or 'nothing'}")

        blame = kinds & SELF_BLAME_KINDS
        if blame:
            bad.append(f"the component reported {sorted(blame)}, which "
                       f"blames itself for a broken link")

        stray = kinds - TRANSPORT_KINDS - CONSEQUENCE_KINDS
        if stray:
            bad.append(f"unexpected error kind(s) {sorted(stray)}")

    if out.get("CLOSE") not in (None, "ok"):
        bad.append(f"CLOSE did not succeed after a fault: "
                   f"{out.get('CLOSE')!r}")
    bad.extend(typed_shapes_ok(out))
    return bad


def expect_dies_midway(out):
    """Opened cleanly, then the link went away. The first reads should
    work and later ones should not — and it must still close.
    正常に接続した後、回線が消えます。最初の読み取りは成功し、後の
    ものは失敗すべきで、それでもクローズできなければなりません。"""
    bad = expect_reported_not_hung(out, require_failure=True)
    if out.get("OPEN") != "ok":
        bad.append("the link was supposed to be healthy at open time")
    return bad


SCENARIOS = [
    Scenario(
        "serial-normal",
        "a real serial path to a real backend's protocol code",
        serial_setup("normal"),
        ["--policy=slow", "--commands=3"],
        expect_working, budget=90),
    Scenario(
        "serial-silent",
        "the tier-1 timeout: a rig that accepts commands and never "
        "answers",
        serial_setup("silent"),
        ["--policy=fast", "--commands=2", "--budget-ms=15000"],
        lambda out: expect_reported_not_hung(out), budget=120),
    Scenario(
        "serial-slow",
        "a reply that arrives later than the policy allows",
        serial_setup("slow", delay=3),
        ["--policy=fast", "--commands=2", "--budget-ms=15000"],
        lambda out: expect_reported_not_hung(out, require_failure=False),
        budget=120),
    Scenario(
        "serial-partial",
        "a reply that starts and never finishes",
        serial_setup("partial"),
        ["--policy=fast", "--commands=2", "--budget-ms=15000"],
        lambda out: expect_reported_not_hung(out), budget=120),
    Scenario(
        "serial-garbage",
        "bytes that are not a valid CAT reply",
        serial_setup("garbage"),
        ["--policy=fast", "--commands=2", "--budget-ms=15000"],
        lambda out: expect_reported_not_hung(out), budget=120),
    Scenario(
        "serial-dies",
        "the link goes quiet mid-session",
        serial_setup("die-after", silent_after=4),
        ["--policy=fast", "--commands=4", "--budget-ms=15000",
         "--gap-ms=300"],
        expect_dies_midway, budget=150),
    Scenario(
        "net-normal",
        "model 2 over TCP to rigctld",
        net_setup(),
        ["--policy=default", "--commands=3"],
        expect_working, budget=90),
    Scenario(
        "net-killed",
        "rigctld killed mid-session",
        net_setup(kill_after=1.5),
        ["--policy=fast", "--commands=6", "--budget-ms=10000",
         "--gap-ms=700"],
        lambda out: expect_reported_not_hung(out), budget=120),
]


def parse_output(text):
    out = {}
    for line in text.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def run_one(sc, exe, keep_logs):
    workdir = tempfile.mkdtemp(prefix="transport-%s-" % sc.name)
    cleanup = None
    try:
        port, cleanup, _ = sc.setup(workdir)
        model = (MODEL_NETRIGCTL if sc.name.startswith("net")
                 else MODEL_TS2000)
        cmd = [exe, f"--model={model}", f"--port={port}"] + sc.args

        started = time.time()
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True,
                                  timeout=sc.budget, cwd=workdir)
            elapsed = time.time() - started
            text = proc.stdout
            timed_out = False
        except subprocess.TimeoutExpired as exc:
            elapsed = time.time() - started
            text = (exc.stdout or b"").decode() if isinstance(
                exc.stdout, bytes) else (exc.stdout or "")
            timed_out = True

        out = parse_output(text)
        failures = []
        if timed_out:
            failures.append(
                f"HUNG: still running after {sc.budget} s — a component "
                f"that never returns on a dead rig cannot be told apart "
                f"from a slow one")
        else:
            failures = sc.expect(out)

        return dict(name=sc.name, why=sc.why, elapsed=elapsed,
                    out=out, failures=failures, raw=text, workdir=workdir)
    finally:
        if cleanup:
            cleanup()
        if not keep_logs:
            shutil.rmtree(workdir, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--exe", required=True)
    ap.add_argument("--only", default=None)
    ap.add_argument("--keep-logs", action="store_true")
    args = ap.parse_args()

    if not os.path.exists(args.exe):
        print(f"no such executable: {args.exe}", file=sys.stderr)
        return 1
    for tool in ("socat", "rigctld"):
        if shutil.which(tool) is None:
            print(f"SKIP: {tool} is not installed, so the real-transport "
                  f"scenarios cannot run here.")
            return 0

    scenarios = [s for s in SCENARIOS
                 if args.only is None or args.only in s.name]

    failed = 0
    for sc in scenarios:
        print(f"\n--- {sc.name} ---")
        print(f"    {sc.why}")
        r = run_one(sc, os.path.abspath(args.exe), args.keep_logs)

        interesting = [k for k in ("OPEN", "GETFREQ1", "GETFREQ2",
                                   "GETFREQ3", "GETFREQ4", "SETFREQ",
                                   "READBACK", "SETMODE", "SETSPLIT",
                                   "TYPED_SHAPES", "BREAKER_FINAL",
                                   "CLOSE", "TOTAL_MS")
                       if k in r["out"]]
        for k in interesting:
            print(f"      {k:<14} {r['out'][k]}")
        print(f"      {'wall':<14} {r['elapsed']:.1f} s")

        if r["failures"]:
            failed += 1
            for f in r["failures"]:
                print(f"      [FAIL] {f}")
        else:
            print("      [ok]")
        if args.keep_logs:
            print(f"      logs in {r['workdir']}")

    print()
    total = len(scenarios)
    if failed:
        print(f"TRANSPORT TESTS: {failed} of {total} scenarios FAILED")
        return 1
    print(f"TRANSPORT TESTS: all {total} scenarios passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
