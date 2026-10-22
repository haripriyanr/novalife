"""The 128-bit tag block: build, split and verify.

Layout (bit 0 first, MSB-first inside every field):

    0..3    4 bits    version
    4..15   12 bits   hub_id
    16..79  64 bits   handle    (random, opaque, no identifier of any kind)
    80..127 48 bits   tag       (truncated Ascon-AEAD128 MAC over the first 80 bits)

Total 128 bits, exactly the payload of one polar codeword (N=256, K=128), per
`docs/algorithm.md` section 2 stage P2.

The MAC is documented in `ascon_primitives.mac_truncated`.  Short version: Ascon-AEAD128
with an empty plaintext and the 10-byte header as associated data, under the hub key, and
the 128-bit authentication tag of that run truncated to its first 48 bits.  That is a
standard AEAD-turned-MAC construction (NIST SP 800-232 lists tag truncation as an allowed
option) over the standard Ascon primitive; it is not a home-made cipher or MAC.

Nothing here knows the ROI, the image or the codec.  It is deliberately the smallest
module in the reference so the enclave version of it is a few registers.
"""
from __future__ import annotations

import numpy as np

from ascon_primitives import MAC_DOMAIN, mac_truncated

# --- the block, fixed by the locked design ------------------------------------

VERSION_BITS = 4
HUB_ID_BITS = 12
HANDLE_BITS = 64
TAG_BITS = 48
TOTAL_BITS = VERSION_BITS + HUB_ID_BITS + HANDLE_BITS + TAG_BITS
HEADER_BYTES = (VERSION_BITS + HUB_ID_BITS + HANDLE_BITS) // 8  # 10 bytes

CURRENT_VERSION = 1  # 4-bit field, fits

# Test-only demo key.  This is NOT the hub key: the real one is loaded into the PL at
# boot and never crosses Linux (docs/system_architecture.md, decision D5).  It is here so
# the reference is runnable and reproducible.
DEMO_HUB_KEY = bytes.fromhex("00112233445566778899aabbccddeeff")

HANDLE_SEED = 20261011  # fixed so the demo's handle is the same every run


# --- bit <-> byte helpers -----------------------------------------------------


def bits_to_bytes(bits: np.ndarray) -> bytes:
    b = np.asarray(bits, dtype=np.uint8).astype(np.uint8)
    assert b.size % 8 == 0, f"{b.size} bits is not a whole number of bytes"
    return np.packbits(b).tobytes()


def bytes_to_bits(data: bytes) -> np.ndarray:
    return np.unpackbits(np.frombuffer(data, dtype=np.uint8)).astype(np.uint8)


def split_field(bits: np.ndarray, lo: int, hi: int) -> int:
    """Value of bits[lo:hi], MSB-first."""
    v = 0
    for bit in bits[lo:hi]:
        v = (v << 1) | int(bit)
    return v


# --- the MAC ------------------------------------------------------------------


