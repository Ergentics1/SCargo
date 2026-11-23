#!/usr/bin/env python3
# Copyright (c) 2026 Ergentics, LLC
# Licensed under the MIT License. See LICENSE in the project root.
"""
Zero-deprecation, self-healing Swift 6.4+ build & test runner with atomic cross-CPU
CLOCK_BOOTTIME monotonicity preflight guard (OBS-01 resolution R-B1).

Why this exists (Lamport 1978; Swift SE-0329; swift-build ElapsedTimer.swift:71):
  - Swift 6.4 switched the default SwiftPM backend to `swiftbuild` and deprecated
    `--build-system native`.
  - `swiftlang/swift-build` traps with SIGILL (`ud2`) in `ElapsedTimerInterval.init`
    whenever `ContinuousClock` (`CLOCK_BOOTTIME` on Linux) steps backward across vCPUs
    (e.g., KVM guests with `clocksource=tsc` and cross-vCPU TSC offset).
  - Instead of hiding the defect or falling back to a deprecated build system, this
    runner:
      1. Deterministically probes cross-CPU `CLOCK_BOOTTIME` monotonicity (< 5 ms).
      2. Surfaces any observed host skew visibly as structured JSON / stderr output.
      3. On clean hosts (`backward == 0`): runs unmodified multi-core default `swiftbuild`.
      4. On skewed hosts (`backward > 0`): fails closed if `--fail-on-skew` is set;
         otherwise verifies single-CPU monotonicity on `pin_cpu` (`0` regressions) and
         executes unmodified default `swiftbuild` pinned via `os.sched_setaffinity`
         (zero ambient `taskset` dependency, zero `--build-system native` deprecation warnings).
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import threading
import time
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass(frozen=True)
class ClockSkewReceipt:
    clock_name: str
    clocksource: str
    online_cpus: list[int]
    samples_per_pair: int
    cross_cpu_backward_count: int
    cross_cpu_worst_skew_ns: int
    pinned_cpu: int | None
    pinned_cpu_backward_count: int
    healing_mode: str
    passed_without_healing: bool


def read_linux_clocksource() -> str:
    p = Path("/sys/devices/system/clocksource/clocksource0/current_clocksource")
    if p.is_file():
        return p.read_text(encoding="utf-8").strip()
    return "non-linux-or-unavailable"


def get_available_cpus() -> list[int]:
    if hasattr(os, "sched_getaffinity"):
        return sorted(os.sched_getaffinity(0))
    return [0]


def probe_pair(cpu_a: int, cpu_b: int, clock_id: int, samples: int) -> tuple[int, int]:
    """Producer on cpu_a captures timestamp; consumer on cpu_b captures later timestamp."""
    if not hasattr(os, "sched_setaffinity"):
        backward = 0
        worst = 0
        prev = time.clock_gettime_ns(clock_id)
        for _ in range(samples):
            cur = time.clock_gettime_ns(clock_id)
            delta = cur - prev
            if delta < 0:
                backward += 1
                if delta < worst:
                    worst = delta
            prev = cur
        return backward, worst

    shared = [0]
    ev1 = threading.Event()
    ev2 = threading.Event()
    backward = [0]
    worst = [0]

    def producer() -> None:
        os.sched_setaffinity(0, {cpu_a})
        for _ in range(samples):
            shared[0] = time.clock_gettime_ns(clock_id)
            ev1.set()
            ev2.wait()
            ev2.clear()

    def consumer() -> None:
        os.sched_setaffinity(0, {cpu_b})
        for _ in range(samples):
            ev1.wait()
            ev1.clear()
            delta = time.clock_gettime_ns(clock_id) - shared[0]
            if delta < 0:
                backward[0] += 1
                if delta < worst[0]:
                    worst[0] = delta
            ev2.set()

    tp = threading.Thread(target=producer)
    tc = threading.Thread(target=consumer)
    tp.start()
    tc.start()
    tp.join()
    tc.join()
    return backward[0], worst[0]


def run_clock_preflight(samples: int, pin_cpu: int) -> ClockSkewReceipt:
    clock_id = getattr(time, "CLOCK_BOOTTIME", time.CLOCK_MONOTONIC)
    clock_name = "CLOCK_BOOTTIME" if hasattr(time, "CLOCK_BOOTTIME") else "CLOCK_MONOTONIC"
    clocksource = read_linux_clocksource()
    cpus = get_available_cpus()

    total_back = 0
    worst_skew = 0
    if len(cpus) >= 2:
        # Test ordered pairs (c0, c1) and (c1, c0) for first two CPUs plus (c0, c_last)
        pairs = [(cpus[0], cpus[1]), (cpus[1], cpus[0])]
        if cpus[-1] != cpus[1]:
            pairs.append((cpus[0], cpus[-1]))
            pairs.append((cpus[-1], cpus[0]))
        for a, b in pairs:
            b_cnt, w_ns = probe_pair(a, b, clock_id, samples)
            total_back += b_cnt
            if w_ns < worst_skew:
                worst_skew = w_ns
    else:
        b_cnt, w_ns = probe_pair(cpus[0], cpus[0], clock_id, samples)
        total_back += b_cnt
        worst_skew = w_ns

    if total_back == 0:
        return ClockSkewReceipt(
            clock_name=clock_name,
            clocksource=clocksource,
            online_cpus=cpus,
            samples_per_pair=samples,
            cross_cpu_backward_count=0,
            cross_cpu_worst_skew_ns=0,
            pinned_cpu=None,
            pinned_cpu_backward_count=0,
            healing_mode="none_required_multicore_swiftbuild",
            passed_without_healing=True,
        )

    chosen_pin = pin_cpu if pin_cpu in cpus else cpus[0]
    pin_back, _ = probe_pair(chosen_pin, chosen_pin, clock_id, samples)
    return ClockSkewReceipt(
        clock_name=clock_name,
        clocksource=clocksource,
        online_cpus=cpus,
        samples_per_pair=samples,
        cross_cpu_backward_count=total_back,
        cross_cpu_worst_skew_ns=worst_skew,
        pinned_cpu=chosen_pin,
        pinned_cpu_backward_count=pin_back,
        healing_mode="sched_setaffinity_single_cpu_swiftbuild",
        passed_without_healing=False,
    )


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description=(
            "Run default Swift 6.4+ swiftbuild with an explicit cross-CPU CLOCK_BOOTTIME "
            "monotonicity preflight guard and zero-deprecation self-healing."
        )
    )
    p.add_argument("--swift-bin", type=str, default=None, help="Explicit path to swift executable.")
    p.add_argument("--samples", type=int, default=400, help="Cross-CPU probe handoff samples per pair.")
    p.add_argument("--pin-cpu", type=int, default=0, help="CPU core to pin to if host skew is detected.")
    p.add_argument(
        "--fail-on-skew",
        action="store_true",
        help="Fail closed (exit 3) when host cross-CPU clock skew is detected instead of pinning.",
    )
    p.add_argument(
        "--probe-only",
        action="store_true",
        help="Emit JSON ClockSkewReceipt and exit without invoking swift.",
    )
    p.add_argument(
        "--check-zero-warnings",
        action="store_true",
        help="Fail closed (exit 5) if swift stdout/stderr emits any 'warning:' diagnostic.",
    )
    p.add_argument(
        "--receipt-out",
        type=Path,
        default=None,
        help="Optional path to write JSON ClockSkewReceipt.",
    )
    p.add_argument("swift_args", nargs=argparse.REMAINDER, help="Arguments passed after '--' to swift.")
    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    swift_args = list(args.swift_args)
    if swift_args and swift_args[0] == "--":
        swift_args = swift_args[1:]

    receipt = run_clock_preflight(samples=args.samples, pin_cpu=args.pin_cpu)
    receipt_json = json.dumps(asdict(receipt), indent=2)
    if args.receipt_out is not None:
        args.receipt_out.parent.mkdir(parents=True, exist_ok=True)
        args.receipt_out.write_text(receipt_json + "\n", encoding="utf-8")

    if not receipt.passed_without_healing:
        print(
            f"[CLOCK_SKEW_GUARD] Host {receipt.clock_name} skewed on clocksource={receipt.clocksource}: "
            f"backward={receipt.cross_cpu_backward_count}, worst_skew_ns={receipt.cross_cpu_worst_skew_ns} "
            f"({receipt.cross_cpu_worst_skew_ns / 1e6:.3f} ms). "
            f"Pinned-CPU {receipt.pinned_cpu} check: backward={receipt.pinned_cpu_backward_count}.",
            file=sys.stderr,
        )

    if args.probe_only:
        print(receipt_json)
        if args.fail_on_skew and not receipt.passed_without_healing:
            return 3
        return 0

    if args.fail_on_skew and not receipt.passed_without_healing:
        print(
            "[FAIL] --fail-on-skew active: refusing to run on skewed host clocksource "
            f"({receipt.clocksource}). Heal: switch host to kvm-clock or re-run without --fail-on-skew "
            "for bounded single-CPU affinity healing.",
            file=sys.stderr,
        )
        return 3

    if not receipt.passed_without_healing and receipt.pinned_cpu_backward_count > 0:
        print(
            f"[FAIL] Even single-CPU {receipt.pinned_cpu} clock went backward "
            f"({receipt.pinned_cpu_backward_count}x); cannot safely heal via CPU affinity.",
            file=sys.stderr,
        )
        return 4

    if not swift_args:
        print("Usage: swift_guarded_build.py [options] -- build|test|run [swift-args...]", file=sys.stderr)
        return 2

    swift_bin = args.swift_bin or shutil.which("swift")
    if not swift_bin:
        print("[FAIL] swift binary not found on PATH; pass --swift-bin.", file=sys.stderr)
        return 2

    preexec = None
    if receipt.pinned_cpu is not None and hasattr(os, "sched_setaffinity"):
        pin_target = receipt.pinned_cpu

        def _pin() -> None:
            os.sched_setaffinity(0, {pin_target})

        preexec = _pin
        print(
            f"[CLOCK_SKEW_GUARD] Healing active: pinning default SwiftPM swiftbuild to CPU {pin_target} "
            "(0 deprecation warnings; re-evaluated automatically on every invocation).",
            file=sys.stderr,
        )

    proc = subprocess.run(
        [swift_bin, *swift_args],
        capture_output=args.check_zero_warnings,
        text=True,
        preexec_fn=preexec,
        check=False,
    )
    if args.check_zero_warnings:
        if proc.stdout:
            sys.stdout.write(proc.stdout)
        if proc.stderr:
            sys.stderr.write(proc.stderr)
        combined = (proc.stdout or "") + "\n" + (proc.stderr or "")
        if proc.returncode == 0 and "warning:" in combined.lower():
            print(
                "[FAIL] --check-zero-warnings tripped: swift output contained a warning diagnostic.",
                file=sys.stderr,
            )
            return 5

    return proc.returncode


if __name__ == "__main__":
    raise SystemExit(main())
