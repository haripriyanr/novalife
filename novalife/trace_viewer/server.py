#!/usr/bin/env python3
"""server.py -- live scheduling Gantt for the NovaLife hub, fed over JTAG.

    python3 novalife/trace_viewer/server.py                          # live, http://127.0.0.1:8765
    python3 novalife/trace_viewer/server.py --replay recordings/trace_<time>.bin
    python3 novalife/trace_viewer/server.py --replay recordings/trace_<time>.jsonl   # first viewer's format

Every event goes to disk (recordings/trace_<time>.bin, 20 bytes per event, plus a .json sidecar with the
timer rate and task names).  Nothing older than the live window is kept in memory: the page holds at most
WINDOW_S seconds, and when paused it asks /window for any other WINDOW_S-second stretch, read back from the
file.  Standard library only.

Wire format of an event (JSON array): [ring, ts_ticks, type, a, b, c, arg]; ring 0 = CPU0, 1 = CPU1.
A lost-events marker is [ring, ts, 0x7F, 0, 0, 0, lost].
"""
import argparse
import array
import json
import os
import queue
import struct
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_XSDB = "/home/user/develop/Xilinx/2026.1/Vitis/bin/xsdb"
WINDOW_S = 60.0                 # what the page shows and holds
CONTEXT_S = 120.0               # how far back /window looks for the state at the window's start
REC = struct.Struct("<QBBBBBxxxI")   # ts, ring, type, a, b, c, pad, arg  -> 20 bytes
TE_TASK, TE_LANE, TE_LINK_B, TE_LINK_E, TE_CPU1_B, TE_CPU1_E, TE_BOOT, TE_GAP = 1, 2, 3, 4, 5, 6, 0x7E, 0x7F
STALL_S = 3.0                   # trace head not moving this long: the board is not running


class Recording:
    """Append-only event file with an in-memory time index (one entry per written batch)."""

    def __init__(self, path, mode):
        self.path = path
        self.f = open(path, mode)
        self.lock = threading.Lock()
        self.n = 0                                   # records in the file
        self.idx_min, self.idx_max, self.idx_off = array.array("q"), array.array("q"), array.array("q")
        self.first_ts = None
        self.last_ts = None

    def append(self, evs):
        if not evs:
            return
        buf = b"".join(REC.pack(e[1], e[0], e[2], e[3], e[4], e[5], e[6]) for e in evs)
        lo = min(e[1] for e in evs)
        hi = max(e[1] for e in evs)
        with self.lock:
            self.f.seek(0, 2)
            self.f.write(buf)
            self.f.flush()
            self.idx_min.append(lo)
            self.idx_max.append(hi)
            self.idx_off.append(self.n)
            self.n += len(evs)
            self.first_ts = lo if self.first_ts is None else min(self.first_ts, lo)
            self.last_ts = hi if self.last_ts is None else max(self.last_ts, hi)

    def index_existing(self, chunk=4096):
        """Build the index of a file written earlier (replay)."""
        size = os.path.getsize(self.path)
        self.f.seek(0)
        off = 0
        while off * REC.size < size:
            data = self.f.read(chunk * REC.size)
            if not data:
                break
            ts = [r[0] for r in REC.iter_unpack(data[: len(data) - len(data) % REC.size])]
            if not ts:
                break
            self.idx_min.append(min(ts)); self.idx_max.append(max(ts)); self.idx_off.append(off)
            self.first_ts = ts[0] if self.first_ts is None else min(self.first_ts, min(ts))
            self.last_ts = max(ts) if self.last_ts is None else max(self.last_ts, max(ts))
            off += len(ts)
        self.n = off

    def read(self, lo, hi):
        """All records with lo <= ts <= hi, in time order."""
        out = []
        with self.lock:
            nb = len(self.idx_off)
            for i in range(nb):
                if self.idx_max[i] < lo or self.idx_min[i] > hi:
                    continue
                start = self.idx_off[i]
                end = self.idx_off[i + 1] if i + 1 < nb else self.n
                self.f.seek(start * REC.size)
                data = self.f.read((end - start) * REC.size)
                for ts, ring, typ, a, b, c, arg in REC.iter_unpack(data):
                    if lo <= ts <= hi:
                        out.append([ring, ts, typ, a, b, c, arg])
        out.sort(key=lambda e: e[1])
        return out


