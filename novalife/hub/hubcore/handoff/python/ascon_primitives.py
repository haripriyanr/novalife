"""Ascon-AEAD128 as standardised in NIST SP 800-232 (Aug 2025), in plain Python, plus the two
derivations this reference builds from it: a truncated MAC and a keystream.

History (why this file says what it says)
-----------------------------------------
* The original `tools/stego_research/sims/ascon128.py` was named for Ascon but implemented
  AES-128-GCM; it is quarantined in `legacy/sims_ascon128_actually_aes128gcm.py`.
* Until 2026-10-20 this module implemented **Ascon-128 v1.2** (the 2019 CAESAR/LWC submission:
  IV 0x80400C0600000000, 64-bit rate, big-endian words, p^6 data rounds) while its docstring
  called it SP 800-232.  It also loaded a partial final plaintext block little-endian and its
  `ascon_aead_decrypt` recomputed the tag by encrypting zeros (wrong for any non-empty
  ciphertext).  On the owner's decision of 2026-10-20 it now implements the standard
  (`docs/improvement_review_2026-10-20.md` A6), so every tag and the placement keystream
  changed and the dependent measurements were re-run.

Specification followed (SP 800-232 Ascon-AEAD128; ascon-c `crypto_aead/asconaead128/ref`)
  * 128-bit key, 128-bit nonce, 128-bit tag, **128-bit rate** (16 bytes per block)
  * bytes are loaded into 64-bit words **little-endian**
  * initialise:  S = (IV, K0, K1, N0, N1), IV = 0x00001000808C0001;  p^12;  S3 ^= K0; S4 ^= K1
  * absorb AD (only if non-empty): S0 ^= A[0:8]; S1 ^= A[8:16]; p^8 per block; the last
                (possibly empty) block is padded with 0x01 after the last byte
  * separate:    S4 ^= 0x80 << 56
  * encrypt:     (S0, S1) ^= P block -> C;  p^8 between full blocks;  last block padded as AD
  * finalise:    S2 ^= K0; S3 ^= K1;  p^12;  T = LE(S3 ^ K0) || LE(S4 ^ K1)

`selftest()` checks this module against **all 1089** official known-answer vectors in
`vectors/kat/LWC_AEAD_KAT_128_128.txt` (ascon-c, `crypto_aead/asconaead128/`, fetched
2026-10-20, SHA-256 bbbc34692fe05e5fda0a3b025585622ab3e3747495e5e3655b29aae8c2a4bd33) and
round-trips decryption on every one.  `KAT_VECTORS` is a block-boundary subset of that file,
embedded so the module still self-checks without the file and so the RTL vectors can use it.

No dependencies: this file uses no library at all.
"""
from __future__ import annotations

from pathlib import Path

# --- constants from NIST SP 800-232 -------------------------------------------

IV = 0x00001000808C0001
RATE = 16  # bytes
TAG_BYTES = 16
DSEP = 0x80 << 56
ROUND_CONSTS = (0xF0, 0xE1, 0xD2, 0xC3, 0xB4, 0xA5, 0x96, 0x87, 0x78, 0x69, 0x5A, 0x4B)
MASK64 = (1 << 64) - 1
WORD_BYTEORDER = "little"

