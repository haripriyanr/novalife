#!/usr/bin/env python3
"""NovaLife gateway -- minimal reference implementation for e2e testing.

Runs on the PC (or the board's PS).  Exposes the Part-2 API from
docs/hub_http_api.md over HTTP, backed by the Python tag reference and an
in-memory store.  Not production: no TLS, no MFA, no rate limiting, no audit
chain.  Those are G3/G4 deliverables.

Usage:
    novalife_hub/.venv/bin/python novalife_hub/gateway/gateway.py --port 8080
"""
import argparse
import hashlib
import json
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

HERE = Path(__file__).resolve().parent
HUB = HERE.parent
sys.path.insert(0, str(HUB / "tools" / "tag_reference"))
sys.path.insert(0, str(HUB / "tools" / "stego_research" / "sims"))

import embed  # noqa: E402
import extract  # noqa: E402
import tag_block  # noqa: E402
from PIL import Image
import io

# In-memory store
HANDLES = {}   # handle -> {hub_id, version, tag, revoked}
RECORDS = {}   # handle -> record view
SCANS = {}     # image_hash -> handle


def extract_tag_from_image(img_bytes: bytes):
    """Extract tag from image using the reference extractor."""
    img = Image.open(io.BytesIO(img_bytes)).convert("L")
    arr = np.asarray(img, dtype=np.uint8)
    # Use declared shape = image shape (no resize)
    r = extract.recover(arr, embed.HUB_KEY, declared_shape=arr.shape,
                        codeword=None)
    return r


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/status":
            self._json(200, {"ok": True, "vault_files": 0, "pl": "absent"})
        elif self.path == "/vault/index.txt":
            self._json(200, {"files": []})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length > 0 else b""
        if self.path == "/api/v1/verify":
            self._handle_verify(body)
        elif self.path == "/api/v1/records":
            self._handle_records(body)
        elif self.path == "/api/v1/submit":
            self._handle_submit(body)
        else:
            self._json(404, {"error": "not found"})

    def _handle_verify(self, body):
        try:
            data = json.loads(body) if body else {}
        except Exception:
            self._json(400, {"ok": False, "reason": "bad json"})
            return
        # If image is provided, extract tag from it
        image_b64 = data.get("image_b64")
        if image_b64:
            import base64
            img_bytes = base64.b64decode(image_b64)
            r = extract_tag_from_image(img_bytes)
            if not r.tag_ok:
                self._json(200, {"ok": False, "reason": "tag verification failed"})
                return
            handle = int.from_bytes(r.bits[4:12], "big") if len(r.bits) >= 12 else 0
            # Simplified: use the handle from the extracted bits
            handle_str = f"H-{r.bits.tobytes().hex()[:16]}"
            if handle_str in HANDLES and HANDLES[handle_str].get("revoked"):
                self._json(200, {"ok": False, "reason": "handle revoked"})
                return
            HANDLES.setdefault(handle_str, {"revoked": False})
            self._json(200, {"ok": True, "reason": "verified", "handle": handle_str})
        else:
            # Manual verify with provided fields
            handle = data.get("handle", "")
            if handle in HANDLES and HANDLES[handle].get("revoked"):
                self._json(200, {"ok": False, "reason": "handle revoked"})
                return
            self._json(200, {"ok": True, "reason": "verified"})

    def _handle_records(self, body):
        try:
            data = json.loads(body) if body else {}
        except Exception:
            self._json(400, {"error": "bad json"})
            return
        handle = data.get("handle", "")
        if handle in RECORDS:
            self._json(200, {"record_view": RECORDS[handle]})
        else:
            self._json(403, {"error": "no record for handle"})

    def _handle_submit(self, body):
        try:
            data = json.loads(body) if body else {}
        except Exception:
            self._json(400, {"error": "bad json"})
            return
        handle = f"H-{len(HANDLES):04d}"
        HANDLES[handle] = {"revoked": False}
        RECORDS[handle] = {"title": data.get("title", "Untitled"), "body": data.get("body", "")}
        self._json(200, {"handle": handle, "status": "stored"})

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass  # quiet


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--host", type=str, default="0.0.0.0")
    args = ap.parse_args()
    httpd = HTTPServer((args.host, args.port), Handler)
    print(f"NovaLife gateway listening on {args.host}:{args.port}")
    httpd.serve_forever()


if __name__ == "__main__":
    # Need numpy for extract
    import numpy as np
    main()
