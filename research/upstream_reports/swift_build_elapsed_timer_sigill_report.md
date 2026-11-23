<!-- Copyright (c) 2026 Ergentics, LLC. Licensed under the MIT License. -->

# Upstream Bug Report Draft: `swiftlang/swift-build` — `SIGILL` (`ud2`) in `ElapsedTimerInterval.init` on Linux KVM Guests with Cross-vCPU TSC Skew

> **Status:** Draft prepared for review before optional submission to `https://github.com/swiftlang/swift-build/issues` (not posted).
> **Observed Toolchain:** Official Swift `6.4.3` (`swift-6.4.3-RELEASE`, `x86_64-unknown-linux-gnu`, PGP-verified via `swiftly 1.2.0`).
> **Verified Still Unpatched On:** `swiftlang/swift-build` `main` (commit `bd8b331f94`, `Sources/SWBUtil/ElapsedTimer.swift:71`).

---

## 1. Summary

On Linux x86_64 KVM guests using `clocksource=tsc` where guest vCPUs have a small static TSC offset (~2 ms), `swift build` (which defaults to `swiftbuild` starting in Swift 6.4) terminates deterministically with **`Signal 4 (SIGILL)`** inside `SWBUtil.ElapsedTimerInterval.init(duration:)` (inlined into `OperationDelegate.taskComplete(_:taskIdentifier:task:delegate:)`).

Because `ElapsedTimer` is used strictly for informational build-task telemetry (`BuildOperationTaskEnded`), a release-mode `precondition` aborting the entire build driver on a sub-2 ms backward `CLOCK_BOOTTIME` reading across `DispatchWorker` threads conflates observability with build soundness.

## 2. Environment

- **Swift version:** `Swift version 6.4.3 (swift-6.4.3-RELEASE)`, Target: `x86_64-unknown-linux-gnu`
- **OS / Kernel:** Ubuntu 24.04.5 LTS, `Linux 6.18.57 x86_64` under KVM (2 vCPUs)
- **Active Linux clocksource:** `tsc` (`available_clocksource`: `tsc kvm-clock acpi_pm`)
- **Measured cross-vCPU `CLOCK_BOOTTIME` skew (`5,000` pinned handoffs):**
  - `CPU 0 -> CPU 0`: `0 / 5,000` backward (min `+0.0069 ms`)
  - `CPU 1 -> CPU 1`: `0 / 5,000` backward (min `+0.0071 ms`)
  - `CPU 1 -> CPU 0`: `0 / 5,000` backward (median `+2.1306 ms`)
  - `CPU 0 -> CPU 1`: `4,995 / 5,000` backward (min `-2.0782 ms`, median `-2.0575 ms`)

## 3. Crash Stack Trace & Disassembly Proof

Command:
```bash
swift build --package-path compartments/swift
```

Crash trace (`swift-package`, Swift 6.4.3):
```text
*** Program crashed: Illegal instruction at 0x00005637a3bc01ef ***
Thread 7 "DispatchWorker" crashed:
 0 [inlined] [system] 0x00005637a3bc01ef specialized ElapsedTimer.elapsedTime()
 1                    0x00005637a3bc01ef specialized OperationDelegate.taskComplete(_:taskIdentifier:task:delegate:) + 2127
                      at Sources/SWBBuildService/BuildOperationMessages.swift:1348:39
```

Crash registers & decoded 128-bit `ContinuousClock.Instant` values:
- `r13` (`start`, captured on task start): `21636.411039009 s`
- `rsp` (`clock.now`, captured on `taskComplete`): `21636.410038474 s`
- Exact delta `clock.now - start`: **`-1,000,535 ns` (`-1.000535 ms`)**
- `Duration.components`: `seconds = 0` (`rax = 0x0`), `attoseconds = -1,000,535,000,000,000` (`rcx = 0xfffc7204cabd5a00`)
- Disassembly of `swift-package` around file offset `0x1aedb0f`–`0x1aee1ef`:
  - `1aedb14`: `test %rax, %rax; js 1aee1ed` (`seconds >= 0` succeeds)
  - `1aedb28`: `test %rdx, %rdx; js 1aee1ef` (`attoseconds >= 0` fails → jumps to `0f 0b` (`ud2`) at `1aee1ef`)

