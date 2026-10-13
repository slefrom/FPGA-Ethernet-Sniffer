import logging
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer, with_timeout
from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource

import common

DEPTH = 256


def rand_pause(p):
    while True:
        yield random.random() < p


class TB:
    def __init__(self, dut, s_ps, m_ps):
        self.dut = dut
        self.s_ps, self.m_ps = s_ps, m_ps
        self.source = AxiStreamSource(AxiStreamBus.from_entity(dut.s_axis), dut.s_clk, dut.s_rst)
        self.sink = AxiStreamSink(AxiStreamBus.from_entity(dut.m_axis), dut.m_clk, dut.m_rst)
        self.source.log.setLevel(logging.WARNING)
        self.sink.log.setLevel(logging.WARNING)
        self.status = []
        self.multi = 0
        self.gray_errors = []

    async def start(self):
        # independent clocks with a random phase between them
        cocotb.start_soon(Clock(self.dut.s_clk, self.s_ps, unit="ps").start())
        await Timer(random.randint(0, self.m_ps), unit="ps")
        cocotb.start_soon(Clock(self.dut.m_clk, self.m_ps, unit="ps").start())
        cocotb.start_soon(self._status_monitor())
        cocotb.start_soon(self._gray_monitor(self.dut.s_clk, self.dut.s_rst, self.dut.uut.wr_gray_reg, "write"))
        cocotb.start_soon(self._gray_monitor(self.dut.m_clk, self.dut.m_rst, self.dut.uut.rd_gray_reg, "read"))

        self.dut.s_rst.value = 1
        self.dut.m_rst.value = 1
        await Timer(20 * max(self.s_ps, self.m_ps), unit="ps")
        self.dut.s_rst.value = 0
        self.dut.m_rst.value = 0
        await Timer(10 * max(self.s_ps, self.m_ps), unit="ps")

    async def _status_monitor(self):
        while True:
            await RisingEdge(self.dut.s_clk)
            hits = [n for n, s in (("good", self.dut.s_status_good_frame),
                                   ("bad", self.dut.s_status_bad_frame),
                                   ("ovf", self.dut.s_status_overflow)) if s.value]
            if len(hits) > 1:
                self.multi += 1
            self.status += hits

    async def _gray_monitor(self, clk, rst, sig, name):
        prev = None
        while True:
            await RisingEdge(clk)
            if rst.value:          
                prev = None
                continue
            v = int(sig.value)
            if prev is not None and bin(v ^ prev).count("1") > 1:
                self.gray_errors.append((name, prev, v))
            prev = v

    async def send(self, frames, bad=()):
        for i, f in enumerate(frames):
            tuser = [0] * (len(f) - 1) + [int(i in bad)]
            await self.source.send(AxiStreamFrame(f, tuser=tuser))
        await self.source.wait()
        await ClockCycles(self.dut.s_clk, 4)

    async def check(self, frames, bad=(), offset=0):
        """Status pulses for these frames start at index `offset`."""
        st = self.status[offset:offset + len(frames)]
        assert len(st) == len(frames), f"{len(st)} status pulses for {len(frames)} frames"
        assert self.multi == 0, "more than one status pulse in a cycle"
        expect = []
        for i, (f, s) in enumerate(zip(frames, st)):
            if i in bad:
                assert s in ("bad", "ovf"), f"frame {i}: bad frame reported {s}"
            else:
                assert s in ("good", "ovf"), f"frame {i}: good frame reported {s}"
            if s == "good":
                expect.append(f)
        for i, f in enumerate(expect):
            rx = await with_timeout(self.sink.recv(), 2000 * self.m_ps + 400 * len(f) * self.m_ps, "ps")
            assert bytes(rx.tdata) == f, f"output frame {i} differs (len {len(rx.tdata)} vs {len(f)})"
            tu = rx.tuser if isinstance(rx.tuser, list) else [rx.tuser]
            assert not any(tu), "tuser set on output"
        await Timer(200 * self.m_ps, unit="ps")
        assert self.sink.empty(), "extra data on the output"
        assert not self.gray_errors, f"multi-bit change on a crossing pointer: {self.gray_errors[:3]}"
        return st


def rand_frames(n, lo=1, hi=200):
    return [bytes(random.getrandbits(8) for _ in range(random.randint(lo, hi))) for _ in range(n)]

CLOCKS = [(40000, 10000), (10000, 40000), (10000, 10314), (13000, 7000), (7000, 13000), (10000, 10000)]


@cocotb.test()
@cocotb.parametrize(clocks=CLOCKS)
async def clock_ratios(dut, clocks):
    tb = TB(dut, *clocks)
    await tb.start()
    tb.source.set_pause_generator(rand_pause(0.3))
    tb.sink.set_pause_generator(rand_pause(0.3))
    frames = rand_frames(150)
    bad = {i for i in range(len(frames)) if random.random() < 0.1}
    await tb.send(frames, bad)
    st = await tb.check(frames, bad)
    logging.getLogger("cocotb.tb").info("clocks %s: %s", clocks, {k: st.count(k) for k in ("good", "bad", "ovf")})


@cocotb.test()
async def fast_reader_no_loss(dut):
    tb = TB(dut, 40000, 10000)
    await tb.start()
    frames = rand_frames(300, 20, 120)
    await tb.send(frames)
    st = await tb.check(frames)
    assert st.count("good") == len(frames)
    assert sum(map(len, frames)) > 50 * DEPTH


@cocotb.test()
async def overflow_and_recovery(dut):
    tb = TB(dut, 40000, 10000)
    await tb.start()
    tb.sink.pause = True
    frames = rand_frames(40, 30, 60)
    await tb.send(frames)
    tb.sink.pause = False
    st = await tb.check(frames)
    assert st.count("ovf") > 0 and st.count("good") > 0
    # the output register holds one entry outside the RAM
    assert sum(len(f) for f, s in zip(frames, st) if s == "good") <= DEPTH + 1

    more = rand_frames(30, 30, 60)
    await tb.send(more)
    st2 = await tb.check(more, offset=len(frames))
    assert st2.count("good") == len(more)


@cocotb.test()
async def frame_size_limits(dut):
    tb = TB(dut, 40000, 10000)
    await tb.start()
    exact = rand_frames(1, DEPTH, DEPTH)
    await tb.send(exact)
    assert (await tb.check(exact)) == ["good"]
    over = rand_frames(1, DEPTH + 1, DEPTH + 1)
    await tb.send(over)
    assert (await tb.check(over, offset=1)) == ["ovf"]
    after = rand_frames(5)
    await tb.send(after)
    assert (await tb.check(after, offset=2)).count("good") == 5


def test_async_frame_fifo():
    common.run(
        toplevel="test_async_frame_fifo",
        sources=common.rtl("sync_ff.sv", "async_frame_fifo.sv")
        + common.taxi("axis/rtl/taxi_axis_if.sv")
        + [__file__.replace(".py", ".sv")],
        test_file=__file__,
        parameters={"DEPTH": DEPTH},
    )
