# NovaLife: The Practical Need, the Image Tag, and the Ecosystem

> Status: **PROPOSAL for professor review.** Everything marked *design target* is a plan, not a
> measurement. Honesty rules in `AGENTS.md` apply: no hardware metric, speedup or robustness claim
> until it is measured.

## 1. The problem we are solving

A hospital image starts life as a DICOM file. The DICOM header carries who the patient is, which
study it belongs to and which hospital made it. That works while the file stays inside the DICOM
world (PACS, viewers, TLS between systems).

In day-to-day Indian clinical practice images routinely leave that world: they are exported as JPEG,
screenshotted, or forwarded over chat apps for a quick second opinion. When that happens **the header
is gone**. The image can no longer be tied back to the right patient record, and a swapped or
mislabelled image cannot be detected.

> Evidence status: informal reports show doctors in India share patient images over WhatsApp
> (IJME letter, small informal poll), and chat apps recompress images (an Indonesian study measured
> pixel and detail loss). **We found no study that measures how often metadata is lost or how often
> this causes a wrong-patient error.** Measuring this ourselves is Phase A below, and it is cheap:
> send test images through the real apps and look at what survives.

**NovaLife's job:** let an image carry a *small, authenticated pointer to its record* inside the
pixels, so that after it leaves DICOM, an authorised person can scan it with the NovaLife app, have
it verified, and be taken to the right record, under their role and the patient's consent.

What we are **not** doing: hiding the health record inside the image. The full record stays in the
database. This removes the weakest part of the earlier design (large payload, fragile, changes
diagnostic pixels) and keeps patient data out of any image that is shared.

## 2. Ecosystem: who does what

```
 Hospital PACS / HIS
        | DICOM image (LAN or SD card)
        v
 +-------------------------------------------------------------+
 | NovaLife HUB: one Zynq board (hybrid, see system_architecture)|
 |  PS / Linux (gateway)          PL (secure enclave)           |
 |  - receives image, creates     - builds the 128-bit tag:     |
 |    record + random handle        version | hub | handle |   |
 |  - asks the enclave to           authentication tag          |
 |    BUILD_TAG / MARK_IMAGE      - polar-codes the tag, embeds |
 |  - stores marked image,          it outside the diagnostic   |
 |    record, handle, audit         region                      |
 |  - serves the apps             - holds the key (Linux can    |
 |                                  ask, never read)            |
 +----------------------+--------------------------------------+
                        | marked image shared by any route
                        v
 Image leaves DICOM:  JPEG / screenshot / chat forward / print-scan
                        |
                        v
 NovaLife app (Flutter): picks image -> extracts tag -> sends it to the
 hub's server (over the internet, via the access gateway)
 -> PL VERIFY_TAG, then Linux checks handle, revocation, role, consent
 -> returns the record view allowed for that role, or "no"
```

Users (three groups; the server enforces these, never the app):

| Role | Can do |
|---|---|
| Lab tech | Submit images and reports for marking; see what they submitted; no clinical records beyond that |
| Doctor | Verify an image; open records of patients they treat, with consent where required |
| Patient | See own records and who accessed them; grant or withdraw consent |

An admin/DPO function (audit, erasure requests, hub keys) exists behind the scenes. Whether it is a
fourth app role is an open question for the professor.

Actors and what they hold:

| Actor | Holds | Never holds |
|---|---|---|
| Enclave (PL) | hub key, tag builder and verifier, embedder | the patient database |
| Gateway (PS/Linux) | handle -> record map, consent, audit log, perceptual hashes | the hub key |
| App | the image, a session after login | any key |
| The shared image | opaque handle + authentication tag | any patient name, ABHA ID or diagnosis |

## 3. The image tag (design target)

One tag = **128 bits**, which is exactly one polar codeword's information block (N=256, K=128,
already in the project).

| Field | Bits | Purpose |
|---|---:|---|
| version | 4 | format changes without breaking old images |
| hub_id | 12 | which hub issued it (up to 4096 hubs) |
| handle | 64 | random opaque pointer, not derived from the patient; unique per marked image |
| tag | 48 | truncated MAC over (version, hub_id, handle) with the hub key |

Why these sizes:

- **handle 64 bits**: random, so it reveals nothing. The server checks uniqueness on insert, so a
  chance collision is rejected at issue time rather than discovered later.
- **tag 48 bits**: a forger must guess 2^48 values per attempt; the server rate-limits verification
  per user and per IP and logs every failure. It authenticates *the pointer*, so guessed or edited
  pointers cannot be used to probe the database.
- Sizes are a **design target**, to be reviewed with the professor. They trade forgery resistance
  against codeword length, and longer tags mean less robustness.

MAC construction: an Ascon-based keyed construction (Ascon is now the NIST lightweight standard,
SP 800-232), truncated to 48 bits. **We do not design a new cipher or MAC.** The hub key lives only
in the PL enclave. Because the MAC is symmetric, whoever verifies must hold the key, so
verification is also done by the enclave (`VERIFY_TAG`). Key loading and escrow: see
`system_architecture.md` section 3.

## 4. Embedding and recovery (design target)

1. **Where:** only outside the diagnostic region of interest (ROI) found by the perceptual mask
   already built (`perceptual_mask_core`); never inside the ROI.
2. **How:** quantisation index modulation (QIM) of transform coefficients, keyed placement driven by
   an Ascon-based keyed generator (standard construction, not a chaotic map).
3. **Redundancy:** the same 256-bit codeword is embedded in R independent regions of the image. At
   recovery the soft decisions from the regions are combined before polar decoding. This is the main
   defence against JPEG requantisation and local damage.
4. **Share-ready export:** the hub can export a marked copy at a chosen resolution, so the most
   common chat-app path changes the file only by JPEG requantisation, not by unpredictable resizing.
