"""Integration test, pins to pins: MII source in, UART sink out, records
decoded with the host protocol module. A small MDIO PHY model watches
bring-up.

Checks: BMCR forced at bring-up; records for a protocol mix; bad-FCS frames
never appear; COBS edge cases (zeros, long non-zero runs); and under a
line-rate burst, every frame is either delivered whole or counted in a
later record's drop field."""

import logging
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
from cocotb.utils import get_sim_time
from cocotbext.eth import GmiiFrame, MiiSource
from cocotbext.uart import UartSink
from scapy.layers.inet import ICMP, IP, TCP, UDP
from scapy.layers.inet6 import IPv6
from scapy.layers.l2 import ARP, Dot1Q, Ether
from scapy.packet import Raw

import common
from mdio_phy import MdioPhy
from sniffer.protocol import BadRecord, Decoder, Record

SYS_HZ = 100_000_000
PRESCALE = 8                    # fastest taxi_uart setting: f_sys / 8
BAUD = SYS_HZ // PRESCALE       # 12.5 Mbaud in simulation
SNAPLEN = 300
FIFO_DEPTH = 4096
PHY_ADDR = 1

MAC_A = "02:00:00:00:00:01"
MAC_B = "02:00:00:00:00:02"


class TB:
    def __init__(self, dut):
        self.dut = dut
        self.log = logging.getLogger("cocotb.tb")
        cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
        cocotb.start_soon(Clock(dut.mii_rx_clk, 40, unit="ns").start())
        cocotb.start_soon(Clock(dut.mii_tx_clk, 40, unit="ns").start())

        self.mii = MiiSource(dut.mii_rxd, dut.mii_rx_er, dut.mii_rx_dv, dut.mii_rx_clk)
        self.mii.log.setLevel(logging.WARNING)
        self.uart = UartSink(dut.uart_txd, baud=BAUD, bits=8)
        self.uart.log.setLevel(logging.WARNING)
        self.phy = MdioPhy(dut.mdc, dut.mdio_o, dut.mdio_t, dut.mdio_i, PHY_ADDR, {})

        self.decoder = Decoder()
        self.records: list[Record] = []
        self.bad: list[BadRecord] = []
        self.last_rx_ns = 0
        cocotb.start_soon(self._reader())

    async def _reader(self):
        while True:
            data = await self.uart.read(1)
            self.last_rx_ns = get_sim_time("ns")
            for r in self.decoder.feed(data):
                (self.records if isinstance(r, Record) else self.bad).append(r)

    async def start(self):
        self.dut.rst.value = 1
        self.dut.mii_rxd.value = 0
        self.dut.mii_rx_dv.value = 0
        self.dut.mii_rx_er.value = 0
        await ClockCycles(self.dut.clk, 20)
        self.dut.rst.value = 0
        for _ in range(100):
            await Timer(5, unit="us")
            if self.dut.led.value.to_unsigned() & 0b1000:
                return
        raise AssertionError("PHY init never finished")

    async def send(self, frames, bad_fcs=False, paced=False):
        """paced: wait for each frame's record before sending the next, so the
        UART (far slower than the line) never forces a drop."""
        for f in frames:
            if bad_fcs:
                gf = GmiiFrame.from_raw_payload(f + b"\xde\xad\xbe\xef")
            else:
                gf = GmiiFrame.from_payload(f, min_len=0)
            n = len(self.records)
            await self.mii.send(gf)
            if paced and not bad_fcs:
                for _ in range(400):
                    if len(self.records) > n:
                        break
                    await Timer(5, unit="us")
                else:
                    raise AssertionError("no record for a paced frame")
        await self.mii.wait()

    async def drain(self, quiet_us=200, timeout_us=40000):
        """Wait until nothing has arrived on the UART for quiet_us."""
        await self.mii.wait()
        start = get_sim_time("ns")
        while True:
            await Timer(10, unit="us")
            now = get_sim_time("ns")
            if now - max(self.last_rx_ns, start) > quiet_us * 1000:
                return
            assert now - start < timeout_us * 1000, "UART never went quiet"


def protocol_mix(n):
    def pl():
        return Raw(bytes(random.getrandbits(8) for _ in range(random.randint(0, 400))))
    makers = [
        lambda: Ether(src=MAC_A, dst=MAC_B) / IP(src="10.0.0.1", dst="10.0.0.2") / TCP(dport=80) / pl(),
        lambda: Ether(src=MAC_A, dst=MAC_B) / IP(src="10.0.0.3", dst="8.8.8.8") / UDP(sport=5353, dport=53) / pl(),
        lambda: Ether(src=MAC_A, dst=MAC_B) / IP() / ICMP(type=8) / pl(),
        lambda: Ether(src=MAC_A, dst="ff:ff:ff:ff:ff:ff") / ARP(psrc="10.0.0.1", pdst="10.0.0.5"),
        lambda: Ether(src=MAC_A, dst=MAC_B) / Dot1Q(vlan=42) / IP() / UDP() / pl(),
        lambda: Ether(src=MAC_A, dst="33:33:00:00:00:01") / IPv6() / UDP() / pl(),
    ]
    out = []
    for _ in range(n):
        f = bytes(random.choice(makers)())
        out.append(f + bytes(max(0, 60 - len(f))))
    return out