class State:
    def __init__(self):
        self.lock = threading.Lock()
        self.hz = 333_333_333
        self.names = {}
        self.status = {"mode": "starting", "msg": "", "gaps": 0, "dropped_same_task": 0}
        self.clients = []
        self.pending = []
        self.rec = None
        self.sidecar = None
        self.last_task = None                  # CPU0 task last switched in (filters same-task switches)
        # The global timer restarts at 0 when the board restarts; an offset keeps the recording's time
        # increasing across restarts (a TE_BOOT marker is written at each one).
        self.ts_offset = 0                     # None: take it from the next event
        self.max_ts = 0
        self.max_ts_wall = 0.0

    def save_sidecar(self):
        if self.sidecar:
            tmp = self.sidecar + ".tmp"
            with open(tmp, "w") as f:
                json.dump({"hz": self.hz, "names": {str(k): v for k, v in self.names.items()}}, f)
            os.replace(tmp, self.sidecar)

    def broadcast(self, kind, payload):
        msg = f"event: {kind}\ndata: {json.dumps(payload, separators=(',', ':'))}\n\n".encode()
        with self.lock:
            for q in list(self.clients):
                try:
                    q.put_nowait(msg)
                except queue.Full:            # a stalled page loses its stream, not the server
                    self.clients.remove(q)

    def board_restarted(self):
        """Called when the trace heads went backwards: the next events start a new timer epoch."""
        self.ts_offset = None                  # set from the first event of the new run
        self.last_task = None

    def add_events(self, evs):
        keep = []
        for e in evs:
            if self.ts_offset is not None and self.max_ts and e[1] + self.ts_offset < self.max_ts - self.hz:
                self.board_restarted()             # the shared timer went backwards: a new run
            if self.ts_offset is None:
                gap = int((time.time() - self.max_ts_wall) * self.hz) if self.max_ts_wall else 0
                self.ts_offset = self.max_ts + max(gap, self.hz // 10) - e[1]
                keep.append([0, e[1] + self.ts_offset - 1, TE_BOOT, 0, 0, 0, 0])
            e[1] += self.ts_offset
            if e[1] > self.max_ts:
                self.max_ts = e[1]
                self.max_ts_wall = time.time()
            if e[0] == 0 and e[2] == TE_TASK:
                # The kernel runs vTaskSwitchContext on every yield, also when it picks the same task again
                # (measured 2026-10-29: 99.6% of switches were espw -> espw).  Only a change is a switch.
                if e[6] == self.last_task:
                    self.status["dropped_same_task"] += 1
                    continue
                self.last_task = e[6]
            elif e[2] in (TE_GAP, TE_BOOT) and e[0] == 0:
                self.last_task = None
            keep.append(e)
        self.rec.append(keep)
        with self.lock:
            self.pending.extend(keep)

    def set_names(self, names):
        changed = False
        with self.lock:
            for k, v in names.items():
                if self.names.get(k) != v:
                    self.names[k] = v
                    changed = True
        if changed:
            self.save_sidecar()
            self.broadcast("names", {str(k): v for k, v in self.names.items()})

    def info(self):
        r = self.rec
        return {"hz": self.hz, "names": {str(k): v for k, v in self.names.items()}, "status": self.status,
                "first_ts": r.first_ts, "last_ts": r.last_ts, "window_s": WINDOW_S,
                "file": os.path.basename(r.path), "bytes": r.n * REC.size, "events": r.n}


S = State()


def decode_entries(ring, words):
    out = []
    for i in range(0, len(words) - 3, 4):
        lo, hi, w2, arg = words[i:i + 4]
        typ = w2 & 0xFF
        if typ == 0:                           # never-written slot
            continue
        out.append([ring, (hi << 32) | lo, typ, (w2 >> 8) & 0xFF, (w2 >> 16) & 0xFF, (w2 >> 24) & 0xFF, arg])
    return out


def decode_names(words):
    names = {}
    for i in range(0, len(words) - 3, 4):
        num = words[i]
        if num == 0xFFFFFFFF:
            continue
        raw = b"".join(w.to_bytes(4, "little") for w in words[i + 1:i + 4])
        names[num] = raw.split(b"\0", 1)[0].decode("ascii", "replace")
    return names


def reader_thread(xsdb):
    tcl = os.path.join(HERE, "trace_reader.tcl")
    last_ts = {0: 0, 1: 0}
    head_seen, head_moved = None, time.time()
    while True:
        S.status.update(mode="connecting", msg=f"starting {os.path.basename(xsdb)}")
        proc = subprocess.Popen([xsdb, tcl], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        for line in proc.stdout:
            parts = line.split()
            if not parts:
                continue
            tag = parts[0]
            try:
                if tag in ("R0", "R1"):
                    ring = 0 if tag == "R0" else 1
                    evs = decode_entries(ring, [int(x) for x in parts[2:]])
                    if evs:
                        last_ts[ring] = evs[-1][1]
                    S.add_events(evs)
                    S.status["mode"] = "live"
                elif tag == "HDR":
                    hz = int(parts[1])
                    if hz != S.hz:
                        S.hz = hz
                        S.save_sidecar()
                    h = (int(parts[4]), int(parts[5]))
                    now = time.time()
                    if h != head_seen:
                        head_seen, head_moved = h, now
                    if now - head_moved > STALL_S:
                        S.status.update(mode="stalled", msg=f"trace not moving for {now - head_moved:.0f} s: the board "
                                        "is not running (power, reset or a failed boot); what is in DDR is old")
                    else:
                        S.status.update(mode="live", msg="")
                    S.status.update(head0=h[0], head1=h[1])
                elif tag == "REBOOT":
                    S.board_restarted()
                elif tag == "NAMES":
                    S.set_names(decode_names([int(x) for x in parts[1:]]))
                elif tag == "GAP":
                    ring = 0 if parts[1] == "R0" else 1
                    S.status["gaps"] += int(parts[2])
                    S.add_events([[ring, last_ts[ring], TE_GAP, 0, 0, 0, int(parts[2])]])
                elif tag == "WAIT":
                    S.status.update(mode="waiting", msg=line[5:].strip(), head0=None, head1=None)
                    head_seen = None
            except ValueError:
                pass                              # xsdb banner and other text
        proc.wait()
        S.status.update(mode="waiting", msg=f"xsdb exited ({proc.returncode}), restarting")
        time.sleep(2)


def window(to_ts, span_s):
    """Events of [to - span, to] plus, before them, the events that set the state at the window's start:
    the running task, each lane's state, an unfinished link operation and an unfinished CPU1 verify."""
    r = S.rec
    if r.last_ts is None:
        return {"from_ts": None, "to_ts": None, "events": []}
    span = int(min(span_s, WINDOW_S) * S.hz)
    to_ts = min(to_ts if to_ts is not None else r.last_ts, r.last_ts)
    lo = max(to_ts - span, r.first_ts)
    hi = to_ts
    body = r.read(lo, hi)
    ctx = r.read(max(lo - int(CONTEXT_S * S.hz), r.first_ts), lo - 1)
    task = None; lanes = {}; link = None; cpu1 = None
    for e in ctx:
        t = e[2]
        if t == TE_TASK: task = e
        elif t == TE_LANE: lanes[e[3]] = e
        elif t == TE_LINK_B: link = e
        elif t == TE_LINK_E: link = None
        elif t == TE_CPU1_B: cpu1 = e
        elif t == TE_CPU1_E: cpu1 = None
        elif t == TE_GAP and e[0] == 0: task = None
    pre = [e for e in [task, link, cpu1] + list(lanes.values()) if e]
    pre.sort(key=lambda e: e[1])
    return {"from_ts": lo, "to_ts": hi, "events": pre + body}


def pump_thread():
    while True:
        time.sleep(0.2)
        with S.lock:
            batch, S.pending = S.pending, []
        if batch:
            S.broadcast("ev", batch)
        S.broadcast("status", S.info())


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send_json(self, obj):
        body = json.dumps(obj, separators=(",", ":")).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if u.path in ("/", "/index.html"):
            body = open(os.path.join(HERE, "web", "index.html"), "rb").read()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif u.path == "/info":
            self.send_json(S.info())
        elif u.path == "/window":
            to = int(q["to"][0]) if "to" in q else None
            span = float(q.get("span", [WINDOW_S])[0])
            self.send_json(window(to, span))
        elif u.path == "/events":
            self.stream()
        else:
            self.send_error(404)

    def stream(self):
        q = queue.Queue(maxsize=600)
        with S.lock:
            S.clients.append(q)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        try:
            self.wfile.write(f"event: hello\ndata: {json.dumps(S.info(), separators=(',', ':'))}\n\n".encode())
            self.wfile.flush()
            while True:
                try:
                    msg = q.get(timeout=5)
                except queue.Empty:
                    msg = b": keepalive\n\n"
                self.wfile.write(msg)
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            with S.lock:
                if q in S.clients:
                    S.clients.remove(q)


def convert_jsonl(path):
    """Turn a recording of the first viewer (JSON lines, every reschedule) into .bin + .json."""
    base = os.path.splitext(path)[0]
    if os.path.exists(base + ".bin") and os.path.getmtime(base + ".bin") >= os.path.getmtime(path):
        return base + ".bin"
    S.rec = Recording(base + ".bin", "w+b")
    S.sidecar = base + ".json"
    batch, last_ts = [], {0: 0, 1: 0}
    with open(path) as f:
        for line in f:
            r = json.loads(line)
            if "e" in r:
                e = r["e"]
                if e[1] < 0:                       # old gap marker
                    e = [e[0], last_ts[e[0]], TE_GAP, 0, 0, 0, e[6]]
                else:
                    last_ts[e[0]] = e[1]
                batch.append(e)
                if len(batch) >= 4096:
                    S.add_events(batch); batch = []
            elif "names" in r:
                S.names.update({int(k): v for k, v in r["names"].items()})
            elif "hz" in r:
                S.hz = r["hz"]
    S.add_events(batch)
    S.save_sidecar()
    S.rec.f.close()
    S.pending = []
    print(f"converted {path}: {S.rec.n} events kept, {S.status['dropped_same_task']} same-task reschedules dropped")
    S.status["dropped_same_task"] = 0
    S.last_task = None
    return base + ".bin"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--xsdb", default=os.environ.get("XSDB", DEFAULT_XSDB))
    ap.add_argument("--replay", help="serve a recording (.bin) instead of reading the board")
    args = ap.parse_args()

    if args.replay:
        if args.replay.endswith(".jsonl"):
            args.replay = convert_jsonl(args.replay)
        S.rec = Recording(args.replay, "rb")
        S.rec.index_existing()
        side = os.path.splitext(args.replay)[0] + ".json"
        if os.path.exists(side):
            meta = json.load(open(side))
            S.hz = meta.get("hz", S.hz)
            S.names = {int(k): v for k, v in meta.get("names", {}).items()}
        S.status.update(mode="replay", msg=os.path.basename(args.replay))
    else:
        os.makedirs(os.path.join(HERE, "recordings"), exist_ok=True)
        base = os.path.join(HERE, "recordings", time.strftime("trace_%Y%m%d_%H%M%S"))
        S.rec = Recording(base + ".bin", "w+b")
        S.sidecar = base + ".json"
        S.save_sidecar()
        print("recording to", base + ".bin")
        threading.Thread(target=reader_thread, args=(args.xsdb,), daemon=True).start()
    threading.Thread(target=pump_thread, daemon=True).start()
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    srv.daemon_threads = True
    print(f"trace viewer on http://127.0.0.1:{args.port}")
    srv.serve_forever()


if __name__ == "__main__":
    main()
