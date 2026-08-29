# ============================================================================
# wns_gate.tcl -- standalone timing gate for CI (spec Section 8)
# Parses WNS from the latest implementation timing report; exits nonzero if
# any clock domain violates. Run: vivado -mode batch -source ci/gates/wns_gate.tcl
# (build.tcl already embeds the same gate post-route; this is the re-check.)
# ============================================================================

set reports [glob -nocomplain build/*_timing_impl.rpt]
if {[llength $reports] == 0} {
    puts "FAIL: no implementation timing reports found in build/"
    exit 1
}

set failed 0
foreach rpt $reports {
    set fh [open $rpt r]
    set content [read $fh]
    close $fh
    foreach {match wns tns whs} [regexp -all -inline {WNS\(ns\)\s+TNS\(ns\).*?\n\s*(-?[\d.]+)\s+(-?[\d.]+).*?WHS\(ns\)} $content] {
        puts "[file tail $rpt]: WNS=$wns TNS=$tns WHS=$whs"
        if {$wns < 0 || $whs < 0} { set failed 1 }
    }
}

if {$failed} {
    puts "FAIL: timing violations present"
    exit 1
}
puts "PASS: all clock domains meet timing"
