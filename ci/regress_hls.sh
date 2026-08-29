#!/usr/bin/env bash
# ============================================================================
# regress_hls.sh -- SPECTRUM SENTRY HLS csim regression
# Runs each kernel's csim via vitis-run (2025.x unified CLI) and gates on
# the testbench "PASS:" line. Golden vectors are the SAME files the UVM
# regression uses (single source of truth).
# Usage: ./ci/regress_hls.sh [kernel ...]   (default: all four)
# ============================================================================
set -uo pipefail

AMD_TOOLS="${AMD_TOOLS:-C:/AMDDesignTools/2025.2}"
case "$AMD_TOOLS" in
  [A-Za-z]:/*) AMD_TOOLS="/$(echo "$AMD_TOOLS" | cut -d: -f1 | tr 'A-Z' 'a-z')$(echo "$AMD_TOOLS" | cut -d: -f2)" ;;
esac
VITIS_RUN="$AMD_TOOLS/Vitis/bin/vitis-run.bat"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOGDIR="$REPO_ROOT/build/logs"
mkdir -p "$LOGDIR"

export SENTRY_VECTORS="$REPO_ROOT/vectors"

ALL_KERNELS="fft_psd tile_pack replay_gov fir_chan"
KERNELS="${*:-$ALL_KERNELS}"

FAILED=0
for k in $KERNELS; do
  echo "== hls csim: $k"
  if [ ! -f "$REPO_ROOT/hls/$k/run_hls.tcl" ]; then
    echo "FAIL: $k (no run_hls.tcl)"; FAILED=1; continue
  fi
  ( cd "$REPO_ROOT/hls/$k" && \
    timeout 900 "$VITIS_RUN" --tcl run_hls.tcl --work_dir . \
    > "$LOGDIR/hls_${k}_csim.log" 2>&1 )
  rc=$?
  log="$LOGDIR/hls_${k}_csim.log"
  if [ $rc -ne 0 ] && ! grep -q "^PASS: " "$log"; then
    echo "FAIL: $k (exit $rc)"; tail -15 "$log"; FAILED=1; continue
  fi
  if ! grep -q "^PASS: " "$log"; then
    echo "FAIL: $k (no PASS line)"; tail -15 "$log"; FAILED=1; continue
  fi
  echo "PASS: $k  ($(grep '^PASS: ' "$log" | head -1))"
done

echo "----------------------------------------"
if [ $FAILED -eq 0 ]; then
  echo "HLS REGRESSION: PASS ($*)"
  exit 0
else
  echo "HLS REGRESSION: FAIL"
  exit 1
fi