## 4. Exact Root Cause in `swiftlang/swift-build`

1. On Linux, `ContinuousClock.now` calls `clock_gettime(CLOCK_BOOTTIME, &continuous)` (`swiftlang/swift` `stdlib/public/Concurrency/Clock.cpp:52`).
2. `TaskOutputHandler` captures `let timer = ElapsedTimer()` on the `DispatchWorker` thread running `taskStarted` (`Sources/SWBBuildService/BuildOperationMessages.swift:741`).
3. `OperationDelegate.taskComplete` evaluates `delegate.timer.elapsedTime()` on another `DispatchWorker` thread (`BuildOperationMessages.swift:1348`).
4. For any fast task (`< 2.09 ms`) migrating from vCPU 0 to vCPU 1, `start.duration(to: clock.now)` returns a slightly negative `Duration`, hitting the unconditional release trap in `Sources/SWBUtil/ElapsedTimer.swift:71`:
   ```swift
   fileprivate init(duration: Duration) {
       precondition(duration.components.seconds >= 0 && duration.components.attoseconds >= 0, "Duration must be positive")
       self.duration = duration
   }
   ```
5. **Control verification:** Pinning unmodified `swift build` (`swiftbuild`) to a single vCPU (`taskset -c 0 swift build`) succeeds reliably (`exit 0`, `[42 / 42]`, 0 warnings). `--build-system native` also succeeds (does not invoke `SWBUtil.ElapsedTimerInterval`) but is deprecated in Swift 6.4.

## 5. Minimal Standalone Reproducer

On any Linux guest with cross-vCPU `CLOCK_BOOTTIME` skew (or using a mock `Clock` whose `now` steps backward by 1 ms):

```swift
import SWBUtil

struct SkewedClock: Clock {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }
    final class State: @unchecked Sendable { var ticks = 0 }
    let state = State()
    var minimumResolution: Duration { .nanoseconds(1) }
    var now: Instant {
        state.ticks += 1
        // Simulate vCPU 0 -> vCPU 1 -1.000535 ms TSC skew between task start and completion
        return state.ticks == 1 ? Instant(offset: .nanoseconds(1_000_535)) : Instant(offset: .zero)
    }
    func sleep(until deadline: Instant, tolerance: Duration?) async throws {}
}

let timer = ElapsedTimer(clock: SkewedClock())
_ = timer.elapsedTime() // Crashes with SIGILL (ud2): "Duration must be positive"
```

## 6. Suggested Minimal Upstream Fix

Align `ElapsedTimer.elapsedTime()` with Rust's `std::time::Instant::elapsed()` (which saturates to `Duration::ZERO` on backward OS/hypervisor clock readings rather than aborting the process; see `rust-lang/rust` `library/std/src/time.rs` *"Monotonicity"*):

```diff
--- a/Sources/SWBUtil/ElapsedTimer.swift
+++ b/Sources/SWBUtil/ElapsedTimer.swift
@@ -34,7 +34,8 @@ public struct ElapsedTimer<ClockType: Clock>: Sendable where ClockType.Duration
     ///
     /// This value is guaranteed to be positive.
     public func elapsedTime() -> ElapsedTimerInterval {
-        return ElapsedTimerInterval(duration: start.duration(to: clock.now))
+        let raw = start.duration(to: clock.now)
+        return ElapsedTimerInterval(duration: raw < .zero ? .zero : raw)
     }
```

Optionally expose a non-clamping `checkedElapsedTime() -> Duration` helper or debug metric counter if callers wish to observe host clock skew without crashing release builds.
