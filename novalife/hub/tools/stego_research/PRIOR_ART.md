# PRIOR_ART.md — prior art for the NovaLife image tag

> **Scope:** every technique in `docs/algorithm.md`, what published work it comes from, and the one
> thing we might contribute. **Nothing here is claimed to be new.** This file is the record that the
> prior-art survey happened before a claim was made, and it must be finished before the paper.

## 1. The technique set we use, and where each piece is published

| Piece we use | Published prior art | What we actually do with it |
|---|---|---|
| QIM | Chen & Wornell, *Quantization index modulation*, IEEE Trans. Inf. Theory 47(4), 2001 | textbook binary QIM |
| Adaptive step `16 + 0.15 x local_std` | Eggers et al. scalar Costa scheme and the adaptive-QIM follow-ons | scale the step with local variance; already measured in `tools/stego_dct_qim/` |
| Keyed coefficient placement | F5 (Westfeld, IH 2001); HMAC-permuted order is standard | obfuscation of location, **not** encryption |
| 5/3 lifting integer wavelet | standard lifting | integer, bit-exact Python <-> RTL |
| Block DCT inside a wavelet band | the DWT-DCT-SVD family | puts the embedding where JPEG re-quantisation lands |
| Polar coding N=256, K=128 | Arikan, IEEE Trans. Inf. Theory 55(7), 2009 | one codeword per 128-bit tag; soft-combining across regions |
| Ascon, 48-bit tag | NIST SP 800-232, final 13 Aug 2025 | standard MAC, truncated; no home-made construction |
| Pilot grid for scale estimation | Kawano & Kawamura, *Watermarking method with scaling rate estimation using pilot signal*, IEICE Trans. Inf. & Syst. 2023EDP7222 (2024), https://globals.ieice.org/en_transactions/information/10.1587/transinf.2023EDP7222 | a secret grid interval; autocorrelation of the projection sums plus a windowed DFT gives the scale rate |
| Log-polar / template resynchronisation | Pereira, *Template based recovery of Fourier-based watermarks using log-polar and log-log maps*; Alattar & Meyer, *Watermark re-synchronization using log-polar mapping of image autocorrelation*; Sharma & Coumou, *Watermark Synchronization: Perspectives and a New Paradigm*, CISS 2006 (a taxonomy: geometric-invariant transform, recovery-assisted, feature-based, exhaustive search) | the heavier options we did **not** take first; rotation recovery if we need it later |
| Medical ROI / RONI watermarking with an identifier | Coatrieux et al., *Watermarking medical images with anonymous patient identification*, 2008; a hybrid DICOM scheme with zero-watermarking of the ROI and RONI embedding, Appl. Sci. 13(10):6132, 2023; Chauhan, quantization-based multiple medical watermarking with BCH/Turbo codes | the honest context: embedding in the non-diagnostic region with ECC is a well-populated field |

## 2. Benchmarks and independent measurements we must cite (and not confuse with our own)

| Source | What it gives | How we use it |
|---|---|---|
| WARP benchmark, https://arxiv.org/html/2609.40031 (32 methods, 34 attacks) | **no method is uniformly robust**; geometric alignment is the crucial weakness; "post-hoc methods with explicit synchronization" are the right family when the threat is conventional processing; post-hoc beats generative only for non-destructive processing | justifies the family we chose, and warns us not to over-claim |
| HarrisonSec, *Why Hidden Data Dies in Chat Apps: LSB vs a Robust Watermark, Measured*, 23 Sep 2026, https://harrisonsec.com/blog/hidden-data-dies-in-chat-apps-measured/ | LSB ~50% BER through a simulated WhatsApp send; DWT-DCT-SVD 3.2%; RS(32,8) took recompression from 0/10 to 10/10 exact recoveries; **any rescale destroys transform-domain marks**; exporting above the platform cap turns a resize into a recompression | the four facts that shaped `algorithm.md`. **Simulated platform parameters, not verified sends** — cite it as such |
| Risenberg thesis (CU Denver), https://www.ucdenver.edu/docs/librariesprovider27/ncmf-docs/theses/risemberg_thesis_spring2020.pdf | WhatsApp strips EXIF from 123/79 entries to 22; iPhone images downscaled 2.52x, Android 3.32x; mobile path is progressive DCT with aggressive quantisation, desktop path differs | what Phase A must verify on the real apps |
| Indonesian repository study, http://repository.upnvj.ac.id/51960/ | DWT-based stego survives WhatsApp compression better than LSB (LSB failure up to 37.5%); document files pass unchanged while images do not | prior art for the DWT-over-LSB conclusion |
| JPEG Trust Part 3 (ISO/IEC 21617) watermarking benchmark, ICIP 2026 grand challenge, https://jpeg-trust-community.github.io/watermarking/benchmark/ | a standardised 100-bit payload benchmark with PSNR/wPSNR/SSIM/JND/FID and a defined attack list | a protocol we could align to later; our payload is 128 bits |