def check_records(recs, frames, drops_expected=0):
    assert len(recs) == len(frames), f"{len(recs)} records for {len(frames)} frames"
    for i, (r, f) in enumerate(zip(recs, frames)):
        assert r.orig_len == len(f), f"record {i}: orig_len {r.orig_len} != {len(f)}"
        assert r.data == f[:SNAPLEN], f"record {i}: payload mismatch"
        assert r.drops == drops_expected, f"record {i}: drops {r.drops}"
    ts = [r.ts_ticks for r in recs]
    assert all(b > a for a, b in zip(ts, ts[1:])), "timestamps not increasing"


@cocotb.test()
async def bringup(dut):
    tb = TB(dut)
    await tb.start()
    await Timer(20, unit="us")
    assert tb.phy.writes == [(PHY_ADDR, 0, 0x2100)], f"MDIO writes: {tb.phy.writes}"
    assert int(dut.phy_rst_n.value) == 1


@cocotb.test()
async def capture_protocol_mix(dut):
    tb = TB(dut)
    await tb.start()
    frames = protocol_mix(30)
    await tb.send(frames, paced=True)
    await tb.drain()
    check_records(tb.records, frames)
    assert not tb.bad, f"undecodable records: {tb.bad[:2]}"


@cocotb.test()
async def bad_fcs_dropped(dut):
    tb = TB(dut)
    await tb.start()
    good, bad = protocol_mix(6), protocol_mix(5)
    await tb.send(good[:3], paced=True)
    await tb.send(bad, bad_fcs=True)
    await tb.send(good[3:], paced=True)
    await tb.drain()
    check_records(tb.records, good)


@cocotb.test()
async def cobs_edge_payloads(dut):
    """Records full of 0x00 and with non-zero runs longer than 254 bytes."""
    tb = TB(dut)
    await tb.start()
    hdr = bytes(Ether(src=MAC_A, dst=MAC_B, type=0x88B5))
    frames = [
        hdr + bytes(286),
        hdr + b"\x55" * 400,
        hdr + b"\x55" * 240 + b"\x00" + b"\xaa" * 100,
        hdr + b"\x00\x01" * 150,
        b"\xff" * 6 + bytes(54),
    ]
    await tb.send(frames, paced=True)
    await tb.drain()
    check_records(tb.records, frames)
    assert not tb.bad


@cocotb.test()
async def burst_accounting(dut):
    tb = TB(dut)
    await tb.start()
    frames = []
    for i in range(200):
        n = random.randint(60, 600)
        body = i.to_bytes(2, "big") + bytes(random.getrandbits(8) for _ in range(n - 16))
        frames.append(bytes(Ether(src=MAC_A, dst=MAC_B, type=0x88B5)) + body)
    await tb.send(frames)
    await tb.drain(quiet_us=300)
    marker = bytes(Ether(src=MAC_A, dst=MAC_B, type=0x88B6)) + bytes(50)
    await tb.send([marker])
    await tb.drain()

    recs = tb.records
    assert recs[-1].data == marker[:SNAPLEN], "flush frame missing"
    delivered = recs[:-1]
    dropped = sum(r.drops for r in recs)
    tb.log.info("burst: %d delivered, %d dropped", len(delivered), dropped)
    assert dropped > 0, "burst did not fill the FIFO"
    assert len(delivered) + dropped == len(frames), \
        f"{len(delivered)} delivered + {dropped} dropped != {len(frames)} sent"

    # each delivered record is complete, in order, and matches its own frame
    seq = [int.from_bytes(r.data[14:16], "big") for r in delivered]
    assert seq == sorted(seq), "records out of order"
    for r, s in zip(delivered, seq):
        f = frames[s]
        assert r.orig_len == len(f) and r.data == f[:SNAPLEN]
    assert not tb.bad


def test_top():
    common.run(
        toplevel="sniffer_core",
        sources=common.rtl("sync_ff.sv", "async_frame_fifo.sv", "record_builder.sv",
                           "phy_init.sv", "sniffer_core.sv")
        + common.taxi(
            "eth/rtl/taxi_eth_mac_mii.f",
            "axis/rtl/taxi_axis_cobs_encode.f",
            "lss/rtl/taxi_uart.f",
            "lss/rtl/taxi_mdio_master.sv",
        ),
        test_file=__file__,
        parameters={
            "SIM": 1,
            "SNAPLEN": SNAPLEN,
            "FIFO_DEPTH": FIFO_DEPTH,
            "UART_PRESCALE": PRESCALE,
            "PHY_RESET_CYCLES": 10,
            "PHY_WAIT_CYCLES": 100,
            "LED_STRETCH_W": 4,
        },
    )
