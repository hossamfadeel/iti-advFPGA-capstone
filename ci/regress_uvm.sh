#!/usr/bin/env bash
# ============================================================================
# regress_uvm.sh -- SPECTRUM SENTRY UVM regression (the virtual ZCU102)
# Compiles RTL + UVM env + all TB tops against the xsim-bundled UVM 1.2
# (compiled with UVM_NO_DPI: pure SystemVerilog, no C linking) and runs each
# testbench. PASS requires: exit 0 AND a final "PASS: <test>" line AND
# zero UVM_ERROR/UVM_FATAL.
# Usage: ./ci/regress_uvm.sh [tb1 tb2 ...]   (default: all four)
# ============================================================================
set -uo pipefail

# ---- tool root (override with AMD_TOOLS env var) --------------------------
AMD_TOOLS="${AMD_TOOLS:-C:/AMDDesignTools/2025.2}"
# normalize to a bash-style path (C:/x -> /c/x) so PATH lookups work
case "$AMD_TOOLS" in
  [A-Za-z]:/*) AMD_TOOLS="/$(echo "$AMD_TOOLS" | cut -d: -f1 | tr 'A-Z' 'a-z')$(echo "$AMD_TOOLS" | cut -d: -f2)" ;;
esac
UVM_SRC="$AMD_TOOLS/Vivado/data/system_verilog/uvm_1.2/xlnx_uvm_package.sv"
UVM_INC="$AMD_TOOLS/Vivado/data/system_verilog/uvm_1.2"

export PATH="$AMD_TOOLS/Vivado/bin:$PATH"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"                     # vectors/ resolved from here

LOGDIR="$REPO_ROOT/build/logs"
SIMDIR="$REPO_ROOT/build/sim_$$"    # unique per run: immune to stale locks
mkdir -p "$LOGDIR" "$SIMDIR"
cp -r "$REPO_ROOT/vectors" "$SIMDIR/vectors"   # relative-path lookup for TBs

# ---- kill any zombie simulator holding library locks ----------------------
powershell -NoProfile -Command \
  "Get-Process xsim* -ErrorAction SilentlyContinue | Stop-Process -Force" \
  2>/dev/null || true
sleep 1

ALL_TBS="tb_spec_ctrl tb_frame_check tb_decouple tb_sentry_e2e"
TBS="${*:-$ALL_TBS}"

cd "$SIMDIR" || exit 1

echo "== [1/3] compiling UVM 1.2 (UVM_NO_DPI, pure SV)"
xvlog -sv -work uvm_lib -d UVM_NO_DPI "$UVM_SRC" -i "$UVM_INC" \
      > "$LOGDIR/01_uvm_compile.log" 2>&1 || {
  echo "FAIL: UVM compilation"; tail -20 "$LOGDIR/01_uvm_compile.log"; exit 1; }

echo "== [2/3] compiling design + environment + TBs"
xvlog -sv -work sentry -L uvm_lib \
  ../../rtl/sentry_defs.sv ../../rtl/skid_buffer.sv ../../rtl/cdc_async_fifo.sv \
  ../../rtl/spec_ctrl.sv ../../rtl/frame_gen.sv ../../rtl/frame_check.sv \
  ../../rtl/decouple.sv ../../rtl/rm1_energy.sv \
  ../../uvm/sentry_ifs.sv ../../uvm/sentry_uvm_pkg.sv \
  ../../uvm/tb_spec_ctrl.sv ../../uvm/tb_frame_check.sv \
  ../../uvm/tb_decouple.sv ../../uvm/tb_sentry_e2e.sv \
  > "$LOGDIR/02_design_compile.log" 2>&1 || {
  echo "FAIL: design compilation"; tail -20 "$LOGDIR/02_design_compile.log"; exit 1; }

FAILED=0
for tb in $TBS; do
  echo "== [3/3] $tb: elaborate + run"
  if ! xelab -debug typical -s "${tb}_sn" -L uvm_lib -L sentry \
        --timescale 1ns/1ps "sentry.$tb" \
        > "$LOGDIR/${tb}_elab.log" 2>&1; then
    echo "FAIL: $tb (elaboration)"
    tail -20 "$LOGDIR/${tb}_elab.log"
    FAILED=1
    continue
  fi
  timeout 600 xsim "${tb}_sn" -runall > "$LOGDIR/${tb}_run.log" 2>&1
  rc=$?
  log="$LOGDIR/${tb}_run.log"
  if [ $rc -ne 0 ]; then
    echo "FAIL: $tb (exit $rc)"; tail -15 "$log"; FAILED=1; continue
  fi
  if ! grep -q "^PASS: " "$log"; then
    echo "FAIL: $tb (no PASS line)"; tail -15 "$log"; FAILED=1; continue
  fi
  if grep -qE "UVM_ERROR : *[1-9]" "$log" || grep -qE "UVM_FATAL : *[1-9]" "$log"; then
    echo "FAIL: $tb (nonzero error/fatal count)"; tail -15 "$log"; FAILED=1; continue
  fi
  echo "PASS: $tb  ($(grep '^PASS: ' "$log" | head -1))"
done

echo "----------------------------------------"
if [ $FAILED -eq 0 ]; then
  echo "UVM REGRESSION: PASS ($*)"
  exit 0
else
  echo "UVM REGRESSION: FAIL"
  exit 1
fi
