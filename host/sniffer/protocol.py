from __future__ import annotations

import struct
from dataclasses import dataclass
from typing import Iterable, Union

TS_BYTES = 6
TRAILER_BYTES = 4
TICK_NS = 40  # rx_clk period at 100 Mb/s


def cobs_encode(data: bytes) -> bytes:
    out = bytearray()
    block = bytearray()
    for b in data:
        if b == 0:
            out.append(len(block) + 1)
            out += block
            block.clear()
        else:
            block.append(b)
            if len(block) == 254:
                out.append(255)
                out += block
                block.clear()
    out.append(len(block) + 1)
    out += block
    return bytes(out)


def cobs_decode(data: bytes) -> bytes:
    out = bytearray()
    i, n = 0, len(data)
    while i < n:
        code = data[i]
        if code == 0:
            raise ValueError("zero byte inside COBS block")
        i += 1
        if i + code - 1 > n:
            raise ValueError("truncated COBS block")
        out += data[i:i + code - 1]
        i += code - 1
        if code < 255 and i < n:
            out.append(0)
    return bytes(out)


@dataclass
class Record:
    ts_ticks: int
    data: bytes
    orig_len: int
    drops: int

    @property
    def incl_len(self) -> int:
        return len(self.data)

    @property
    def ts_ns(self) -> int:
        return self.ts_ticks * TICK_NS


@dataclass
class BadRecord:
    raw: bytes
    reason: str


def parse_record(msg: bytes) -> Union[Record, BadRecord]:
    if len(msg) < TS_BYTES + 1 + TRAILER_BYTES:
        return BadRecord(msg, f"too short ({len(msg)} bytes)")
    ts = int.from_bytes(msg[:TS_BYTES], "little")
    orig_len, drops = struct.unpack("<HH", msg[-TRAILER_BYTES:])
    data = bytes(msg[TS_BYTES:-TRAILER_BYTES])
    if len(data) > orig_len:
        return BadRecord(msg, f"incl_len {len(data)} > orig_len {orig_len}")
    return Record(ts, data, orig_len, drops)


class Decoder:
    def __init__(self):
        self._buf = bytearray()

    def feed(self, data: Iterable[int]) -> list[Union[Record, BadRecord]]:
        out = []
        for b in bytes(data):
            if b == 0:
                if self._buf:
                    try:
                        out.append(parse_record(cobs_decode(bytes(self._buf))))
                    except ValueError as e:
                        out.append(BadRecord(bytes(self._buf), str(e)))
                self._buf.clear()
            else:
                self._buf.append(b)
        return out
