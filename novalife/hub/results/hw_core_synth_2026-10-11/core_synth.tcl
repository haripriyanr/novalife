# ============================================================================
# NovaLife HUB - per-core POST-SYNTHESIS area + timing measurement
# ----------------------------------------------------------------------------
# What it does (and does NOT do):
#   - Creates ONE throwaway project per core, adds ONLY that core's source(s),
#     sets the core module as top, applies a 10 ns (100 MHz) create_clock, and
#     runs ONLY synth_1 (launch_runs synth_1 / wait_on_run).
#   - Writes report_utilization and report_timing_summary per core.
#   - Does NOT run implementation, does NOT generate a bitstream, does NOT open
#     the hardware manager, does NOT touch a board.
# Each core is wrapped in catch{} so a failure is recorded as a valid result
# and the loop continues to the remaining cores.
# ============================================================================

# (WebTalk is disabled on the command line / via env, not needed here.)

set base    /run/media/user/DATA/repos/embedded_proj/novalife_hub/results/hw_core_synth_2026-10-11
set iprepo  /run/media/user/DATA/repos/embedded_proj/novalife_hub/vivado/ip_repo
set part    xc7z010clg400-1

# {rundir_name  top_module  {src files, relative to ip_repo}  clock_port}
set cores {
    {ascon_core    ascon128_aead           {ascon_core/ascon128_aead.v}                          clk}
    {perceptual_mask_core perceptual_mask_core {perceptual_mask_core/perceptual_mask_core.v}    clk}
    {iwt_53_core   iwt_53_core             {iwt_53_core/iwt_53_core.v}                            clk}
    {dwt_2d_core   dwt_2d_transform        {dwt_2d_core/dwt_2d_transform.v}                       clk}
    {polar_encoder polar_encoder           {polar_encoder/polar_encoder.v}                        clk}
    {axi_lite_ctrl axi_lite_ctrl           {axi_lite_ctrl/axi_lite_ctrl.v}                        s_axi_aclk}
    {dwt_2d_2level dwt_2d_transform_2level {dwt_2d_core/dwt_2d_transform.v dwt_2d_core/dwt_2d_transform_2level.v} clk}
}

proc synth_one {name top rellist clport} {
    global base iprepo part
    set rundir [file join $base $name]
    file mkdir $rundir

    set status [file join $rundir "status.txt"]
    set xdc    [file join $rundir "timing.xdc"]

    # 10 ns (100 MHz) single-clock constraint, independent of the PS FCLK.
    set fh [open $xdc w]
    puts $fh "# 100 MHz clock constraint (post-synthesis timing check)"
    puts $fh "create_clock -name ${name}_clk -period 10.000 \[get_ports $clport\]"
    close $fh

    set srclist [list]
    foreach r $rellist { lappend srclist [file join $iprepo $r] }

    if {[catch {
        create_project -force ${name}_synth [file join $rundir proj] -part $part
        add_files -fileset sources_1  $srclist
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
