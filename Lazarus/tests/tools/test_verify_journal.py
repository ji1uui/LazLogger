from __future__ import annotations

import binascii
import importlib.util
import struct
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).parents[2] / "tools" / "verify_journal.py"
SPEC = importlib.util.spec_from_file_location("verify_journal", MODULE_PATH)
assert SPEC and SPEC.loader
VERIFY_JOURNAL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY_JOURNAL)


def encoded_string(value: str) -> bytes:
    encoded = value.encode("utf-8")
    return struct.pack("<I", len(encoded)) + encoded


def journal_record(received_exchange: str = "599 東京都") -> bytes:
    payload = b"".join(
        (
            bytes((1,)),
            encoded_string("fixture-1"),
            encoded_string("JA1ZLO"),
            struct.pack("<qB", 7_000_000, 1),
            encoded_string("599 001"),
            encoded_string(received_exchange),
            struct.pack("<q", 1_900_000_000_000),
        )
    )
    return struct.pack("<4sII", b"ZQSO", len(payload), binascii.crc32(payload)) + payload


class JournalVerifierTests(unittest.TestCase):
    def write_fixture(self, content: bytes) -> Path:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "fixture.journal"
        path.write_bytes(content)
        return path

    def test_decodes_complete_record(self) -> None:
        records, valid_bytes = VERIFY_JOURNAL.read_journal(self.write_fixture(journal_record()))
        self.assertEqual(1, len(records))
        self.assertEqual("JA1ZLO", records[0]["callsign"])
        self.assertEqual(7_000_000, records[0]["frequency_hz"])
        self.assertEqual("599 東京都", records[0]["received_exchange"])
        self.assertEqual(len(journal_record()), valid_bytes)

    def test_reports_incomplete_tail_without_accepting_it(self) -> None:
        complete = journal_record()
        records, valid_bytes = VERIFY_JOURNAL.read_journal(
            self.write_fixture(complete + b"ZQS")
        )
        self.assertEqual(1, len(records))
        self.assertEqual(len(complete), valid_bytes)

    def test_rejects_crc_corruption(self) -> None:
        corrupted = bytearray(journal_record())
        corrupted[-1] ^= 0xFF
        with self.assertRaisesRegex(VERIFY_JOURNAL.JournalError, "CRC mismatch"):
            VERIFY_JOURNAL.read_journal(self.write_fixture(corrupted))

    def test_decodes_multibyte_utf8_without_using_character_count_as_byte_length(self) -> None:
        record = journal_record("599 北海道 石狩振興局")
        records, valid_bytes = VERIFY_JOURNAL.read_journal(self.write_fixture(record))
        self.assertEqual("599 北海道 石狩振興局", records[0]["received_exchange"])
        self.assertEqual(len(record), valid_bytes)


if __name__ == "__main__":
    unittest.main()
