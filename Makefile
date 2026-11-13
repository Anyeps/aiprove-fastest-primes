# fastest-primes — build the entry binary.
#
#   make            -> ./primes  (DEFAULT: gcc -O3 -nostdlib -static.
#                                 No libc, no dynamic loader, no CPU
#                                 assumptions: the binary runs on any
#                                 x86-64 Linux box and only uses AVX2
#                                 when the CPU reports it at runtime.)
#   make dynamic    -> ./primes  (plain libc build of the same algorithm,
#                                 for environments that insist on libc)
#   make check      -> runs the public cases + edge cases
#
# Run:  echo 5000000 | ./primes        -> 348513
CC      ?= gcc
CFLAGS  ?= -O3 -Wall -Wextra

all: primes

primes: primes.c
	$(CC) $(CFLAGS) -nostdlib -static -o $@ $<

dynamic: primes.c
	$(CC) $(CFLAGS) -o primes $<

check: primes
	@for n in 10 100 1000 100000 1000000; do \
		printf '%s => ' "$$n"; echo "$$n" | ./primes; done
	@for n in 1 2 3 4 5 5000000 4999999; do \
		printf '%s => ' "$$n"; echo "$$n" | ./primes; done

clean:
	rm -f primes

.PHONY: all dynamic check clean
