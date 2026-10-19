#!/usr/bin/env python3
"""
check_layers.py — an architectural fitness function for the unit graph.

ユニット依存グラフに対するアーキテクチャ・フィットネス関数。

Why this exists / 本スクリプトの存在理由
------------------------------------------------------------------
The design document says the package is layered and that its core is
LCL-free. Neither claim is enforced by anything: Object Pascal is happy
to let HamlibLoader use HamlibService, and nothing stops a unit in src/
from adding `Forms` to its uses clause and quietly making the whole
component unusable from a console program or a unit test.

設計書はパッケージが層構造であり、中核が LCL 非依存であると述べます。
どちらも何にも強制されていません。Object Pascal は HamlibLoader が
HamlibService を使うことを平気で許しますし、src/ のユニットが uses 節に
`Forms` を足して、コンポーネント全体をコンソールプログラムやユニット
テストから使えなくすることを止めるものは何もありません。

A claim in a document that nothing checks is a claim that will be false
eventually. This script turns five such claims into a failing exit code.

誰も検査しない文書上の主張は、いずれ偽になる主張です。本スクリプトは
その種の主張 5 つを、失敗する終了コードに変換します。

What it checks / 検査する内容
------------------------------------------------------------------
  R1  the core is LCL-free — no unit in src/ uses an LCL or GUI unit
  R2  no unit reaches upward into the facade (Service / Worker /
      Dispatch / Factory) from below it
  R3  the pure L2 units (codecs, policies, types) depend on nothing but
      HamlibInterfaces, each other, and the RTL, so they stay testable
      with no library present
  R4  no L3 command unit uses another L3 command unit except the shared
      base — commands must not couple to each other
  R5  no cycle in the interface-section graph, and implementation-section
      cycles are reported (Pascal allows them; they still cost)

Usage:
    python3 tools/check_layers.py [--src DIR] [--quiet]
Exit code 0 when every rule holds, 1 otherwise.
"""

import argparse
import os
import re
import sys

# ------------------------------------------------------------------
# Unit classification. Taken from each unit's own "Layer:" header so
# the script and the source cannot drift apart silently; the few
# units with no header are listed here.
#
# ユニットの分類。各ユニット自身の "Layer:" ヘッダから読み取るため、
# 本スクリプトとソースが黙って乖離することはありません。ヘッダを
# 持たない少数のユニットのみここに列挙します。
# ------------------------------------------------------------------

NO_HEADER = {
    "HamlibComponent": "master",   # build-only aggregate / ビルド専用の集約
    "HamlibRegister": "ide",       # IDE registration / IDE 登録
}

CROSS_CUTTING = "HamlibInterfaces"

# Units that form the facade. Nothing below them may name them.
# ファサードを構成するユニット。下位のものがこれらを名指してはいけません。
FACADE = {"HamlibService", "HamlibWorker", "HamlibDispatch", "HamlibFactory"}

# Who is allowed to name a facade unit, and what they may name.
# ファサードを名指してよいのは誰か、そして何を名指してよいか。
FACADE_CALLERS = {
    "HamlibService": {"HamlibWorker", "HamlibDispatch"},
    "HamlibFactory": {"HamlibService"},
    "HamlibComponent": set(FACADE),
    "HamlibRegister": set(FACADE),
}

# The pure L2 units: value translation only. They may name each other
# — HamlibTypes delegates to HamlibModeCodec rather than keeping a
# second copy of the mode table, which is the right call — but nothing
# below or above them, or they stop being testable with no Hamlib
# present.
#
# The first draft of this rule forbade pure-to-pure edges and promptly
# reported that DRY delegation as a violation. A fitness function that
# is stricter than the invariant it is meant to protect trains people
# to ignore it, so the rule was corrected rather than the code.
#
# 純粋な L2 ユニット。値の変換のみを行います。互いを名指すことは
# できます (HamlibTypes はモード表の二重定義を持たず HamlibModeCodec へ
# 委譲しており、それが正しい判断です)。しかしそれより下も上も名指せ
# ません。さもないと Hamlib なしにテストできなくなります。
#
# 本ルールの初稿は純粋ユニット同士の辺を禁じ、その DRY な委譲を違反と
# して報告しました。守るべき不変条件より厳しいフィットネス関数は、
# 人にそれを無視する習慣をつけさせます。そのためコードではなくルールを
# 修正しました。
PURE_L2 = {
    "HamlibTypes",
    "HamlibVfoCodec",
    "HamlibModeCodec",
    "HamlibLevelCodec",
    "HamlibTimeoutPolicy",
}

