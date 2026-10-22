"""Recovery: undoing the geometry the attack applied, then reading the tag back.

`docs/algorithm.md` stage 4: *estimate the scale from the pilot grid, undo it, then read
the regions, soft-combine the log-likelihoods, polar SCL decode, and verify.*

    received image
      -> 5/3 IWT, LL band                       [sims/iwt_lifting.py]
      -> measure the pilot grid on the LL band   [pilot_grid.py]
      -> turn (period, phase) into a scale and an offset
      -> resample the image back onto the declared export geometry
      -> read the R regions, soft-combine LLRs   [embed.py]
      -> polar SCL decode, N=256 K=128           [sims/polar_codec.py]
      -> verify the 48-bit tag                   [tag_block.py]

Two things worth knowing before reading the code
-----------------------------------------------

**How the offset is found.** The pilot grid is periodic, so it can never say *where* in
the image it is - a shift of one grid interval is another equally good grid. What it does
say is the scale to a fraction of a percent, and the *shape* of the received image then
gives the offset: a receiver that is shorter than the declared geometry times the scale
must have been cropped, and by exactly that much. The phase measurement is used as a
consistency check on the candidates, not as the primary offset estimate. The identity
candidate is always tried first, so an undamaged copy is restored exactly rather than
being resampled.

**How candidates are ranked.** Each candidate offset is scored cheaply by interpolating
the already-measured LL band (a bilinear sample, no new wavelet transform) and reading
the QIM confidence of a few dozen blocks; the best few then go through the exact path
(resample the image, 5/3 IWT, read all four regions, polar decode) and the 48-bit tag
decides which one is accepted. The cheap ranking is an approximation - a wavelet
transform does not commute exactly with a resample - and is never used for the verdict.

Nothing here is a claim about real platforms. See `README.md`.
"""
from __future__ import annotations

# Make the sibling modules and the shared sims importable from any directory.
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
_SIMS = os.path.abspath(os.path.join(_HERE, "..", "stego_research", "sims"))
if _SIMS not in sys.path:
    sys.path.insert(0, _SIMS)

from dataclasses import dataclass, field

import numpy as np

import embed
import polar_codec
import tag_block
from iwt_lifting import iwt2d_53
from pilot_grid import (  # noqa: F401  (PILOT_INTERVAL_G is re-exported for callers)
    PILOT_INTERVAL_G,
    SCALE_MAX,
    SCALE_MIN,
    measure_grid,
    resample_affine,
)
from tag_block import TOTAL_BITS, verify_block

# --------------------------------------------------------------------------- #
# tuning constants (sweep these)
# --------------------------------------------------------------------------- #

SCALE_SNAP_TOL = 0.03  # a measured period within this of the nominal one means "scale 1"
MIN_PERIOD_LL = 6.0   # below this the grid cannot be resolved; refuse to trust it
MAX_EXACT_CANDIDATES = 5  # coarse candidates that get the full resample+IWT+decode.
# The cheap approximate score misranks after a resample, so the true geometry can
# sit 4th or 5th; the 48-bit tag (not the score) decides, so trying two more is
# safe and costs seconds.
SCORE_SAMPLE_BLOCKS = 64  # block positions sampled per region when scoring
RESIDUAL_MIN_LL = 4.0  # a shape residual below this is measurement noise, not a crop
# A pure resize changes both axes by the same factor, so agreement between the two
# dimension ratios is evidence for "rescaled, not cropped" that uses no pilot number.
# Needed because the pilot can mis-lock by a harmonic (measured: period 24.9 instead of
# 12.5 in the 2048->1600 downscale, i.e. 2x, on a real scan), and gating the only
# pilot-free candidate on a pilot number makes one bad estimate fatal.
AXIS_AGREE_TOL = 0.01  # relative: |s_y - s_x| <= tol * max(s_y, s_x)
OFFSET_PHASE_K = 2  # grid intervals either side of the measured phase to consider
# sub-sample offsets to scan, in LL coefficients.  The pilot grid is only accurate to
# about +/-1 LL coefficient - enough to pick the right grid interval, not enough to align
# the payload blocks, whose tolerance is about +/-0.3 LL (0.6 px).  Different resamplers
# (Pillow, chat apps) also have different sub-pixel phase conventions, so the scan covers
# +/-1.0 LL: the approximate score prunes (except on priority candidates, which scan it
# whole), the exact decode decides.
FINE_STEP = 0.25
FINE_RANGE = 1.0
FINE_OFFSETS = tuple(
    round(v * FINE_STEP, 2)
    for v in range(int(-FINE_RANGE / FINE_STEP), int(FINE_RANGE / FINE_STEP) + 1)
)
FINE_EXACT_TOP = 3  # fine offsets per coarse candidate verified by exact decode+tag
# A priority candidate (identity, dimension-ratio rescale, crop) cannot be trusted to the cheap
# score -- after a resample that score is worse than chance on the downscale side, because a
# wrong lattice makes all four regions collapse to the same wrong bits.  So a priority candidate
# gets the fine scan ordered by distance from the expected sub-pixel offset (FINE_PRIOR).  The
# 48-bit tag still decides every attempt, so trying more cannot cause a false accept.
#
# The full 9x9 = 81 scan is what makes a recovery 95-200 s.  The measured true offsets are always
# within a 5x5 neighbourhood of FINE_PRIOR (the crop true offset is 0.00/0.00, the rescale one is
# -0.25/-0.25, and both are within +/-0.5 LL), so the scan is capped at FINE_PRIORITY_CAP
# offsets.  A candidate that does not verify inside that neighbourhood is abandoned rather than
# scanned to the end: this is the safety/perf trade-off and it is applied ONLY to priority
# candidates, which are the ones that actually carry the answer.  Non-priority candidates keep
# FINE_EXACT_TOP = 3 (they are decoys and the cheap score ranks them).
FINE_PRIORITY_CAP = 25  # 5x5 neighbourhood around FINE_PRIOR for priority candidates
FINE_PRIOR = (-0.25, -0.25)  # expected resampler sub-pixel offset, in LL coefficients

