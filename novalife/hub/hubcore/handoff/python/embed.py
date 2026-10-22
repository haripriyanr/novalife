"""P3 + P4 of `docs/algorithm.md`: mark an image with the 128-bit tag block.

Pipeline, in the order section 2 draws it:

    cover (uint8, grayscale)
      -> 5/3 lifting IWT, 1 level                     [sims/iwt_lifting.py]
      -> mask: ROI support exclusion + local variance  [sims/perceptual_mask.py]
      -> P1 pilot grid in the LL band                  [pilot_grid.py]
      -> P2 polar encode the 128-bit block, N=256 K=128 [sims/polar_codec.py]
      -> P3 keyed placement of the 256-bit codeword    [ascon_primitives.keystream]
      -> P4 QIM on 8x8 DCT blocks of the LL band, one mid-band coefficient each,
            the same codeword in R regions
      -> inverse IWT, clip, uint8

Three things the locked spec does not spell out, recorded here on purpose because the
RTL has to match them:

1. **The ROI is a deterministic function of the image.** `roi_from_image` is the same
   threshold rule `sims/dicom_loader.py` uses (mean + 0.2 x std).  Both sides of the
   pipeline run it, on their own copy of the image, so the block lists they compute
   agree without anything being stored.  A drawn-in ROI (the synthetic phantom's lung
   fields) is used only to *report* how much the marking moved a diagnostic pixel; it
   is not part of the algorithm.
2. **ROI exclusion is per coefficient, and it is exact.** A 5/3 inverse lifts one LL
   coefficient into a 3x3 pixel neighbourhood (`iiwt1d_53` uses d[i-1] and d[i] in both
   directions; verified by `support_test`), so "nothing is written inside the diagnostic
   region" can be made exact: a coefficient is refused when any of its nine pixels is
   ROI, and an 8x8 block is refused when any of its 64 coefficients is refused.  The
   demo measures the result as exactly zero changed pixels inside the ROI.
3. **Payload blocks never overlap the pilot grid.** A grid line biases a whole LL row,
   which would land on the mid-band DCT coefficient the payload uses.  Blocks are
   chosen outside the grid instead, so the two stages stay independent; the cost is
   capacity (half the blocks), which `make_cover` leaves room for.

Everything numeric is a constant at the top of this file, so a sweep only edits
constants.  `python3 embed.py` prints the pixel-support check and marks a demo cover.
"""
from __future__ import annotations

# Make the sibling modules and the shared sims importable from any directory.
import math
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
_SIMS = os.path.abspath(os.path.join(_HERE, "..", "stego_research", "sims"))
if _SIMS not in sys.path:
    sys.path.insert(0, _SIMS)

import json
from dataclasses import dataclass
from functools import lru_cache

import numpy as np
from PIL import Image

import perceptual_mask  # the DSP48-style variance core, reused for the step scaling
import polar_codec  # the codec the RTL targets
from ascon_primitives import ascon_aead_encrypt
from iwt_lifting import iiwt2d_53, iwt2d_53  # bit-exact integer 5/3 lifting
from pilot_grid import PILOT_INTERVAL_G
from tag_block import CURRENT_VERSION, TOTAL_BITS, build_block, verify_block

# --------------------------------------------------------------------------- #
# parameters -- algorithm.md section 3, starting values (sweep these)
# --------------------------------------------------------------------------- #

COVER_SHAPE = (1200, 1600)  # (rows, cols); long edge 1600 px, the declared export size
COVER_SEED = 7010

PHANTOM_SCALE = 0.72  # how much of the frame the patient occupies in the synthetic cover

ROI_SUPPORT_LL = 1  # a 5/3 LL coefficient reaches +/-(this) in each LL direction
ROI_CLEARANCE_LL = 2  # extra LL coefficients (4 px) of head-room around the ROI
ROI_RULE = ("img > mean + 0.2 x std -- the rule sims/dicom_loader.py uses -- mapped to "
            "LL coefficients by their 3x3 pixel support, then dilated")

CLIP_MARGIN = 6  # a block is unusable if its pixel support comes within this of 0 or 255
#                 (raised from 1 with the integer QIM: one LL write can move a pixel by ~5)
BG_FLOOR = 16    # intake: background pixels OUTSIDE the diagnostic region are raised to this
ROI_STATS_FLOOR = BG_FLOOR  # pixels <= this count as 0 in the ROI statistics, so flooring the
#                             background cannot move the ROI threshold (measured 2026-10-20: without
#                             this, flooring moved the threshold and the mark reached brain pixels)
CLIP_RULE = ("a payload block whose 16x16 pixel support touches a uint8 clipping level is "
             "unusable: the uint8 reconstruction clips the write away and a codec turns the "
             "block into a constant, so every such block reads back the same bit.  Measured "
             "on a real cardiac MRI, 94% of the eligible blocks sat on the 0 clip and every "
             "re-encode failed with a hard BER of ~0.54 in all four regions; lifting the "
             "black level by 16 -- changing nothing else -- made the same image pass "
             "JPEG q90/q70/q50.  See results/g1_real_image_2026-10-19.md")

PILOT_ENABLED = False  # 2026-10-20: the pilot grid is no longer embedded (algorithm.md 3.2).
#                        Recovery takes a resize from the exact size ratio and a crop from the
#                        size residual; the grid cost 7/16 of the blocks and most of the PSNR loss.
PILOT_WIDTH_B = 3  # kept for the recovery code's grid geometry; unused while PILOT_ENABLED is False
PILOT_AMPLITUDE = 16 if PILOT_ENABLED else 0

# Integer QIM on a +/-1 Hadamard pattern (algorithm.md 3.2).  Everything below is integer and
# floor-division, so the PL can be bit-exact with no multipliers in the embed path.
QIM_BASE_DELTA = 64       # delta = 64 + (5 * isqrt(local variance)) >> 3, forced even
QIM_ALPHA_NUM = 5
QIM_ALPHA_SHIFT = 3
QIM_ALPHA = QIM_ALPHA_NUM / (1 << QIM_ALPHA_SHIFT)   # 0.625, for reports only
QIM_STD_WINDOW = 3  # local variance over this many LL coefficients around a block

DCT_BLOCK = 4  # payload block, LL coefficients per side (8 x 8 pixels).  The name is historical:
#                the block now carries a Hadamard projection, not a DCT coefficient.
HADAMARD = np.outer([1, 1, -1, -1], [1, 1, -1, -1]).astype(np.int64)   # lowest DC-free sequency, sum h^2 = 16

N_REGIONS = 4  # the most COPIES of the codeword written (2026-10-20: copies are interleaved over
#               the whole LL band in one keyed order, not quadrants; as many as fit are written,
#               copy-major, so copy c's positions never depend on how many copies there are)
BLOCKS_PER_REGION = polar_codec.N  # 256, one block per codeword bit, per copy

PLACEMENT_DOMAIN = b"Novalife/placement/v2"
HUB_KEY = bytes.fromhex("00112233445566778899aabbccddeeff")  # demo key, NOT the hub key
DEMO_HUB_ID = 0x9A3


