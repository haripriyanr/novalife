# ============================================================================
# NovaLife HUB - on-board test of the PL tag engine over JTAG (xsdb)
# ----------------------------------------------------------------------------
# Programs vivado/build_enclave/novalife_enclave.bit, initialises the PS from the XSA's
# ps7_init.tcl (ps7_init + ps7_post_config: the latter enables the PS->PL level shifters,
# without which every AXI access to 0x4000_0000 hangs), then drives the enclave registers
# from the Cortex-A9's memory map with mwr/mrd -- the same sequence the simulation testbench
# vivado/ip_repo/enclave_axi/enclave_axi_tb.v runs -- over every vector in
# tools/tag_reference/vectors/te_{key,fields,tag}.mem (== tag_block.compute_tag).
#
# Prints one line per check and a final BOARD_TAG_TEST PASS/FAIL line.
#
#   xsdb vivado/scripts/board_tag_test.tcl
#
# The key is loaded through the AXI key window (ALLOW_AXI_KEY = 1): a bring-up deviation from
# D5.  The keys are the published test-vector keys, not a hub key.
# ============================================================================

set here  [file normalize [file dirname [info script]]]
set root  [file normalize [file join $here .. ..]]
set build [file join $root vivado build_enclave]
set vec   [file join $root tools tag_reference vectors]
set bit   [file join $build novalife_enclave.bit]
set init  [file join $build xsa ps7_init.tcl]
set B 0x40000000

proc rd {off} { global B; return [mrd -force -value [expr {$B + $off}]] }
proc wr {off v} { global B; mwr -force [expr {$B + $off}] $v }
proc lines {f} {
    set fh [open $f r]; set out {}
    foreach l [split [read $fh] "\n"] { if {[string trim $l] ne ""} { lappend out [string trim $l] } }
    close $fh; return $out
}

set errors 0
proc check {cond what} {
    global errors
    if {$cond} { puts "  ok   $what" } else { puts "  FAIL $what"; incr errors }
}

proc run_cmd {c} {
    wr 0x00 $c
    for {set i 0} {$i < 1000} {incr i} {
        if {[expr {[rd 0x10] & 1}]} { return 1 }
    }
    return 0
}

connect
puts "targets:"; puts [targets]
targets -set -nocase -filter {name =~ "APU*"}
rst -system
after 500
targets -set -nocase -filter {name =~ "*A9*#0"}
set devcfg_before [mrd -force -value 0xF800700C]
targets -set -nocase -filter {name =~ "xc7z010*"}
fpga -file $bit
targets -set -nocase -filter {name =~ "*A9*#0"}
set devcfg_after [mrd -force -value 0xF800700C]
puts [format "devcfg INT_STS before fpga 0x%08x, after 0x%08x (bit 2 = PCFG_DONE)" $devcfg_before $devcfg_after]
source $init
ps7_init
ps7_post_config
after 100

check [expr {($devcfg_after >> 2) & 1}] "devcfg INT_STS.PCFG_DONE set after programming (firmware probe bit)"
set st [rd 0x0C]
puts [format "STATUS after init: 0x%08x" $st]
check [expr {(($st >> 16) & 0xFFFF) == 0x4E4C && ($st & 1) == 1}] "PL present (magic 0x4E4C, READY)"
check [expr {(($st >> 1) & 1) == 0}] "no key loaded after reset"

check [run_cmd 0] "BUILD without key completes"
check [expr {([rd 0x14] & 3) == 1}] "BUILD without key -> NO_KEY"

set keys [lines [file join $vec te_key.mem]]
set flds [lines [file join $vec te_fields.mem]]
set tags [lines [file join $vec te_tag.mem]]
set n [llength $keys]
set build_cycles {}
set verify_cycles {}

for {set c 0} {$c < $n} {incr c} {
    set k [lindex $keys $c]; set f [lindex $flds $c]; set t [lindex $tags $c]
    for {set w 0} {$w < 4} {incr w} {
        wr [expr {0x40 + 4*$w}] 0x[string range $k [expr {8*$w}] [expr {8*$w + 7}]]
    }
    run_cmd 5
    set version [scan [string index $f 0] %x]
    set hub     [scan [string range $f 1 3] %x]
    wr 0x20 [expr {($version << 12) | $hub}]
    wr 0x24 0x[string range $f 4 11]
    wr 0x28 0x[string range $f 12 19]
    set okb [run_cmd 0]
    set res [rd 0x14]
    set got [format "%04x%08x" [expr {[rd 0x34] & 0xFFFF}] [rd 0x38]]
    lappend build_cycles [rd 0x3C]
    check [expr {$okb && ($res & 3) == 0 && $got eq $t}] "vector $c BUILD tag $got (expected $t)"

    wr 0x2C 0x[string range $t 0 3]
    wr 0x30 0x[string range $t 4 11]
    run_cmd 1
    set res [rd 0x14]
    lappend verify_cycles [rd 0x3C]
    check [expr {($res & 3) == 0 && (($res >> 8) & 1) == 1}] "vector $c VERIFY right tag accepted"
    if {$c < 3} {
        wr 0x30 [expr {[scan [string range $t 4 11] %x] ^ 1}]
        run_cmd 1
        set res [rd 0x14]
        check [expr {($res & 3) == 0 && (($res >> 8) & 1) == 0}] "vector $c VERIFY flipped tag rejected"
    }
}

run_cmd 7
check [expr {(([rd 0x0C] >> 1) & 1) == 0}] "key wiped"
check [expr {[rd 0x40] == 0}] "key window reads 0"

puts "BUILD_TAG cycles (PL counter, 100 MHz FCLK0): $build_cycles"
puts "VERIFY_TAG cycles: $verify_cycles"
if {$errors == 0} {
    puts "BOARD_TAG_TEST PASS ($n vectors on the board)"
} else {
    puts "BOARD_TAG_TEST FAIL ($errors errors)"
}