## 3. Families we rejected, with the reason (full version in `algorithm.md` section 6)

| Family | Why not |
|---|---|
| Chaotic map + DNA cipher | no reviewed security basis; a standard keyed generator does the same obfuscation. Removed from the repo; git history keeps it if the professor wants it for the proposal |
| AES-CTR as a product primitive | superseded by Ascon, and its measured timing failure is why the first PL path did not close timing |
| Learned watermarks (CNN / GAN / Transformer / Mamba / diffusion), surveyed in *Deep Learning for Image Watermarking*, Sensors 26(2):444, 2026, https://www.mdpi.com/1424-8220/26/2/444 | right family for adversarial threats and for in-generation marking, wrong family for ours; cannot be bit-exact against a hardware pipeline, cannot fit the PL budget, and its robustness advantage does not apply to our threat model |
| SVD in the embedding path | marginal gain for exact recovery of a 128-bit pointer; expensive in hardware |
| Zero-watermarking the ROI | preserves pixels exactly but does not give exact recovery of the pointer |

## 4. Survey round 2 — 2026-10-19 (done before any claim)

**Method:** paper/database search for the four candidate contributions in §5 and for the problem-side
claim. This round searched literature and public benchmarks, **not patent offices** (see §4.4).
Nothing below says an idea is new — it says **who already did the neighbours**. A claim is only valid
relative to this list.

### 4.1 Closest prior art per candidate contribution

| Our candidate (§5) | Closest work found | Distance |
|---|---|---|
| 1. authenticated **pointer-not-payload** (record stays in the DB) | **Coatrieux et al. 2008**, *Watermarking medical images with anonymous patient identification* — embeds a DICOM UID / anonymous patient identifier and verifies authenticity; **Seenivasagam et al. 2013** (PMC3732617), *QR-code zero-watermarking for medical image authentication* — encodes patient-identification data and checks it against a stored secret; the whole **zero-watermarking** family (Sheng 2023, Dong 2023, Arévalo-Ancona 2024); industry **Digimarc forensic watermarking** — a revocable ID that traces content back to a distributor | **Anticipated in concept.** Embedding *an identifier that points to a stored record and is checked server-side* is 2008-era work, and revoke-by-ID is sold commercially for media. Our differences are engineering: the pointer is random/opaque, carries a truncated Ascon MAC, and drives a consent/role gate — a **system** difference, not a new primitive |
| 2. **multi-region soft-combining** of one polar codeword for chat-app recompression | **Evsutin et al. 2024**, *Watermarking for Social Networks Images With Improved Robustness* (IEEE 10640090) uses error-correcting **polar codes**; **Zhang et al. 2024** (EURASIP JIS 10.1186/s13635-024-00173-4) steganographic polar codes; **Li & Liu**, *Robust Steganography Based on Polar Codes*; **NAWE 2026** (arXiv 2609.25972) uses polar redundancy. Repetition + soft-LLR combining is textbook coding | **Weak novelty.** Polar-coded robust watermarking aimed at social-media recompression is published; repetition across regions is standard |
| 3. **pilot-grid synchroniser** sized for a 128-bit payload | **Kawano & Kawamura 2024** (secret-interval grid; autocorrelation + windowed DFT — §1); **Kawano 2024** IEEE 10848801 (rotation + anisotropic scale); **arXiv 2601.18385** (2026) *Estimation of geometric transformation matrices using grid-shaped pilot signal* (grid + Radon); **SyncSeal**; log-polar/template resynchronisation (§1) | **Anticipated as technique.** Grid/pilot geometric synchronisation is an active published line. "Sized for a 128-bit payload on a small PL" is an optimisation, not a new method |
| 4. **hybrid Zynq**: Linux serves, PL enclave holds the key and marks/verifies | FPGA watermarking is crowded: **Zynq near-lossless robust watermarking for real-time medical use** (Springer 10.1007/s12083-026-02248-0, 2026); **Kaibou et al. 2021** FPGA chaos crypto-watermarking; **Hajjaji et al. 2019** FPGA Haar DWT; **Das et al. 2022** FPGA reversible; HW/SW co-design DCT schemes | **Least covered, but the pattern is standard.** "Keep the secret in the PL; let Linux only ask" is the ordinary secure-enclave split. Any claim must be about the **measured system**, not the idea |
| Problem: DICOM metadata lost on export | **No study found that quantifies** metadata loss or wrong-patient error from chat-app forwarding in India; sources are format facts (JPEG has no DICOM tags) or de-identification tooling | **Genuine gap — ours to measure (Phase A).** The strongest novelty position we hold |

