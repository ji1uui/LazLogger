#!/usr/bin/env python3
"""Independent structural verifier for the zLog append-only QSO journal."""

from __future__ import annotations

import argparse
import binascii
import struct
import sys
from pathlib import Path

MAGIC = b"ZQSO"
HEADER = struct.Struct("<4sII")
MAX_PAYLOAD = 1024 * 1024
PAYLOAD_VERSION = 1
VALID_MODES = {1, 2, 3}


class JournalError(ValueError):
    pass


def valid_callsign(value: str) -> bool:
    return (
        3 <= len(value) <= 16
        and value == value.upper()
        and any(character.isascii() and character.isalpha() for character in value)
        and any(character.isdigit() for character in value)
        and all(character.isascii() and (character.isalnum() or character == "/") for character in value)
        and not value.startswith("/")
        and not value.endswith("/")
        and "//" not in value
    )


def read_string(payload: memoryview, offset: int) -> tuple[str, int]:
    if len(payload) - offset < 4:
        raise JournalError("truncated string length")
    length = struct.unpack_from("<I", payload, offset)[0]
    offset += 4
    if length > MAX_PAYLOAD or len(payload) - offset < length:
        raise JournalError("invalid string length")
    try:
        value = bytes(payload[offset : offset + length]).decode("utf-8")
    except UnicodeDecodeError as error:
        raise JournalError("invalid UTF-8 string") from error
    return value, offset + length


def decode_payload(raw: bytes) -> dict[str, object]:
    payload = memoryview(raw)
    if not payload or payload[0] != PAYLOAD_VERSION:
        raise JournalError("unsupported payload version")
    offset = 1
    qso_id, offset = read_string(payload, offset)
    callsign, offset = read_string(payload, offset)
    if len(payload) - offset < 9:
        raise JournalError("truncated frequency or mode")
    frequency_hz = struct.unpack_from("<q", payload, offset)[0]
    offset += 8
    mode = payload[offset]
    offset += 1
    sent_exchange, offset = read_string(payload, offset)
    received_exchange, offset = read_string(payload, offset)
    if len(payload) - offset < 8:
        raise JournalError("truncated timestamp")
    occurred_at_utc_ms = struct.unpack_from("<q", payload, offset)[0]
    offset += 8
    if offset != len(payload):
        raise JournalError("unexpected payload suffix")
    if (
        not qso_id
        or not valid_callsign(callsign)
        or mode not in VALID_MODES
        or not 100_000 <= frequency_hz <= 300_000_000_000
    ):
        raise JournalError("invalid domain values")
    return {
        "id": qso_id,
        "callsign": callsign,
        "frequency_hz": frequency_hz,
        "mode": mode,
        "sent_exchange": sent_exchange,
        "received_exchange": received_exchange,
        "occurred_at_utc_ms": occurred_at_utc_ms,
    }


def read_journal(path: Path) -> tuple[list[dict[str, object]], int]:
    data = path.read_bytes()
    records: list[dict[str, object]] = []
    offset = 0
    while offset < len(data):
        if len(data) - offset < HEADER.size:
            return records, offset
        magic, length, expected_crc = HEADER.unpack_from(data, offset)
        if magic != MAGIC:
            raise JournalError(f"invalid marker at byte {offset}")
        if length > MAX_PAYLOAD:
            raise JournalError(f"oversized payload at byte {offset}")
        payload_start = offset + HEADER.size
        payload_end = payload_start + length
        if payload_end > len(data):
            return records, offset
        payload = data[payload_start:payload_end]
        actual_crc = binascii.crc32(payload) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            raise JournalError(f"CRC mismatch at byte {offset}")
        records.append(decode_payload(payload))
        offset = payload_end
    return records, offset


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("journal", type=Path)
    parser.add_argument("--expect-count", type=int)
    parser.add_argument("--require-complete-tail", action="store_true")
    arguments = parser.parse_args()
    try:
        records, valid_bytes = read_journal(arguments.journal)
        size = arguments.journal.stat().st_size
        if arguments.expect_count is not None and len(records) != arguments.expect_count:
            raise JournalError(f"expected {arguments.expect_count} records, found {len(records)}")
        if arguments.require_complete_tail and valid_bytes != size:
            raise JournalError(f"incomplete tail begins at byte {valid_bytes}")
    except (OSError, JournalError) as error:
        print(f"journal verification failed: {error}", file=sys.stderr)
        return 1
    print(f"journal verified: records={len(records)} bytes={size} valid_bytes={valid_bytes}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
