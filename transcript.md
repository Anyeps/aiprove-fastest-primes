# Build transcript — fastest-primes (AIProve)

Session log of how this entry was built, including every variant tried,
every measurement, and every bug found. Written as the work happened.

## 1. Read the spec

- `challenges/fastest-primes/README.md`: read N (1..5,000,000) from
  stdin, print pi(N). Metric is wall-clock latency on hidden N values;
  wrong output disqualifies before timing. Sandbox runs entries back to
  back on the same machine.
- `cases.json`: 10→4, 100→25, 1000→168, 100000→9592, 1000000→78498.
- Grader dir in the AIProve repo only implements FORECAST grading; the
  code-execution sandbox has no published build convention, so the entry
  is kept maximally simple: one C file + Makefile, `make` -> `./primes`.

## 2. Baseline: odd-only byte sieve (libc, dynamic, -O3)

`primes.c` v1: odd-only byte array, `calloc`, raw `read`/`write`,
hand-rolled parse/print, separate counting pass.

- All 5 public cases pass. Edge cases 1→0, 2→1, 3→2, 4→2, 5→3,
  5000000→348513 (known pi(5,000,000)).
- Cross-checked against an independent Python sieve on 16 values
  (incl. 123456→11601, 777777→62301, 2500000→183072, 4999963→348512,
  4999999→348513): all match.
- Timing harness (`bench.c`: fork+exec, `clock_gettime`, 200 runs):
  N=5,000,000 dynamic -O3: **min 6.657 ms, p50 7.498 ms**;
  N=10: min 0.681 ms (startup-dominated).

## 3. Variant sweep (N=5,000,000, 200 runs each)

| variant | min | p50 |
|---|---|---|
| dynamic -O3 | 6.657 ms | 7.498 ms |
| static -O3 | 6.270 ms | 6.534 ms |
| -march=native | 5.512 ms | 5.897 ms |
| -nostdlib -static | 6.088 ms | 6.311 ms |

Startup (N=10): dynamic 0.681 ms, static 0.413 ms, nostdlib 0.192 ms.
Conclusion: the dynamic loader + libc init cost ~0.5 ms per run, and
`-march=native` (AVX2-vectorised counting) saved ~1 ms. Both effects
were worth keeping, but `-march=native` carries a SIGILL risk if the
build machine and the run machine differ — so the final entry uses
runtime CPU dispatch instead of `-march=native`.

## 4. Where the time goes (dynamic -O3, N=5,000,000)

Full run 6.56 ms vs sieve-only (count skipped) 5.19 ms → counting pass
≈ 1.4 ms, sieve + startup ≈ 5.2 ms. Both needed work.

## 5. Bug found: unrolled marking loop overflowed for small N

A 4x-unrolled marking loop computed `stop4 = half - 3*step` as `size_t`.
For N=10 (half=5, step=3) this underflowed to a huge number and the
loop wrote out of bounds (heap overflow; N=10 printed nothing while
large N looked fine). Fixed by guarding the unrolled loop with
`if (half > 3 * step)`. Re-tested: all values correct. The unroll
itself gave no clear win over what -O3 already does, so it was dropped
from the final entry — but the bug is recorded here because the same
pattern is easy to reintroduce.

## 6. Wheel-6 sieve (the big win)

Replaced the odd-only sieve with a wheel-6 sieve: array holds only
numbers coprime to 6 (residues 1,5 mod 6), ~N/3 bytes. Marking steps
for prime p derived by hand and verified numerically for p = 5, 7, 11,
13 before coding:
- p = 6k+1 → alternating steps (8k+1, 4k+1)
- p = 6k+5 → alternating steps (4k+3, 8k+7)

Verified correct on all 16 cross-check values.
N=5,000,000: **min 4.006 ms, p50 4.242 ms** (was 6.56 ms) — a 39% cut.
N=1,000,000: min 1.220 ms. N=10: 0.664 ms.

## 7. Wheel-6 + nostdlib

Ported the wheel-6 sieve to `_start` + raw syscalls + BSS array
(no libc, no loader). Correct on all 16 values.
N=5,000,000: **min 3.458 ms, p50 3.693 ms**; N=1,000,000: 0.704 ms;
N=10: 0.183 ms. Binary 9,368 bytes, static ELF.

## 8. Counting pass: AVX2 with runtime dispatch

Split measurement on wheel-6/nostdlib: full 3.46 ms vs sieve-only
2.56 ms → counting ≈ 0.9 ms. Implemented `count_avx2` (32 bytes/iter,
`cmpeq` + `movemask` + `popcnt`) under `target("avx2,popcnt")`,
gated by a cpuid + XCR0 check (`have_avx2`), scalar fallback otherwise.

Build failure on first attempt: `_xgetbv` from `<immintrin.h>` is
`always_inline` and refuses to inline into a function compiled without
the xsave target. Fixed by issuing `xgetbv` via raw inline asm
instead of the intrinsic.

Final binary, N=5,000,000: **min 2.625 ms, p50 2.862 ms**.
Scalar fallback binary (built with `-DFORCE_NO_AVX2`): min 3.484 ms.
Both paths produce identical output on all 16 test values.

## 9. Final verification

- `make` from clean: builds with no warnings.
- Public cases + edge cases (`make check`): all pass.
- Random sweep: 326 random + boundary N values across 1..5,000,000
  vs an independent Python sieve — **0 mismatches**.
- Fresh-directory build test: copied `primes.c` + `Makefile` to a
  clean dir, `make` + `make check` pass (build is self-contained).

## 10. Final timings (200 runs each, AMD EPYC shared VM)

| N | min | p50 |
|---|---|---|
| 5,000,000 | 2.63 ms | 2.86 ms |
| 1,000,000 | 0.59 ms | 0.73 ms |
| 100,000 | 0.24 ms | 0.37 ms |
| 1,000 | 0.22 ms | 0.33 ms |
| 100 | 0.22 ms | 0.36 ms |
| 10 | 0.21 ms | 0.30 ms |

Overall vs the first baseline (odd-only, dynamic libc): 6.66 ms →
2.63 ms at N=5,000,000 (2.5x faster). A Python bytearray sieve needs
~56 ms for the sieve alone (plus ~25 ms interpreter startup).

## Decisions kept

- Default build is `-nostdlib -static -O3`, no `-march=native`:
  fastest startup, builds with gcc alone, runs on any x86-64 Linux.
- AVX2 is used only when the CPU reports it at runtime — speed
  without the SIGILL risk.
- No wheel-30: wheel-6 already captures most of the gain; wheel-30's
  per-prime step tables add bug risk for a smaller incremental win.
- Single source file, no generated files in the repo.