KAT_FILE = Path(__file__).resolve().parent / "vectors" / "kat" / "LWC_AEAD_KAT_128_128.txt"
KAT_KEY = bytes.fromhex("000102030405060708090A0B0C0D0E0F")
KAT_NONCE = bytes.fromhex("101112131415161718191A1B1C1D1E1F")
# (Count, PT, AD, CT||tag) -- block boundaries of both the AD and the PT path
KAT_VECTORS = [
    (1, '', '', '4F9C278211BEC9316BF68F46EE8B2EC6'),
    (2, '', '30', 'CCCB674FE18A09A285D6AB11B35675C0'),
    (8, '', '30313233343536', 'B38ABBD573E071C6265EEAC4A68F65AB'),
    (9, '', '3031323334353637', '865C594093A9EDEE2C1D6384CCB4939E'),
    (16, '', '303132333435363738393A3B3C3D3E', '759102A6953861627AAE1836D003A294'),
    (17, '', '303132333435363738393A3B3C3D3E3F', 'E4230CDB8330EE9DC0CFD7C7B346E6DC'),
    (18, '', '303132333435363738393A3B3C3D3E3F40', 'BD8851CD3AF9847844839A791DD70E8C'),
    (32, '', '303132333435363738393A3B3C3D3E3F404142434445464748494A4B4C4D4E', 'C6306F1F154C78833984173360AAE874'),
    (33, '', '303132333435363738393A3B3C3D3E3F404142434445464748494A4B4C4D4E4F', 'EFC3E78B02AD9A80A6F0548C5B0BB5BA'),
    (34, '20', '', 'E8DD576ABA1CD3E6FC704DE02AEDB79588'),
    (235, '20212223242526', '303132', '66D0D52BF401C64CFCCEA25BB53CEF292120521D154BF4'),
    (265, '2021222324252627', '', 'E8C3DEEE246CC5EAE455EF6B33B782A3DD91ED6695373C27'),
    (512, '202122232425262728292A2B2C2D2E', '303132333435363738393A3B3C3D3E3F', '6373EBB28BE97C9BAC090CF399C13E646BE0C80B0404770341EB48D6178948'),
    (529, '202122232425262728292A2B2C2D2E2F', '', 'E8C3DEEE246CC5EAE3E872313897A2BB9EAA915C9DD3245D77048F24D46D27A7'),
    (545, '202122232425262728292A2B2C2D2E2F', '303132333435363738393A3B3C3D3E3F', '6373EBB28BE97C9BAC090CF399C13EF13ABFC0D209E8F4844C90814D13F32C59'),
    (571, '202122232425262728292A2B2C2D2E2F30', '303132333435363738', 'BF79D7476D6FB05B8891A079BE8A1992B63DAB0CA49C0138BB79BD161A0E6403A3'),
    (793, '202122232425262728292A2B2C2D2E2F3031323334353637', '', 'E8C3DEEE246CC5EAE3E872313897A2BB6089AA3E15E80307F2D00B0754CB343B0EA742A196423647'),
    (1055, '202122232425262728292A2B2C2D2E2F303132333435363738393A3B3C3D3E', '303132333435363738393A3B3C3D3E3F404142434445464748494A4B4C4D4E', '4B392E5FA60E0CBBCA547DB96E3262BD8382D6C0E608E24F441AAAFC4726E57640E8294794DD3C2AA021192B091DE3'),
    (1089, '202122232425262728292A2B2C2D2E2F303132333435363738393A3B3C3D3E3F', '303132333435363738393A3B3C3D3E3F404142434445464748494A4B4C4D4E4F', 'CB34D04660A66DBFBE9C856601F5B8AA51A499B55AC8F7FBEFBC331A613EE9CDFD191750A47F211C0A15ED28173D7CAA'),
]


# --- permutation (unchanged between v1.2 and SP 800-232) -----------------------


def _ror(x: int, n: int) -> int:
    return ((x >> n) | (x << (64 - n))) & MASK64


def _round(s: list[int], c: int) -> None:
    s[2] ^= c
    s[0] ^= s[4]
    s[4] ^= s[3]
    s[2] ^= s[1]
    t0 = s[0] ^ (~s[1] & s[2])
    t1 = s[1] ^ (~s[2] & s[3])
    t2 = s[2] ^ (~s[3] & s[4])
    t3 = s[3] ^ (~s[4] & s[0])
    t4 = s[4] ^ (~s[0] & s[1])
    t1 ^= t0
    t0 ^= t4
    t3 ^= t2
    t2 = ~t2 & MASK64
    s[0] = t0 ^ _ror(t0, 19) ^ _ror(t0, 28)
    s[1] = t1 ^ _ror(t1, 61) ^ _ror(t1, 39)
    s[2] = t2 ^ _ror(t2, 1) ^ _ror(t2, 6)
    s[3] = t3 ^ _ror(t3, 10) ^ _ror(t3, 17)
    s[4] = t4 ^ _ror(t4, 7) ^ _ror(t4, 41)


def permute(s: list[int], rounds: int) -> None:
    """Apply p^rounds (1..12) in place, using the last `rounds` round constants."""
    for i in range(12 - rounds, 12):
        _round(s, ROUND_CONSTS[i])


def _ld(b: bytes) -> int:
    """Load up to 8 bytes little-endian (missing high bytes are zero)."""
    return int.from_bytes(b, WORD_BYTEORDER)