def header_bytes_of(version: int, hub_id: int, handle: int) -> bytes:
    """The 10 bytes (version | hub_id | handle) that the MAC authenticates."""
    return (
        version.to_bytes(1, "big", signed=False)[-1:]  # 4 bits used
        + hub_id.to_bytes(2, "big")[-2:]
        + handle.to_bytes(HANDLE_BITS // 8, "big")
    )


def compute_tag(key: bytes, version: int, hub_id: int, handle: int) -> int:
    """48-bit truncated Ascon MAC over (version, hub_id, handle)."""
    header = header_bytes_of(version, hub_id, handle)
    # the header is always exactly HEADER_BYTES long; encode its length too so the MAC
    # input can never be ambiguous
    message = bytes([len(header)]) + header
    tag_bytes = mac_truncated(key, MAC_DOMAIN + message, TAG_BITS)
    return int.from_bytes(tag_bytes, "big")


# --- build / split / verify ---------------------------------------------------


def build_block(key: bytes, version: int, hub_id: int, handle: int) -> np.ndarray:
    """Return the 128-bit numpy array for (version, hub_id, handle, tag)."""
    assert 0 <= version < (1 << VERSION_BITS), "version does not fit in 4 bits"
    assert 0 <= hub_id < (1 << HUB_ID_BITS), "hub_id does not fit in 12 bits"
    assert 0 <= handle < (1 << HANDLE_BITS), "handle does not fit in 64 bits"
    tag = compute_tag(key, version, hub_id, handle)
    header = f"{version:0{VERSION_BITS}b}{hub_id:0{HUB_ID_BITS}b}{handle:0{HANDLE_BITS}b}"
    full = header + f"{tag:0{TAG_BITS}b}"
    bits = np.array([int(ch) for ch in full], dtype=np.uint8)
    assert bits.size == TOTAL_BITS
    return bits


def split_block(bits: np.ndarray) -> dict:
    """Split a 128-bit array into its four fields (no verification)."""
    bits = np.asarray(bits, dtype=np.uint8)
    if bits.size != TOTAL_BITS:
        raise ValueError(f"expected {TOTAL_BITS} bits, got {bits.size}")
    return {
        "version": split_field(bits, 0, VERSION_BITS),
        "hub_id": split_field(bits, VERSION_BITS, VERSION_BITS + HUB_ID_BITS),
        "handle": split_field(bits, VERSION_BITS + HUB_ID_BITS, VERSION_BITS + HUB_ID_BITS + HANDLE_BITS),
        "tag": split_field(
            bits, TOTAL_BITS - TAG_BITS, TOTAL_BITS
        ),
    }


def verify_block(bits: np.ndarray, key: bytes) -> dict:
    """Verify the tag inside a recovered 128-bit array.

    `tag_ok` is True only if the 48 bits are exactly what this key computes over the
    first 80 bits.  A wrong key, a wrong version, hub_id or handle, or a single bit flip
    anywhere in the block makes it False.  There is no partial accept.
    """
    fields = split_block(bits)
    expected = compute_tag(key, fields["version"], fields["hub_id"], fields["handle"])
    return {**fields, "tag_ok": bool(expected == fields["tag"]), "expected_tag": expected}


def new_handle(seed: int | None = None) -> int:
    """A fresh 64-bit handle.  Random and opaque: it must not encode anything."""
    rng = np.random.default_rng(seed)
    while True:
        h = int.from_bytes(rng.integers(0, 256, 8, dtype=np.uint8).tobytes(), "big")
        if h < (1 << HANDLE_BITS):
            return h


def format_block(bits: np.ndarray) -> str:
    f = split_block(bits)
    return (
        f"version={f['version']} hub_id={f['hub_id']} "
        f"handle=0x{f['handle']:016x} tag=0x{f['tag']:012x}"
    )


if __name__ == "__main__":  # pragma: no cover - manual check
    rng_handle = new_handle(HANDLE_SEED)
    blk = build_block(DEMO_HUB_KEY, CURRENT_VERSION, 0x9A3, rng_handle)
    v = verify_block(blk, DEMO_HUB_KEY)
    assert v["tag_ok"], "clean block must verify"
    assert v["handle"] == rng_handle
    print(format_block(blk))
    print("expect_tag :", format_block(build_block(DEMO_HUB_KEY, CURRENT_VERSION, 0x9A3, rng_handle)))
    # a single flipped bit must fail
    for pos in (0, 4, 16, 40, 79, 80, 127):
        bad = blk.copy()
        bad[pos] ^= 1
        assert not verify_block(bad, DEMO_HUB_KEY)["tag_ok"], f"bit {pos} accepted"
    # a wrong key must fail
    assert not verify_block(blk, bytes(16))["tag_ok"]
    # a different handle must give a different tag
    assert compute_tag(DEMO_HUB_KEY, 1, 0x9A3, 1) != compute_tag(DEMO_HUB_KEY, 1, 0x9A3, 2)
    print("tag_block self-test: PASS (single-bit and wrong-key rejection)")
