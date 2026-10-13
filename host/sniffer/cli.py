"""Capture tool: read records from the UART and write pcap.

    python -m sniffer.cli -p /dev/ttyUSB1 -w out.pcap
    python -m sniffer.cli -p /dev/ttyUSB1 | wireshark -k -i -

Drop counts from the record trailers are summed and printed on exit.
"""

from __future__ import annotations

import argparse
import sys

import serial  # pyserial

from .pcap import PcapWriter
from .protocol import BadRecord, Decoder, Record


def main(argv=None):
    ap = argparse.ArgumentParser(prog="sniffer")
    ap.add_argument("-p", "--port", required=True)
    ap.add_argument("-b", "--baud", type=int, default=3_000_000, help="must match UART_PRESCALE in the build")
    ap.add_argument("-w", "--write", default="-", help="pcap file, or - for stdout")
    a = ap.parse_args(argv)

    ser = serial.Serial(a.port, a.baud, timeout=0.1)
    out = sys.stdout.buffer if a.write == "-" else open(a.write, "wb")
    pcap = PcapWriter(out)
    dec = Decoder()
    records = drops = bad = 0
    try:
        while True:
            for r in dec.feed(ser.read(4096)):
                if isinstance(r, Record):
                    pcap.write(r)
                    records += 1
                    drops += r.drops
                elif isinstance(r, BadRecord):
                    bad += 1
    except (KeyboardInterrupt, BrokenPipeError):
        pass
    finally:
        print(f"\n{records} records, {drops} frames dropped, {bad} undecodable", file=sys.stderr)


if __name__ == "__main__":
    main()
