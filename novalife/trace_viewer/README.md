# Trace viewer: live scheduling Gantt over JTAG

Shows what the hub is doing, live: every FreeRTOS task switch on CPU0, the CPU1 verify worker, the two job
lanes (verify, mark) and every ESP32 link operation, on one time axis.  Pause, zoom and click to inspect;
a second tab shows the project schedule.

```
python3 novalife/trace_viewer/server.py              # live; open http://127.0.0.1:8765
python3 novalife/trace_viewer/server.py --replay novalife/trace_viewer/recordings/trace_<time>.bin
```

## Memory: 60 seconds in RAM, everything on disk

- The server writes every event to `recordings/trace_<time>.bin` (20 bytes per event) with a `.json` sidecar
  (timer rate, task names), and keeps only a time index in memory (one entry per JTAG read batch).
- The page holds at most 60 s.  Live, older bars are dropped every second.  Paused, the picture stays put;
  dragging, the arrow keys or the history bar under the chart move the view, and when it leaves the 60 s in
  memory the page asks `/window` for that 60 s stretch, read back from the file, together with the state at
  its start (running task, lane states, an unfinished link operation or CPU1 verify).  Resume reloads the
  latest 60 s.
- Measured on the first board run (2026-10-29): 207 s of trace was 135 MB as JSON lines with every
  reschedule; the same run is 0.79 MB as `.bin` once same-task reschedules are filtered (39,627 events).
- `--replay` also reads the first viewer's `.jsonl` recordings (converted to `.bin` next to them once).

## How the data gets out

- `hub/firmware/src/trace.h`: a header and two rings in the top 1 MB of the AMP shared window (0x1FF0_0000),
  mapped non-cacheable by both CPUs.  CPU0 writes ring 0, CPU1 writes ring 1; each entry is 16 bytes with a
  global-timer timestamp (333.33 MHz, shared by both CPUs).
- Task switches come from `traceTASK_SWITCHED_IN` in the kernel.  The BSP's `libfreertos.a` has no trace hook,
  so `hub/firmware/src/rtos_trace_tasks.c` compiles the same `tasks.c` with the hook.  The kernel calls it on
  every yield, also when it picks the same task again (99.6% of calls on the first run: `espw` -> `espw`,
  about 16,000/s), so the firmware records only a change of task, and the server filters again for older
  images.
- `trace_reader.tcl` (run by `server.py` through xsdb) polls the heads every 50 ms and reads new entries with
  `mrd -force`, which does **not** halt either CPU.  Measured: 1.4 ms per header read, ~640 KB/s bulk.

## Using the page

Space pauses, the wheel zooms at the cursor (at most 60 s), a drag pans, shift-drag zooms to a range, a
double click zooms to a bar, and a click pins a bar and highlights its job in every row.  Runs shorter than a
pixel are drawn as the share of that pixel's time the task ran.  **Perfetto** exports the visible window as
Chrome trace JSON for ui.perfetto.dev.

A firmware without the trace shows "no trace header": the reader keeps waiting and starts when the board
boots a traced image.