def _st(w: int, n: int = 8) -> bytes:
    return (w & MASK64).to_bytes(8, WORD_BYTEORDER)[:n]


def _pad(i: int) -> int:
    """The 0x01 padding byte at byte position i (0..7) of a little-endian word."""
    return 0x01 << (8 * i)


def _xor_block(s: list[int], block: bytes) -> None:
    """XOR a partial (< 16 byte) block into S0||S1 and add the 0x01 padding."""
    r = len(block)
    if r < 8:
        s[0] ^= _ld(block) ^ _pad(r)
    else:
        s[0] ^= _ld(block[:8])
        s[1] ^= _ld(block[8:]) ^ _pad(r - 8)


# --- AEAD ---------------------------------------------------------------------


def _init(key: bytes, nonce: bytes) -> tuple[list[int], int, int]:
    assert len(key) == 16 and len(nonce) == 16
    k0, k1 = _ld(key[:8]), _ld(key[8:])
    s = [IV, k0, k1, _ld(nonce[:8]), _ld(nonce[8:])]
    permute(s, 12)
    s[3] ^= k0
    s[4] ^= k1
    return s, k0, k1


def _absorb_ad(s: list[int], ad: bytes) -> None:
    if ad:
        off = 0
        while len(ad) - off >= RATE:
            s[0] ^= _ld(ad[off : off + 8])
            s[1] ^= _ld(ad[off + 8 : off + 16])
            permute(s, 8)
            off += RATE
        _xor_block(s, ad[off:])
        permute(s, 8)
    s[4] ^= DSEP


def _finalise(s: list[int], k0: int, k1: int) -> bytes:
    s[2] ^= k0
    s[3] ^= k1
    permute(s, 12)
    return _st(s[3] ^ k0) + _st(s[4] ^ k1)


def ascon_aead_encrypt(key: bytes, nonce: bytes, plaintext: bytes, ad: bytes = b"") -> bytes:
    """Ascon-AEAD128 encrypt.  Returns ciphertext || 16-byte tag."""
    s, k0, k1 = _init(key, nonce)
    _absorb_ad(s, ad)
    out = bytearray()
    off = 0
    while len(plaintext) - off >= RATE:
        s[0] ^= _ld(plaintext[off : off + 8])
        s[1] ^= _ld(plaintext[off + 8 : off + 16])
        out += _st(s[0]) + _st(s[1])
        permute(s, 8)
        off += RATE
    rem = plaintext[off:]
    _xor_block(s, rem)
    out += (_st(s[0]) + _st(s[1]))[: len(rem)]
    return bytes(out) + _finalise(s, k0, k1)


def ascon_aead_decrypt(key: bytes, nonce: bytes, ct_and_tag: bytes, ad: bytes = b"") -> bytes | None:
    """Ascon-AEAD128 decrypt (duplex: the state takes the ciphertext).  None if the tag fails."""
    if len(ct_and_tag) < TAG_BYTES:
        return None
    body, tag = ct_and_tag[:-TAG_BYTES], ct_and_tag[-TAG_BYTES:]
    s, k0, k1 = _init(key, nonce)
    _absorb_ad(s, ad)
    out = bytearray()
    off = 0
    while len(body) - off >= RATE:
        c0, c1 = _ld(body[off : off + 8]), _ld(body[off + 8 : off + 16])
        out += _st(s[0] ^ c0) + _st(s[1] ^ c1)
        s[0], s[1] = c0, c1
        permute(s, 8)
        off += RATE
    rem = body[off:]
    r = len(rem)
    ks = (_st(s[0]) + _st(s[1]))[:r]
    pt = bytes(a ^ b for a, b in zip(rem, ks))
    out += pt
    _xor_block(s, pt)          # absorbing P into the keystream state leaves exactly C || pad
    calc = _finalise(s, k0, k1)
    diff = 0
    for a, b in zip(calc, tag):
        diff |= a ^ b
    return bytes(out) if diff == 0 else None


# --- derivations used by the tag reference -------------------------------------

# Fixed, published, non-secret nonces.  The constructions below are deterministic PRF-style
# uses of the AEAD: the same key and nonce always produce the same value, which is what
# makes the tag verifiable and the placement reproducible.  Distinct nonce constants
# separate the two uses so they never share a state.
NONCE_MAC = bytes.fromhex("4E6F76614C6966654D41435430303031")  # "NovaLifeMACT0001"
NONCE_STREAM = bytes.fromhex("4E6F76614C6966655354524D30303031")  # "NovaLifeSTRM0001"
MAC_DOMAIN = b"Novalife/tag-block/v1"


