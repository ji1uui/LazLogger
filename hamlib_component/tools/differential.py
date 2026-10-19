#!/usr/bin/env python3
"""Differential test: our component against Hamlib's own rigctld.

Every other test in this project checks the component against our own
understanding of Hamlib. That is a closed loop -- a misreading of the C
API produces a test that asserts the misreading, and the suite goes
green. This script breaks the loop by running the identical sequence of
operations through Hamlib's own reference server and comparing.

本プロジェクトの他のすべてのテストは、コンポーネントを「我々の Hamlib
理解」と照合します。これは閉じた環です。C API の読み違いは、その読み
違いを主張するテストを生み、テスト群は緑になります。本スクリプトは、
同一の操作列を Hamlib 自身の参照サーバへ流して比較することで環を破ります。

Both sides talk to a *fresh* dummy rig, and the dummy's answers depend on
the state built by earlier steps (the S-meter reading moves with the
frequency), so the sequences must match step for step. test/DifferentialTest.lpr
holds our side; the STEPS table below holds rigctld's.

Usage:
    python3 tools/differential.py --binary /path/to/DifferentialTest
"""

import argparse
import os
import re
import socket
import subprocess
import sys
import time

PORT = 4599          # not the rigctld default, so a stray server is not used
HOST = "127.0.0.1"

# (step-id, rigctld command, how to read its reply)
#   "rprt"   -- expect RPRT 0; normalise to 'RPRT 0'
#   "line"   -- the reply is the value
#   "two"    -- two lines, joined with '|'
#   "split"  -- get_split_vfo: two lines, joined with '|'
STEPS = [
    ("01-set-freq",        "F 14205000",        "rprt"),
    ("02-get-freq",        "f",                 "line"),
    ("03-set-mode",        "M USB 2400",        "rprt"),
    ("04-get-mode",        "m",                 "two"),
    ("05-set-vfo",         "V VFOB",            "rprt"),
    ("06-get-vfo",         "v",                 "line"),
    ("07-set-split",       "S 1 VFOB",          "rprt"),
    ("08-get-split",       "s",                 "split"),
    ("09-set-split-freq",  "I 14250000",        "rprt"),
    ("10-get-split-again", "s",                 "split"),
    ("11-get-strength",    "l STRENGTH",        "line"),
    ("12-set-rfpower",     "L RFPOWER 0.42",    "rprt"),
    ("13-get-rfpower",     "l RFPOWER",         "line"),
    ("14-set-nb",          "U NB 1",            "rprt"),
    ("15-get-nb",          "u NB",              "line"),
    ("16-vfo-op-toggle",   "G TOGGLE",          "rprt"),
    ("17-get-vfo-again",   "v",                 "line"),
    ("18-set-keyspeed",    "L KEYSPD 27",       "rprt"),
    ("19-get-keyspeed",    "l KEYSPD",          "line"),
    ("20-split-off",       "S 0 VFOB",          "rprt"),
    ("21-get-split-off",   "s",                 "split"),
]

# Steps where the two sides are allowed to differ, each with the reason.
# A difference without an entry here is a failure. Keeping the reasons in
# the table rather than in a comment means an unexplained difference can
# never be waved through.
#
# 両者が異なってよいステップと、その理由。ここに項目のない差異は失敗です。
# 理由をコメントではなく表に置くことで、説明のつかない差異が黙って通る
# ことはなくなります。
KNOWN_DIFFERENCES = {
    "11-get-strength": (
        "the dummy backend computes RIG_LEVEL_STRENGTH as "
        "qrm + (time(NULL) % 32) + (rand() % 4) - att + preamp "
        "(rigs/dummy/dummy.c, comment: 'make S-Meter jiggle'), so it is "
        "deliberately non-deterministic and two processes cannot agree "
        "on it. Both answers must still be integers in the range the "
        "formula can produce at this frequency.",
        # qrm = -30 below 21 MHz; time term 0..31; rand term 0..3;
        # attenuator and preamp both 0 because this sequence sets neither.
        (-30, 4),
    ),
}


