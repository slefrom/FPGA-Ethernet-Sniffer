"""Minimal clause-22 MDIO PHY model for cocotb.

Watches MDC/MDIO from the FPGA's MDIO master, decodes read and write frames
(32-bit preamble, ST=01, OP, PHYAD, REGAD, TA, 16 data bits), answers reads
from a register dict and records writes.
"""

from __future__ import annotations

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge, Timer


class MdioPhy:
    def __init__(self, mdc, mdio_o, mdio_t, mdio_i, phy_addr=1, regs=None):
        self.mdc = mdc
        self.mdio_o = mdio_o
        self.mdio_t = mdio_t
        self.mdio_i = mdio_i
        self.phy_addr = phy_addr
        self.regs = dict(regs or {})
        self.writes: list[tuple[int, int, int]] = []   # (phy, reg, value)
        self.reads: list[tuple[int, int]] = []
        self.mdio_i.value = 1
        cocotb.start_soon(self._run())

    def _bit(self) -> int:
        # pulled up when the master is not driving
        if int(self.mdio_t.value):
            return 1
        return int(self.mdio_o.value)

    async def _drive(self, bits):
        """Drive one bit per MDC period, changing just after each rising edge."""
        for b in bits:
            await Timer(1, unit="ns")
            self.mdio_i.value = b
            await RisingEdge(self.mdc)
        await FallingEdge(self.mdc)
        self.mdio_i.value = 1

    async def _run(self):
        ones = 0
        while True:
            await RisingEdge(self.mdc)
            b = self._bit()
            if b:
                ones += 1
                continue
            if ones < 32:
                ones = 0
                continue
            ones = 0
            # this rising edge carried ST bit 0; collect the next 13 bits
            hdr = [0]
            for _ in range(13):
                await RisingEdge(self.mdc)
                hdr.append(self._bit())
            st = hdr[0:2]
            op = hdr[2] << 1 | hdr[3]
            phy = int("".join(map(str, hdr[4:9])), 2)
            reg = int("".join(map(str, hdr[9:14])), 2)
            if st != [0, 1]:
                continue
            if op == 0b10:
                # read: TA bit 1 is Z, TA bit 0 driven low by the PHY, then data
                self.reads.append((phy, reg))
                await RisingEdge(self.mdc)          # TA bit 1 (period 14)
                if phy == self.phy_addr:
                    val = self.regs.get(reg, 0xFFFF)
                    data = [(val >> (15 - i)) & 1 for i in range(16)]
                    await self._drive([0] + data)
                else:
                    for _ in range(17):
                        await RisingEdge(self.mdc)
            elif op == 0b01:
                bits = []
                for _ in range(18):                 # TA (2) + data (16)
                    await RisingEdge(self.mdc)
                    bits.append(self._bit())
                val = int("".join(map(str, bits[2:])), 2)
                self.writes.append((phy, reg, val))
                if phy == self.phy_addr:
                    self.regs[reg] = val
