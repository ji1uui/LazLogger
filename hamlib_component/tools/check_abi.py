#!/usr/bin/env python3
"""
check_abi.py — verify this component's Hamlib constants against the real
headers.

本コンポーネントの Hamlib 定数を実ヘッダと照合します。

Why this exists
---------------
Every value this component shares with Hamlib — VFO bits, mode bits,
error codes, model numbers, C type widths — is a *connascence of value*
whose two ends live in different repositories. That is the worst possible
locality for a coupling, and it is exactly where this component has
actually failed: 9 of 11 model numbers and 2 of 6 VFO bits were wrong, and
pbwidth_t was bound as int64 instead of long.

The coupling cannot be removed; Hamlib's numbers are Hamlib's. What this
script does is make the coupling *checkable*, so a mismatch is a failed CI
run instead of a radio that half works.

本スクリプトの存在理由
---------------------
本コンポーネントが Hamlib と共有する値（VFO ビット、モードビット、
エラーコード、モデル番号、C 型幅）はすべて「値のコナーセンス」であり、
その両端は別リポジトリにあります。結合の局所性としては最悪で、実際に
ここで失敗しています（モデル番号 11 個中 9 個、VFO ビット 6 個中 2 個が
誤り、pbwidth_t を long ではなく int64 で束縛）。

結合自体は除去できません。Hamlib の番号は Hamlib のものです。本スクリプトが
するのは結合を「検証可能」にすることで、不一致を「半分だけ動く無線機」では
なく「CI の失敗」に変えます。

Usage
-----
    python3 tools/check_abi.py                      # fetch master
    python3 tools/check_abi.py --ref 4.7.2          # fetch a tag
    python3 tools/check_abi.py --headers /usr/include/hamlib
    python3 tools/check_abi.py --ref 4.5.5 --ref 4.7.2   # check a range

Exit code 0 = all constants agree. 1 = at least one mismatch.
終了コード 0 = 全定数一致。1 = 1 件以上の不一致。
"""

import argparse
import os
import re
import sys
import urllib.request

RAW = "https://raw.githubusercontent.com/Hamlib/Hamlib/{ref}/include/hamlib/{name}"

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src")


# ---------------------------------------------------------------- headers

def load_header(name, ref, local_dir):
    """Return header text from a local directory or from GitHub."""
    if local_dir:
        path = os.path.join(local_dir, name)
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    url = RAW.format(ref=ref, name=name)
    with urllib.request.urlopen(url, timeout=60) as resp:
        return resp.read().decode("utf-8", errors="replace")


# ------------------------------------------------- parse the C side

def c_vfo_bits(rig_h):
    """RIG_VFO_x -> bit number, from RIG_VFO_N(n) = (1u<<(n))."""
    out = {}
    for m in re.finditer(r"#define\s+RIG_VFO_([A-Z0-9_]+)\s+RIG_VFO_N\((\d+)\)", rig_h):
        out[m.group(1)] = int(m.group(2))
    return out


def c_mode_bits(rig_h):
    """RIG_MODE_x -> bit number, from CONSTANT_64BIT_FLAG(n)."""
    out = {}
    for m in re.finditer(
        r"#define\s+RIG_MODE_([A-Z0-9_]+)\s+CONSTANT_64BIT_FLAG\s*\((\d+)\)", rig_h
    ):
        out[m.group(1)] = int(m.group(2))
    return out


def c_error_codes(rig_h):
    """RIG_E* -> ordinal, from the enum that starts at RIG_OK = 0."""
    block = re.search(r"RIG_OK\s*=\s*0\s*,(.*?)RIG_EEND", rig_h, re.S)
    if not block:
        return {}
    out = {"OK": 0}
    ordinal = 1
    for line in block.group(1).splitlines():
        m = re.match(r"\s*RIG_([A-Z0-9_]+)\s*,", line)
        if m:
            out[m.group(1)] = ordinal
            ordinal += 1
    return out


