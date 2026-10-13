"""record_builder: timestamp latched at the first byte, frame truncated to
SNAPLEN, trailer with orig_len and drop count, bad flag only on the record's
last beat, drop count kept until the FIFO confirms a record was committed.
Built for two SNAPLEN values."""

import itertools
import logging
import os
import random

import cocotb
import pytest
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource

import common
from sniffer.protocol import Record, parse_record

SNAPLEN = int(os.environ.get("TB_SNAPLEN", "64"))


class TB:
    def __init__(self, dut):
        self.dut = dut
        cocotb.start_soon(Clock(dut.clk, 40, unit="ns").start())
        self.source = AxiStreamSource(AxiStreamBus.from_entity(dut.s_axis), dut.clk, dut.rst)
        self.sink = AxiStreamSink(AxiStreamBus.from_entity(dut.m_axis), dut.clk, dut.rst)
        self.source.log.setLevel(logging.WARNING)
        self.sink.log.setLevel(logging.WARNING)
        self.sof_ts = []
        self.overflows = 0
        cocotb.start_soon(self._monitor())

    async def _monitor(self):
        sof = True
        while True:
            await RisingEdge(self.dut.clk)
            if self.dut.overflow.value:
                self.overflows += 1
            if self.dut.s_axis.tvalid.value:
                if sof:
                    self.sof_ts.append(int(self.dut.ts_count.value))
                sof = bool(self.dut.s_axis.tlast.value)

    async def reset(self):
        self.dut.fifo_good.value = 0
        self.dut.fifo_overflow.value = 0
        self.dut.rst.value = 1
        await ClockCycles(self.dut.clk, 4)
        self.dut.rst.value = 0
        await ClockCycles(self.dut.clk, 4)
        self.sof_ts.clear()

    async def pulse(self, sig, n=1):
        for _ in range(n):
            sig.value = 1
            await RisingEdge(self.dut.clk)
            sig.value = 0
            await RisingEdge(self.dut.clk)

    async def send(self, data, bad=False, ifg=40):
        await self.source.send(AxiStreamFrame(data, tuser=[0] * (len(data) - 1) + [int(bad)]))
        await self.source.wait()
        if ifg:
            await ClockCycles(self.dut.clk, ifg)

    async def recv(self):
        rx = await self.sink.recv()
        tu = rx.tuser if isinstance(rx.tuser, list) else [rx.tuser] * len(rx.tdata)
        rec = parse_record(bytes(rx.tdata))
        assert isinstance(rec, Record), f"unparseable record: {rec}"
        return rec, tu


def frame(n):
    return bytes(random.getrandbits(8) for _ in range(n))


def check(rec, data, ts, drops=0):
    assert rec.ts_ticks == ts, f"ts {rec.ts_ticks} != {ts}"
    assert rec.orig_len == len(data), f"orig_len {rec.orig_len} != {len(data)}"
    assert rec.data == data[:SNAPLEN], f"payload: got {len(rec.data)} bytes, expected {min(len(data), SNAPLEN)}"
    assert rec.drops == drops, f"drops {rec.drops} != {drops}"


LENGTHS = [1, 2, SNAPLEN - 1, SNAPLEN, SNAPLEN + 1, 59, 60, 64, 100, 1514, 1518]


@cocotb.test()
async def mii_paced(dut):
    """One byte every two clocks with the MII inter-frame gap."""
    tb = TB(dut)
    await tb.reset()
    tb.source.set_pause_generator(itertools.cycle([0, 1]))
    frames = [frame(n) for n in LENGTHS + [random.randint(1, 600) for _ in range(20)]]
    for f in frames:
        await tb.send(f)
    for i, f in enumerate(frames):
        rec, tu = await tb.recv()
        check(rec, f, tb.sof_ts[i])
        assert not any(tu), "tuser on a good frame"
    assert tb.overflows == 0


@cocotb.test()
async def byte_every_cycle(dut):
    """Worst case input rate (one byte per clock) with the minimum gap."""
    tb = TB(dut)
    await tb.reset()
    frames = [frame(n) for n in LENGTHS + [random.randint(1, 300) for _ in range(30)]]
    for f in frames:
        await tb.send(f, ifg=20)
    for i, f in enumerate(frames):
        rec, _ = await tb.recv()
        check(rec, f, tb.sof_ts[i])
    assert tb.overflows == 0


@cocotb.test()
async def output_backpressure(dut):
    tb = TB(dut)
    await tb.reset()
    tb.source.set_pause_generator(itertools.cycle([0, 1]))
    tb.sink.set_pause_generator(itertools.cycle([0, 0, 1]))
    frames = [frame(random.randint(1, 200)) for _ in range(20)]
    for f in frames:
        await tb.send(f, ifg=200)
    for i, f in enumerate(frames):
        rec, _ = await tb.recv()
        check(rec, f, tb.sof_ts[i])
    assert tb.overflows == 0


@cocotb.test()
async def bad_flag_on_last_beat(dut):
    tb = TB(dut)
    await tb.reset()
    tb.source.set_pause_generator(itertools.cycle([0, 1]))
    frames = [(frame(random.randint(1, 300)), i % 2 == 1) for i in range(10)]
    for f, bad in frames:
        await tb.send(f, bad)
    for f, bad in frames:
        rec, tu = await tb.recv()
        assert not any(tu[:-1]), "tuser before the last beat"
        assert bool(tu[-1]) == bad


@cocotb.test()
async def drop_count(dut):
    """The FIFO is emulated: after each record the test either commits it
    (good pulse) or drops it (overflow pulse). Each record must report the
    drops since the last committed record."""
    tb = TB(dut)
    await tb.reset()
    tb.source.set_pause_generator(itertools.cycle([0, 1]))
    model = 0
    await tb.pulse(dut.fifo_overflow, 3)
    model += 3
    for i in range(40):
        await tb.send(frame(random.randint(20, 120)))
        rec, _ = await tb.recv()
        assert rec.drops == model, f"record {i}: drops {rec.drops}, expected {model}"
        if random.random() < 0.4:
            await tb.pulse(dut.fifo_overflow)       
            model += 1
        else:
            await tb.pulse(dut.fifo_good)           
            model -= rec.drops
        extra = random.choice([0, 0, 1, 2])         
        await tb.pulse(dut.fifo_overflow, extra)
        model += extra


@pytest.mark.parametrize("snaplen", [16, 64])
def test_record_builder(snaplen):
    os.environ["TB_SNAPLEN"] = str(snaplen)
    common.run(
        toplevel="test_record_builder",
        sources=common.rtl("record_builder.sv")
        + common.taxi("axis/rtl/taxi_axis_if.sv")
        + [__file__.replace(".py", ".sv")],
        test_file=__file__,
        parameters={"SNAPLEN": snaplen},
        build_tag=f"snaplen{snaplen}",
    )