# --------------------------------------------------------------------------- #
# candidate geometry
# --------------------------------------------------------------------------- #


@dataclass
class Candidate:
    label: str
    scale_y: float  # declared row / received row
    beta_y: float   # declared row 0 comes from received row (scale*0 + beta)
    scale_x: float
    beta_x: float
    score: float = 0.0
    exact: bool = False
    accepted: bool = False
    priority: bool = False  # always given the exact path, whatever the cheap score says
    detail: dict = field(default_factory=dict)

    @property
    def is_identity(self) -> bool:
        return (
            abs(self.scale_y - 1.0) < 1e-12 and abs(self.scale_x - 1.0) < 1e-12
            and abs(self.beta_y) < 1e-12 and abs(self.beta_x) < 1e-12
        )


def snapped_scale(period: float) -> float:
    """The measured period, snapped to 1.0 when it is within tolerance of G.

    A declared-geometry export has no business being resampled back onto itself because
    the measurement came out 16.05 instead of 16.00; that would blur a clean copy for
    nothing. Anything further away than the tolerance is a real resize and is corrected.
    """
    s = period / PILOT_INTERVAL_G
    if abs(s - 1.0) <= SCALE_SNAP_TOL:
        return 1.0
    return s


def offset_candidates(
    n_decl_ll: int, n_recv_ll: int, scale: float, period: float, phase: float
) -> list[float]:
    """Offsets (in LL coefficients) to try on one axis.

    `residual = n_recv - n_decl * scale` is how much shorter or longer the received axis
    is than a pure rescale, i.e. how much was cropped off the top/left.  It is only used
    when it is big enough to be a real crop rather than scale-measurement noise.  The
    other candidates are the measured phase plus whole grid intervals, because the pilot
    is periodic: a shift by one interval is an equally good grid, and the phase can only
    tell us the remainder.  Zero is always in the list, so an undamaged or purely
    rescaled copy restores untouched.
    """
    cands = [0.0]
    residual = n_recv_ll - n_decl_ll * scale
    if abs(residual) >= RESIDUAL_MIN_LL:
        for b in (residual, 0.5 * residual, -residual, -0.5 * residual):
            cands.append(b)
    for k in range(-OFFSET_PHASE_K, OFFSET_PHASE_K + 1):
        cands.append(phase + k * period)
        if abs(residual) >= RESIDUAL_MIN_LL:
            for base in (residual, 0.5 * residual, -residual, -0.5 * residual):
                cands.append(base + k * period)
    out: list[float] = []
    for b in cands:
        if all(abs(b - o) > 0.5 for o in out):
            out.append(b)
    # the identity first, then everything else by distance from zero
    out.sort(key=lambda b: (abs(b) > 1e-9, abs(b)))
    return out