def mac_truncated(key: bytes, message: bytes, nbits: int) -> bytes:
    """48-bit (or any) truncated Ascon-AEAD128 (NIST SP 800-232) MAC over `message`.

    Construction: Ascon-AEAD128 with an *empty* plaintext and `message` as the associated
    data, under the hub key and NONCE_MAC.  The authentication tag of that run is a 128-bit
    MAC of the message; the first `nbits` bits of it are returned.

    This is the standard "AEAD over an empty message with the data as associated data"
    instantiation of a MAC.  NIST SP 800-232 allows a truncated tag (the leftmost
    bits of T); truncating to 48 bits leaves 48 bits of integrity strength,
    which is the value written in `docs/algorithm.md` section 3.

    Not a home-made cipher or MAC: the only primitive used is Ascon-AEAD128.
    """
    ct_tag = ascon_aead_encrypt(key, NONCE_MAC, b"", MAC_DOMAIN + message)
    tag = ct_tag[-TAG_BYTES:]
    assert nbits % 8 == 0
    return tag[: nbits // 8]


def keystream(key: bytes, domain: bytes, nbytes: int) -> bytes:
    """Deterministic Ascon-CTR keystream, `nbytes` long.

    Ascon-AEAD128's encryption body is a counter-mode-style keystream generator: the block
    after initialisation and AD absorption is XORed with the plaintext to form the
    ciphertext, so encrypting an all-zero plaintext of length L under this key yields
    exactly L bytes of keystream.  That is what this returns, with a domain separator in
    the associated data so the stream is bound to its purpose.

    Used only for the placement permutation (obfuscation of location, per
    `docs/algorithm.md` stage P3) -- it is never used to encrypt the image.
    """
    if nbytes == 0:
        return b""
    zeros = bytes(nbytes)
    return ascon_aead_encrypt(key, NONCE_STREAM, zeros, domain)[:nbytes]


def load_kat_file(path: Path = KAT_FILE) -> list[tuple[int, str, str, str]]:
    """Parse the official LWC KAT file into (Count, PT, AD, CT) tuples."""
    out = []
    for blk in path.read_text().strip().split("\n\n"):
        d = {}
        for line in blk.splitlines():
            k, _, v = line.partition("=")
            d[k.strip()] = v.strip()
        assert d["Key"] == KAT_KEY.hex().upper() and d["Nonce"] == KAT_NONCE.hex().upper()
        out.append((int(d["Count"]), d["PT"], d["AD"], d["CT"]))
    return out


def selftest() -> int:
    """Check against the official KATs (all 1089 if the file is present).  Returns the count."""
    vectors = load_kat_file() if KAT_FILE.exists() else list(KAT_VECTORS)
    embedded = {v[0]: v for v in KAT_VECTORS}
    for count, pt, ad, ct in vectors:
        if count in embedded:
            assert embedded[count] == (count, pt, ad, ct), f"embedded KAT {count} differs from the file"
        got = ascon_aead_encrypt(KAT_KEY, KAT_NONCE, bytes.fromhex(pt), bytes.fromhex(ad))
        if got.hex().upper() != ct.upper():
            raise AssertionError(f"Ascon-AEAD128 KAT {count} mismatch\n  got {got.hex().upper()}\n  exp {ct}")
        back = ascon_aead_decrypt(KAT_KEY, KAT_NONCE, got, bytes.fromhex(ad))
        assert back == bytes.fromhex(pt), f"decrypt failed on KAT {count}"
        bad = bytearray(got)
        bad[-1] ^= 1
        assert ascon_aead_decrypt(KAT_KEY, KAT_NONCE, bytes(bad), bytes.fromhex(ad)) is None
        if pt:
            badc = bytearray(got)
            badc[0] ^= 1
            assert ascon_aead_decrypt(KAT_KEY, KAT_NONCE, bytes(badc), bytes.fromhex(ad)) is None
    return len(vectors)


if __name__ == "__main__":  # pragma: no cover - manual check
    n = selftest()
    print(f"Ascon-AEAD128 (NIST SP 800-232) KAT self-test: PASS ({n} official vectors, encrypt + decrypt + tamper)")
