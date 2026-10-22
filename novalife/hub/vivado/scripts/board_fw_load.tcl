# ============================================================================
# NovaLife HUB - load the enclave bitstream + FreeRTOS firmware over JTAG and start it
# ----------------------------------------------------------------------------
#   xsdb vivado/scripts/board_fw_load.tcl [testkey]
#
# With "testkey": loads tag-engine test vector 0's key (the published demo key from
# tools/tag_reference/vectors/te_key.mem, NOT a hub key) through the AXI admin window before
# the firmware starts -- a stand-in for the PL-wired admin console (ALLOW_AXI_KEY bring-up
# deviation from D5).  The firmware itself never loads a key.
# ============================================================================

set here  [file normalize [file dirname [info script]]]
set root  [file normalize [file join $here .. ..]]
set build [file join $root vivado build_enclave]
set elf   [file join $root firmware vitis_ws novalife_hub_fw build novalife_hub_fw.elf]
set B 0x40000000

connect
targets -set -nocase -filter {name =~ "APU*"}
rst -system
after 500
targets -set -nocase -filter {name =~ "xc7z010*"}
fpga -file [file join $build novalife_enclave.bit]
targets -set -nocase -filter {name =~ "*A9*#0"}
source [file join $build xsa ps7_init.tcl]
ps7_init
ps7_post_config
after 100
puts [format "STATUS 0x%08x" [mrd -force -value [expr {$B + 0x0C}]]]

if {[lsearch $argv testkey] >= 0} {
    set fh [open [file join $root tools tag_reference vectors te_key.mem] r]
    set k [string trim [lindex [split [read $fh] "\n"] 0]]; close $fh
    for {set w 0} {$w < 4} {incr w} {
        mwr -force [expr {$B + 0x40 + 4*$w}] 0x[string range $k [expr {8*$w}] [expr {8*$w + 7}]]
    }
    mwr -force [expr {$B + 0x00}] 5
    after 10
    puts [format "test key loaded, STATUS 0x%08x" [mrd -force -value [expr {$B + 0x0C}]]]
}

dow $elf
con
puts "FIRMWARE_STARTED $elf"