# L3 command units. They may use the shared base and the codecs, but
# not each other: a command that knows about another command is a
# command that cannot be scheduled independently.
# L3 コマンドユニット。共通基底とコーデックは使えますが、互いを使うこと
# はできません。他のコマンドを知るコマンドは、独立にスケジュールできない
# コマンドです。
COMMAND_UNITS = {
    "HamlibFreqCommands",
    "HamlibModeCommands",
    "HamlibPttCommands",
    "HamlibRigCommands",
}
COMMAND_BASE = "HamlibCommandBase"

# RTL / FPC units that are not part of this package.
# 本パッケージに属さない RTL / FPC ユニット。
RTL = {
    "sysutils", "classes", "syncobjs", "dynlibs", "ctypes", "math",
    "strutils", "dateutils", "contnrs", "fgl", "unix", "baseunix",
    "windows", "cthreads", "types", "variants", "typinfo",
}

# Anything that drags in a widgetset. The core must name none of them.
# ウィジェットセットを引き込むもの。中核はいずれも名指してはなりません。
GUI_UNITS = {
    "forms", "controls", "graphics", "dialogs", "stdctrls", "extctrls",
    "comctrls", "buttons", "menus", "grids", "spin", "lcltype",
    "lclintf", "lclproc", "interfaces", "lresources", "lmessages",
    "clipbrd", "printers", "themes", "imglist", "actnlist",
}


def strip_comments(text):
    """Remove { } and // comments so a uses clause inside a comment is
    not mistaken for a dependency.
    コメント内の uses 節を依存と誤認しないよう、{ } と // を除去します。"""
    out = []
    depth = 0
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            if depth:
                depth -= 1
        elif depth == 0:
            if ch == "/" and i + 1 < n and text[i + 1] == "/":
                while i < n and text[i] != "\n":
                    i += 1
                out.append("\n")
                continue
            out.append(ch)
        i += 1
    return "".join(out)


