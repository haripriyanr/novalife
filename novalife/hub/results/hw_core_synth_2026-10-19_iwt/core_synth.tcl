# ============================================================================
# NovaLife HUB - POST-SYNTHESIS area + timing for iwt_53_core (G2, 2026-10-19)
# ----------------------------------------------------------------------------
# The core is now a real per-line 5/3 lifting transform, bit-exact against
# tools/stego_research/sims/iwt_lifting.py over 12 1D lines (iwt1d_53) and two
# frames incl. a NON-SQUARE one (iwt2d_53, composed from two instantiations in
# the testbench).  Before this it computed `d = x - ((x+0)>>>1)` and was not a
# lifting transform at all.
#
#   vivado -mode batch -source core_synth.tcl
#
# Throwaway project, core forced as top, one 10 ns (100 MHz) create_clock,
# ONLY synth_1.  No implementation, no bitstream, no board.
# ============================================================================

set base    /run/media/user/DATA/repos/embedded_proj/novalife_hub/results/hw_core_synth_2026-10-19_iwt
set iprepo  /run/media/user/DATA/repos/embedded_proj/novalife_hub/vivado/ip_repo
set incdir  /run/media/user/DATA/repos/embedded_proj/novalife_hub/tools/tag_reference/vectors
set part    xc7z010clg400-1

set cores {
    {iwt_53_core iwt_53_core {iwt_53_core/iwt_53_core.v} clk}
}

proc synth_one {name top rellist clport} {
    global base iprepo part incdir
    set rundir [file join $base $name]
    file mkdir $rundir

    set status [file join $rundir "status.txt"]
    set xdc    [file join $rundir "timing.xdc"]

    set fh [open $xdc w]
    puts $fh "# 100 MHz clock constraint (post-synthesis timing check)"
    puts $fh "create_clock -name ${name}_clk -period 10.000 \[get_ports $clport\]"
    close $fh

    set srclist [list]
    foreach r $rellist { lappend srclist [file join $iprepo $r] }

    if {[catch {
        create_project -force ${name}_synth [file join $rundir proj] -part $part
        add_files -fileset sources_1  $srclist
        set_property include_dirs $incdir [get_filesets sources_1]
        add_files -fileset constrs_1  $xdc
        set_property top $top [current_fileset]

        launch_runs synth_1
        wait_on_run  synth_1
        open_run     synth_1

        report_utilization    -file          [file join $rundir util.rpt]
        report_timing_summary -max_paths 25  -file [file join $rundir timing.rpt]

        close_project
    } err]} {
        set fh2 [open $status w]
        puts $fh2 "STATUS: FAIL"
        puts $fh2 "ERROR:"
        puts $fh2 $err
        puts $fh2 ""
        puts $fh2 "ERRORINFO:"
        puts $fh2 $::errorInfo
        close $fh2
        catch { close_project }
        puts "CORE $name: FAIL (see $status)"
        return
    }

    set fh2 [open $status w]
    puts $fh2 "STATUS: OK"
    close $fh2
    puts "CORE $name: OK"
}

foreach c $cores {
    synth_one {*}$c
}

puts "ALL_DONE"
