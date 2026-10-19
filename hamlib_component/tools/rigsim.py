#!/usr/bin/env python3
"""
rigsim.py — a Kenwood TS-2000 CAT simulator on a pseudo-terminal.

擬似端末上で動作する Kenwood TS-2000 CAT シミュレータ。

Why / 目的
------------------------------------------------------------------
Every test in this project so far has talked to Hamlib's dummy
backend, which answers in microseconds, never drops a byte, and never
fails to reply. That leaves four things permanently unverified:

  - the serial path at all — our port string, the baud and handshake
    settings the component applies, and whether a real backend's
    protocol code is reached
  - the tier-1 timeout, which is Hamlib's own: a dummy rig cannot
    fail to answer
  - partial and malformed replies, which a real CAT link produces when
    a cable is marginal
  - a reply that arrives late but does arrive, which is the case that
    separates "slow rig" from "dead rig"

本プロジェクトのこれまでの全テストは Hamlib のダミーバックエンドと
会話してきました。マイクロ秒で応答し、バイトを落とさず、返答に失敗
することがありません。そのため次の 4 つが恒久的に未検証でした
(上記: シリアル経路そのもの、第 1 段タイムアウト、部分応答・不正応答、
遅れて届く応答)。

This script is the other end of a `socat` PTY pair. Our component
opens one side as a Kenwood TS-2000 (model 2014); this script answers
on the other side, and can be told to misbehave in specific ways.

本スクリプトは `socat` の PTY 対のもう一方の端です。コンポーネントは
片側を Kenwood TS-2000 (model 2014) として開き、本スクリプトがもう一方
で応答します。特定の壊れ方を指示することもできます。

It is a test fixture, not a rig emulator: it implements the commands
Hamlib's kenwood backend actually sends during open, read and write,
and logs anything else so the gap is visible rather than silent.

これはテスト用の治具であり、リグのエミュレータではありません。Hamlib
の kenwood バックエンドが open・読み取り・書き込みで実際に送るコマンド
を実装し、それ以外は記録します。欠落が黙って隠れないようにするためです。

Usage:
    rigsim.py --pty /dev/pts/N [--mode normal|silent|slow|partial|garbage]
              [--silent-after N] [--delay SECONDS] [--log FILE]

Modes / モード:
    normal    answer everything correctly
    silent    accept commands, never answer (tier-1 timeout)
    slow      answer after --delay seconds
    partial   answer, but truncate the reply before its terminator
    garbage   answer with bytes that are not a valid CAT reply
    die-after answer N commands correctly, then stop answering
"""

import argparse
import os
import sys
import time

TERM = b";"


class Rig:
    """The simulated radio's state. Deliberately minimal.
    シミュレートされた無線機の状態。意図的に最小限です。"""

    def __init__(self):
        self.vfo_a = 14074000
        self.vfo_b = 14205000
        self.rx_vfo = 0          # 0 = VFO A, 1 = VFO B
        self.tx_vfo = 0
        self.split = 0
        self.mode = 2            # 2 = USB in the Kenwood table
        self.ptt = 0
        self.power = 50
        self.smeter = 9
        self.nb = 0

    @property
    def freq(self):
        return self.vfo_b if self.rx_vfo else self.vfo_a

    @freq.setter
    def freq(self, hz):
        if self.rx_vfo:
            self.vfo_b = hz
        else:
            self.vfo_a = hz


def build_if(rig):
    """The Kenwood IF reply: a fixed-width status string. Hamlib parses
    this by offset, so the widths matter more than the values.
    Kenwood の IF 応答。固定幅の状態文字列です。Hamlib はこれを位置で
    解析するため、値より幅が重要です。"""
    return (
        "IF"
        + "%011d" % rig.freq      # P1  frequency, 11 digits
        + "     "                 # P2  5 spaces
        + "+0000"                 # P3  RIT/XIT offset, 5
        + "0"                     # P4  RIT on/off
        + "0"                     # P5  XIT on/off
        + "000"                   # P6-P7 memory channel
        + "%d" % rig.ptt          # P8  0 = RX, 1 = TX
        + "%d" % rig.mode         # P9  mode
        + "%d" % rig.rx_vfo       # P10 receive VFO
        + "0"                     # P11 scan
        + "%d" % rig.split        # P12 split
        + "0"                     # P13 tone
        + "00"                    # P14 tone number
        + "0"                     # P15 reserved
        + ";"
    )


