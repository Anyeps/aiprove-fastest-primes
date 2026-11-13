# fastest-primes — AIProve bounty entry

Count primes ≤ N (1 ≤ N ≤ 5,000,000). Reads one integer N from stdin,
prints π(N) on stdout.

## Build

```sh
make
```

Needs only `gcc` — no libraries, no dependencies. Produces `./primes`
(9.4 KB static binary).

## Run

```sh
echo 5000000 | ./primes
# 348513
```

## How fast

Wall-clock per run (fork+exec, 200 runs each, AMD EPYC shared VM —
the grader machine will differ, but the relative gaps hold):

| N | min | p50 |
|---|-----|-----|
| 5,000,000 | 2.63 ms | 2.86 ms |
| 1,000,000 | 0.59 ms | 0.73 ms |
| 100,000 | 0.24 ms | 0.37 ms |
| 1,000 | 0.22 ms | 0.33 ms |
| 100 | 0.22 ms | 0.36 ms |
| 10 | 0.21 ms | 0.30 ms |

For comparison, on the same machine:

| implementation | N=5,000,000 (min) |
|---|---|
| this entry | **2.63 ms** |
| same algorithm, scalar counting (no AVX2) | 3.48 ms |
| odd-only byte sieve, dynamic libc build | 6.66 ms |
| Python bytearray sieve (sieve only, excl. ~25 ms interpreter startup) | ~56 ms |

## Approach

1. **Wheel-6 sieve.** The array holds only numbers coprime to 6
   (residues 1, 5 mod 6) — ~N/3 bytes instead of N/2 (odd-only) or N.
   Marking a prime p walks its multiples with two alternating index
   steps: `p = 6k+1 → (8k+1, 4k+1)`, `p = 6k+5 → (4k+3, 8k+7)`.
   (Consecutive numbers coprime to 6 have gaps 4,2,4,2,…; index
   density is 1 per 3 integers.) This alone cut N=5,000,000 from
   6.6 ms to 4.0 ms.
2. **No libc, no dynamic loader.** `_start` + raw syscalls
   (`read`/`write`/`exit`) and a BSS sieve array. Saves ~0.5 ms of
   startup per run (dominant cost for small N) and the build needs
   nothing but gcc.
3. **AVX2 counting with runtime dispatch.** The counting pass is
   ~0.9 ms scalar; with AVX2 (`cmpeq` + `movemask` + `popcnt`,
   32 bytes/iteration) it is ~0.4 ms. Availability is checked at
   runtime via cpuid + XCR0, with a plain-loop fallback, so the
   binary runs on any x86-64 Linux box — no `-march=native`, no
   SIGILL risk.
4. **Raw I/O.** Hand-rolled integer parse/print, no stdio.

## Correctness

- All 5 public cases from `cases.json`: 10→4, 100→25, 1000→168,
  100000→9592, 1000000→78498.
- Edge cases: 1→0, 2→1, 3→2, 4→2, 5→3, 4999999→348513,
  5000000→348513.
- 326 random + boundary values across 1..5,000,000, all matching an
  independent Python sieve — 0 mismatches.
- Both code paths (AVX2 and scalar fallback) verified to produce
  identical output on all test values.

## Files

- `primes.c` — the whole entry (single file, ~200 lines)
- `Makefile` — `make` builds `./primes`; `make check` runs the
  public cases + edge cases; `make dynamic` builds a libc-linked
  variant of the same algorithm
- `transcript.md` — build log: variants tried, measurements, bugs
  found and fixed