def c_models(riglist_h):
    """RIG_MODEL_x -> number, resolving RIG_MAKE_MODEL(backend, n)."""
    per = re.search(r"#define\s+MAX_MODELS_PER_BACKEND\s+(\d+)", riglist_h)
    if not per:
        return {}
    stride = int(per.group(1))

    backends = {
        m.group(1): int(m.group(2))
        for m in re.finditer(r"#define\s+RIG_([A-Z0-9_]+)\s+(\d+)\s*$",
                             riglist_h, re.M)
    }

    out = {}
    for m in re.finditer(
        r"#define\s+RIG_MODEL_([A-Z0-9_]+)\s+RIG_MAKE_MODEL\(RIG_([A-Z0-9_]+),\s*(\d+)\)",
        riglist_h,
    ):
        name, backend, n = m.group(1), m.group(2), int(m.group(3))
        if backend in backends:
            out[name] = stride * backends[backend] + n
    return out


def c_typedefs(rig_h, riglist_h):
    """The C spelling of each ABI-relevant typedef, normalised."""
    text = rig_h + "\n" + riglist_h
    wanted = {
        "freq_t": None,
        "shortfreq_t": None,
        "pbwidth_t": None,
        "vfo_t": None,
        "rmode_t": None,
        "rig_model_t": None,
        # 4.6+ spells the config-token type hamlib_token_t and keeps
        # token_t as a macro alias; 4.5.5 only has "typedef long token_t".
        # Accept either, and let compare_types pick whichever exists.
        "hamlib_token_t": None,
        "token_t": None,
    }
    for name in wanted:
        m = re.search(r"typedef\s+([A-Za-z0-9_ ]+?)\s+" + name + r"\s*;", text)
        if m:
            wanted[name] = " ".join(m.group(1).split())
    return wanted


# --------------------------------------------- parse the Pascal side

def read_src(name):
    with open(os.path.join(SRC, name), encoding="utf-8", errors="replace") as fh:
        return fh.read()


def pas_vfo_bits():
    """HL_VFO_x = (1 shl n) in HamlibVfoCodec.pas."""
    text = read_src("HamlibVfoCodec.pas")
    return {
        m.group(1): int(m.group(2))
        for m in re.finditer(r"HL_VFO_([A-Z]+)\s*=\s*\(1\s+shl\s+(\d+)\)", text)
    }


def pas_mode_bits():
    """RIG_MODE_x = (Int64(1) shl n) in HamlibTypes.pas."""
    text = read_src("HamlibTypes.pas")
    return {
        m.group(1): int(m.group(2))
        for m in re.finditer(
            r"RIG_MODE_([A-Z0-9]+)\s*:\s*Int64\s*=\s*\(Int64\(1\)\s+shl\s+(\d+)\)", text
        )
    }


def pas_error_codes():
    text = read_src("HamlibTypes.pas")
    return {
        m.group(1): int(m.group(2))
        for m in re.finditer(r"^\s*RIG_([A-Z0-9_]+)\s*=\s*(\d+);", text, re.M)
        if not m.group(1).startswith("MODE_") and not m.group(1).startswith("MODEL_")
    }


def pas_error_code_copies():
    """Every RIG_E* value defined ANYWHERE in src/, not just in HamlibTypes.

    The error ordinals are duplicated on purpose: HamlibLoader.pas and
    HamlibRigCommands.pas declare their own copies so they do not have to
    depend on HamlibTypes. Duplication is acceptable only while something
    proves the copies agree -- otherwise it is connascence of value spread
    across units, which is the exact failure this script exists to catch.
    Until Rev.6.0 this function did not exist, so three of the four copies
    were never checked against rig.h at all.

    Returns {(file, identifier): (c_name, abs_value)}.
    """
    out = {}
    for fname in sorted(os.listdir(SRC)):
        if not fname.endswith(".pas"):
            continue
        text = read_src(fname)
        for m in re.finditer(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(-?\d+)\s*;",
                             text, re.M):
            ident, value = m.group(1), int(m.group(2))
            name = ident
            # RIG_ETIMEOUT_CODE -> ETIMEOUT ; ENAVAIL -> ENAVAIL
            if name.startswith("RIG_"):
                name = name[4:]
            if name.endswith("_CODE"):
                name = name[:-5]
            if not re.fullmatch(r"E[A-Z]+", name):
                continue
            out[(fname, ident)] = (name, abs(value))
    return out