# --------------------------------------------------------------------------- #
# a synthetic cover (never patient data)
# --------------------------------------------------------------------------- #


def make_cover(seed: int = COVER_SEED) -> tuple[np.ndarray, np.ndarray]:
    """A 1600x1200 synthetic chest-radiograph-shaped phantom and its diagnostic ROI.

    Returns `(cover, roi)` with `roi` = 1 on the diagnostic area (lung fields,
    mediastinum, spine, ribs) and 0 on the soft tissue and the film margin.  The ROI is
    drawn rather than thresholded so that "nothing changed inside the ROI" is a real
    check with a ground truth behind it; `roi_from_image` is what the algorithm uses.

    The patient is drawn small on purpose: the payload needs roughly a quarter of the
    frame outside the diagnostic region (one 8x8 LL block per bit, half the blocks
    removed by the pilot grid, R = 4 regions), so a cover whose patient fills the frame
    would have nowhere to put the mark.  That is a real constraint of the algorithm, not
    an artefact of this picture, and it is measured in the demo output.
    """
    rng = np.random.default_rng(seed)
    h, w = COVER_SHAPE
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    nx, ny = xx / w, yy / h
    cx, cy = nx - 0.5, ny - 0.5

    S = PHANTOM_SCALE  # every anatomical radius is multiplied by this
    img = np.full((h, w), 22.0, dtype=np.float64)  # the dark film margin

    # soft tissue: the patient, brighter than the margin, still not diagnostic
    body = np.sqrt((cx / (0.30 * S)) ** 2 + (cy / (0.34 * S)) ** 2) <= 1.0
    img[body] = 84.0 + 20.0 * np.cos(2.2 * cx[body] + 1.0) * np.sin(2.0 * cy[body])

    roi = np.zeros((h, w), dtype=np.uint8)

    # lung fields -- the ROI, and the brightest structure in the frame
    for side in (-1.0, 1.0):
        ex = (cx - side * 0.135 * S) / (0.125 * S)
        ey = (cy + 0.015 * S) / (0.185 * S)
        lung = (ex**2 + ey**2) <= 1.0
        roi[lung] = 1
        grad = np.clip(1.0 - np.sqrt(ex**2 + ey**2), 0.0, 1.0)
        img[lung] = 168.0 + 84.0 * grad[lung]
        img += lung * (16.0 * np.cos(8.0 * ex) * np.sin(8.0 * ey))

    # mediastinum + spine
    med = (np.abs(cx) < 0.040 * S) & (np.abs(cy) < 0.16 * S)
    roi[med] = 1
    med_val = 176.0 + 30.0 * np.cos(10.0 * cy)
    img[med] = med_val[med]
    spine = (np.sqrt((cx / (0.046 * S)) ** 2 + ((cy + 0.06 * S) / (0.23 * S)) ** 2) <= 1.0)
    roi[spine] = 1
    img[spine] = 188.0

    # ribs: bright arcs crossing both lung fields
    for k in range(-5, 6):
        a = 0.185 * S + 0.028 * S * abs(k)
        rib = np.abs(np.sqrt(cx**2 + (cy + 0.012 * S) ** 2) - a) < 0.0065 * S
        rib &= (cy < 0.012 * S) & (np.abs(cx) > 0.052 * S)
        roi[rib] = 1
        img[rib] = 200.0 + 22.0 * np.exp(-(k**2) / 8.0)

    # fine texture in the soft tissue and margin, so the embeddable area is not flat
    tex = rng.normal(0.0, 5.0, (h, w))
    small = np.clip(tex * 16 + 128, 0, 255).astype(np.uint8)
    tex = np.asarray(
        Image.fromarray(small, mode="L")
        .resize((w // 4, h // 4), Image.BICUBIC)
        .resize((w, h), Image.BICUBIC),
        dtype=np.float64,
    )
    img += (tex - 128.0) / 16.0
    img[roi.astype(bool)] += rng.normal(0.0, 2.0, int(roi.sum()))

    cover = np.clip(np.round(img), 0, 255).astype(np.uint8)
    return cover, roi


def roi_cut(n: int, s: int, q: int) -> int:
    """Smallest pixel value that is ROI: p > mean + 0.2*std, in exact integer arithmetic.

    mean = s/n, var = (n*q - s^2)/n^2, so  p > mean + 0.2*std  <=>  d := p*n - s > 0 and
    25*d^2 > D with D = n*q - s^2.  The rule is monotone in p, so the answer is one integer in
    0..256 (256: no pixel is ROI), found by binary search -- the PL core does the same
    search with the same integers (`roi_cut_core`, algorithm.md 3.2).
    """
    d_big = n * q - s * s

    def is_roi(p: int) -> bool:
        d = p * n - s
        return d > 0 and 25 * d * d > d_big

    lo, hi = 0, 256
    while lo < hi:
        mid = (lo + hi) >> 1
        if is_roi(mid):
            hi = mid
        else:
            lo = mid + 1
    return lo


def roi_from_image(img: np.ndarray, valid: np.ndarray | None = None) -> np.ndarray:
    """The ROI the algorithm actually uses: a deterministic function of the image.

    Identical to `sims/dicom_loader.load_dicom_or_create`'s rule, `img > mean + 0.2*std`,
    so the encoder and the decoder derive the same block lists from their own copies of
    the image with nothing stored in between.  Returns a uint8 mask.

    `valid` restricts the mean/std to pixels that actually came from the received image.
    A cropped copy is restored into a declared-size frame whose uncovered part is filled
    with 0 by the resampler; those pixels are not part of the picture, and letting them
    into the statistics moves the threshold and re-derives the whole ROI.  Measured on a
    40% corner crop: the plain rule put 0 usable blocks in every region, including the
    one quadrant that was untouched.
    """
    img = np.asarray(img)
    # Pixels at or below ROI_STATS_FLOOR count as 0 in the statistics.  The intake step
    # (`floor_background`) raises background pixels to BG_FLOOR; with this rule the floored image
    # and the original give the same mean and std, hence the same ROI, on both sides.
    stats = np.where(img <= ROI_STATS_FLOOR, 0, img)
    if valid is None:
        sample = stats
    else:
        sample = stats[np.asarray(valid, dtype=bool)]
        if sample.size == 0:
            sample = stats
    s64 = sample.astype(np.int64)
    n, ssum, qsum = int(s64.size), int(s64.sum()), int((s64 * s64).sum())
    out = (img >= roi_cut(n, ssum, qsum)).astype(np.uint8)
    if valid is not None:
        # Uncovered pixels are replicated border, not picture: they must never be
        # classified as ROI, or the taint disagrees with the encoder's and the
        # scan-based placement shifts whole regions.  Measured on a 5% symmetric
        # crop before this change: restored pixels max-diff 0.0, region BER 0.53.
        out = (out.astype(bool) & np.asarray(valid, dtype=bool)).astype(np.uint8)
    return out


# --------------------------------------------------------------------------- #
# Amplitude normalisation at intake -- the product answer for a clipped input.
# --------------------------------------------------------------------------- #

SAFE_LO, SAFE_HI = 16, 235


def floor_background(img: np.ndarray) -> np.ndarray:
    """Intake step: raise background pixels OUTSIDE the diagnostic region to >= BG_FLOOR.

    A medical slice is a bright anatomy on a black (0-valued) background, and a mark cannot
    survive on a clipped level (`CLIP_RULE`).  Raising only the background -- never a pixel of
    the region `roi_from_image` calls diagnostic -- removes the clip without touching the
    anatomy, and `ROI_STATS_FLOOR` makes the ROI of the floored image identical to the ROI of
    the original.  Measured on 256 x 256 brain MRI slices, 20-63% of whose pixels are 0.
    """
    img = np.asarray(img, dtype=np.uint8)
    roi = roi_from_image(img).astype(bool)
    out = img.copy()
    bg = ~roi
    out[bg] = np.maximum(out[bg], BG_FLOOR)
    return out


def normalise_amplitude(img: np.ndarray) -> np.ndarray:
    """Map an image's pixel range onto [SAFE_LO, SAFE_HI] with head-room at both
    clipping boundaries.

    A scan exported from a PACS, or a screenshot, often has large areas clipped at
    0 (black margin) or 255.  `mark` refuses such an input because the mark has no
    room to move in those regions (`clipped_blocks`).  Normalising at intake -- the
    gateway's job, never the app's -- puts the whole image inside a safe range so
    nothing is clipped anywhere and the mark has room to move.  Returns a uint8
    image of the same shape.

    This is the same transform as `run_real_image._normalise_safe_range`; it lives
    here so the gateway and the reference share one implementation.
    """
    c = np.asarray(img)
    if c.size == 0:
        return c.astype(np.uint8)
    lo, hi = float(c.min()), float(c.max())
    if hi <= lo:
        return np.full(c.shape, SAFE_LO, dtype=np.uint8)
    out = SAFE_LO + (c.astype(np.float64) - lo) * (SAFE_HI - SAFE_LO) / (hi - lo)
    return np.clip(np.round(out), 0, 255).astype(np.uint8)


# --------------------------------------------------------------------------- #
# the mask: which coefficients and blocks may be written at all
# --------------------------------------------------------------------------- #


def ll_support_roi(roi: np.ndarray) -> np.ndarray:
    """LL-resolution mask of every coefficient whose pixels can touch the ROI.

    One LL coefficient `(r, c)` of a 1-level 5/3 IWT reaches image rows `2r-1..2r+1`
    and columns `2c-1..2c+1`; that is verified empirically by `support_test`.  A
    coefficient is therefore blocked when any of those nine pixels is ROI, and writing
    a blocked coefficient provably cannot move a diagnostic pixel.
    """
    roi = np.asarray(roi, dtype=bool)
    h, w = roi.shape
    lh, lw = h // 2, w // 2
    m = np.zeros((lh, lw), dtype=bool)
    for dr in range(-ROI_SUPPORT_LL, ROI_SUPPORT_LL + 1):
        for dc in range(-ROI_SUPPORT_LL, ROI_SUPPORT_LL + 1):
            src_r = np.arange(lh) * 2 + dr
            keep_r = (src_r >= 0) & (src_r < h)
            src_c = np.arange(lw) * 2 + dc
            keep_c = (src_c >= 0) & (src_c < w)
            m[np.ix_(keep_r, keep_c)] |= roi[np.ix_(src_r[keep_r], src_c[keep_c])]
    return m


def blocks_for_payload(
    roi_blocks: np.ndarray, ll_shape: tuple[int, int], g: int = PILOT_INTERVAL_G
) -> list[tuple[int, int]]:
    """DEPRECATED-ish helper: eligible blocks in row-major order (kept for diagnostics).

    A block is eligible when it is outside the ROI mask **and** touches no grid line.
    `placement_map` does not use the *order* of this list, so a disagreement about one
    block cannot cascade; that is deliberate.
    """
    lh, lw = ll_shape
    nbh, nbw = roi_blocks.shape
    grid = _grid_ll(ll_shape, g)
    out = []
    for br in range(nbh):
        if roi_blocks[br].all():
            continue
        rows = np.arange(br * DCT_BLOCK, br * DCT_BLOCK + DCT_BLOCK)
        for bc in range(nbw):
            if roi_blocks[br, bc]:
                continue
            cols = np.arange(bc * DCT_BLOCK, bc * DCT_BLOCK + DCT_BLOCK)
            if grid[np.ix_(rows, cols)].any():
                continue
            out.append((int(rows[0]), int(cols[0])))
    return out


def _grid_ll(ll_shape: tuple[int, int], g: int = PILOT_INTERVAL_G) -> np.ndarray:
    """Boolean LL-resolution map of every coefficient a grid line touches."""
    lh, lw = ll_shape
    grid = np.zeros((lh, lw), dtype=bool)
    for r in range(0, max(0, lh - PILOT_WIDTH_B + 1), g):
        grid[r:r + PILOT_WIDTH_B, :] = True
    for c in range(0, max(0, lw - PILOT_WIDTH_B + 1), g):
        grid[:, c:c + PILOT_WIDTH_B] = True
    return grid


def region_of(r: int, c: int, ll_shape: tuple[int, int]) -> int:
    """Which of the R regions an LL block is in: 0=top-left 1=top-right 2=bottom-left 3=bottom-right."""
    lh, lw = ll_shape
    return (1 if r >= lh // 2 else 0) * 2 + (1 if c >= lw // 2 else 0)


@lru_cache(maxsize=64)
def block_universe(ll_shape: tuple[int, int], g: int = PILOT_INTERVAL_G) -> list[tuple[int, int]]:
    """Every payload-grid block in the LL band: **geometry only**, no image involved.

    With G = 16 LL coefficients and 8 LL coefficients per block, exactly half of all
    8x8-aligned blocks touch a grid line, so this list is half of the aligned blocks and
    is byte-identical on both sides for a given declared geometry.  The keyed
    assignment below is built on it, which is what stops an ROI disagreement from
    cascading: see `placement_map`.
    """
    lh, lw = ll_shape
    grid = _grid_ll(ll_shape, g) if PILOT_ENABLED else None
    out = []
    for br in range(lh // DCT_BLOCK):
        for bc in range(lw // DCT_BLOCK):
            rows = np.arange(br * DCT_BLOCK, br * DCT_BLOCK + DCT_BLOCK)
            cols = np.arange(bc * DCT_BLOCK, bc * DCT_BLOCK + DCT_BLOCK)
            if grid is not None and grid[np.ix_(rows, cols)].any():
                continue
            out.append((int(rows[0]), int(cols[0])))
    return out


def _dilate_ll(mask: np.ndarray, m: int) -> np.ndarray:
    """Binary dilation by `m` cells in each direction, no wraparound."""
    out = mask.copy()
    h, w = mask.shape
    for dr in range(-m, m + 1):
        for dc in range(-m, m + 1):
            if dr == 0 and dc == 0:
                continue
            r0, r1 = max(0, dr), min(h, h + dr)
            c0, c1 = max(0, dc), min(w, w + dc)
            shifted = np.zeros_like(mask)
            shifted[r0:r1, c0:c1] = mask[r0 - dr:r1 - dr, c0 - dc:c1 - dc]
            out |= shifted
    return out


def _dilate(mask: np.ndarray, m: int) -> np.ndarray:
    """Binary dilation by `m` cells in each direction, no wraparound."""
    return _dilate_ll(mask, m)


def roi_masks(ll_shape: tuple[int, int], img: np.ndarray,
              valid: np.ndarray | None = None) -> tuple[np.ndarray, np.ndarray]:
    """`(roi_blocks, roi_ll)` for an image at the declared geometry.

    `roi_ll` is the exact, full-resolution rule: every LL coefficient whose 3x3 pixel
    support touches a pixel of the thresholded ROI, dilated by `ROI_CLEARANCE_LL` more
    for head-room.  `roi_blocks` is the same thing folded onto payload blocks - a block
    is not writable if any of its coefficients is in `roi_ll`, which exactly covers the
    block's image-domain support (rows `16*br-1 .. 16*br+15`).

    Because `roi_ll` is derived from the full-resolution threshold, the ROI guarantee
    (a diagnostic pixel cannot move) is exact and measurable.  It is not perfectly
    stable: the encoder derives it from the cover and the decoder from the damaged
    copy, so a block on the ROI boundary can be classified differently by the two.  The
    scan-based placement in `placement_map` is what makes that cost a bit or two instead
    of the whole region.
    """
    lh, lw = ll_shape
    roi_full = np.asarray(roi_from_image(img, valid=valid), dtype=bool)
    roi_ll = ll_support_roi(roi_full)
    if ROI_CLEARANCE_LL > 0:
        roi_ll = _dilate_ll(roi_ll, ROI_CLEARANCE_LL)
    nbh, nbw = lh // DCT_BLOCK, lw // DCT_BLOCK
    roi_blocks = np.zeros((nbh, nbw), dtype=bool)
    for br in range(nbh):
        for bc in range(nbw):
            if roi_ll[br * DCT_BLOCK:(br + 1) * DCT_BLOCK,
                      bc * DCT_BLOCK:(bc + 1) * DCT_BLOCK].any():
                roi_blocks[br, bc] = True
    return roi_blocks, roi_ll


def clipped_blocks(ll_shape: tuple[int, int], img: np.ndarray) -> np.ndarray:
    """Block-resolution mask: 1 where a payload block touches a uint8 clipping level.

    The pixel support of one LL block is the same span `roi_masks` uses (rows
    `16*br-1 .. 16*br+15`), so this is the exact set of pixels a write into that block can
    reach.  `CLIP_RULE` explains why such a block cannot hold a mark; this is the encoder's
    and the decoder's shared rule for finding them, derived from each side's own copy of
    the image exactly like the ROI, so nothing has to be transmitted.

    Deliberately computed from the *pixels*, not the LL: clipping is stable under a
    re-encode or a downscale (a black region stays black), whereas an LL-domain test would
    drift with the codec.
    """
    lh, lw = ll_shape
    img = np.asarray(img)
    h, w = img.shape
    nbh, nbw = lh // DCT_BLOCK, lw // DCT_BLOCK
    out = np.zeros((nbh, nbw), dtype=bool)
    for br in range(nbh):
        r0 = max(0, 2 * br * DCT_BLOCK - 1)
        r1 = min(h, 2 * br * DCT_BLOCK + 2 * DCT_BLOCK)
        for bc in range(nbw):
            c0 = max(0, 2 * bc * DCT_BLOCK - 1)
            c1 = min(w, 2 * bc * DCT_BLOCK + 2 * DCT_BLOCK)
            sup = img[r0:r1, c0:c1]
            if sup.size == 0:
                out[br, bc] = True  # nothing to write into
                continue
            out[br, bc] = bool(sup.min() < CLIP_MARGIN or sup.max() > 255 - CLIP_MARGIN)
    return out


def blocked_blocks(
    ll_shape: tuple[int, int],
    img: np.ndarray,
    coverage: np.ndarray | None = None,
) -> np.ndarray:
    """Blocks a mark may not use: inside the ROI, or touching a clipping level.

    `universe` stays a function of the geometry alone, on purpose: the keyed permutation is indexed by
    keystream by `len(universe)`, so changing the universe between encoder and decoder would
    re-key every block and destroy the whole region.  Taint, not membership, is what the two
    sides are allowed to disagree about -- `placement_map` absorbs a disagreement as a bit or
    two.  This keeps that property and adds the clipping taint to it.

    With `coverage` this returns the *erasure* taint, not the placement taint: it also
    covers blocks whose pixels were cropped away (see `undercovered_blocks`).  The two
    must not be conflated -- a block that holds no mark is an erasure, but letting it into
    `placement_map` would shift which block carries which bit, and that desynchronises the
    whole region.  `placement_blocks` is the placement taint.
    """
    blocked = placement_blocks(ll_shape, img, valid=coverage)
    if coverage is not None:
        blocked = blocked | undercovered_blocks(ll_shape, np.asarray(coverage, dtype=bool))
    return blocked


def placement_blocks(ll_shape: tuple[int, int], img: np.ndarray,
                     valid: np.ndarray | None = None) -> np.ndarray:
    """The taint `placement_map` is allowed to see: ROI and clipping level only.

    The encoder and the decoder must agree on this or every bit after a tainted block
    moves; it is deliberately *not* widened by knowledge only the decoder has.  `valid`
    only narrows the pixel statistics the ROI is derived from, which is what makes the
    ROI stable when part of the frame is fill.
    """
    roi_blocks, _ = roi_masks(ll_shape, img, valid=valid)
    clip_src = img
    if valid is not None:
        # Uncovered pixels are fill (0 from the resampler), not picture, and 0 is a clipping
        # level: testing them taints every block the crop removed, which the encoder never
        # tainted, and shifts the placement of every copy.  Measured on a 25% corner crop
        # after the 2026-10-20 copy-major change: 13,187 disputed blocks, BER 0.24 in every
        # copy at the exact geometry.  A neutral fill can never read as clipped.
        clip_src = np.where(np.asarray(valid, dtype=bool), img, 128).astype(np.uint8)
    return np.asarray(roi_blocks, dtype=bool) | clipped_blocks(ll_shape, clip_src)


BLOCK_COVERAGE_MIN = 0.75  # fraction of a payload block's pixels that must exist


def undercovered_blocks(ll_shape: tuple[int, int], coverage: np.ndarray) -> np.ndarray:
    """Block-resolution mask: 1 where too much of the block's pixel support is missing.

    The payload block at `(br, bc)` owns 8x8 LL coefficients, i.e. 16x16 pixels at
    `(16*br, 16*bc)`.  If a quarter or more of that support was cropped away, the DCT
    mid-band of the block is dominated by the fill, so the block cannot be trusted to
    carry its bit -- and pretending otherwise is what made a 10% symmetric crop fail on
    pixels that were restored exactly.
    """
    nbh, nbw = ll_shape[0] // DCT_BLOCK, ll_shape[1] // DCT_BLOCK
    out = np.zeros((nbh, nbw), dtype=bool)
    cov = np.asarray(coverage, dtype=np.float64)
    step = DCT_BLOCK * 2
    for br in range(nbh):
        r0, r1 = br * step, min((br + 1) * step, cov.shape[0])
        for bc in range(nbw):
            c0, c1 = bc * step, min((bc + 1) * step, cov.shape[1])
            if r0 >= r1 or c0 >= c1 or float(cov[r0:r1, c0:c1].mean()) < BLOCK_COVERAGE_MIN:
                out[br, bc] = True
    return out


def region_capacities(
    universe: list[tuple[int, int]], blocked: np.ndarray, ll_shape: tuple[int, int]
) -> list[int]:
    """Writable blocks left for each copy, from one shared pool (copy-major placement).

    Copy c can be written when its entry is >= BLOCKS_PER_REGION.  `blocked` is the combined
    taint mask from `blocked_blocks` (ROI or clipping).
    """
    free = sum(1 for br, bc in universe if not blocked[br // DCT_BLOCK, bc // DCT_BLOCK])
    return [max(0, free - c * BLOCKS_PER_REGION) for c in range(N_REGIONS)]


# --- keyed placement: a Feistel permutation of the block indices (2026-10-22) ------------------
#
# Slot -> block is a keyed bijection on [0, m): a balanced Feistel network over the smallest even
# bit width 2h with 2^(2h) >= m, cycle-walked into range (Black & Rogaway), whose round function is
# the Ascon-AEAD128 tag (a standard PRF) of (domain, round, right half).  It replaces "sort every
# block by a keyed tag": that needs m 64-bit keys in memory and a sort, impossible in the PL for a
# 2048-px image (m ~ 37,000), while the permutation needs O(1) state and is evaluated only for the
# ~1,100 slots a mark actually visits.  Placement stays obfuscation of location, not encryption.

PLACEMENT_ROUNDS = 6
PLACEMENT_NONCE = bytes(16)


@lru_cache(maxsize=1 << 16)
def _feistel_f(key: bytes, rnd: int, right: int, hbits: int) -> int:
    ad = PLACEMENT_DOMAIN + bytes([rnd]) + right.to_bytes(4, "big")
    tag = ascon_aead_encrypt(key, PLACEMENT_NONCE, b"", ad)[-16:]
    return int.from_bytes(tag[:4], "big") & ((1 << hbits) - 1)


def feistel_half_bits(m: int) -> int:
    return max(1, ((m - 1).bit_length() + 1) // 2)


@lru_cache(maxsize=1 << 18)
def placement_permute(key: bytes, m: int, slot: int) -> int:
    """The block index (raster order of `block_universe`) that slot `slot` maps to."""
    h = feistel_half_bits(m)
    mask = (1 << h) - 1
    x = slot
    while True:
        left, right = x >> h, x & mask
        for r in range(PLACEMENT_ROUNDS):
            left, right = right, left ^ _feistel_f(key, r, right, h)
        x = (left << h) | right
        if x < m:
            return x


_PLACEMENT_CACHE_MAX = 2048


@lru_cache(maxsize=_PLACEMENT_CACHE_MAX)
def _placement_map_cached(key: bytes, ll_shape: tuple, region: int, n: int,
                          blocked_bytes: bytes, allow_erasures: bool) -> tuple:
    """`placement_map` is a pure function of (key, geometry, region, taint, n), so cache it.

    Measured on a 25% corner crop: 488 calls but only **79 distinct taint masks** -- the same
    mask recurs for every fine offset that leaves the ROI unchanged -- so the cache is hit 6x.
    """
    lh, lw = ll_shape
    blocked = np.frombuffer(blocked_bytes, dtype=bool).reshape(lh // DCT_BLOCK, lw // DCT_BLOCK)
    return tuple(_placement_map_impl(key, ll_shape, region, blocked, n, None, allow_erasures))


def placement_map(
    key: bytes,
    ll_shape: tuple[int, int],
    region: int,
    blocked: np.ndarray,
    n: int = BLOCKS_PER_REGION,
    universe: list[tuple[int, int]] | None = None,
    allow_erasures: bool = False,
) -> list[tuple[int, int] | None]:
    """P3/P4: which block in `region` carries codeword bit `i`, for i in 0..n-1.

    The blocks of the region are ordered by a keyed tag (an Ascon-CTR keystream over the
    block coordinates: obfuscation of location, not encryption), and each bit scans
    forward from its own evenly spread starting position for the first block that is
    neither ROI-blocked nor already used.

    Scanning from a per-bit start, rather than taking "the first n free blocks in keyed
    order", is deliberate: the encoder and the decoder each derive the ROI from their own
    copy of the image and can disagree by a borderline block or two.  With a ranked list,
    one disagreement shifts every later bit and destroys the region; with this scheme it
    costs the one or two bits whose scan crossed the disputed block, which the polar
    code and the other regions absorb.

    `allow_erasures` is for the **decoder only**: when the region cannot carry all `n`
    bits (a crop removed the area, a clipped margin ate the capacity) the missing bits are
    returned as `None` instead of raising.  The caller then reads them as zero LLRs, which
    is exactly "no information from this position", and the other regions -- which each
    carry the whole codeword -- decide.  The encoder never passes this flag: refusing to
    mark is the correct answer there, and it must stay loud.
    """
    if universe is not None and list(universe) != block_universe(tuple(ll_shape)):
        return _placement_map_impl(key, tuple(ll_shape), region, blocked, n, universe,
                                   allow_erasures)
    return list(_placement_map_cached(key, tuple(ll_shape), region, n,
                                      np.asarray(blocked, dtype=bool).tobytes(),
                                      bool(allow_erasures)))


def _placement_map_impl(
    key: bytes,
    ll_shape: tuple[int, int],
    region: int,
    blocked: np.ndarray,
    n: int = BLOCKS_PER_REGION,
    universe: list[tuple[int, int]] | None = None,
    allow_erasures: bool = False,
) -> list[tuple[int, int] | None]:
    """Which block carries codeword bit `i` of COPY `region` (2026-10-20 placement).

    One keyed order of every block in the LL band (an Ascon keystream over the block
    coordinates: obfuscation of location, not encryption) is shared by all copies.  Copies are
    placed copy-major: copy 0 first, then copy 1 among the blocks copy 0 left, and so on, so
    the positions of copy c depend only on copies 0..c-1 -- never on how many copies the
    encoder managed to write.  Inside a copy, bit i scans forward from its own evenly spread
    start for the first block that is neither tainted nor used; one disputed block between
    encoder and decoder therefore costs a bit or two, not the copy.  The copies interleave over
    the whole image, so a crop erases a fraction of every copy instead of one copy whole.

    Without `allow_erasures` (the encoder) a copy that cannot be completed raises
    `ValueError`; `mark` then writes the copies before it.  With it (the decoder) a missing
    position is returned as None and read as an erasure (LLR 0).
    """
    if universe is None:
        universe = block_universe(ll_shape)
    m = len(universe)
    used: set[int] = set()
    stride = max(1, m // max(n, 1))
    cstride = max(1, stride // N_REGIONS)
    out: list[tuple[int, int] | None] = []
    for c in range(region + 1):
        out = []
        for i in range(n):
            j = (i * stride + c * cstride) % m
            steps = 0
            while steps < m:
                br, bc = universe[placement_permute(key, m, j)]
                if j not in used and not blocked[br // DCT_BLOCK, bc // DCT_BLOCK]:
                    break
                j = (j + 1) % m        # wrap: a copy fails only when the whole pool is spent
                steps += 1
            if steps >= m:
                if allow_erasures:
                    out.append(None)
                    continue
                raise ValueError(f"copy {c}: ran out of blocks while placing bit {i}")
            used.add(j)
            out.append((br, bc))
    return out


def local_variance(ll: np.ndarray, r: int, c: int, win: int = QIM_STD_WINDOW) -> int:
    """The integer local variance around one block (the DSP48 variance core's arithmetic).

    `perceptual_mask.compute_dsp48_variance` is the variance core the RTL implements
    (floor-divided E[X^2] - E[X]^2); it is reused here rather than reimplemented.
    """
    lh, lw = ll.shape
    r0, r1 = max(0, r - win), min(lh, r + win + 1)
    c0, c1 = max(0, c - win), min(lw, c + win + 1)
    if r0 >= r1 or c0 >= c1:
        # The block coordinate is outside `ll` (placements from the *declared* geometry scored
        # against a smaller received LL band, i.e. every downscale candidate): no window, so
        # the step drops to its floor QIM_BASE_DELTA.
        return 0
    return int(perceptual_mask.compute_dsp48_variance(ll[r0:r1, c0:c1]))


def local_std(ll: np.ndarray, r: int, c: int, win: int = QIM_STD_WINDOW) -> int:
    """Integer square root of the local variance (what the step is computed from)."""
    return math.isqrt(local_variance(ll, r, c, win))


def qim_delta(std: int) -> int:
    """The QIM step, all integer: 64 + (5 * isqrt(var)) >> 3, forced even (delta/2 exact)."""
    d = QIM_BASE_DELTA + ((QIM_ALPHA_NUM * int(std)) >> QIM_ALPHA_SHIFT)
    return d + (d & 1)


# --------------------------------------------------------------------------- #
# The bit in one block: integer, sign of the 4x4 Hadamard projection
# --------------------------------------------------------------------------- #
#
#   v = sum(H * x)            H = outer([1,1,-1,-1],[1,1,-1,-1]),  sum(H^2) = 16
#   T = delta / 2             (delta from the local variance, as before)
#   bit 0  <=>  v >= +T        bit 1  <=>  v <= -T
#   embed: e = (+T - v) if bit 0 and v < T;  (-T - v) if bit 1 and v > -T;  else 0
#          e is capped at +/-SIGN_MAX_MOVE_T * T (a strong opposite host is left to the code);
#          x' = x + H * d,  d_k = floor(e/16) + (1 for the first (e mod 16) positions),
#          so v' = v + e exactly.
#   read:  bit = (v < 0), LLR = 2 * v / T clipped to +/-SIGN_LLR_CLIP (positive = bit 0).
#
# Why a sign and not a lattice (measured 2026-10-20): a resample attenuates the pattern -- a
# 0.5x downscale keeps 58% of v for this pattern, 21% for [1,-1,-1,1] -- and lattice QIM reads
# a scaled projection as the wrong lattice (BER 0.52 at 0.5x).  The sign survives any positive
# gain.  The host projection is small (median |v| = 3 on the phantom, 0 on floored MRI), so the
# embedding cost stays about T per block.  All integer: adders and a compare in the PL.

SIGN_MAX_MOVE_T = 4
SIGN_LLR_CLIP = 8.0


def block_projection(ll_block: np.ndarray) -> int:
    return int(np.sum(HADAMARD * np.asarray(ll_block, dtype=np.int64)))


def sign_threshold(delta: int) -> int:
    return int(delta) // 2


def read_block_llr(ll_block: np.ndarray, delta: int) -> tuple[int, float]:
    """Hard bit and soft LLR (positive = bit 0) of one 4x4 LL block."""
    v = block_projection(ll_block)
    t = sign_threshold(delta)
    llr = max(-SIGN_LLR_CLIP, min(SIGN_LLR_CLIP, 2.0 * v / t))
    return (1 if v < 0 else 0), llr


def block_confidence(ll_block: np.ndarray, delta: int) -> float:
    """min(|v| / T, 1): 1 on a cleanly written block, ~0 on an unwritten one."""
    return min(1.0, abs(block_projection(ll_block)) / sign_threshold(delta))


def embed_error(v: int, bit: int, delta: int) -> int:
    """The integer change e to the projection that writes `bit`."""
    t = sign_threshold(delta)
    cap = SIGN_MAX_MOVE_T * t
    if bit == 0:
        e = t - v if v < t else 0
    else:
        e = -t - v if v > -t else 0
    return max(-cap, min(cap, e))


_HFLAT = HADAMARD.reshape(-1)


def quantize_block(ll_block: np.ndarray, bit: int, delta: int) -> np.ndarray:
    """The integer LL block whose Hadamard projection carries `bit` (v' = v + e exactly)."""
    x = np.asarray(ll_block, dtype=np.int64)
    e = embed_error(block_projection(x), int(bit), int(delta))
    q, rem = divmod(e, 16)            # floor division: q*16 + rem == e, 0 <= rem < 16
    d = np.full(16, q, dtype=np.int64)
    d[:rem] += 1
    return x + (_HFLAT * d).reshape(DCT_BLOCK, DCT_BLOCK)


# --------------------------------------------------------------------------- #
# reading the regions back
# --------------------------------------------------------------------------- #


@dataclass
class RegionRead:
    region: int
    blocks: list[tuple[int, int]]
    bits: np.ndarray
    llrs: np.ndarray
    deltas: np.ndarray
    blocks_available: int = 0
    bit_errors_vs: np.ndarray | None = None  # positions where a known codeword disagrees
    ber: float | None = None
    n_erased: int = 0  # codeword bits this region had no block for (LLR 0, no information)


def read_regions(
    img: np.ndarray,
    key: bytes,
    codeword: np.ndarray | None = None,
    placements: list[list[tuple[int, int]]] | None = None,
    coverage: np.ndarray | None = None,
) -> tuple[list[RegionRead], np.ndarray]:
    """Read all R regions of an image at the declared geometry.

    Returns `(regions, ll)`; `ll` is the LL band the blocks came from, which the caller
    needs for the pilot measurement.  `codeword`, if given, only reports the per-region
    hard BER before decoding.  `placements` can be passed in when the caller already
    knows the block maps (embedding always does).

    A region that cannot place all 256 bits -- the usual cause is a crop, which removes
    the area the region's blocks live in -- yields **erasures**, not an exception: the
    missing positions get LLR 0.0, which says "no information here", and the other regions
    carry the full codeword.  Before this, one starved region aborted the whole read and a
    10% corner crop was unrecoverable even though three regions were intact.
    """
    img = np.asarray(img, dtype=np.uint8)
    assert img.shape[0] % 2 == 0 and img.shape[1] % 2 == 0, "even dimensions needed"
    ll, _ = iwt2d_53(img.astype(np.int32))
    # Two different masks, on purpose:
    #   * `place_taint` decides *which block carries which bit*. It must match the encoder's,
    #     so it is the ROI (statistics from covered pixels only) plus the clipping rule --
    #     never the coverage mask, because the encoder had no such mask. Letting coverage in
    #     here shifts every later bit and desynchronises the region: measured on a 5%
    #     symmetric crop, half of every region read wrong while the pixels were exact.
    #   * `erase_taint` decides which blocks the decoder *distrusts*. A block whose pixels
    #     were cropped away holds no mark at all, so its LLR is set to 0.0 (an erasure)
    #     instead of being read as a confident wrong bit.
    place_taint = placement_blocks(ll.shape, img, valid=coverage)
    universe = block_universe(ll.shape)
    erase_taint = place_taint
    if coverage is not None:
        erase_taint = erase_taint | undercovered_blocks(
            ll.shape, np.asarray(coverage, dtype=bool))
    if placements is None:
        placements = [
            placement_map(key, ll.shape, r, place_taint, BLOCKS_PER_REGION, universe,
                          allow_erasures=True)
            for r in range(N_REGIONS)
        ]
    available = region_capacities(universe, place_taint, ll.shape)
    out: list[RegionRead] = []
    for r in range(N_REGIONS):
        order = placements[r]
        bits = np.zeros(BLOCKS_PER_REGION, dtype=np.uint8)
        llrs = np.zeros(BLOCKS_PER_REGION, dtype=np.float64)
        deltas = np.zeros(BLOCKS_PER_REGION, dtype=np.float64)
        erased = 0
        read_mask = np.zeros(BLOCKS_PER_REGION, dtype=bool)
        for i, pos in enumerate(order):
            if pos is None:
                erased += 1
                continue  # LLR stays 0.0: an erasure, not a guess
            br, bc = pos
            if erase_taint[br // DCT_BLOCK, bc // DCT_BLOCK]:
                erased += 1
                continue  # the block exists but carries no mark: no information
            d = qim_delta(local_std(ll, br, bc))
            b, l = read_block_llr(ll[br:br + DCT_BLOCK, bc:bc + DCT_BLOCK], d)
            bits[i] = b
            llrs[i] = l
            deltas[i] = d
            read_mask[i] = True
        rr = RegionRead(r, order, bits, llrs, deltas, available[r], n_erased=erased)
        if codeword is not None:
            # BER over the bits that were actually read; an erasure is not a bit error and
            # must not be reported as one (with no erasures this is the old number exactly).
            n_read = int(read_mask.sum())
            err = np.nonzero((bits != np.asarray(codeword, dtype=np.uint8)) & read_mask)[0]
            rr.bit_errors_vs = err
            rr.ber = float(err.size) / max(1, n_read)
        out.append(rr)
    return out, ll


# --------------------------------------------------------------------------- #
# embedding
# --------------------------------------------------------------------------- #


def mark(
    cover: np.ndarray,
    drawn_roi: np.ndarray,
    block: np.ndarray,
    key: bytes = HUB_KEY,
) -> tuple[np.ndarray, dict]:
    """Mark `cover` with the 128-bit `block`.  Returns `(marked, info)`.

    `drawn_roi` is only reported against (the phantom's ground-truth diagnostic
    region); the algorithm's own ROI comes from `roi_from_image`.
    """
    cover = np.asarray(cover, dtype=np.uint8)
    h, w = cover.shape
    assert h % 2 == 0 and w % 2 == 0, "the 5/3 IWT needs even dimensions"

    ll, subbands = iwt2d_53(cover.astype(np.int32))
    ll_shape = tuple(ll.shape)

    # --- the mask ---------------------------------------------------------
    roi_blocks, roi_ll = roi_masks(ll_shape, cover)
    clip = clipped_blocks(ll_shape, cover)
    blocked = np.asarray(roi_blocks, dtype=bool) | clip
    universe = block_universe(ll_shape)
    available = region_capacities(universe, blocked, ll_shape)
    if available[0] < BLOCKS_PER_REGION:
        # Say which taint is responsible: a capacity failure caused by clipping is a
        # statement about the image (floor the background at intake), while one caused by
        # the ROI is a statement about how much diagnostic area the frame has.
        clip_only = region_capacities(universe, clip, ll_shape)
        roi_only = region_capacities(universe, np.asarray(roi_blocks, dtype=bool), ll_shape)
        raise ValueError(
            f"cannot place one copy of {BLOCKS_PER_REGION} blocks: "
            f"available {available[0]}; ignoring the ROI taint {clip_only[0]}, ignoring the "
            f"clipping taint {roi_only[0]}.  If the clipping count is the low one, the "
            "image's non-diagnostic area sits on a uint8 clipping level (a clipped black "
            "margin is the common case) and the fix is `floor_background` at intake, not a "
            "change to the transform.  Otherwise the frame is too small for its ROI.  "
            "CLIP_RULE records the measurement."
        )

    # --- P2: the codeword ------------------------------------------------
    bits = np.asarray(block, dtype=np.uint8)
    assert bits.size == TOTAL_BITS
    codeword = polar_codec.polar_encode(bits)

    # --- P3 + P4: placement and QIM (no pilot grid: algorithm.md 3.2) -----
    # Copies are written copy-major until one cannot be completed; copy c's positions depend
    # only on copies < c, so the decoder can read any prefix of copies without knowing how
    # many the encoder wrote.  The step is computed from the *cover* LL band.
    out = ll.astype(np.int64).copy()
    placements: list[list[tuple[int, int]]] = []
    for r in range(N_REGIONS):
        try:
            order = placement_map(key, ll_shape, r, blocked, BLOCKS_PER_REGION, universe)
        except ValueError:
            break
        placements.append(order)
        for i, (br, bc) in enumerate(order):
            delta = qim_delta(local_std(ll, br, bc))
            out[br:br + DCT_BLOCK, bc:bc + DCT_BLOCK] = quantize_block(
                ll[br:br + DCT_BLOCK, bc:bc + DCT_BLOCK], int(codeword[i]), delta)

    recon = iiwt2d_53(out.astype(np.int32), subbands)
    n_clipped_px = int(np.sum((recon < 0) | (recon > 255)))
    marked = np.clip(recon, 0, 255).astype(np.uint8)

    # --- what the marking actually touched -------------------------------
    diff = np.abs(marked.astype(np.int32) - cover.astype(np.int32))
    drawn = np.asarray(drawn_roi, dtype=bool)
    alg_roi = np.asarray(roi_from_image(cover), dtype=bool)
    # the exact rule, computed at full resolution: no written coefficient may have a
    # pixel support that touches the ROI.  This is a self-check on the block-resolution
    # rule above, which is the coarser of the two.
    support = ll_support_roi(alg_roi)
    written = np.zeros(ll_shape, dtype=bool)
    for order in placements:
        for br, bc in order:
            written[br:br + DCT_BLOCK, bc:bc + DCT_BLOCK] = True
    info = {
        "max_abs_change_inside_drawn_roi": int(diff[drawn].max()) if drawn.any() else 0,
        "max_abs_change_inside_algorithm_roi": int(diff[alg_roi].max()) if alg_roi.any() else 0,
        "max_abs_change_outside_roi": int(diff[~alg_roi].max()) if (~alg_roi).any() else 0,
        "mean_abs_change_outside_roi": float(diff[~alg_roi].mean()) if (~alg_roi).any() else 0.0,
        "support_rule_violations": int((written & support).sum()),
        "blocks_available_per_region": available,
        "blocks_blocked_by_clipping_per_region": region_capacities(universe, clip, ll_shape),
        "clipping_rule": CLIP_RULE,
        "blocks_used_per_region": BLOCKS_PER_REGION,
        "copies_written": len(placements),
        "pixels_clipped_after_inverse": n_clipped_px,
        "pilot_lines_applied": 0,
        "ll_shape": [int(ll_shape[0]), int(ll_shape[1])],
        "placements": placements,
        "codeword": codeword,
        "drawn_vs_algorithm_roi_jaccard": float(
            (drawn & alg_roi).sum() / max(1, (drawn | alg_roi).sum())
        ),
    }

    # --- self-check: the marked export verifies with the same key --------
    regions, _ = read_regions(marked, key, codeword)
    # combine only the copies that were written: an unwritten copy reads unmarked blocks
    combined = sum((r.llrs for r in regions[:len(placements)]), np.zeros(BLOCKS_PER_REGION))
    dec, _ = polar_codec.polar_scl_decode(combined)
    info["round_trip_tag_ok"] = bool(verify_block(dec, key)["tag_ok"])
    info["round_trip_region_ber"] = [r.ber for r in regions]
    info["llr_confidence"] = float(
        np.mean([np.mean(np.abs(r.llrs)) for r in regions])
    )
    return marked, info


# --------------------------------------------------------------------------- #
# the pixel-support claim, checked rather than asserted
# --------------------------------------------------------------------------- #


def support_test() -> dict:
    """Perturb one LL coefficient and report which pixels moved."""
    rng = np.random.default_rng(0)
    img = rng.integers(0, 256, (8, 8), dtype=np.int32)
    ll, sub = iwt2d_53(img)
    r, c = 1, 1
    pert = ll.copy()
    pert[r, c] += 7
    after = iiwt2d_53(pert, sub)
    moved = np.argwhere(np.abs(after.astype(int) - img.astype(int)) > 0)
    return {
        "ll_coordinate": [int(r), int(c)],
        "pixels_touched": moved.tolist(),
        "rows": sorted({int(t[0]) for t in moved}),
        "cols": sorted({int(t[1]) for t in moved}),
        "expected_rows": [2 * r - 1, 2 * r, 2 * r + 1],
        "expected_cols": [2 * c - 1, 2 * c, 2 * c + 1],
    }


def clipping_test() -> dict:
    """The clipped-input precondition (`docs/algorithm.md` 3.1), as a permanent check.

    A cover whose non-diagnostic area sits on a uint8 clipping level cannot hold the mark: the
    reconstruction clips the write away and the first codec turns the block into a constant, so
    every such block reads back the same bit.  The earlier revision accepted such a cover and
    emitted a tag that failed every re-encode at a hard BER of ~0.53 in all four regions
    (`results/g1_real_image_2026-10-19.md`).  `mark` must now refuse it and name clipping as the
    cause.  The phantom itself must stay clip-free, or every phantom measurement would change.
    """
    cover, roi = make_cover()
    ll_shape = (cover.shape[0] // 2, cover.shape[1] // 2)
    on_phantom = int(clipped_blocks(ll_shape, cover).sum())
    roi_only = np.asarray(roi_masks(ll_shape, cover)[0], dtype=bool)
    # A few phantom blocks do sit on a clip, but they are all already ROI-tainted -- which is
    # exactly why the clipping taint cannot change any phantom measurement.
    assert np.array_equal(blocked_blocks(ll_shape, cover), roi_only), (
        f"the clipping taint must add nothing on the phantom ({on_phantom} clipped blocks, "
        "all of which must be ROI-tainted)")

    # Push the non-ROI area onto the 0 clip and drop the black level everywhere else too.
    flat = np.where(roi, cover, np.maximum(0, cover.astype(np.int32) - 22)).astype(np.uint8)
    flat[flat < 8] = 0
    on_flat = int(clipped_blocks(ll_shape, flat).sum())
    out = {"phantom_clipped_blocks": on_phantom, "clipped_cover_clipped_blocks": on_flat}
    assert on_flat > 0, "the clipped cover must actually contain clipped blocks"

    block = build_block(HUB_KEY, CURRENT_VERSION, DEMO_HUB_ID, 0x1234567812345678)
    try:
        mark(flat, roi, block)
    except ValueError as exc:
        out["mark_refused"] = True
        out["refused_names_clipping"] = "clipping" in str(exc)
    else:
        out["mark_refused"] = False
        out["refused_names_clipping"] = False
    assert out["mark_refused"], "mark must refuse an input it cannot mark survivably"
    assert out["refused_names_clipping"], "the refusal must name clipping as a cause"
    return out


if __name__ == "__main__":
    print(json.dumps(clipping_test(), indent=2))
    print(json.dumps(support_test(), indent=2))
    cover, roi = make_cover()
    alg_roi = roi_from_image(cover)
    print(f"cover {cover.shape}, drawn ROI {int(roi.sum())} px, "
          f"algorithm ROI {int(alg_roi.sum())} px, "
          f"jaccard {float((roi & alg_roi).sum() / max(1, (roi | alg_roi).sum())):.4f}")
    block = build_block(HUB_KEY, 1, DEMO_HUB_ID, 0x1234567812345678)
    marked, info = mark(cover, roi, block)
    os.makedirs(_HERE + "/demo_out", exist_ok=True)
    Image.fromarray(marked).save(_HERE + "/demo_out/marked_selftest.png")
    print(f"blocks per region available: {info['blocks_available_per_region']} "
          f"(need {BLOCKS_PER_REGION})")
    print(f"max |change| drawn ROI {info['max_abs_change_inside_drawn_roi']}, "
          f"algorithm ROI {info['max_abs_change_inside_algorithm_roi']}, "
          f"outside ROI {info['max_abs_change_outside_roi']}")
    print(f"pixel-support rule violations: {info['support_rule_violations']} "
          f"(must be 0 for the ROI guarantee to hold at full resolution)")
    print(f"round trip tag ok: {info['round_trip_tag_ok']}, "
          f"region BER {[round(b, 4) for b in info['round_trip_region_ber']]}")