def candidate_maps(est, declared_shape: tuple[int, int], recv_shape: tuple[int, int]):
    """Every (scale, offset) pair to try, identity first, ranked by phase error.

    The two axes are combined only after each axis has been ranked, so the number of
    combinations stays small (a few per axis, not a full cross product).
    """
    decl_ll = (declared_shape[0] // 2, declared_shape[1] // 2)
    recv_ll = (recv_shape[0] // 2, recv_shape[1] // 2)
    if embed.PILOT_ENABLED:
        s_y = snapped_scale(est.rows.period)
        s_x = snapped_scale(est.cols.period)
    else:
        # No pilot grid (algorithm.md 3.2): the scale comes from the image sizes only.  The crop
        # residual is taken at scale 1 (a pure crop); the size-ratio candidate covers a pure
        # resize.  A crop followed by a resize has no anchor and is a documented limitation.
        s_y = s_x = 1.0

    def rank(axis) -> list[tuple[float, float]]:
        n_d = decl_ll[0] if axis == "rows" else decl_ll[1]
        n_r = recv_ll[0] if axis == "rows" else recv_ll[1]
        a = est.rows if axis == "rows" else est.cols
        s = s_y if axis == "rows" else s_x
        residual = n_r - n_d * s  # how much this axis was cropped, in LL coefficients
        scored = []
        for b in offset_candidates(n_d, n_r, s, a.period, a.phase):
            # distance from this offset to the measured phase, modulo one period
            d = (b - a.phase) % a.period
            d = min(d, a.period - d)
            scored.append((d, abs(b - residual), b))
        scored.sort()
        return [(d, b) for d, _, b in scored[:4]]

    rows = rank("rows") if embed.PILOT_ENABLED else []
    cols = rank("cols") if embed.PILOT_ENABLED else []
    out = [Candidate("identity", 1.0, 0.0, 1.0, 0.0, priority=True)]
    # A pure rescale into the declared geometry fixes the scale exactly: it is
    # recv_size / declared_size, with no pilot needed.  This matters because the pilot
    # period carries a ~0.2% bias (pilot grid + 5/3 IWT), which at 0.5x sits far outside
    # the QIM block tolerance, while the dimension ratio is exact.  Two independent
    # signals say the change was a rescale rather than a crop: the pilot residual, and
    # the two dimension ratios agreeing with each other (a crop does not scale both axes
    # by one factor).  Either is enough, because the pilot mis-locks by a harmonic on
    # real scans and must not be able to delete this candidate -- the 48-bit tag is the
    # verdict, so an extra wrong candidate costs seconds, a missing right one loses the
    # image.
    s_dim_y = recv_shape[0] / declared_shape[0]
    s_dim_x = recv_shape[1] / declared_shape[1]
    res_y = recv_ll[0] - decl_ll[0] * s_y
    res_x = recv_ll[1] - decl_ll[1] * s_x
    no_crop = abs(res_y) < RESIDUAL_MIN_LL and abs(res_x) < RESIDUAL_MIN_LL
    axes_agree = (
        abs(s_dim_y - s_dim_x) <= AXIS_AGREE_TOL * max(s_dim_y, s_dim_x)
    )
    resized = (
        abs(s_dim_y - 1.0) > SCALE_SNAP_TOL or abs(s_dim_x - 1.0) > SCALE_SNAP_TOL
    )
    if (
        resized
        and (no_crop or axes_agree)
        and SCALE_MIN <= s_dim_y <= SCALE_MAX
        and SCALE_MIN <= s_dim_x <= SCALE_MAX
    ):
        out.append(
            Candidate(
                label=f"rescale recv/decl {s_dim_y:.4f}/{s_dim_x:.4f}",
                scale_y=s_dim_y,
                beta_y=0.0,
                scale_x=s_dim_x,
                beta_x=0.0,
                priority=True,
            )
        )
    # A crop leaves the same signature the rescale does, one step later: the size shrinks
    # while the scale does not, so the *residual* `recv_ll - decl_ll*scale` is exactly how
    # far the surviving content moved in the declared frame.  The pilot supplied the scale
    # and the shape supplied the residual, so this pair is exact for a pure crop -- and it
    # must be a priority candidate, because the pilot-phase candidates below are equally
    # good grids shifted by whole periods and they outrank it on the cheap score.  That
    # ranking is what kept a 5% crop unrecoverable even though the geometry was known.
    #
    # The residual is the *total* size loss, so it is the content shift only when all of the
    # loss is on one side (a corner crop).  A symmetric crop loses half on each side, so the
    # content moved by half the residual -- measured: 5% and 10% symmetric crops restored to
    # within 0.0 of the original and still failed, because only `residual` was offered and
    # the true shift was `residual/2`.  Both cases are kept: the tag decides.
    if not no_crop and (SCALE_MIN <= s_y <= SCALE_MAX) and (SCALE_MIN <= s_x <= SCALE_MAX):
        for frac, why in ((1.0, "corner"), (0.5, "symmetric")):
            out.append(
                Candidate(
                    label=(f"residual crop {frac:.1f}x {res_y * frac:+.1f}/"
                           f"{res_x * frac:+.1f} LL ({why})"),
                    scale_y=s_y,
                    beta_y=res_y * frac,
                    scale_x=s_x,
                    beta_x=res_x * frac,
                    priority=True,
                )
            )
    for _py, by in rows:
        for _px, bx in cols:
            if abs(by) < 1e-9 and abs(bx) < 1e-9:
                continue
            out.append(
                Candidate(
                    label=f"scale {s_y:.3f}/{s_x:.3f} offset {by:.1f}/{bx:.1f} LL",
                    scale_y=s_y, beta_y=by, scale_x=s_x, beta_x=bx,
                )
            )
    out[1:] = sorted(out[1:], key=lambda c: (c.beta_y**2 + c.beta_x**2))
    # remember the phase agreement for the report
    for c in out:
        c.detail["phase_error_ll"] = [
            (c.beta_y - est.rows.phase) % est.rows.period,
            (c.beta_x - est.cols.phase) % est.cols.period,
        ]
    return out


# --------------------------------------------------------------------------- #
# cheap ranking: interpolate the LL band, no new wavelet transform
# --------------------------------------------------------------------------- #


def approximate_ll(ll_recv: np.ndarray, cand: Candidate, decl_ll_shape) -> np.ndarray:
    """The LL band the declared geometry should have, from the received one.

    Bilinear sample at `(scale_y * i + beta_y, scale_x * j + beta_x)` with the border
    repeated, which mirrors what `pilot_grid.resample_affine` does in the pixel domain.
    Approximate on purpose: the 5/3 transform does not commute exactly with a resample,
    and this is only used to rank candidates.  (Bilinear in plain numpy: the only
    external deps of this reference are numpy and Pillow.)
    """
    if cand.is_identity or (
        abs(cand.scale_y - 1.0) < 1e-12 and abs(cand.scale_x - 1.0) < 1e-12
        and ll_recv.shape == tuple(decl_ll_shape)
    ):
        return np.asarray(ll_recv, dtype=np.float64)
    src = np.asarray(ll_recv, dtype=np.float64)
    ih, iw = src.shape
    ys = cand.scale_y * np.arange(decl_ll_shape[0], dtype=np.float64) + cand.beta_y
    xs = cand.scale_x * np.arange(decl_ll_shape[1], dtype=np.float64) + cand.beta_x
    ys = np.clip(ys, 0, ih - 1)
    xs = np.clip(xs, 0, iw - 1)
    y0 = np.floor(ys).astype(np.int64)
    x0 = np.floor(xs).astype(np.int64)
    y1 = np.minimum(y0 + 1, ih - 1)
    x1 = np.minimum(x0 + 1, iw - 1)
    fy = (ys - y0)[:, None]
    fx = (xs - x0)[None, :]
    top = src[np.ix_(y0, x0)] * (1 - fx) + src[np.ix_(y0, x1)] * fx
    bot = src[np.ix_(y1, x0)] * (1 - fx) + src[np.ix_(y1, x1)] * fx
    return top * (1 - fy) + bot * fy


# --------------------------------------------------------------------------- #
# scoring during the search: all R regions carry the SAME codeword
# --------------------------------------------------------------------------- #


def copy_confidence(
    ll: np.ndarray,
    placement: list[tuple[int, int] | None],
    n_pos: int = SCORE_SAMPLE_BLOCKS,
) -> float:
    """Mean QIM confidence of one copy at sampled positions, in [0, 1]; needs no codeword.

    For each sampled block, min(|v| / T, 1): a block read at the right geometry carries
    |v| >= T (confidence 1 before damage); a misaligned one reads the small host projection.  Copy 0 is the one copy every marked image has, so this works on a
    256 x 256 slice that carries only one or two copies, where the old "3 of 4 regions agree"
    statistic had nothing to compare.  Used only to search; the verdict is the 48-bit tag.
    """
    positions = np.linspace(0, embed.BLOCKS_PER_REGION - 1, n_pos).astype(int)
    lh, lw = ll.shape
    vals = []
    for i in positions:
        pos = placement[i]
        if pos is None:
            continue
        br, bc = pos
        if br + embed.DCT_BLOCK > lh or bc + embed.DCT_BLOCK > lw:
            continue
        blk = np.round(ll[br:br + embed.DCT_BLOCK, bc:bc + embed.DCT_BLOCK]).astype(np.int64)
        vals.append(embed.block_confidence(blk, embed.qim_delta(embed.local_std(ll, br, bc))))
    return float(np.mean(vals)) if vals else 0.0


def score_ll_band(
    ll_recv: np.ndarray,
    cand: Candidate,
    decl_ll_shape,
    placements: list[list[tuple[int, int]]],
) -> float:
    """Copy-0 confidence when the LL band is restored with `cand`.

    The LL band is interpolated, not recomputed, so this is an approximation of the
    exact path: cheap enough to try every candidate, never used for the verdict.
    """
    ll = approximate_ll(ll_recv, cand, decl_ll_shape)
    try:
        return copy_confidence(ll, placements[0])
    except Exception:
        return 0.0


# --------------------------------------------------------------------------- #
# the exact path
# --------------------------------------------------------------------------- #


def restore(img: np.ndarray, cand: Candidate, declared_shape) -> np.ndarray:
    """Resample `img` back onto the declared export geometry (image domain, exact)."""
    img = np.asarray(img, dtype=np.float64)
    if cand.is_identity and img.shape == tuple(declared_shape):
        return img
    out = resample_affine(img, cand.scale_y, cand.beta_y * 2.0,
                          cand.scale_x, cand.beta_x * 2.0, tuple(declared_shape))
    return np.clip(np.round(out), 0, 255)


def coverage_map(img_shape, cand: Candidate, out_shape) -> np.ndarray:
    """Which pixels of the declared frame came from the received image.

    `resample_affine` (the pixel-domain `restore`) clamps out-of-range source coordinates to the
    image border, so a cropped copy is restored into a declared-size frame whose uncovered part is
    **replicated edge content, not picture**: no mark was ever written there, and a diagnostic
    pixel's value is invented. Those pixels must not be read as payload and must not enter the ROI
    statistics. This mask is the decoder's knowledge of that, derived from the candidate geometry
    alone.

    The rule mirrors the resampler's own: a source coordinate one pixel outside still clamps to a
    real border sample, so only coordinates more than one pixel outside are uncovered. (Without
    that tolerance a resize with a half-pixel phase, beta = -0.25 LL, reported row 0 as missing and
    the mask came out 0.998542 instead of 1.0.)
    """
    h, w = out_shape
    ih, iw = img_shape
    if cand.is_identity and (ih, iw) == (h, w):
        return np.ones((h, w), dtype=bool)
    ys = np.arange(h, dtype=np.float64) * cand.scale_y + cand.beta_y * 2.0
    xs = np.arange(w, dtype=np.float64) * cand.scale_x + cand.beta_x * 2.0
    ok_y = (ys >= -1.0) & (ys <= ih)
    ok_x = (xs >= -1.0) & (xs <= iw)
    return ok_y[:, None] & ok_x[None, :]


def _pad_even(img: np.ndarray) -> np.ndarray:
    h, w = img.shape
    if h % 2 or w % 2:
        img = img[: h - (h % 2), : w - (w % 2)]
    return img


@dataclass
class Recovery:
    exact: bool
    tag_ok: bool
    bits: np.ndarray
    fields: dict
    accepted: Candidate
    candidates: list[Candidate]
    pilot: dict
    residual: list[float]
    region_hard_ber: list[float] | None
    llr_confidence: float
    ll: np.ndarray
    restored: np.ndarray
    failures: list[str] = field(default_factory=list)


def recover(
    img: np.ndarray,
    key: bytes,
    declared_shape: tuple[int, int],
    codeword: np.ndarray | None = None,
    verbose: bool = False,
) -> Recovery:
    """Recover and verify a tag from a possibly damaged copy of the marked export."""
    img = _pad_even(np.asarray(img, dtype=np.float64))
    declared_shape = tuple(declared_shape)
    failures: list[str] = []

    # 1. measure the pilot on the received image
    ll_recv, _ = iwt2d_53(img.astype(np.int32))
    est = measure_grid(ll_recv)
    if embed.PILOT_ENABLED:
        if not (est.rows.period >= MIN_PERIOD_LL and est.cols.period >= MIN_PERIOD_LL):
            failures.append("pilot period below the resolvable limit")
        if not est.trusted:
            failures.append("pilot measurement reported low confidence")

    # 2. candidates
    cands = candidate_maps(est, declared_shape, img.shape)
    decl_ll = (declared_shape[0] // 2, declared_shape[1] // 2)
    universe = embed.block_universe(decl_ll)

    # ROI and clipping taint, and placements once, for ranking only: rescale the received
    # image to the declared geometry (scale-only map, no offset) and derive both there.  The
    # previous revision sampled the received image with an identity map, which on a
    # resized copy clamps every index to the border, yields a degenerate ROI that
    # taints every block, and kills the run in placement_map instead of reporting
    # a recovery failure.  If even the declared geometry has no room for the
    # codeword, report tag FAIL gracefully: a damaged copy must never traceback.
    # The taint must be derived the same way the encoder derived it (`blocked_blocks`), or
    # the decoder reads different blocks than the encoder wrote.
    approx_decl = resample_affine(
        img, img.shape[0] / declared_shape[0], 0.0,
        img.shape[1] / declared_shape[1], 0.0, tuple(declared_shape))
    blocked_for_score = embed.blocked_blocks(
        decl_ll, np.clip(np.round(approx_decl), 0, 255).astype(np.uint8))
    try:
        score_placements = [
            embed.placement_map(key, decl_ll, r, blocked_for_score,
                                embed.BLOCKS_PER_REGION, universe, allow_erasures=True)
            for r in range(embed.N_REGIONS)
        ]
    except ValueError as exc:
        failures.append(f"no placement at declared geometry: {exc}")
        blank = np.zeros(polar_codec.K, dtype=np.uint8)
        return Recovery(
            exact=False, tag_ok=False, bits=blank, fields={}, accepted=cands[0],
            candidates=cands, pilot={
                "period_rows": round(est.rows.period, 4),
                "period_cols": round(est.cols.period, 4),
                "phase_rows": round(est.rows.phase, 3),
                "phase_cols": round(est.cols.phase, 3),
                "scale_rows": round(est.rows.scale, 4),
                "scale_cols": round(est.cols.scale, 4),
                "amplitude_rows": round(est.rows.amplitude, 3),
                "amplitude_cols": round(est.cols.amplitude, 3),
                "confidence_rows": round(est.rows.confidence, 4),
                "confidence_cols": round(est.cols.confidence, 4),
                "trusted": bool(est.trusted),
                "residual": [
                    round(img.shape[0] // 2 - decl_ll[0] * snapped_scale(est.rows.period), 2),
                    round(img.shape[1] // 2 - decl_ll[1] * snapped_scale(est.cols.period), 2),
                ],
            },
            residual=[0.0, 0.0], region_hard_ber=None, llr_confidence=0.0,
            ll=ll_recv, restored=np.clip(np.round(approx_decl), 0, 255),
            failures=failures,
        )

    # 3. rank every coarse candidate by region agreement on the interpolated LL band
    for c in cands:
        c.score = score_ll_band(ll_recv, c, decl_ll, score_placements)
    cands.sort(key=lambda c: -c.score)
    # The cheap approximate score misranks after a resample (a wavelet transform does not
    # commute with one), so the priority candidates -- identity and the dimension-ratio
    # rescale -- are always exact-tested first, whatever their cheap score says.
    priority = [c for c in cands if c.priority]
    other = [c for c in cands if not c.priority]
    # Priority candidates are the pilot-free safety net and must never be crowded out of
    # the exact budget by a pilot-derived guess, so they take their slots first and the
    # remainder is filled in cheap-score order.  Among themselves they are ordered by that
    # same cheap score, with the identity map pinned first (a clean copy must stay exactly
    # bit-exact): the wrong pilot-free guess costs a full fine scan otherwise, which is
    # ~100 s per decoy in the reference.
    identity_first = [c for c in priority if c.is_identity]
    priority_rest = sorted([c for c in priority if not c.is_identity], key=lambda c: -c.score)
    ordered = identity_first + priority_rest + other[: max(0, MAX_EXACT_CANDIDATES - len(priority))]
    if verbose:
        for c in ordered[:8]:
            print(f"   coarse {c.label:<44} agreement {c.score:.3f}")

    # 4. the best few get a fine-offset scan, then the exact path; the tag decides.
    # Decode attempts per candidate: the copy prefixes, largest first ({0,1,2,3}, {0,1,2},
    # {0,1}, {0}) -- the encoder writes copies 0..C-1 and the decoder does not know C -- then
    # copies 1, 2, 3 alone.  Every attempt is gated by the 48-bit tag, but every attempt is
    # also one more 2^-48 chance of a false accept (union bound): one recover() call makes at
    # most MAX_EXACT_CANDIDATES x FINE_PRIORITY_CAP x 7 = 875 tag checks, so the per-image
    # bound is ~2^-38.2, not 2^-48.  A forger gets that many guesses per submitted image; the
    # server rate limit must count images, not checks.
    def decode_attempts(regions: list) -> tuple:
        all_llrs = [rr.llrs for rr in regions]
        n = embed.N_REGIONS
        subsets = [tuple(range(k)) for k in range(n, 0, -1)]
        subsets += [(r,) for r in range(1, n)]
        for s in subsets:
            combined = np.zeros(embed.BLOCKS_PER_REGION, dtype=np.float64)
            for i in s:
                combined += all_llrs[i]
            dec, _pm = polar_codec.polar_scl_decode(combined)
            v = verify_block(dec, key)
            if v["tag_ok"]:
                return dec, s, v
        # nothing verified: return the combined decode for reporting
        dec, _pm = polar_codec.polar_scl_decode(
            sum(all_llrs, np.zeros(embed.BLOCKS_PER_REGION, dtype=np.float64)))
        return dec, tuple(range(embed.N_REGIONS)), verify_block(dec, key)

    def evaluate(c: Candidate) -> tuple[np.ndarray, list, dict] | None:
        restored = restore(img, c, declared_shape)
        cov = coverage_map(img.shape, c, tuple(declared_shape))
        try:
            regions, _ = embed.read_regions(restored.astype(np.uint8), key, coverage=cov)
        except Exception as exc:
            c.detail["read_error"] = repr(exc)
            failures.append(f"{c.label}: {exc!r}")
            return None
        dec, subset, v = decode_attempts(regions)
        c.exact = True
        c.detail["decoded_subset"] = list(subset)
        c.detail["llr_confidence"] = round(
            float(np.mean([np.mean(np.abs(rr.llrs)) for rr in regions])), 4
        )
        c.detail["region_ber"] = [None] * embed.N_REGIONS
        if codeword is not None:
            for rr in regions:
                if rr.ber is not None:
                    c.detail["region_ber"][rr.region] = round(rr.ber, 4)
        return dec, regions, v

    def fine_offsets(coarse: Candidate) -> list[float]:
        """Sub-sample offsets to try around a coarse candidate.

        The identity candidate on an image that is already at the declared geometry is
        not touched: the clean round trip must stay bit-exact, not "bit-exact after a
        half-pixel nudge".
        """
        if coarse.is_identity and img.shape == tuple(declared_shape):
            return [0.0]
        return list(FINE_OFFSETS)

    accepted: Candidate | None = None
    dec: np.ndarray | None = None
    regions: list = []
    for coarse in ordered[:MAX_EXACT_CANDIDATES]:
        if coarse.is_identity and img.shape != tuple(declared_shape):
            continue  # the identity map on the wrong geometry just replicates a border
        fys = fine_offsets(coarse)
        scored_fine = []
        for dy in fys:
            for dx in fys:
                fine = Candidate(
                    label=f"{coarse.label} + fine {dy:+.2f}/{dx:+.2f}",
                    scale_y=coarse.scale_y, beta_y=coarse.beta_y + dy,
                    scale_x=coarse.scale_x, beta_x=coarse.beta_x + dx,
                )
                s = score_ll_band(ll_recv, fine, decl_ll, score_placements)
                fine.score = s
                scored_fine.append(fine)
        scored_fine.sort(key=lambda c: -c.score)
        if coarse.priority and not coarse.is_identity:
            # Order the full fine scan by distance from the expected sub-pixel offset; the
            # cheap score is not trustworthy after a resample (see FINE_PRIOR).
            scored_fine.sort(
                key=lambda c: ((c.beta_y - coarse.beta_y) - FINE_PRIOR[0]) ** 2
                            + ((c.beta_x - coarse.beta_x) - FINE_PRIOR[1]) ** 2
            )
            budget = min(FINE_PRIORITY_CAP, len(scored_fine))
        else:
            budget = FINE_EXACT_TOP
        # exact path on the fine offsets; the tag decides, because the approximate score
        # misranks after a resample.
        exact_tried = 0
        for fine in scored_fine[:budget]:
            got = evaluate(fine)
            if got is None:
                continue
            exact_tried += 1
            dec, regions, v = got
            if v["tag_ok"]:
                fine.accepted = True
                accepted = fine
                coarse.accepted = True
                if verbose:
                    print(f"   accepted: {fine.label}")
                break
            if accepted is None:
                accepted = fine  # remember the first one that could be read at all
        best_fine = scored_fine[0]
        coarse.detail["fine_scan_best"] = [
            round(best_fine.beta_y, 3), round(best_fine.beta_x, 3),
            round(best_fine.score, 3),
        ]
        coarse.detail["fine_exact_tried"] = exact_tried
        if verbose:
            print(f"   coarse {coarse.label:<44} best fine "
                  f"{best_fine.beta_y:+.3f}/{best_fine.beta_x:+.3f} LL "
                  f"agreement {best_fine.score:.3f} exact-tried {exact_tried}")
        if accepted is not None and accepted.accepted:
            break

    if accepted is None:
        accepted = Candidate("declared geometry (no offset)", 1.0, 0.0, 1.0, 0.0)
        got = evaluate(accepted)
        if got is None:
            dec = np.zeros(polar_codec.K, dtype=np.uint8)
            regions = []
            failures.append("no candidate could be read at all")
        else:
            dec, regions, _v = got

    ber = None
    if codeword is not None and regions:
        ber = []
        for rr in regions:
            err = int(np.sum(rr.bits != np.asarray(codeword, dtype=np.uint8)))
            ber.append(err / embed.BLOCKS_PER_REGION)

    restored = restore(img, accepted, declared_shape)
    pilot = {
        "period_rows": round(est.rows.period, 4),
        "period_cols": round(est.cols.period, 4),
        "phase_rows": round(est.rows.phase, 3),
        "phase_cols": round(est.cols.phase, 3),
        "scale_rows": round(est.rows.scale, 4),
        "scale_cols": round(est.cols.scale, 4),
        "amplitude_rows": round(est.rows.amplitude, 3),
        "amplitude_cols": round(est.cols.amplitude, 3),
        "confidence_rows": round(est.rows.confidence, 4),
        "confidence_cols": round(est.cols.confidence, 4),
        "trusted": bool(est.trusted),
        "residual": [
            round(img.shape[0] // 2 - decl_ll[0] * snapped_scale(est.rows.period), 2),
            round(img.shape[1] // 2 - decl_ll[1] * snapped_scale(est.cols.period), 2),
        ],
    }
    conf = 0.0
    if regions:
        conf = float(np.mean([np.mean(np.abs(rr.llrs)) for rr in regions]))
    return Recovery(
        exact=False,
        tag_ok=bool(verify_block(dec, key)["tag_ok"]) if dec is not None else False,
        bits=dec if dec is not None else np.zeros(polar_codec.K, dtype=np.uint8),
        fields=verify_block(dec, key) if dec is not None else {},
        accepted=accepted,
        candidates=cands,
        pilot=pilot,
        residual=pilot["residual"],
        region_hard_ber=ber,
        llr_confidence=round(conf, 3),
        ll=ll_recv,
        restored=restored,
        failures=failures,
    )


if __name__ == "__main__":
    # self-test: mark a synthetic cover, damage it three ways, recover each time
    import embed as _embed
    from tag_block import build_block, format_block

    cover, roi = _embed.make_cover()
    handle = tag_block.new_handle(20261011)
    block = build_block(_embed.HUB_KEY, 1, _embed.DEMO_HUB_ID, handle)
    marked, info = _embed.mark(cover, roi, block)
    print("marked:", info["blocks_available_per_region"], "blocks/region;",
          "clean self-check", info["round_trip_tag_ok"])

    def resize(a, f):
        from PIL import Image
        h, w = a.shape
        nh, nw = int(h * f) // 2 * 2, int(w * f) // 2 * 2
        return np.asarray(Image.fromarray(a).resize((nw, nh), Image.BICUBIC), dtype=np.uint8)

    tests = {
        "none": marked,
        "resize 0.5x": resize(marked, 0.5),
        "resize 0.75x": resize(marked, 0.75),
        "resize 1.5x": resize(marked, 1.5),
        "resize 2.0x": resize(marked, 2.0),
        "crop 25% top-left": marked[300:, 400:],
    }
    for name, img in tests.items():
        r = recover(img, _embed.HUB_KEY, cover.shape, codeword=info["codeword"], verbose=True)
        ok = np.array_equal(r.bits, block)
        ber = None if r.region_hard_ber is None else [round(b, 3) for b in r.region_hard_ber]
        print(f"{name:<20} scale {r.pilot['scale_rows']:.4f}/{r.pilot['scale_cols']:.4f} "
              f"exact={ok} tag={'PASS' if r.tag_ok else 'FAIL'} "
              f"accepted='{r.accepted.label}' candidate_tried={len(r.candidates)} "
              f"region_ber={ber}")
        if r.failures:
            print("    notes:", r.failures)

    # Regression: a mis-locked pilot must not delete the pilot-free candidate.
    # Measured failure mode on a real scan (period 24.9 instead of 12.5 in LL, i.e. the 2x
    # harmonic, flagged trusted=False) where that single number removed the only exact
    # geometry and lost a channel the harsher 1280 variant survived.
    # See results/g1_1600_geometry_2026-10-19.md.
    resized = resize(marked, 0.75)
    real_grid = measure_grid

    def mislocked(ll):
        est = real_grid(ll)
        for ax in (est.rows, est.cols):
            ax.period *= 2.0
            ax.trusted = False
        return est

    globals()["measure_grid"] = mislocked
    try:
        ll_r, _ = iwt2d_53(resized.astype(np.int32))
        cands = candidate_maps(mislocked(ll_r), cover.shape, resized.shape)
        r = recover(resized, _embed.HUB_KEY, cover.shape, codeword=info["codeword"])
    finally:
        globals()["measure_grid"] = real_grid
    has = any(c.label.startswith("rescale recv/decl") for c in cands)
    exact = np.array_equal(r.bits, block)
    print(f"mis-locked pilot (2x harmonic, trusted=False): "
          f"size-ratio candidate present={has} exact={exact} tag={'PASS' if r.tag_ok else 'FAIL'}")
    assert has, "a mis-locked pilot must not delete the size-ratio candidate"
    assert exact and r.tag_ok, "recovery must survive a mis-locked pilot on a pure resize"