def read_reply(sock, timeout=2.0):
    sock.settimeout(timeout)
    chunks = []
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            data = sock.recv(8192)
        except socket.timeout:
            break
        if not data:
            break
        chunks.append(data.decode(errors="replace"))
        # rigctld answers one command at a time; a short pause after the
        # first chunk is enough to collect a two-line reply.
        time.sleep(0.05)
        if chunks and ("\n" in "".join(chunks)):
            try:
                sock.settimeout(0.08)
                more = sock.recv(8192)
                if more:
                    chunks.append(more.decode(errors="replace"))
            except socket.timeout:
                pass
            break
    return "".join(chunks).strip()


def normalise(reply, kind):
    """Turn rigctld's reply into the same shape DifferentialTest prints."""
    if reply.startswith("RPRT "):
        code = reply.split()[1]
        return "RPRT 0" if code == "0" else f"RPRT {code}"
    lines = [l for l in reply.splitlines() if l.strip() != ""]
    if kind == "rprt":
        return "RPRT 0"
    if kind == "line":
        return lines[0] if lines else ""
    if kind in ("two", "split"):
        return "|".join(lines[:2])
    return reply


def run_oracle():
    server = subprocess.Popen(
        ["rigctld", "-m", "1", "-t", str(PORT)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        # Wait for the port rather than sleeping a guessed amount.
        sock = None
        for _ in range(50):
            try:
                sock = socket.create_connection((HOST, PORT), timeout=1)
                break
            except OSError:
                time.sleep(0.1)
        if sock is None:
            raise RuntimeError("rigctld did not start listening")

        out = {}
        for step_id, command, kind in STEPS:
            sock.sendall((command + "\n").encode())
            out[step_id] = normalise(read_reply(sock), kind)
        sock.close()
        return out
    finally:
        server.terminate()
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()


def run_ours(binary):
    res = subprocess.run([binary], capture_output=True, text=True, timeout=300)
    out = {}
    for line in res.stdout.splitlines():
        if "|" not in line:
            continue
        step_id, _, value = line.partition("|")
        if re.match(r"^\d\d-", step_id):
            out[step_id] = value.strip()
    if not out:
        print(res.stdout)
        print(res.stderr, file=sys.stderr)
        raise RuntimeError("the component binary printed no steps")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--binary", required=True,
                    help="path to the built DifferentialTest")
    args = ap.parse_args()

    if not os.path.exists(args.binary):
        print(f"no such binary: {args.binary}", file=sys.stderr)
        return 2

    print("Differential test — the component vs Hamlib's own rigctld")
    print("=" * 72)

    oracle = run_oracle()
    ours = run_ours(args.binary)

    agreed = 0
    problems = []
    print(f"{'step':<20} {'rigctld (Hamlib)':<22} {'component':<22} ")
    print("-" * 72)
    for step_id, command, _kind in STEPS:
        a = oracle.get(step_id, "<missing>")
        b = ours.get(step_id, "<missing>")
        if a == b:
            agreed += 1
            mark = "ok "
        elif step_id in KNOWN_DIFFERENCES:
            # A step listed here is not simply waved through: the entry
            # carries the range the value may legitimately take, and both
            # sides are still required to fall inside it. An exemption
            # that checked nothing would be an exemption from testing.
            _reason, (lo, hi) = KNOWN_DIFFERENCES[step_id]
            try:
                ok = all(lo <= int(v) <= hi for v in (a, b))
            except ValueError:
                ok = False
            if ok:
                agreed += 1
                mark = "~ok"
            else:
                mark = "!! "
                problems.append((step_id, command, a, b))
        else:
            mark = "!! "
            problems.append((step_id, command, a, b))
        print(f"{mark} {step_id:<17} {a:<22} {b:<22}")

    print("-" * 72)
    for step_id, (reason, (lo, hi)) in KNOWN_DIFFERENCES.items():
        print(f"  ~ok {step_id}: values differ by design, both checked "
              f"to lie in [{lo}, {hi}]")
        print(f"      {reason}")
    for step_id, command, a, b in problems:
        print(f"  DISAGREEMENT at {step_id} (rigctld: '{command}')")
        print(f"    Hamlib's own client says : {a}")
        print(f"    our component says       : {b}")
    print(f"  {agreed} agreed, {len(problems)} disagreed "
          f"(of {len(STEPS)} steps)\n")

    if problems:
        print("DIFFERENTIAL TEST FAILED — the component and Hamlib's own "
              "client disagree about what the same rig did.")
        return 1
    print("Differential test passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
