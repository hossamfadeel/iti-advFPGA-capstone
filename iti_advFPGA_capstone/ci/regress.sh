#!/usr/bin/env bash
# ============================================================================
# regress.sh -- xsim regression for SPECTRUM SENTRY (CI gate)
# Rule: every testbench must print PASS on its last line.
# Skeleton: extend TESTS as testbenches land in sim/ (spec Section 5.8).
# ============================================================================
set -euo pipefail

TESTS=(sim/tb_spec_ctrl.sv sim/tb_frame_check.sv sim/tb_fir_chan.sv sim/tb_decouple.sv)
PASS=0; SKIP=0; FAIL=0

for tb in "${TESTS[@]}"; do
    if [[ ! -f "$tb" ]]; then
        echo "SKIP (not yet implemented): $tb"; SKIP=$((SKIP+1)); continue
    fi
    top=$(basename "$tb" .sv)
    echo "== regress: $top"
    xvlog -sv "$tb" rtl/*/*.sv -log "build/$top.log" > /dev/null
    xelab "$top" -snapshot "$top" -log "build/$top.elab.log" > /dev/null
    if xsim "$top" -runall -log "build/$top.run.log" | tail -1 | grep -q "PASS"; then
        echo "PASS: $top"; PASS=$((PASS+1))
    else
        echo "FAIL: $top (last line was not PASS)"; FAIL=$((FAIL+1))
    fi
done

echo "----------------------------------------"
echo "regression: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
