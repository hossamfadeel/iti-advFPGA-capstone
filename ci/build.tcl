# ============================================================================
# build.tcl -- non-project mode synthesis/implementation for SPECTRUM SENTRY
# Spec: Section 5.8 (CI/CD). Usage:
#   vivado -mode batch -source ci/build.tcl -tclargs synth|impl NODE_A|NODE_B
# ============================================================================

set step  [lindex $argv 0]
set topo  [lindex $argv 1]
if {$topo ne "NODE_A" && $topo ne "NODE_B"} {
    puts "ERROR: topology must be NODE_A or NODE_B"
    exit 1
}

set part xczu9eg-ffvb1156-2-e
set top  [expr {$topo eq "NODE_A" ? "node_a_top" : "node_b_top"}]

# ---- part 1: read everything, synthesize, checkpoint -----------------------
if {$step eq "synth"} {
    read_verilog -sv [glob rtl/*/*.sv]
    read_xdc constr/${topo}.xdc
    read_bd   bd/${topo}.bd          ;# or: source bd/${topo}.tcl
    synth_design -top $top -part $part
    write_checkpoint -force build/${topo}_synth.dcp
    report_utilization -file build/${topo}_util_synth.rpt
    report_timing_summary -file build/${topo}_timing_synth.rpt
}

# ---- part 2: implement, gate on timing, write bitstream --------------------
if {$step eq "impl"} {
    open_checkpoint build/${topo}_synth.dcp
    opt_design
    place_design
    phys_opt_design
    route_design
    write_checkpoint -force build/${topo}_impl.dcp
    report_utilization -file build/${topo}_util_impl.rpt
    report_timing_summary -file build/${topo}_timing_impl.rpt

    # CI acceptance gate: timing must be clean (spec Section 8, verbatim)
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1]]
    if {$wns < 0} {
        puts "FAIL: WNS $wns"
        exit 1
    } else {
        puts "PASS: WNS $wns"
    }

    write_bitstream -force build/${topo}.bit
}
