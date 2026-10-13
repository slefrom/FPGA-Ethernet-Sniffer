from __future__ import annotations

import struct
import time
from typing import BinaryIO

from .protocol import TICK_NS, Record

LINKTYPE_ETHERNET = 1


class PcapWriter:
    def __init__(self, fp: BinaryIO, snaplen: int = 65535):
        self.fp = fp
        self._t0_ns = None
        self._tick0 = 0
        fp.write(struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, snaplen, LINKTYPE_ETHERNET))
        fp.flush()

    def write(self, rec: Record):
        if self._t0_ns is None:
            self._t0_ns = time.time_ns()
            self._tick0 = rec.ts_ticks
        dticks = (rec.ts_ticks - self._tick0) % (1 << 48) 
        sec, ns = divmod(self._t0_ns + dticks * TICK_NS, 1_000_000_000)
        self.fp.write(struct.pack("<IIII", sec, ns // 1000, rec.incl_len, rec.orig_len))
        self.fp.write(rec.data)
        self.fp.flush()
