# trace_reader.tcl -- stream the firmware's scheduling trace rings (firmware/src/trace.h) over JTAG.
#
# Run by server.py as:  xsdb trace_reader.tcl
# Reads memory with `mrd -force` through the APU target, which does NOT halt either CPU (never `stop` a
# running board).  Prints one line per record on stdout:
#   HDR  <gt_hz> <cap0> <cap1> <head0> <head1>
#   NAMES <num0> <w0 w1 w2> <num1> ...          task-name table, every ~1 s
#   R0 <first_index> <w0 w1 w2 w3> ...          new CPU0 entries (4 words each)
#   R1 <first_index> ...                        new CPU1 entries
#   GAP <ring> <lost>                           the reader fell more than one ring behind
#   REBOOT R0                                   the heads went backwards: the board restarted
#   WAIT <reason>                               no trace yet (old firmware, board off, JTAG busy)
# Measured 2026-10-29 on the EDGE board: 1.4 ms per 8-word read, 102 ms per 16384 words (~640 KB/s).

set BASE     0x1FF00000
set MAGIC    0x54524331
set RING0    [expr {$BASE + 0x1000}]
set NAMES_AT [expr {$BASE + 0x20}]
set CHUNK    4096          ;# entries per read at most (16384 words, ~100 ms)
set POLL_MS  50

proc out {s} { puts $s; flush stdout }

proc connect_board {} {
    while {[catch {connect; targets -set -filter {name =~ "APU*"}} err]} {
        out "WAIT connect: $err"
        catch {disconnect}
        after 2000
    }
}

# read n entries of a ring starting at entry index i (handles the wrap)
proc read_ring {tag ring_addr cap i n} {
    while {$n > 0} {
        set slot [expr {$i % $cap}]
        set k [expr {min($n, $cap - $slot, $::CHUNK)}]
        set words [mrd -force -value [expr {$ring_addr + $slot * 16}] [expr {$k * 4}]]
        out "$tag $i $words"
        incr i $k
        incr n -$k
    }
}

connect_board
set last0 -1
set last1 -1
set loops 0
set epoch0 -1
while {1} {
    if {[catch {set h [mrd -force -value $BASE 8]} err]} {
        out "WAIT read: $err"
        catch {disconnect}
        after 1000
        connect_board
        continue
    }
    lassign $h magic ver hz cap0 cap1 head0 head1 r1off
    if {$magic != $MAGIC} {
        out [format "WAIT no trace header (magic %08x): firmware without the trace, or still booting" $magic]
        # the next valid header is a fresh start (trace_init cleared it): read that run from its first entry
        set last0 0
        set last1 0
        after 1000
        continue
    }
    # A restarted board resets the heads below what we have read: read its new entries from the start.
    if {$last0 >= 0 && $head0 < $last0} { set last0 0; out "REBOOT R0" }
    if {$last1 >= 0 && $head1 < $last1} { set last1 0 }
    out "HDR $hz $cap0 $cap1 $head0 $head1"

    if {$loops % 20 == 0} {
        out "NAMES [mrd -force -value $NAMES_AT 256]"
    }
    incr loops

    foreach {tag cap head lastvar addr} [list R0 $cap0 $head0 last0 $RING0 R1 $cap1 $head1 last1 [expr {$BASE + $r1off}]] {
        set last [set $lastvar]
        # First look: start at the current head.  DRAM keeps its contents across a reset for a while, so what
        # is already in the ring may be a previous run's (measured 2026-10-29 after a failed boot).
        if {$last < 0} { set last $head }
        set n [expr {$head - $last}]
        if {$n > $cap} {
            out "GAP $tag [expr {$n - $cap}]"
            set last [expr {$head - $cap}]
            set n $cap
        }
        if {$n > 0} {
            if {[catch {read_ring $tag $addr $cap $last $n} err]} {
                out "WAIT ring read: $err"
                break
            }
            set last $head
        }
        set $lastvar $last
    }
    after $POLL_MS
}