def pas_models():
    text = read_src("HamlibTypes.pas")
    return {
        m.group(1): int(m.group(2))
        for m in re.finditer(r"RIG_MODEL_([A-Z0-9_]+)\s*=\s*(\d+);", text)
    }


def pas_typedefs():
    """hl_* aliases in HamlibLoader.pas, mapped to the C spelling they claim."""
    text = read_src("HamlibLoader.pas")
    found = {
        m.group(1): m.group(2).strip()
        for m in re.finditer(r"hl_(\w+)\s*=\s*(c\w+);", text)
    }
    # How each FPC ctypes alias must correspond to a C type.
    expect = {
        "cdouble": {"double"},
        "cuint": {"unsigned int"},
        "cuint64": {"uint64_t", "unsigned long long"},
        "cuint32": {"uint32_t", "unsigned int"},
        "clong": {"signed long", "long"},
        "cint": {"int", "signed int"},
    }
    return found, expect


def pas_rigmode_enum():
    """TRigMode identifiers from HamlibInterfaces.pas, in declaration order."""
    text = read_src("HamlibInterfaces.pas")
    m = re.search(r"TRigMode\s*=\s*\((.*?)\n\s*\);", text, re.S)
    if not m:
        return []
    body = re.sub(r"\{[^{}]*\}", "", m.group(1))
    return [n.strip() for n in body.split(",") if n.strip()]


def pas_codec_mode_bits():
    """MODE_BITS values from HamlibModeCodec.pas, in declaration order.

    Read positionally and paired with the enum, NOT by the trailing
    comment: a table whose values were shifted relative to the enum would
    still carry correct-looking comments, and that is precisely the
    mistake this check has to catch.
    """
    text = read_src("HamlibModeCodec.pas")
    m = re.search(r"MODE_BITS:\s*array\[TRigMode\]\s*of\s*Byte\s*=\s*\((.*?)\n\s*\);",
                  text, re.S)
    if not m:
        return []
    body = re.sub(r"\{[^{}]*\}", "", m.group(1))
    return [v.strip() for v in body.split(",") if v.strip()]


# Pascal mode identifiers are the C names with the RIG_MODE_ prefix
# dropped and the capitalisation made readable, so uppercasing recovers
# the C name. One exception needs stating.
CODEC_NAME_ALIASES = {
    "NXDNN": "NXDN_N",
}


def compare_codec_modes(rep, pas_enum, pas_bits, c_modes):
    """Check MODE_BITS against the headers, pairing by position."""
    if not pas_enum or not pas_bits:
        rep.bad("codec mode table: could not parse TRigMode or MODE_BITS")
        return
    if len(pas_enum) != len(pas_bits):
        rep.bad(f"codec mode table: TRigMode has {len(pas_enum)} values but "
                f"MODE_BITS has {len(pas_bits)} entries")
        return

    for name, raw in zip(pas_enum, pas_bits):
        if not name.startswith("rm"):
            rep.bad(f"codec mode table: '{name}' does not look like a TRigMode "
                    f"identifier")
            continue
        short = name[2:]
        if short == "Unknown":
            if raw != "MODE_BIT_UNDEFINED":
                rep.bad(f"codec mode table: rmUnknown must be "
                        f"MODE_BIT_UNDEFINED, found {raw}")
            else:
                rep.ok()
            continue
        if not raw.isdigit():
            rep.bad(f"codec mode table: {name} has non-numeric bit '{raw}'")
            continue

        bit = int(raw)
        cname = CODEC_NAME_ALIASES.get(short.upper(), short.upper())

        if cname in c_modes:
            if c_modes[cname] != bit:
                rep.bad(f"codec mode bit: {name} is {bit}, header says "
                        f"{c_modes[cname]} for RIG_MODE_{cname}")
            else:
                rep.ok()
            continue

        # Not in this header. Accept it only if the header still has that
        # bit reserved under its RIG_MODE_BITnn placeholder name — that is
        # the documented way Hamlib adds modes, and it means the binding
        # is ahead of this particular version rather than wrong.
        placeholder = f"BIT{bit}"
        if c_modes.get(placeholder) == bit:
            rep.ok()
        else:
            rep.bad(f"codec mode bit: {name} claims bit {bit}, but this "
                    f"header has neither RIG_MODE_{cname} nor a reserved "
                    f"RIG_MODE_{placeholder} there")


