# ============================================================================
# build.tcl -- non-project mode synthesis/implementation for SPECTRUM SENTRY
# Usage:
#   vivado -mode batch -source ci/build.tcl -tclargs synth|impl NODE_A|NODE_B [zcu102|kr260]
# Board abstraction: part + constraint directory come from the board table
# below; logical constraints (clocks/CDC) live in constr/<board>/node_*.xdc,
# physical pins in the board's carrier/pin XDC (KR260: fill from XTP685).
# ============================================================================

set step  [lindex $argv 0]
set topo  [lindex $argv 1]
set board [lindex $argv 2]
if {$board eq ""} { set board "zcu102" }

if {$topo ne "NODE_A" && $topo ne "NODE_B"} {
    puts "ERROR: topology must be NODE_A or NODE_B"
    exit 1
}

# ---- board table -----------------------------------------------------------
set part(zcu102) xczu9eg-ffvb1156-2-e
set part(kr260)  xck26-sfvc784-2LV-c
if {![info exists part($board)]} {
    puts "ERROR: unknown board '$board' (zcu102 | kr260)"
    exit 1
}
set top  [expr {$topo eq "NODE_A" ? "node_a_top" : "node_b_top"}]

# ---- part 1: read everything, synthesize, checkpoint -----------------------
if {$step eq "synth"} {
    read_verilog -sv [glob rtl/*/*.sv]
    read_xdc constr/$board/${topo}.xdc
    # Physical pin file (KR260: fill constr/kr260/carrier_pins.xdc from XTP685)
    if {[file exists constr/$board/carrier_pins.xdc]} {
        read_xdc constr/$board/carrier_pins.xdc
    }
    if {[file exists bd/${topo}.tcl]} {
        # BD scripts are skeletons for the hardware stage; source when the
        # PS/GT wrappers exist (see docs/BOARDS.md bring-up checklist).
        # source bd/${topo}.tcl
    }
    synth_design -top $top -part $part($board)
    write_checkpoint -force build/${board}_${topo}_synth.dcp
    report_utilization -file build/${board}_${topo}_util_synth.rpt
    report_timing_summary -file build/${board}_${topo}_timing_synth.rpt
}

# ---- part 2: implement, gate on timing, write bitstream --------------------
if {$step eq "impl"} {
    open_checkpoint build/${board}_${topo}_synth.dcp
    opt_design
    place_design
    phys_opt_design
    route_design
    write_checkpoint -force build/${board}_${topo}_impl.dcp
    report_utilization -file build/${board}_${topo}_util_impl.rpt
    report_timing_summary -file build/${board}_${topo}_timing_impl.rpt

    # CI acceptance gate: timing must be clean (spec Section 8, verbatim)
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1]]
    if {$wns < 0} {
        puts "FAIL: WNS $wns"
        exit 1
    } else {
        puts "PASS: WNS $wns"
    }

    write_bitstream -force build/${board}_${topo}.bit
    # Kria runtime loaders (fpga-mgr / dfx-mgr) consume .bin:
    if {$board eq "kr260"} {
        catch {write_cfgmem -force -format BIN -interface SMAP -size 128 \
               -loadbit "up 0x0 build/${board}_${topo}.bit" \
               build/${board}_${topo}.bin}
        puts "NOTE: wrote .bin for Kria fpga-mgr/dfx-mgr"
    }
}