def handle(cmd, rig, log):
    """Return the reply bytes for one command, or None for no reply.
    1 コマンドに対する応答バイト列を返します。応答なしの場合は None。"""
    c = cmd.decode("ascii", "replace")

    # --- identity and housekeeping / 識別と管理 ---
    if c == "ID":
        return "ID019;"                      # 019 = TS-2000
    if c.startswith("AI"):
        return "AI0;" if c == "AI" else None
    if c == "PS":
        return "PS1;"
    if c.startswith("PS"):
        return None
    if c == "IF":
        return build_if(rig)

    # --- frequency / 周波数 ---
    if c == "FA":
        return "FA%011d;" % rig.vfo_a
    if c.startswith("FA") and len(c) == 13:
        rig.vfo_a = int(c[2:])
        return None
    if c == "FB":
        return "FB%011d;" % rig.vfo_b
    if c.startswith("FB") and len(c) == 13:
        rig.vfo_b = int(c[2:])
        return None

    # --- mode / モード ---
    if c == "MD":
        return "MD%d;" % rig.mode
    if c.startswith("MD") and len(c) == 3:
        rig.mode = int(c[2])
        return None

    # --- VFO selection and split / VFO 選択とスプリット ---
    if c == "FR":
        return "FR%d;" % rig.rx_vfo
    if c.startswith("FR") and len(c) == 3:
        rig.rx_vfo = int(c[2])
        return None
    if c == "FT":
        return "FT%d;" % rig.tx_vfo
    if c.startswith("FT") and len(c) == 3:
        rig.tx_vfo = int(c[2])
        rig.split = 1 if rig.tx_vfo != rig.rx_vfo else 0
        return None

    # --- PTT ---
    if c == "TX":
        rig.ptt = 1
        return None
    if c == "RX":
        rig.ptt = 0
        return None

    # --- levels / レベル ---
    if c.startswith("SM"):
        return "SM0%04d;" % rig.smeter
    if c == "PC":
        return "PC%03d;" % rig.power
    if c.startswith("PC") and len(c) == 5:
        rig.power = int(c[2:])
        return None
    if c == "AG0" or c == "AG":
        return "AG0100;"
    if c == "RG":
        return "RG255;"

    # --- functions / 機能 ---
    if c == "NB":
        return "NB%d;" % rig.nb
    if c.startswith("NB") and len(c) == 3:
        rig.nb = int(c[2])
        return None

    # --- anything else / それ以外 ---
    log("UNHANDLED: %r" % c)
    # A real Kenwood answers '?;' to a command it does not know. Saying
    # so is better than silence, which would look like a dead link.
    # 実機の Kenwood は未知のコマンドに '?;' を返します。沈黙は回線が
    # 死んだように見えるため、そう答える方が適切です。
    return "?;"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pty", required=True, help="the PTY to serve on")
    ap.add_argument("--mode", default="normal",
                    choices=["normal", "silent", "slow", "partial",
                             "garbage", "die-after"])
    ap.add_argument("--silent-after", type=int, default=0,
                    help="for die-after: answer this many, then stop")
    ap.add_argument("--delay", type=float, default=2.0,
                    help="for slow: seconds before replying")
    ap.add_argument("--log", default=None)
    ap.add_argument("--duration", type=float, default=120.0,
                    help="exit after this many seconds")
    args = ap.parse_args()

    logfile = open(args.log, "w", buffering=1) if args.log else sys.stderr

    def log(msg):
        logfile.write("%.3f %s\n" % (time.time(), msg))

    fd = os.open(args.pty, os.O_RDWR | os.O_NOCTTY)
    log("serving %s in mode=%s" % (args.pty, args.mode))

    rig = Rig()
    buf = b""
    served = 0
    deadline = time.time() + args.duration

    try:
        while time.time() < deadline:
            try:
                chunk = os.read(fd, 256)
            except BlockingIOError:
                time.sleep(0.01)
                continue
            except OSError as exc:
                log("read error: %s" % exc)
                break
            if not chunk:
                time.sleep(0.01)
                continue

            buf += chunk
            while TERM in buf:
                cmd, buf = buf.split(TERM, 1)
                cmd = cmd.strip()
                if not cmd:
                    continue
                log("<- %r" % cmd)

                reply = handle(cmd, rig, log)
                served += 1

                if args.mode == "silent":
                    continue
                if args.mode == "die-after" and served > args.silent_after:
                    log("   (silent: past --silent-after)")
                    continue
                if reply is None:
                    continue
                if args.mode == "slow":
                    time.sleep(args.delay)
                if args.mode == "partial":
                    # Drop the terminator: the reply starts and never
                    # finishes, which is what a marginal cable looks
                    # like to the backend's read loop.
                    # 終端を落とします。応答が始まって終わらない状態で、
                    # 不良ケーブルがバックエンドの読み取りループに
                    # 見せる姿です。
                    reply = reply.rstrip(";")[: max(1, len(reply) // 2)]
                if args.mode == "garbage":
                    reply = "\x00\xff\x01rubbish;"

                log("-> %r" % reply)
                os.write(fd, reply.encode("latin-1"))
    finally:
        os.close(fd)
        log("served %d commands" % served)
        if logfile is not sys.stderr:
            logfile.close()


if __name__ == "__main__":
    main()
