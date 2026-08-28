# ITI Advanced FPGA Capstone -- SPECTRUM SENTRY
# Top-level orchestration. Non-project flow: TCL scripts do the work.

VIVADO ?= vivado
VITIS_HLS ?= vitis_hls
XSIM ?= xvlog
TOPOPT ?= NODE_B   # NODE_A | NODE_B

.PHONY: help csim regress synth impl all sw gates clean

help:
	@echo "Targets:"
	@echo "  csim      HLS C-simulation, all kernels (no board)"
	@echo "  regress   xsim regression, all testbenches must print PASS"
	@echo "  synth     non-project synthesis checkpoint ($(TOPOPT))"
	@echo "  impl      place/route + timing gate + write bitstream"
	@echo "  all       synth + impl"
	@echo "  sw        build A53 apps + host dashboard"
	@echo "  gates     run CI gates (WNS, utilization) on latest checkpoint"
	@echo "  clean     remove build artifacts"

# HLS kernels: each kernel dir owns src/, tb/, run_hls.tcl (Week-1 Day-1 stubs)
HLS_KERNELS = fft_psd fir_chan tile_pack replay_gov

csim:
	@for k in $(HLS_KERNELS); do \
	    echo "== csim: $$k"; \
	    (cd hls/$$k && $(VITIS_HLS) -f run_hls.tcl -tclargs csim) || exit 1; \
	done

# Simulation regression: every testbench prints PASS on the last line
regress:
	./ci/regress.sh

synth:
	$(VIVADO) -mode batch -source ci/build.tcl -tclargs synth $(TOPOPT)

impl:
	$(VIVADO) -mode batch -source ci/build.tcl -tclargs impl $(TOPOPT)

all: synth impl

sw:
	@echo "TODO(T5): a53 apps + VART + dashboard build scripts"

gates:
	$(VIVADO) -mode batch -source ci/gates/wns_gate.tcl

clean:
	rm -rf build/ *.jou *.log .Xil
