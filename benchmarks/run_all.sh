#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
# RNS Crystal Benchmark Runner
#
# Compiles and runs all benchmark suites in release mode for accurate
# performance measurement. Each benchmark is a standalone Crystal program.
#
# Usage:
#   ./benchmarks/run_all.sh          # Run all benchmarks
#   ./benchmarks/run_all.sh crypto   # Run only crypto benchmarks
#   ./benchmarks/run_all.sh packet   # Run only packet benchmarks
#   ./benchmarks/run_all.sh link     # Run only link benchmarks
#   ./benchmarks/run_all.sh resource # Run only resource benchmarks
# ═══════════════════════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

echo "════════════════════════════════════════════════════════════════"
echo "  RNS Crystal Performance Benchmarks"
echo "  Compiling in release mode (--release) for accurate results"
echo "════════════════════════════════════════════════════════════════"
echo

FILTER="${1:-all}"

run_bench() {
  local name="$1"
  local file="$2"

  if [ "$FILTER" != "all" ] && [ "$FILTER" != "$name" ]; then
    return
  fi

  echo ">>> Compiling $name benchmarks..."
  crystal build --release "$file" -o "benchmarks/bench_${name}" 2>&1
  echo ">>> Running $name benchmarks..."
  echo
  "./benchmarks/bench_${name}"
  echo
  rm -f "benchmarks/bench_${name}"
}

run_bench "crypto"   "benchmarks/crypto_bench.cr"
run_bench "packet"   "benchmarks/packet_bench.cr"
run_bench "link"     "benchmarks/link_bench.cr"
run_bench "resource" "benchmarks/resource_bench.cr"

echo "════════════════════════════════════════════════════════════════"
echo "  All benchmarks complete."
echo "════════════════════════════════════════════════════════════════"
