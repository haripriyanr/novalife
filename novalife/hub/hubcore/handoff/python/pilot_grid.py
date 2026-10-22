"""Pilot grid: embed and recover the scale (and offset) of a resized image.

What is embedded
----------------
A plain integer grid in the LL band of the 5/3 IWT: at every LL row and column
`i * G` (and the `B` rows/columns after it) the coefficient is raised by a constant
`PILOT_AMPLITUDE`.  It carries **no bits at all** -- there is no payload in the grid and
there never will be, so a failure of this stage cannot corrupt the tag.

Why the grid is in the LL band
------------------------------
A JPEG re-encode, a low-pass resample and additive noise all hit the high frequencies
first; a low-frequency bias survives all three.  What does not survive them is the
*mapping* from coefficient to coefficient, which is exactly what a scale change destroys.
So the grid is placed where the signal lives and used only to re-find the geometry.

How the scale is recovered (Kawano & Kawamura, IEICE Trans. Inf. & Syst. 2024)
-------------------------------------------------------------------------------
1. Per axis, take the projection sums of the LL band along the other axis, so a grid line
   shows up as a bump of `PILOT_AMPLITUDE` at every `i*G`.
2. Subtract a *local* baseline (the `B` samples immediately before each candidate line) so
   slow content trends do not masquerade as grid lines.
3. Autocorrelation of that signal for a coarse integer period, restricted to the supported
   scale window.
4. A Hann-windowed DFT evaluated on a dense frequency grid around the coarse peak, for a
   sub-sample period; the same complex value gives the grid phase (offset).
5. The scale is `period / G`.

Additions to the locked stage P1, recorded here on purpose
----------------------------------------------------------
`docs/algorithm.md` stage P1 only asks for the scale factor.  Two things are needed in
practice and are returned as well; both are extra, not replacements:

* **per-axis offsets.**  A pure scale estimate cannot fix a crop, because the grid is
  periodic: a shift of exactly one grid interval is an equally good grid.  The estimator
  therefore also returns the grid phase and a cheap per-axis line-activity score, and the
  recovery path searches the offsets that the phase leaves ambiguous, letting the 48-bit
  tag arbitrate.  Without this, "crop 25% from a corner" has no mechanism at all.
* **independent scales per axis.**  A crop followed by a stretch changes the row and
  column periods differently.

Both are recorded as deviations from the locked spec that need a written decision from the
owner before the RTL is written.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

# --- constants (algorithm.md section 3, starting values, sweep these) ----------

PILOT_INTERVAL_G = 16  # LL-band coefficients between grid lines.
# algorithm.md writes "interval G = 32 px".  The LL band is half the image scale, so a
# 32 px image-domain spacing is 16 LL coefficients.  Stated here so the sweep is honest
# about which unit it is in.
PILOT_WIDTH_B = 3  # LL coefficients of thickness of every grid line
PILOT_AMPLITUDE = 16  # integer bias added under a grid line (LL coefficient units)

SCALE_MIN = 0.4  # smallest supported scale; below this the grid cannot be resolved at all
SCALE_MAX = 2.0  # largest supported scale

# how many grid intervals either side of the measured phase to try when the phase leaves
# the offset ambiguous (one grid interval = PILOT_INTERVAL_G image pixels * 2)
PHASE_SEARCH_K = 6

# minimum ratio between the strongest autocorrelation peak and the signal energy for the
# period estimate to be believed at all
MIN_PERIOD_CONFIDENCE = 0.05


@dataclass
class AxisEstimate:
    """Everything the pilot tells us about one axis of the received image."""

    axis: str
    n: int  # number of samples in the projection
    period: float  # measured grid period, in LL samples
    phase: float  # measured grid-line start, in [0, period)
    amplitude: float  # measured bump height, in coefficient units
    confidence: float  # peak autocorrelation / mean signal energy, 0..1
    trusted: bool  # False when the period estimate should not be used

    @property
    def scale(self) -> float:
        """Estimated scale factor for this axis (received / original)."""
        return self.period / PILOT_INTERVAL_G

    @property
    def offset_candidates(self) -> list[float]:
        """Phase values one grid interval apart, all consistent with the measurement."""
        k = PHASE_SEARCH_K
        return [self.phase + d * self.period for d in range(-k, k + 1)]

    @property
    def offset_scores(self) -> list[float]:
        return self._offset_scores

    _offset_scores: list[float] = field(default_factory=list, repr=False)


@dataclass
class GridEstimate:
    rows: AxisEstimate
    cols: AxisEstimate

    @property
    def scale(self) -> tuple[float, float]:
        return (self.rows.scale, self.cols.scale)

    @property
    def trusted(self) -> bool:
        return bool(self.rows.trusted and self.cols.trusted)


# --- embedding ----------------------------------------------------------------


def grid_line_starts(n: int, g: int = PILOT_INTERVAL_G) -> np.ndarray:
    """The first index of every grid line along an axis of length `n`."""
    return np.arange(0, max(0, n - PILOT_WIDTH_B + 1), g)


def pilot_mask(shape: tuple[int, int], g: int = PILOT_INTERVAL_G) -> np.ndarray:
    """Boolean LL-shaped mask of every coefficient the grid touches."""
    h, w = shape
    m = np.zeros(shape, dtype=bool)
    for r in grid_line_starts(h, g):
        m[r : r + PILOT_WIDTH_B, :] = True
    for c in grid_line_starts(w, g):
        m[:, c : c + PILOT_WIDTH_B] = True
    return m


def embed_pilot(ll: np.ndarray, roi: np.ndarray | None = None) -> tuple[np.ndarray, int]:
    """Add the pilot grid to an integer LL band.

    The grid is `B`-wide lines every `G` coefficients, in both directions -- the "grid at
    interval G, width B" of `docs/algorithm.md` section 3.

    `roi`, if given, is the LL-resolution ROI mask; anything inside it is left untouched,
    because nothing may be written inside the diagnostic region.  The rest of the line is
    still drawn, which keeps the synchronisation signal intact.

    Returns the piloted LL band (int32) and the number of grid lines that were applied.
    """
    ll = np.asarray(ll, dtype=np.int64).copy()
    h, w = ll.shape
    mask = np.zeros((h, w), dtype=bool)
    for r in grid_line_starts(h):
        mask[r : r + PILOT_WIDTH_B, :] = True
    for c in grid_line_starts(w):
        mask[:, c : c + PILOT_WIDTH_B] = True
    if roi is not None:
        mask &= ~np.asarray(roi, dtype=bool)
    lines = int(mask.any(axis=1).sum()) + int(mask.any(axis=0).sum())
    ll[mask] += PILOT_AMPLITUDE
    return ll.astype(np.int32), lines


# --- measurement --------------------------------------------------------------


def projection(band: np.ndarray, axis: int) -> np.ndarray:
    """Projection sums of an LL band along one axis.

    `axis=0` averages over columns, so the result is indexed by *row*; `axis=1` averages
    over rows, so it is indexed by *column*.  The mean is used rather than the sum so a
    band from a resized image is directly comparable with the nominal band.
    """
    return np.asarray(band, dtype=np.float64).mean(axis=axis)


def _local_baseline(proj: np.ndarray) -> np.ndarray:
    """The `B` samples immediately before each sample.

    Those samples are known to be off-grid (the gap between two grid lines is `G - B`
    wide), so this is a baseline that follows the local content.  Subtracting it gives a
    signal that is `PILOT_AMPLITUDE` high on a grid line and near zero everywhere else,
    which is what the autocorrelation and the DFT are run on.
    """
    base = np.zeros_like(proj)
    for j in range(1, PILOT_WIDTH_B + 1):
        base += np.roll(proj, j)
    return base / float(PILOT_WIDTH_B)


def _template(phi: float, period: float, n: int) -> np.ndarray:
    """The grid signature placed at offset `phi`: +B on the line, -B just before it.

    Zero mean, so a bright or dark image cannot masquerade as a grid line.  This is the
    same shape the autocorrelation sees, and it is what the phase search maximises.
    """
    u = (np.arange(n, dtype=np.float64) - phi) % period
    t = np.zeros(n, dtype=np.float64)
    t[u < PILOT_WIDTH_B] = 1.0
    t[u >= period - PILOT_WIDTH_B] = -1.0
    return t


def grid_score(proj: np.ndarray, phi: float, period: float) -> float:
    """How strongly the projection looks like a grid placed at offset `phi`."""
    return float(np.dot(proj, _template(phi, period, proj.size)))


def refine_phase(proj: np.ndarray, period: float, coarse: float, steps: int = 256) -> tuple[float, float]:
    """Sub-sample grid offset: search `phi` over one full period, finely.

    One grid interval of ambiguity cannot be removed by the measurement (the grid is
    periodic), but the position *within* the interval can; that is what this returns.
    The brute-force search is cheap (`n x steps` adds) and needs no interpolation model,
    which matters because the signature is a 3-sample ramp, not a sinusoid.
    """
    best_phi, best = coarse, -np.inf
    for phi in np.linspace(0.0, period, steps, endpoint=False):
        s = grid_score(proj, phi, period)
        if s > best:
            best_phi, best = float(phi), s
    return best_phi, best


def _autocorrelation(d: np.ndarray, pmax: int) -> np.ndarray:
    x = d - d.mean()
    n = x.size
    r = np.zeros(pmax + 1)
    for k in range(1, min(pmax, n - 1) + 1):
        r[k] = float(np.dot(x[: n - k], x[k:]) / (n - k))
    return r


def _dft(d: np.ndarray, freqs: np.ndarray) -> np.ndarray:
    """Hann-windowed DFT of `d` on a dense frequency grid."""
    n = d.size
    x = (d - d.mean()) * (0.5 - 0.5 * np.cos(2 * np.pi * np.arange(n) / max(1, n - 1)))
    idx = np.arange(n)[:, None]
    return (x[:, None] * np.exp(-2j * np.pi * freqs[None, :] * idx)).sum(axis=0)


def _dft_period(d: np.ndarray, k0: int) -> float:
    """Sub-sample period from a windowed DFT, refined twice around the coarse peak."""
    n = d.size
    f_star = 1.0 / max(k0, 1.0)
    for _ in range(2):
        span = 1.0 / max(4.0 * n, 1.0)
        lo = max(1e-6, f_star - 4.0 * span)
        hi = f_star + 4.0 * span
        freqs = np.linspace(lo, hi, 121)
        z = _dft(d, freqs)
        f_star = float(freqs[int(np.argmax(np.abs(z)))])
    return 1.0 / f_star


def measure_axis(band: np.ndarray, axis: int, name: str) -> AxisEstimate:
    """Estimate the grid period and phase along one axis of an LL band.

    `axis=0` uses the mean over columns (so the result describes the *rows*), `axis=1`
    the mean over rows (describes the *columns*).
    """
    proj = projection(band, axis)
    d = proj - _local_baseline(proj)
    n = d.size
    pmin = max(2.0, SCALE_MIN * PILOT_INTERVAL_G)
    pmax = min(n / 3.0, SCALE_MAX * PILOT_INTERVAL_G)
    r = _autocorrelation(d, int(np.ceil(pmax)))
    energy = float(np.mean(d * d)) + 1e-12
    lo, hi = int(np.ceil(pmin)), int(np.floor(pmax))
    if hi <= lo:
        return AxisEstimate(name, n, float(PILOT_INTERVAL_G), 0.0, 0.0, 0.0, False)

    region = r[lo : hi + 1]
    if float(region.max()) <= 0:
        return AxisEstimate(name, n, float(PILOT_INTERVAL_G), 0.0, 0.0, 0.0, False)

    k0 = int(np.argmax(region)) + lo
    confidence = float(region.max()) / energy
    period = _dft_period(d, k0)

    phase, peak = refine_phase(proj, period, float(k0 % period))
    amplitude = float(d.max() - np.median(d))
    trusted = bool(
        confidence >= MIN_PERIOD_CONFIDENCE
        and PILOT_WIDTH_B + 1 < period
        and peak > 0.5 * PILOT_AMPLITUDE * PILOT_WIDTH_B * n / max(1, n // int(period))
    )

    est = AxisEstimate(name, n, float(period), float(phase), amplitude, confidence, trusted)
    est._offset_scores = [grid_score(proj, ph, period) for ph in est.offset_candidates]
    return est


def measure_grid(ll: np.ndarray) -> GridEstimate:
    """Measure the pilot grid on both axes of an LL band."""
    return GridEstimate(
        rows=measure_axis(np.asarray(ll, dtype=np.float64), axis=0, name="rows"),
        cols=measure_axis(np.asarray(ll, dtype=np.float64), axis=1, name="cols"),
    )


# --- the correction -----------------------------------------------------------


def resample_affine(
    img: np.ndarray,
    alpha_y: float,
    beta_y: float,
    alpha_x: float,
    beta_x: float,
    shape: tuple[int, int],
) -> np.ndarray:
    """Resample `img` so that output pixel (Y, X) comes from (alpha_y*Y + beta_y, alpha_x*X + beta_x).

    One bilinear pass.  Out-of-range source coordinates clamp to the image border, so a
    region the attack destroyed stays filled with something plausible instead of black.
    An identity map is returned untouched, which is what keeps the clean round trip
    bit-exact.
    """
    img = np.asarray(img, dtype=np.float64)
    h, w = shape
    identity = abs(alpha_y - 1.0) < 1e-9 and abs(alpha_x - 1.0) < 1e-9
    identity = identity and abs(beta_y) < 1e-9 and abs(beta_x) < 1e-9
    if identity and img.shape == (h, w):
        return img

    ys, xs = np.meshgrid(np.arange(h, dtype=np.float64), np.arange(w, dtype=np.float64), indexing="ij")
    sy = alpha_y * ys + beta_y
    sx = alpha_x * xs + beta_x
    ih, iw = img.shape
    sy_c = np.clip(sy, 0, ih - 1)
    sx_c = np.clip(sx, 0, iw - 1)
    y0 = np.floor(sy_c).astype(np.int64)
    x0 = np.floor(sx_c).astype(np.int64)
    y1 = np.minimum(y0 + 1, ih - 1)
    x1 = np.minimum(x0 + 1, iw - 1)
    fy = sy_c - y0
    fx = sx_c - x0
    top = img[y0, x0] * (1 - fx) + img[y0, x1] * fx
    bot = img[y1, x0] * (1 - fx) + img[y1, x1] * fx
    out = top * (1 - fy) + bot * fy
    # a border more than a pixel past the edge really is missing content
    out[sy < -1] = 0.0
    out[sx < -1] = 0.0
    return out


def undo_transform(
    img: np.ndarray, est: GridEstimate, shape: tuple[int, int], phase_k: tuple[int, int] = (0, 0)
) -> np.ndarray:
    """Resample a received image back onto the hub's declared export geometry.

    The map comes from the measured per-axis period and phase, doubled into image pixels
    because the LL band is half the image scale:

        image row of the received pixel  u = 2 * (phase + k * period + scale * LL row)

    with `phase_k` selecting which grid interval of the ambiguous ones to try.
    """
    ph_y = est.rows.phase + phase_k[0] * est.rows.period
    ph_x = est.cols.phase + phase_k[1] * est.cols.period
    return resample_affine(
        img,
        est.rows.scale,
        2.0 * ph_y,
        est.cols.scale,
        2.0 * ph_x,
        shape,
    )


if __name__ == "__main__":  # pragma: no cover - manual check
    rng = np.random.default_rng(3)
    ll = rng.normal(120, 25, (256, 256)).astype(np.int32)
    piloted, applied = embed_pilot(ll)
    est = measure_grid(piloted)
    print(f"grid lines applied: {applied}")
    print(f"rows: period={est.rows.period:.4f} phase={est.rows.phase:.4f} "
          f"amp={est.rows.amplitude:.2f} conf={est.rows.confidence:.3f} trusted={est.rows.trusted}")
    print(f"cols: period={est.cols.period:.4f} phase={est.cols.phase:.4f} "
          f"amp={est.cols.amplitude:.2f} conf={est.cols.confidence:.3f} trusted={est.cols.trusted}")
    print(f"scale estimate rows={est.rows.scale:.4f} cols={est.cols.scale:.4f} (true 1.0)")
    print("offset scores (rows):", [round(s, 2) for s in est.rows.offset_scores])
