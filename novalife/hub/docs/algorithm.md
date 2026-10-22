# algorithm.md — the marking algorithm this project builds

> **Status: LOCKED IN, 2026-10-11.** This is the pipeline we implement, measure and compare against
> the visible-QR baseline. It changes only with a written reason recorded here, and every change
> costs a re-measurement.
>
> **Working name: RPP-QIM** — *ROI-masked, pilot-synchronised, polar-coded QIM*.

## 1. Why this algorithm, and not something else

The decision follows from four constraints, in order.

1. **Our threat model is conventional processing, not an attacker.** An image leaves the hospital
   through a chat app. What happens to it is fixed by the platform: resize, then a fresh JPEG
   encode. There is no adversary tuning an attack against our watermark. The 2026 WARP benchmark
   (32 watermarking methods against 34 attacks, https://arxiv.org/html/2609.40031) concludes that
   **no method is uniformly robust** and that "post-hoc methods with explicit synchronization" are
   the right family when the expected threat is conventional processing. Deep and generative
   watermarks buy robustness against regimes we do not face, at a cost we cannot pay.
2. **The hub is a small FPGA.** The PL enclave has to mark and verify deterministically, in
   hardware, inside a `<75%` LUT budget, and stay bit-exact against the Python reference. A trained
   network, SVD, or an iterative optimiser cannot be bit-exact, cannot fit, and cannot be audited.
3. **The payload is tiny and authenticated.** 128 bits: version, hub id, a random record handle,
   and a 48-bit Ascon tag. We need *exact* recovery of 128 bits, not a similarity score.
4. **The clinical constraint is absolute.** Nothing is written inside the diagnostic region.

An independent measurement of exactly our problem (HarrisonSec, 23 Sep 2026,
https://harrisonsec.com/blog/hidden-data-dies-in-chat-apps-measured/) gives the four facts that
shaped this algorithm:

| Measured fact | Consequence for us |
|---|---|
| LSB through a simulated WhatsApp send: **~50% BER**. Not degraded, deleted | no spatial-domain embedding, ever |
| DWT-DCT-SVD through the same send: **3.2% BER** — the mark is intact but exact recovery still fails | exact recovery needs strong error correction, not just a good domain |
| RS(32,8) turned recompression from **0/10 to 10/10** exact recoveries | strong ECC is what makes chat-app sharing work at all |
| **Any** rescale destroys every transform-domain method (BER back to ~50%), because the decoder reads the wrong coefficients | **synchronisation is the real problem**, and it needs an explicit solution |

Note that measurement used *simulated* platform parameters, not verified real sends. We treat its
conclusions as direction, and we measure the real platforms ourselves in Phase A.

## 2. The pipeline

```
                                    ┌── perceptual mask (local variance + ROI)  [exists, RTL]
 DICOM image                        │
   │                                ▼
   ├─► 5/3 lifting IWT ──────────► embeddable-band map   [exists, RTL]
   │        (integer, bit-exact)
   │
   ├─► P1  intake background floor: raise non-ROI pixels <= 16 to safe floor
   │         → prevents clipping taint from eliminating valid placement blocks
   │
   ├─► P2  tag block: 4-bit version | 12-bit hub_id | 64-bit handle | 48-bit Ascon tag
   │         → polar encode N=256, K=128                        [exists, RTL + Python]
   │
   ├─► P3  placement: keyed by an Ascon-CTR keystream → block coordinate order
   │         interleaved copy-major placement over entire LL band with wrap
   │
   ├─► P4  embedding: integer sign-of-Hadamard on 4x4 LL blocks, step delta from local variance,
   │         H = outer([1,1,-1,-1], [1,1,-1,-1]), sum(H^2)=16, bit = sign(v), no pilot grid
   │
   └─► share-ready export at a fixed size (see §3), perceptual hash stored server-side
```

Recovery is the same path in reverse, with three additions: **resolve the geometry, undo it, then read
the regions, soft-combine the log-likelihoods, polar SCL decode, and verify.** Verification happens in
the enclave; the app only reports what the server says.

The geometry step, as measured (2026-10-20): the pilot grid is removed (`PILOT_ENABLED = False`).
For a pure rescale (no crop), the scale is taken **exactly** from the received/declared size ratio.
For crops, residual candidates (`x1.0` corner crop, `x0.5` symmetric crop) are evaluated directly
against the 48-bit tag verdict.

### What each stage buys, and what evidence supports it

| Stage | Why this choice | Evidence |
|---|---|---|
| 5/3 lifting IWT, integer | bit-exact Python↔RTL; low-frequency band survives requantisation; no rounding drift | the core and the Python model already exist and match |
| Sign-of-Hadamard in 4×4 LL blocks | integer arithmetic; survives resample scaling (pattern gain 0.58 at 0.5x); fits 256x256 MRI | measured 2026-10-20: BER 0.000 across 0.5x–2.0x resamples; 50/50 JPEG Q40 |
| Polar N=256, K=128 | exact recovery of a 128-bit block; the encoder exists; soft-combining across copies is a natural fit | Arikan 2009; medical watermarking literature already pairs polar/BCH/Turbo with ROI embedding |
| Copy-major placement with wrap | redundancy against local damage and partial crops; robust to ROI disputes | HarrisonSec: ECC + redundancy turned 0/10 into 10/10; corner crops 5–40% PASS |
| Intake background floor | non-diagnostic background pixels raised to >= 16 | eliminates 0-clipping taint; passes 9/9 chat-app channels on real MRI scans |
| Mask outside the ROI | clinical non-negotiable | the perceptual mask core exists; ROI change is 0.0 everywhere |
| Ascon 48-bit tag | standard, tiny, and it is what makes a guessed pointer useless | NIST SP 800-232 |

## 3. Parameters (measured)

| Parameter | Value | Note |
|---|---|---|
| Cover size | 256×256 patient MRI native (or 2× nearest share export), or 1600+ px | works on 256×256 clinical MRI; export downscales survive |
| Transform | 5/3 lifting IWT, 1 level | integer lifting |
| Embedding domain | 4×4 blocks of the LL band | Hadamard pattern $H = [1,1,-1,-1] \otimes [1,1,-1,-1]$, never in ROI |
| QIM step delta | $64 + (5 \times \text{isqrt}(\text{var})) \gg 3$ forced even | integer adaptive threshold $T = \delta/2$ |
| Pilot grid | Disabled (`PILOT_ENABLED = False`) | geometry resolved via aspect/size ratio and crop residuals |
| Codeword | polar N=256, K=128, systematic | SCL decoder $L=8$ with CRC/tag verification |
| Regions / Copies | Up to 4 copies, interleaved copy-major | placed across whole LL band; soft-combined via LLR |
| Tag | 48-bit Truncated-Ascon MAC over (version, hub_id, handle) | NIST SP 800-232; rate-limit verification |
| Perceptual hash | server-side, coarse, fuzzy compare | error rates must be measured before it is trusted |

### 3.1 The embeddability precondition (added 2026-10-19, measured)

The payload blocks are tainted by two rules, both derived from the image itself (so nothing has to
be transmitted and the encoder and decoder each compute them from their own copy):

1. **ROI taint** — as before: a block whose pixel support touches the thresholded diagnostic region
   is not writable.
2. **Clipping taint** — a block whose 16×16 pixel support comes within `CLIP_MARGIN = 1` of a uint8
   clipping level (0 or 255) is not writable. The uint8 reconstruction clips the write away and the
   first codec turns the block into a constant, so every such block reads back the same bit.

Measured on a real cardiac MRI (2026-10-19, `../results/g1_real_image_2026-10-19.md`): **94.1% of
the eligible blocks sat on the 0 clip** because the ROI mask pushed the mark into the scan's black
margin; every re-encode then failed with a hard BER of ~0.54 in all four regions, while the same
image with the black level lifted by 16 passed JPEG q90/q70/q50. The synthetic phantom hides this
because its margin is textured by construction and sits at 22, not 0.

Consequences, stated before they are used as advantages:

- `embed.mark` now **refuses** (raises) when a region cannot be filled, and names which taint is
  responsible; it no longer emits a tag that cannot survive one re-encode.
- The taint is added *in the same place* as the ROI taint, so a frame with enough clean area is
  marked in the clean area. It is **bit-identical on every phantom cover** (same masks, capacity,
  marked-image SHA-256, BER and verdict), so the G1 matrix numbers are unaffected.
- The **precondition is a property of the input, not of the transform**: a frame whose
  non-diagnostic area is clipped cannot carry this tag at any placement. The product answer is
  **amplitude normalisation at intake** of the non-diagnostic area (mapping to a safe range such as
  [16,235], as every DICOM→display pipeline already windows an image) — not a change to the
  transform.
- On a scan with a large clipped black margin but a smaller ROI, the clipping taint can leave too
  few clean blocks. That is reported as a capacity failure with the reason named, not as a flop.

### 3.2 The 2026-10-20 Algorithm Change for 256x256 Patient MRI (measured)

On 2026-10-20, the algorithm was revised to operate on native 256×256 patient MRI scans (and 2× nearest share export), fully integer-arithmetic in the PL, removing the pilot grid and transitioning from DCT lattice QIM to a Hadamard projection sign embedding.

**Reasons and measurements:**
1. **Lattice QIM Failure under Resampling**:
   A resample scales projection values $v$. Under 0.5× downscaling, the pattern gain for Hadamard $H$ is 0.58. Because lattice QIM relies on absolute modulo grids, scaling causes catastrophic de-quantisation (measured: lattice QIM bit error rate was 0.52 at 0.5×). In contrast, sign embedding ($\text{sign}(v)$) is invariant to arbitrary positive linear scaling, achieving **BER 0.000** across 0.5×, 0.75×, 1.5×, and 2.0× resamples.
2. **4×4 LL Block Granularity vs 8×8 DCT**:
   An 8×8 LL block (16×16 pixels) requires too much non-ROI area; on a 256×256 MRI slice, fewer than 64 blocks fit outside the anatomy. 4×4 LL blocks (8×8 pixels, JPEG-aligned) provide $32 \times 32 = 1024$ total blocks in the LL band, yielding sufficient capacity (111–495 clean blocks native, and 1000+ at 2× nearest share).
3. **Integer Hadamard Projection $H = [1, 1, -1, -1] \otimes [1, 1, -1, -1]$**:
   $H$ is the lowest non-DC Hadamard sequency with $\sum H^2 = 16$. The projection $v = \sum H \cdot x$ is calculated with purely integer additions and subtractions (no multipliers or floating-point DCT). The embedding change $e$ is capped at $\pm 4T$ ($T = \delta/2$) and distributed as $x' = x + H \cdot d$ where $d_k = \lfloor e/16 \rfloor + (k < (e \bmod 16))$, ensuring $v' = v + e$ exactly with minimal spatial disturbance.
4. **Interleaved Copy-Major Placement with Wrap**:
   Instead of quadrant-based regional partitioning, all blocks in the LL band are indexed in a single keyed sequence. Up to 4 copies of the polar codeword are placed copy-major with stride and wrap. A missing or tainted block costs only a single bit rather than desynchronising an entire region.
5. **Pilot Grid Elimination**:
   The pilot grid removed roughly 50% of candidate blocks and introduced harmonic mis-locking. Resampling scale is determined directly from the received/declared dimension ratio, and crop translation is determined from discrete residual shifts evaluated against the 48-bit Ascon tag verdict.
6. **Intake Amplitude Floor**:
   Raising non-ROI background pixels $\le 16$ up to 16 eliminates uint8 0-clipping while preserving the ROI statistics threshold (`ROI_STATS_FLOOR = 16`).

## 4. What this algorithm does **not** handle, stated before we measure it

- **Rotation and unequal aspect ratio.** A pilot grid and log-polar template methods can recover
  rotation (Simitopoulos; Alattar & Meyer's log-polar autocorrelation resynchronisation;
  Pereira's template with log-polar/log-log maps) but that is heavier and is not in the first
  build. Chat apps do not usually rotate; screenshots and humans do.
- **Cropping that removes the pilot and all R regions.** Redundancy is finite. Report the crop
  fraction at which recovery fails.
- **Aggressive downscale below the chat cap** (a "document quality" send, or a screenshot on a
  small screen). As measured 2026-10-19, a pure Pillow BICUBIC downscale to 0.5x *does* recover
  (the geometry fix above); below that, or when the downscale is combined with a crop, it is a
  synchronisation failure and it must be reported, not hidden. The exact floor is to be swept.
- **A crop** — corrected 2026-10-19 by measurement; the earlier "periodic grid cannot be located"
  reading was wrong. The offset is not ambiguous: for a pure crop the scale is unchanged and the size
  is not, so the residual `received_ll − declared_ll × scale` is exactly the content shift (×1.0 for a
  corner crop, ×0.5 for a symmetric one). Crop failed for two other reasons: a region that could not
  place all its bits aborted the whole read instead of contributing erasures, and blocks whose pixels
  had been cropped away were read as data rather than as no information. Both are fixed and measured
  (corner crops to 40%, and a corner crop plus JPEG, recover exact 128 bits). What remains open is a
  **symmetric** crop of 10% or more: every region loses the same border, no quadrant survives intact,
  and the two regions whose restored border is classified differently by the ROI read garbage instead
  of abstaining. Closing that means making the block placement a pure function of geometry and key
  (fixed block per bit, unusable blocks punctured and erased) rather than skipping tainted blocks
  during the scan — which changes the embedded output and is therefore a decision, not a patch. See
  `results/g1_crop_2026-10-19.md`.
- **An adversary who removes the watermark.** Not our threat model. If someone later claims it is,
  this document must be rewritten, not quietly extended.
- **AI-generated or AI-edited images.** Out of scope; not our threat model.
- **An input whose non-diagnostic area is clipped** (a plain black margin, extremely common in
  exported/cropped scans). The tag cannot be placed survivably there: see §3.1. The gateway must
  normalise the amplitude at intake or refuse the marking, and a chip that reports "marked" without
  that step would be lying.

## 5. Honesty about novelty

Every component is published: QIM (Chen & Wornell 2001), adaptive QIM (Eggers et al.), 5/3 IWT,
polar codes (Arikan 2009), Ascon (NIST SP 800-232), pilot-grid scale estimation (Kawano &
Kawamura 2024), log-polar template resynchronisation (Pereira; Alattar & Meyer), and medical
ROI/RONI watermarking with an identifier payload (Coatrieux et al. 2008, and the DWT-DCT-SVD +
BCH/CRC schemes since).

Candidate contributions, **each of which is a claim only after it is surveyed and measured**:

1. an authenticated **pointer-not-payload** construction, where one polar codeword carries the
   128-bit tag and the record stays in the database;
2. **multi-region soft-combining** of one codeword, aimed at chat-app recompression;
3. a **pilot-grid synchroniser sized for a 128-bit payload** on a small PL enclave, i.e. scale
   recovery that costs a 1-D autocorrelation and a DFT, not a full Fourier-Mellin transform;
4. a hybrid split where Linux serves and the PL enclave holds the key, marks and verifies.

`tools/stego_research/PRIOR_ART.md` must be completed for these before the paper is written.

## 6. Explicitly rejected, with reasons

| Rejected | Reason |
|---|---|
| Hyperchaotic map + DNA cipher | no reviewed security basis; a standard keyed generator does the same obfuscation job. Removed from the repository (git history keeps it if the professor wants it for the proposal) |
| AES-CTR as the core primitive | superseded by Ascon; its measured timing failure is why the first PL path did not close |
| Deep / Transformer / Mamba watermarking | right family for adversarial threats, wrong one for ours, and impossible to make bit-exact or to fit the PL budget |
| SVD in the embedding path | robustness gain is marginal over a DCT grid for a 128-bit exact-recovery payload, and it is expensive in hardware |
| Zero-watermarking the ROI | keeps pixels untouched but the check is not exact recovery of a pointer; rejected for the pointer role |
| LSB anything | measured to be deleted by the first re-encode |

## 7. Build order for this algorithm

1. **Phase A (first, no hardware):** measure what the real chat apps do — resolution, quality
   factor, progressive vs baseline, EXIF stripping, chroma subsampling — and publish the numbers
   in `results/`. Without this the pilot grid's budget is a guess.
2. **Phase B:** the Python reference of §2, bit-exact against the existing `polar_codec.py`,
   `iwt_lifting.py`, `perceptual_mask_core`; then the attack matrix; then the visible-QR baseline
   on the same attacks.
3. **Phase C:** server flow and the app's scan screen.
4. **Phase D:** the PL cores (pilot-grid scale estimator, tag engine, QIM embedder, soft-combine),
   each with a testbench and bit-exactness against the Python reference, then real Vivado numbers.