def pas_verified_range():
    text = read_src("HamlibLoader.pas")
    major = re.search(r"VERIFIED_MAJOR\s*=\s*(\d+)", text)
    lo = re.search(r"VERIFIED_MIN_MINOR\s*=\s*(\d+)", text)
    hi = re.search(r"VERIFIED_MAX_MINOR\s*=\s*(\d+)", text)
    if not (major and lo and hi):
        return None
    return int(major.group(1)), int(lo.group(1)), int(hi.group(1))


# ------------------------------------------------------------- compare

class Report:
    def __init__(self):
        self.checked = 0
        self.problems = []

    def ok(self, n=1):
        self.checked += n

    def bad(self, msg):
        self.checked += 1
        self.problems.append(msg)


def compare_map(rep, label, pas, c, c_alias=None):
    """Compare Pascal constants against C, by name. Pascal is the subset."""
    for name, pval in sorted(pas.items()):
        cname = (c_alias or {}).get(name, name)
        if cname not in c:
            rep.bad(f"{label}: {name} = {pval} has no counterpart "
                    f"(looked for RIG_{label.split()[0].upper()}_{cname})")
            continue
        if c[cname] != pval:
            rep.bad(f"{label}: {name} is {pval}, header says {c[cname]}")
        else:
            rep.ok()


def compare_types(rep, pas_found, expect, c_types):
    # Each Pascal alias maps to the C names that may legitimately carry
    # that type, in preference order. More than one entry means the C
    # spelling changed across the supported Hamlib range.
    alias_to_c = {
        "freq_t": ("freq_t",),
        "pbwidth_t": ("pbwidth_t",),
        "vfo_t": ("vfo_t",),
        "rmode_t": ("rmode_t",),
        "model_t": ("rig_model_t",),
        "token_t": ("hamlib_token_t", "token_t"),
    }
    for alias, fpc_type in sorted(pas_found.items()):
        candidates = alias_to_c.get(alias)
        if candidates is None:
            continue
        cname = None
        c_spelling = None
        for cand in candidates:
            if c_types.get(cand) is not None:
                cname, c_spelling = cand, c_types[cand]
                break
        if c_spelling is None:
            rep.bad(f"typedef: none of {list(candidates)} found in the headers")
            continue
        # resolve one level of indirection (pbwidth_t -> shortfreq_t)
        seen = set()
        while c_spelling in c_types and c_spelling not in seen:
            seen.add(c_spelling)
            nxt = c_types[c_spelling]
            if nxt is None:
                break
            c_spelling = nxt
        allowed = expect.get(fpc_type)
        if allowed is None:
            rep.bad(f"typedef: hl_{alias} uses {fpc_type}, which this script "
                    f"does not know how to verify")
        elif c_spelling not in allowed:
            rep.bad(f"typedef: hl_{alias} = {fpc_type}, but C {cname} "
                    f"resolves to '{c_spelling}' (expected one of "
                    f"{sorted(allowed)})")
        else:
            rep.ok()


# ------------------------------------------------------------------ main