### 4.2 Additional context found this round

- **Public robustness benchmarks exist:** WAVES (*Benchmarking the Robustness of Image Watermarks*,
  https://github.com/umd-huang-lab/WAVES), WARP (§2), and DeepMark's published real-world "torture
  test" (theirs reports full bit recovery on compression/enhancement). Cite them; do not claim to be
  first to measure robustness.
- **Content provenance is moving to the same shape:** C2PA 2.0 "soft bindings" = an invisible
  signal-level watermark alongside metadata; Digimarc/Imatag sell forensic, revocable watermarking.
  Our ecosystem is not a new *category*; any difference lives in the medical + DPDP consent/audit +
  exact-128-bit-pointer combination.
- **Ascon already names "authentication of pointers"** as a use case (Ascon-PRFshort, ePrint
  2021/1574 §4.2). It means memory pointers, not image-record pointers — but it means the *phrase* is
  not ours either.

### 4.3 Novelty verdict (honest, 2026-10-19)

**RPP-QIM has no defensible *algorithmic*-novelty claim as specified.** Every stage is published
(§1) and three of the four candidate contributions have published neighbours (§4.1). Claiming "a new
algorithm" invites an incremental-work rejection.

What is defensible, and how to frame it:

1. **A measured system for an under-measured channel** — exact 128-bit authenticated-pointer
   recovery after **real** mobile chat-app transmission of **medical** images in the India/DPDP
   context, with revocation, consent and hash-chained audit. Frame as **systems + measurement**.
2. **The one open algorithmic problem is the one we currently fail:** geometric damage (resize/crop).
   WARP and HarrisonSec both name geometric alignment as *the* bottleneck, and our own matrix fails
   0.5x/1.5x/crop/screenshot. **If pilot-led synchronisation makes a 128-bit *exact* payload survive
   a real resample, that is the contribution.** If it does not, report the negative result with
   numbers. **The novelty and the flop-risk are the same thing.**
3. **A hardware-verified enclave split** with real post-place-and-route numbers — only after Gate 5.

**Owner decision (2026-10-19): RE-SCOPE the algorithm before further testing.** A third search round
was run to find vacant algorithmic ground for that re-scope — see §4.5.

### 4.5 Survey round 3 — re-scope search (2026-10-19): no vacant ground

Looking for an algorithm direction that is **not** already published, these were checked:

| Re-scope direction | Already published |
|---|---|
| Scale/resample robustness by estimating and inverting the factor | **Li et al. 2023**, *Resampling-Detection-Network-Based Robust Image Watermarking against Scaling and Cutting* (PMC10575421); Zheng et al. image normalisation; Bas / Seo 2004 / Tang 2003 / Qi feature-point schemes; screen-cam feature sync (Chen 2020) |
| Self-synchronising watermarks (geometry estimated from the mark itself) | **Guo et al. 2003** self-synchronizing scheme; **SSyncOA** (arXiv 2405.03458); **GSyncCode** (ACM 10.1145/3706060); **SyncSeal** (arXiv 2509.15208) |
| Content/feature-anchored synchronisation (lattice travels with image features) | Celik & Sharma; Seo 2004; Tang 2003; screen-cam feature synchronisation |
| Drop the pixel tag; match by perceptual/content hash against stored records | 3D medical image retrieval by perceptual hashing (Atlantis Press); content-based medical image annotation/retrieval with PHash — plus the zero-watermarking family (§4.1) |
| Constrain QIM embedding as a feasibility/projection problem for robustness | **Altun & Sharma**, *Set-Theoretic QIM Watermarking*, ICASSP 2006 |

**Result: no vacant algorithmic ground on any axis a small project can occupy.** The field is ~25
years deep; every "new" direction re-arrives at a published neighbour.

**Honest conclusion:** a defensible *algorithmic-novelty* claim is **not available** to this project.
Re-scoping the transform cannot create one. The contributions that survive the survey are (i) a
**measured system for an unmeasured channel** and (ii) a **narrow systems/technical result** from
making exact 128-bit authenticated recovery survive a controlled channel. Neither is "a new
algorithm".

### 4.6 Recommendation after round 3

| Path | What it claims | Novelty odds | Cost |
|---|---|---|---|
| **P1. Systems + measurement** (recommended) | a measured, hardware-backed system for an unmeasured channel; the resize result as the technical section | honest and defensible; not "new algorithm" | already most of the work |
| **P2. Narrow technical bet — *authenticated* synchronisation** | the Ascon MAC (not a correlation peak) is the accept/reject oracle over geometry hypotheses, so synchronisation is cryptographically verified | thin; a reviewer may call it incremental; and it may not fix the failure (the resample noise, not the hypothesis choice, looks like the cause) | decoder-side work; bit-exact; cheap in HW |
| **P3. Genuine course change** | occupy ground outside watermarking (e.g. a medical-device/DPDP protocol angle) | unknown; out of this survey's scope | high |

**Recommendation: P1, letting P2 emerge inside the resize work — but claiming P2 only if it actually
fixes the resample failure and is measured.** Do not spend the term hunting a claim the literature
does not leave open.

**Owner's pick (2026-10-19): P1 — systems + measurement.** P2 may be attempted inside the resize work
(Gate G1) and claimed only if it is measured to fix the resample failure. No algorithmic-novelty claim
is made anywhere.

### 4.4 Still open (do before the paper)

- perceptual-hash (swap-detection) false-match rates on medical images;
- a **patent** search (Digimarc/Philips/Dolby families) for grid pilots and revocable forensic IDs;
- any published *medical* measurement of metadata loss or wrong-patient error after chat-app
  forwarding — none found; confirm once more before writing "no study exists".

## 5. Candidate contributions — status after the 2026-10-19 survey (§4)

1. an authenticated **pointer-not-payload** construction, where one polar codeword carries the
   128-bit tag and the record stays in the database — **surveyed: anticipated in concept**
   (Coatrieux 2008; QR zero-watermarking; Digimarc). Defensible only as part of a measured system;
2. **multi-region soft-combining** of one codeword, aimed at chat-app recompression — **surveyed:
   weak novelty** (Evsutin 2024 polar + social networks; standard repetition);
3. a **pilot-grid synchroniser sized for a 128-bit payload** on a small enclave — **surveyed:
   anticipated as a technique** (Kawano 2024; arXiv 2601.18385). The *open* problem it must solve is
   making exact recovery survive a real resample — currently failing in our own matrix;
4. a hybrid split where Linux serves and the PL enclave holds the key, marks and verifies —
   **surveyed: least covered, but the pattern is standard**. Claim only from measured numbers.

**Net: treat the paper as systems + measurement, with the resize result as the technical core.**

## 6. Honesty bans

Do not write, anywhere, until it is measured:

- any BER, PSNR or recovery figure as a percentage improvement or a factor;
- any hardware throughput, latency, power or energy figure;
- "undetectable", or a KL-divergence number presented as proof of security;
- "novel", "first", "100% novel", or any comparison that "beats" another method;
- that the tag survives a chat app, a resize, a crop, a rotation or a screenshot;
- that the hyperchaotic/DNA cipher adds security.
