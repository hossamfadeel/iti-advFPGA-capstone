# ITI Advanced FPGA Capstone -- SPECTRUM SENTRY
# Top-level orchestration. UVM + HLS regressions need no board (the virtual
# ZCU102); synth needs a Vivado install. Override AMD_TOOLS for your install.

AMD_TOOLS ?= C:/AMDDesignTools/2025.2

.PHONY: help vectors regress regress-uvm regress-hls synth impl all sw gates clean

help:
	@echo "Targets:"
	@echo "  vectors      regenerate golden vectors (python+numpy, seed 260)"
	@echo "  regress      FULL regression: UVM (4 TBs) + HLS csim (4 kernels)"
	@echo "  regress-uvm  UVM only: xsim + UVM 1.2 (UVM_NO_DPI); every TB prints PASS"
	@echo "  regress-hls  HLS csim only: vitis-run --tcl per kernel"
	@echo "  synth        non-project synthesis checkpoint (NODE_B)"
	@echo "  impl         place/route + WNS gate + bitstream (NODE_B)"
	@echo "  all          synth + impl"
	@echo "  gates        run CI gates (WNS, utilization) on latest checkpoint"
	@echo "  clean        remove build artifacts"

vectors:
	python sw/golden/gen_vectors.py

regress-uvm:
	./ci/regress_uvm.sh

regress-hls:
	AMD_TOOLS=$(AMD_TOOLS) ./ci/regress_hls.sh

regress: regress-uvm regress-hls
	@echo "FULL REGRESSION COMPLETE"

synth:
	vivado -mode batch -source ci/build.tcl -tclargs synth NODE_B

impl:
	vivado -mode batch -source ci/build.tcl -tclargs impl NODE_B

all: synth impl

sw:
	@echo "sw/: a53 apps + host dashboard are bench-stage deliverables (see docs/REPRODUCE.md)"

gates:
	vivado -mode batch -source ci/gates/wns_gate.tcl

clean:
	rm -rf build/ xsim.dir/ *.jou *.log .Xil
	find hls -maxdepth 2 -name "*_proj" -type d -exec rm -rf {} + 2>/dev/null || true