def check_one(ref, local_dir):
    print(f"--- checking against {'local headers: ' + local_dir if local_dir else 'Hamlib ' + ref} ---")
    rig_h = load_header("rig.h", ref, local_dir)
    riglist_h = load_header("riglist.h", ref, local_dir)

    rep = Report()

    # VFO bits. Pascal names map 1:1 to RIG_VFO_* names.
    compare_map(rep, "VFO bit", pas_vfo_bits(), c_vfo_bits(rig_h))

    # Mode bits in HamlibTypes.pas (the raw RIG_MODE_* constants kept as
    # an escape hatch). Pascal drops the RIG_MODE_ prefix in its key.
    c_modes = c_mode_bits(rig_h)
    compare_map(rep, "mode bit", pas_mode_bits(), c_modes)

    # The authoritative mode table: MODE_BITS in HamlibModeCodec.pas, which
    # is what TRigMode actually translates through.
    compare_codec_modes(rep, pas_rigmode_enum(), pas_codec_mode_bits(), c_modes)

    # Error codes. Pascal uses RIG_<NAME> = ordinal.
    c_err = c_error_codes(rig_h)
    pas_err = {k: v for k, v in pas_error_codes().items() if k in c_err}
    compare_map(rep, "error code", pas_err, c_err)

    # The same ordinals copied into other units. A copy that disagrees with
    # rig.h -- or with the canonical table -- is a rig that reports the
    # wrong failure, which is worse than reporting none.
    copies = pas_error_code_copies()
    for (fname, ident), (cname, value) in sorted(copies.items()):
        if cname not in c_err:
            continue
        rep.checked += 1
        if c_err[cname] != value:
            rep.bad(f"{fname}: {ident} = {value}, but rig.h says "
                    f"RIG_{cname} = {c_err[cname]}")
    n_outside = sum(1 for (f, _i) in copies
                    if f != "HamlibTypes.pas" and _i)
    if n_outside:
        print(f"  {n_outside} error-code copies outside HamlibTypes.pas "
              f"checked against rig.h")

    # Model numbers. FT991 in Pascal is RIG_MODEL_FT991 in the header.
    compare_map(rep, "model number", pas_models(), c_models(riglist_h))

    # C type widths.
    found, expect = pas_typedefs()
    compare_types(rep, found, expect, c_typedefs(rig_h, riglist_h))

    # Does the declared verified range actually cover this ref?
    rng = pas_verified_range()
    if rng and re.match(r"^\d+\.\d+", ref):
        major, lo, hi = rng
        parts = ref.split(".")
        rmaj, rmin = int(parts[0]), int(parts[1])
        covered = (rmaj == major) and (lo <= rmin <= hi)
        if covered:
            rep.ok()
            print(f"  verified range {major}.{lo}..{major}.{hi} covers {ref}")
        else:
            rep.bad(f"verified range {major}.{lo}..{major}.{hi} does NOT "
                    f"cover {ref}; widen VERIFIED_* in HamlibLoader.pas "
                    f"only after this check passes")

    for p in rep.problems:
        print(f"  MISMATCH  {p}")
    print(f"  {rep.checked - len(rep.problems)} agreed, "
          f"{len(rep.problems)} mismatched\n")
    return len(rep.problems) == 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ref", action="append", default=None,
                    help="Hamlib git ref (tag or branch). Repeatable.")
    ap.add_argument("--headers", default=None,
                    help="directory holding rig.h and riglist.h (offline)")
    args = ap.parse_args()

    refs = args.ref or (["master"] if not args.headers else ["local"])

    all_ok = True
    for ref in refs:
        try:
            all_ok &= check_one(ref, args.headers)
        except Exception as exc:          # network, missing file, parse issue
            print(f"  ERROR    could not check {ref}: "
                  f"{exc.__class__.__name__}: {exc}\n")
            all_ok = False

    if all_ok:
        print("ABI check passed.")
        return 0
    print("ABI check FAILED. Do not widen the verified range until this passes.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
