"""herdr-oom-guard picks the biggest Herdr pane process and trips before systemd-oomd."""

from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin/bin/herdr-oom-guard"
GIB = 2**30


def load(cgroup_root, proc):
    env = {"HERDR_OOM_GUARD_CGROUP_ROOT": str(cgroup_root), "HERDR_OOM_GUARD_PROC": str(proc)}
    with mock.patch.dict(os.environ, env):
        loader = SourceFileLoader("herdr_oom_guard", str(SCRIPT))
        module = module_from_spec(spec_from_loader(loader.name, loader))
        loader.exec_module(module)
    return module


class HerdrOomGuardTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.cgroups, self.proc = base / "cgroup", base / "proc"
        self.guard = load(self.cgroups, self.proc)
        self.slice = self.guard.app_slice()

    def tearDown(self):
        self.tmp.cleanup()

    def unit(self, name, pids):
        path = self.slice / name
        path.mkdir(parents=True, exist_ok=True)
        (path / "cgroup.procs").write_text("".join(f"{pid}\n" for pid in pids))

    def process(self, pid, comm, rss, swap=0):
        path = self.proc / str(pid)
        path.mkdir(parents=True)
        (path / "status").write_text(f"Name:\t{comm}\nVmRSS:\t{rss // 1024} kB\nVmSwap:\t{swap // 1024} kB\n")
        (path / "comm").write_text(comm + "\n")
        (path / "cmdline").write_bytes(f"{comm}\0--flag\0".encode())

    def test_picks_largest_pane_process_counting_swap(self):
        self.unit("hc-hold-abc.service", [10, 11, 12])
        self.process(10, "herdr-core", 8 * GIB)
        self.process(11, "claude", 2 * GIB)
        self.process(12, "cargo-test", 1 * GIB, swap=3 * GIB)
        self.unit("chrome.scope", [20])
        self.process(20, "chrome", 30 * GIB)
        pid, size, comm, cmdline = self.guard.pick_victim()
        self.assertEqual((pid, size, comm, cmdline), (12, 4 * GIB, "cargo-test", "cargo-test --flag"))

    def test_finds_processes_in_nested_cgroups(self):
        self.unit("hc-hold-abc.service", [])
        self.unit("hc-hold-abc.service/pane-1", [30])
        self.process(30, "node", 2 * GIB)
        self.assertEqual(self.guard.pick_victim()[0], 30)

    def test_leaves_small_processes_alone(self):
        self.unit("hc-hold-abc.service", [10])
        self.process(10, "bash", 100 * 2**20)
        self.assertIsNone(self.guard.pick_victim())

    def test_skips_processes_that_exited(self):
        self.unit("hc-hold-abc.service", [10, 99])
        self.process(10, "node", 1 * GIB)
        self.assertEqual(self.guard.pick_victim()[0], 10)

    def test_memory_and_swap_both_needed(self):
        trigger = self.guard.Trigger()
        self.assertIsNone(trigger.reason(0.95, 0.30, 0, 0))
        self.assertIsNone(trigger.reason(0.50, 0.95, 0, 0))
        self.assertIn("swap", trigger.reason(0.90, 0.80, 0, 0))

    def test_pressure_must_be_sustained(self):
        trigger = self.guard.Trigger()
        self.assertIsNone(trigger.reason(0.5, 0.5, 40, 100))
        self.assertIsNone(trigger.reason(0.5, 0.5, 40, 103))
        self.assertIsNone(trigger.reason(0.5, 0.5, 10, 104))
        self.assertIsNone(trigger.reason(0.5, 0.5, 40, 105))
        self.assertIn("pressure", trigger.reason(0.5, 0.5, 40, 110))

    def test_reads_meminfo_and_pressure(self):
        self.proc.mkdir(parents=True)
        (self.proc / "meminfo").write_text(
            "MemTotal: 1000 kB\nMemFree: 50 kB\nMemAvailable: 100 kB\nSwapTotal: 400 kB\nSwapFree: 100 kB\n")
        mem, swap = self.guard.memory_state()
        self.assertAlmostEqual(mem, 0.9)
        self.assertAlmostEqual(swap, 0.75)
        self.slice.mkdir(parents=True)
        (self.slice / "memory.pressure").write_text(
            "some avg10=60.00 avg60=1.00 avg300=0.00 total=1\nfull avg10=42.50 avg60=1.00 avg300=0.00 total=1\n")
        self.assertEqual(self.guard.full_pressure(), 42.5)


if __name__ == "__main__":
    unittest.main()
