"""Shared helpers for the cocotb testbenches.

Each test directory holds a thin SystemVerilog wrapper (Taxi style: the
taxi_axis_if interfaces live inside the wrapper so cocotb can reach their
signals) and a Python file with the cocotb tests plus a pytest entry point
that builds and runs the simulation with cocotb's Python runner.

Run everything from the repo root with:   pytest -n auto tb
Waveforms (FST) are written when WAVES=1 is set in the environment.
"""

from __future__ import annotations

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RTL_DIR = ROOT / "rtl"
TAXI_SRC = ROOT / "lib" / "taxi" / "src"

# Verilator: Taxi uses initial values on registers and leaves optional pins
# unconnected, so those style warnings are off. Unknown initial state is
# randomised (--x-initial unique + the rand-reset plusarg) to shake out
# registers that rely on initial values instead of reset.
VERILATOR_ARGS = [
    "-Wno-fatal",
    "-Wno-PINMISSING",
    "-Wno-PINCONNECTEMPTY",
    "-Wno-PROCASSINIT",
    "--x-assign", "unique",
    "--x-initial", "unique",
]
PLUSARGS = ["+verilator+rand+reset+2"]


def _resolve(entry: str, base: Path) -> Path:
    # Taxi .f files reference siblings as ../lib/taxi/src/<...>; map those
    # onto our own lib/taxi checkout.
    marker = "lib/taxi/src/"
    if marker in entry:
        return TAXI_SRC / entry.split(marker, 1)[1]
    return (base / entry).resolve()


def process_f_files(files) -> list[Path]:
    """Expand .f file lists recursively; later duplicates (by name) win."""
    out: dict[str, Path] = {}
    for f in files:
        f = Path(f)
        if f.suffix == ".f":
            entries = f.read_text().split()
            for sub in process_f_files([_resolve(e, f.parent) for e in entries]):
                out[sub.name] = sub
        else:
            out[f.name] = f
    return list(out.values())


def taxi(*rel: str) -> list[Path]:
    """Taxi sources by path relative to lib/taxi/src (.f lists allowed)."""
    return process_f_files([TAXI_SRC / r for r in rel])


def rtl(*names: str) -> list[Path]:
    """Our own RTL files; sniffer_pkg.sv is always first."""
    files = [RTL_DIR / "sniffer_pkg.sv"]
    files += [RTL_DIR / n for n in names if n != "sniffer_pkg.sv"]
    return files


def run(toplevel: str, sources, test_file: str, parameters=None, build_tag: str = ""):
    """Build `toplevel` with Verilator and run the cocotb tests in test_file."""
    from cocotb_tools.runner import get_results, get_runner

    test_dir = Path(test_file).resolve().parent
    module = Path(test_file).stem
    waves = os.environ.get("WAVES", "0") == "1"
    parameters = parameters or {}

    # interface definitions must come before their users
    srcs = process_f_files(sources)
    srcs.sort(key=lambda p: (p.name not in ("taxi_axis_if.sv", "sniffer_pkg.sv"),))

    tag = build_tag or "default"
    build_dir = test_dir / "sim_build" / tag

    runner = get_runner("verilator")
    runner.build(
        sources=[str(s) for s in srcs],
        hdl_toplevel=toplevel,
        parameters=parameters,
        build_args=VERILATOR_ARGS,
        build_dir=build_dir,
        timescale=("1ns", "1ps"),
        waves=waves,
    )
    results = runner.test(
        hdl_toplevel=toplevel,
        test_module=module,
        test_dir=test_dir,
        build_dir=build_dir,
        plusargs=PLUSARGS,
        waves=waves,
        extra_env={"PYTHONPATH": os.pathsep.join([str(ROOT / "tb"), str(ROOT / "host"), str(test_dir)])},
    )
    total, failed = get_results(results)
    assert total > 0, "no cocotb tests ran"
    assert failed == 0, f"{failed} of {total} cocotb tests failed"
