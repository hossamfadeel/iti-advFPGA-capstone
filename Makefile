# ITI Advanced FPGA Capstone -- SPECTRUM SENTRY
# Top-level orchestration. UVM + HLS regressions need no board (the virtual
# ZCU102 -- and they are BOARD-INDEPENDENT for KR260 too); synth needs the
# tools. Override AMD_TOOLS for your install; BOARD selects the target.

AMD_TOOLS ?= C:/AMDDesignTools/2025.2
BOARD     ?= kr260    # kr260 | zcu102  (pins for kr260 need XTP685 fill-in)

.PHONY: help vectors regress regress-uvm regress-hls synth impl all sw gates boards clean

help:
	@echo "Targets:"
	@echo "  vectors      regenerate golden vectors (python+numpy, seed 260)"
	@echo "  regress      FULL regression: UVM (4 TBs) + HLS csim (4 kernels)"
	@echo "  regress-uvm  UVM only: xsim + UVM 1.2 (UVM_NO_DPI); every TB prints PASS"
	@echo "  regress-hls  HLS csim only: vitis-run --tcl per kernel"
	@echo "  synth        non-project synthesis checkpoint (BOARD=$(BOARD))"
	@echo "  impl         place/route + WNS gate + bitstream (BOARD=$(BOARD))"
	@echo "  all          synth + impl"
	@echo "  gates        run CI gates (WNS, utilization) on latest checkpoint"
	@echo "  boards       list board support status (docs/BOARDS.md)"
	@echo "  clean        remove build artifacts"
	@echo "Variables: BOARD=$(BOARD) (kr260|zcu102), AMD_TOOLS=$(AMD_TOOLS)"

vectors:
	python sw/golden/gen_vectors.py

regress-uvm:
	./ci/regress_uvm.sh

regress-hls:
	AMD_TOOLS=$(AMD_TOOLS) ./ci/regress_hls.sh

regress: regress-uvm regress-hls
	@echo "FULL REGRESSION COMPLETE"

synth:
	vivado -mode batch -source ci/build.tcl -tclargs synth NODE_B $(BOARD)

impl:
	vivado -mode batch -source ci/build.tcl -tclargs impl NODE_B $(BOARD)

all: synth impl

sw:
	@echo "sw/: a53 apps + host dashboard are bench-stage deliverables (see docs/REPRODUCE.md)"

gates:
	vivado -mode batch -source ci/gates/wns_gate.tcl

boards:
	@echo "Board support: zcu102 (reference, complete) | kr260 (K26 SOM: logic+docs+build ready, fill carrier_pins.xdc from XTP685)"
	@echo "See docs/BOARDS.md for the full delta table and the 2x KR260 bring-up checklist."

clean:
	rm -rf build/ xsim.dir/ *.jou *.log .Xil
	find hls -maxdepth 2 -name "*_proj" -type d -exec rm -rf {} + 2>/dev/null || true
