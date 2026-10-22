# ============================================================================
# NovaLife HUB - POST-SYNTHESIS area + timing for ascon128_aead after the SP 800-232 port
# ----------------------------------------------------------------------------
# The 2026-10-19 first attempt (results/hw_core_synth_2026-10-19/) did not
# synthesise: the all-register tree needed 39,168 FF > the part's 35,200 and
# Vivado was OOM-killed.  polar_sc_decoder.v is now MEMORY-BACKED (two inferred
# simple-dual-port RAMs hold the tree; a microsequencer walks it).  Re-run to get
# real numbers for the fitting design.
#
# Same method: throwaway project, core forced as top, one 10 ns (100 MHz)
# create_clock, ONLY synth_1.  No implementation, no bitstream, no board.
# ============================================================================

set base    /run/media/user/DATA/repos/embedded_proj/novalife_hub/results/hw_core_synth_2026-10-20_sp800_ascon
set iprepo  /run/media/user/DATA/repos/embedded_proj/novalife_hub/vivado/ip_repo
set incdir  /run/media/user/DATA/repos/embedded_proj/novalife_hub/tools/tag_reference/vectors
set part    xc7z010clg400-1

set cores {
    {ascon128_aead ascon128_aead {ascon_core/ascon128_aead.v} clk}
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
