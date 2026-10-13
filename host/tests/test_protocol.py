
import io
import random
import struct

from sniffer import protocol as P
from sniffer.pcap import PcapWriter


def record_bytes(ts, data, orig_len, drops):
    return ts.to_bytes(6, "little") + data + struct.pack("<HH", orig_len, drops)


def test_cobs_round_trip():
    cases = [b"", b"\x00", b"\x00\x00", bytes(range(1, 256)), bytes([1]) * 254,
             bytes([1]) * 255, bytes([1]) * 508, bytes(300)]
    cases += [bytes(random.getrandbits(8) for _ in range(random.randint(0, 1000))) for _ in range(200)]
    for c in cases:
        enc = P.cobs_encode(c)
        assert 0 not in enc and P.cobs_decode(enc) == c


def test_record_parse_and_resync():
    raw = record_bytes(0x123456789ABC, b"abcdef", 1500, 7)
    stream = b"\x05\x05\x00" + P.cobs_encode(raw) + b"\x00"
    recs = [r for r in P.Decoder().feed(stream) if isinstance(r, P.Record)]
    assert len(recs) == 1
    r = recs[0]
    assert (r.ts_ticks, r.data, r.orig_len, r.drops, r.incl_len) == (0x123456789ABC, b"abcdef", 1500, 7, 6)


def test_bad_records():
    assert isinstance(P.parse_record(b"\x01\x02"), P.BadRecord)
    assert isinstance(P.parse_record(record_bytes(1, b"x" * 10, 5, 0)), P.BadRecord)


def test_pcap_writer():
    buf = io.BytesIO()
    w = PcapWriter(buf)
    w.write(P.Record(1000, b"\x11" * 20, 60, 0))
    w.write(P.Record(1000 + 25_000_000, b"\x22" * 20, 60, 0))   # 1 s later
    b = buf.getvalue()
    assert struct.unpack_from("<I", b)[0] == 0xA1B2C3D4
    s1, us1, incl1, orig1 = struct.unpack_from("<IIII", b, 24)
    s2, us2, _, _ = struct.unpack_from("<IIII", b, 24 + 16 + 20)
    assert (incl1, orig1) == (20, 60)
    assert (s2 * 1_000_000 + us2) - (s1 * 1_000_000 + us1) == 1_000_000