5. **Recovery:** extract coefficients, combine regions, polar SCL decode, return the 128 bits.

Honest main risk: **geometric damage** (rescaling, cropping, rotation). QIM on a fixed coefficient
grid is weak against it. Mitigations to test, in order: (a) export at a fixed share size, (b) embed
in low-frequency bands that survive moderate scaling, (c) add a small synchronisation pattern.
If none works well enough for the real apps, we say so and report the conditions where it does work.

## 5. Verification, privacy and consent

`verify(image)` in the app:

1. Extract and decode the 128 bits locally. If decoding fails, report "no tag found".
2. Send (version, hub_id, handle, tag) to the hub's server over TLS, through the access gateway
   (the box opens no inbound ports; see `system_architecture.md` section 7).
3. The gateway asks the enclave to `VERIFY_TAG`, then checks: handle exists and is **not revoked**,
   caller is logged in and has a role and (where required) the patient's consent.
4. On success return the record view allowed for that role. Every attempt, success or failure, goes
   to the hash-chained audit log.

Content binding (detecting a swapped image): the server stores a coarse **perceptual hash** of the
marked image next to the handle. The app also sends its own hash of the received image, and the
server compares them by Hamming distance. A MAC cannot tolerate the small differences JPEG
introduces, so this check is fuzzy and server-side. Its error rates (false match / false reject)
must be measured before it is relied on.

Privacy properties this gives, which are the practical value for DPDP and NABH:

- The shared image holds no patient identifier.
- Revoking a handle on the server makes every circulating copy useless, instantly.
- Every lookup is attributable and audited.
- An image from outside the system simply returns "no tag".

## 6. Baselines we must compare against

A professor will ask "why not something simpler?". These are the honest alternatives, and the
project must show where the pixel tag does better or admit where it does not:

| Baseline | Strength | Weakness we must test |
|---|---|---|
| DICOM header only | standard, nothing to build | lost on JPEG, screenshot, chat forward |
| Visible QR/barcode stamped in a margin | trivial, robust, readable by any phone | easily cropped out, visible to everyone, changes the layout |
| Pointer in pixels (our tag) | survives crops that keep its regions, invisible, authenticated | geometric damage, needs our app, pixel changes |

Build the visible-QR baseline first: it is a few days of work, and it is the number our tag must be
compared with.

## 7. Evaluation protocol (Phase A/B), criteria to agree before running

Metrics, all measured on real images (DICOM series from a public source, never real patients):

- **Recovery rate** of the correct 128 bits after: JPEG at several qualities, real round trips
  through the actual chat apps, screenshots, printing and scanning, resizing, cropping.
- **False accept rate** (a wrong or forged tag accepted) and **false reject rate**.
- **Image impact:** PSNR/SSIM and the ROI-distortion metric, measured **outside the ROI and inside
  it** (inside it must be zero by construction).
- **Perceptual-hash error rates** for swap detection.
- **Hardware:** only after Phase 4, from real Vivado reports (LUT/DSP/BRAM, timing) and measured
  embed/recover time on the board.

Pass/fail thresholds are set with the professor *before* the runs, so results cannot be tuned to fit.

## 8. What happens to the earlier crypto and stego pieces

| Piece | Decision (proposed) | Reason |
|---|---|---|
| Ascon (AEAD/MAC/KDF) | **core** | NIST standard; used for tag and vault encryption |
| Polar code N=256 K=128 | **core** | one block holds exactly one tag |
| ROI-aware perceptual mask, QIM | **core** | prevents touching diagnostic pixels |
| ML-KEM-512 | **optional hardening** | hub-to-server key exchange; keep if time, do not present as the need |
| Hyperchaotic map + DNA cipher | **rejected and removed** | no trusted security basis; a standard keyed generator does the same obfuscation. Reasons in `algorithm.md` section 6 |
| Whole-EHR embedding | **removed** | replaced by pointer + tag |

## 9. Novelty statement (to be written only after the prior-art survey)

We make **no novelty claim yet.** Pieces such as QIM, polar codes, Ascon and watermarking of medical
images are published. Candidate contributions, each of which must be checked against prior art and
measured before it is claimed:

1. An authenticated *pointer-not-payload* design where one polar codeword carries a 128-bit tag
   with a server-side revocation and consent flow.
2. Multi-region soft-combining of a single codeword for chat-app recompression.
3. A hybrid Zynq design where Linux serves and a PL enclave holds the key and does marking and
   verification, with measured cost and a stated threat model.

Phase A deliverable: update `tools/stego_research/PRIOR_ART.md` for items 1-3 (medical-image
watermarking with patient-ID/pointer payloads, JPEG-robust QIM, polar-coded watermarks,
pilot-grid and log-polar synchronisation, and any published chat-app robustness measurement).

## 10. Plan and order of work

| Phase | Work | Output |
|---|---|---|
| A | Measure the problem: real round trips of test images through chat apps; what metadata survives. Build the visible-QR baseline. Prior-art survey. | numbers + baseline + updated PRIOR_ART.md |
| B | Python reference of the tag: build, embed, attack, recover, verify. Compare with the baseline. | measured recovery/false-accept tables |
| C | Server flow: handle table, revoke, rate-limit, audit, perceptual-hash match (Supabase migration). App: scan and verify screen. | working end-to-end in software |
| D | Hardware: tag builder and embedder in PL, bit-exact against the Python reference, then Vivado numbers on the board. | testbenches + real reports |
| E | Paper and demo: write only what Phases A-D measured. | updated paper |

Open questions for the professor: acceptable tag size, pass/fail thresholds, whether the visible-QR
comparison should appear in the paper, and whether the ML-KEM piece is wanted.