def parse_unit(path):
    """Return (name, layer, interface_uses, implementation_uses, lines)."""
    raw = open(path, encoding="utf-8").read()
    name = os.path.splitext(os.path.basename(path))[0]
    lines = raw.count("\n") + 1

    m = re.search(r"^\s*Layer:\s*(\S+)", raw, re.M)
    layer = m.group(1) if m else NO_HEADER.get(name, "?")

    body = strip_comments(raw)

    # Split at the implementation keyword so the two uses clauses can be
    # told apart. An interface-section cycle is a compile error; an
    # implementation-section one is legal and merely costly.
    # implementation で分割し、2 つの uses 節を区別します。interface 側の
    # 循環はコンパイルエラー、implementation 側は合法で、費用がかかる
    # だけです。
    parts = re.split(r"\bimplementation\b", body, maxsplit=1, flags=re.I)
    head = parts[0]
    tail = parts[1] if len(parts) > 1 else ""

    def uses_of(section):
        m = re.search(r"\buses\b(.*?);", section, re.S | re.I)
        if not m:
            return []
        return [u.strip() for u in m.group(1).split(",") if u.strip()]

    return name, layer, uses_of(head), uses_of(tail), lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=None, help="the src directory")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    src = args.src or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "src")
    src = os.path.normpath(src)

    units = {}
    for fn in sorted(os.listdir(src)):
        if fn.endswith(".pas"):
            name, layer, iu, pu, lines = parse_unit(os.path.join(src, fn))
            units[name] = dict(layer=layer, iface=iu, impl=pu, lines=lines)

    if not units:
        print(f"no units found under {src}", file=sys.stderr)
        return 1

    failures = []
    notes = []

    def own(lst):
        """Only the units of this package.
        本パッケージのユニットのみ。"""
        return [u for u in lst if u in units]

    # ---- R1: the core is LCL-free ----------------------------------
    for name, info in units.items():
        if name == "HamlibRegister":
            # The IDE registration unit is the one place a widgetset is
            # legitimate, and it is excluded from the runtime package's
            # core by design.
            # IDE 登録ユニットはウィジェットセットが正当な唯一の場所で
            # あり、設計上、実行時パッケージの中核から除外されます。
            continue
        for u in info["iface"] + info["impl"]:
            if u.lower() in GUI_UNITS:
                failures.append(
                    f"R1 {name} uses {u}: the core must stay LCL-free, or "
                    f"it can no longer be used from a console program or a "
                    f"unit test")

    # ---- R2: nothing reaches up into the facade --------------------
    for name, info in units.items():
        allowed = FACADE_CALLERS.get(name, set())
        for u in own(info["iface"] + info["impl"]):
            if u in FACADE and u not in allowed and u != name:
                who = (", ".join(sorted(allowed))
                       if allowed else "no facade unit at all")
                failures.append(
                    f"R2 {name} uses {u}: from here the only facade unit "
                    f"that may be named is {who}")

    # ---- R3: the pure L2 units stay pure ---------------------------
    for name in sorted(PURE_L2):
        if name not in units:
            continue
        for u in own(units[name]["iface"] + units[name]["impl"]):
            if u != CROSS_CUTTING and u not in PURE_L2:
                failures.append(
                    f"R3 {name} uses {u}: a pure translation unit may name "
                    f"only {CROSS_CUTTING}, another pure translation unit, "
                    f"and the RTL, so it stays testable with no Hamlib "
                    f"present")

    # ---- R4: commands do not know about each other -----------------
    for name in sorted(COMMAND_UNITS):
        if name not in units:
            continue
        for u in own(units[name]["iface"] + units[name]["impl"]):
            if u in COMMAND_UNITS and u != name:
                failures.append(
                    f"R4 {name} uses {u}: command units must not couple to "
                    f"each other — only {COMMAND_BASE} is shared")

    # ---- R5: cycles ------------------------------------------------
    def find_cycles(edges):
        cycles = []
        colour = {}

        def walk(u, stack):
            colour[u] = 1
            for v in edges.get(u, []):
                if colour.get(v, 0) == 1:
                    cycles.append(stack[stack.index(v):] + [v])
                elif colour.get(v, 0) == 0:
                    walk(v, stack + [v])
            colour[u] = 2

        for u in sorted(edges):
            if colour.get(u, 0) == 0:
                walk(u, [u])
        return cycles

    iface_edges = {n: own(i["iface"]) for n, i in units.items()}
    for cyc in find_cycles(iface_edges):
        failures.append("R5 interface-section cycle: " + " -> ".join(cyc))

    all_edges = {n: own(i["iface"] + i["impl"]) for n, i in units.items()}
    impl_cycles = find_cycles(all_edges)
    for cyc in impl_cycles:
        notes.append("implementation-section cycle: " + " -> ".join(cyc))

    # ---- report ----------------------------------------------------
    if not args.quiet:
        print(f"--- {len(units)} units under {src} ---")
        widest = max(len(n) for n in units)
        for name in sorted(units):
            info = units[name]
            print(f"  {name:<{widest}}  {info['layer']:<16} "
                  f"{len(own(info['iface'])):>2} iface + "
                  f"{len(own(info['impl'])):>2} impl deps  "
                  f"{info['lines']:>5} lines")
        print()

    for n in notes:
        print(f"  note: {n}")
    if notes:
        print()

    if failures:
        print(f"LAYER CHECK FAILED — {len(failures)} violation(s):")
        for f in failures:
            print(f"  {f}")
        return 1

    print("Layer check passed: R1 LCL-free core, R2 no upward reach, "
          "R3 pure codecs, R4 independent commands, R5 no cycles.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
