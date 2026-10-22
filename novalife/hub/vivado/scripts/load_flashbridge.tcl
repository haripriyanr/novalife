# Load the flash-bridge bitstream and the UART0<->UART1 byte bridge (tools/esp_flash/bridge.elf).
#   xsdb vivado/scripts/load_flashbridge.tcl        then:  esptool --port /dev/ttyUSB1 ...
set here  [file normalize [file dirname [info script]]]
set root  [file normalize [file join $here .. ..]]
set build [file join $root vivado build_flashbridge]
set elf   [file join $root tools esp_flash bridge.elf]
connect
targets -set -nocase -filter {name =~ "APU*"}
rst -system
after 500
targets -set -nocase -filter {name =~ "xc7z010*"}
fpga -file [file join $build flashbridge.bit]
targets -set -nocase -filter {name =~ "*A9*#0"}
source [file join $build ps7_init.tcl]
ps7_init
ps7_post_config
dow $elf
con
puts "FLASHBRIDGE_STARTED"
