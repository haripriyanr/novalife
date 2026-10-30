# AGENTS.md — NovaLife monorepo handoff

> **New session? Read this file first, then the one file named for your task.**
> The design docs live in `hub/docs/`; measured data in `hub/results/`; phase table in `PROGRESS.md`.

## Repository layout

```
novalife/
  app/          Flutter client (three roles: lab tech, doctor, patient)
  hub/          Zynq firmware, PL RTL cores, Python oracle, measured results
    docs/       algorithm.md  system_architecture.md  hub_http_api.md  ...
    firmware/   FreeRTOS C source (src/), boot artifacts gitignored
    hubcore/    C port of the algorithm, bit-exact vs Python oracle
    rtl/        Verilog cores (block_embed, ascon, polar, iwt, …)
    vivado/     Scripts only — project output gitignored, regenerate with build_enclave.tcl
    results/    Measured data only — .md summaries + small json/tcl/xdc files
    tools/      Python oracle (tag_reference/), ESP32 flash tooling, stego research
  supabase/     Migrations 001–012
  packages/     aether_ui — shared Flutter design-system package
  README.md     Public-facing DeCad-style README (numbers from results/ only)
  AGENTS.md     This file
  PROGRESS.md   Gate table and phase status
```

## Current state (2026-10-28)

**Steps 1–5 DONE and verified:**

| # | What | Evidence |
|---|---|---|
| G1 | Algorithm end-to-end — 50/50 JPEG/resize, 50/50 crop 25%, 9/9 real cardiac MRI | `hub/results/g1_hadamard_2026-10-20.md` |
| G2 | block_embed_core — 123/123 vectors, WNS +1.411 ns @ 100 MHz | `hub/results/g2_block_embed_2026-10-20.md` |
| G3 | Cloud relay live — 6 FCFS jobs in 5.80 s, outbound TLS verified | `hub/results/cloud_worker_2026-10-22.md` |
| G4 | Real MRI e2e on hardware — mark 10.67 s, verify 8.80 s, bit-exact | `hub/results/e2e_2026-10-22.md` |
| G5 | C port — 47/47 bit-exact vs Python oracle | `hub/results/c_port_2026-10-22.md` |
| App | 49/49 tests pass, debug APK built, HubJobsService wired | `app/test/` |

**Open / in-progress:**
- Symmetric crop ≥10% — no recovery yet (owner decision: keep open, do not redesign)
- Real chat-app round-trip — needs owner's phone
- RLS migration 009 — drafted, not applied (`hub_patients` SELECT open to all signed-in)
- App UI — all 3 roles, dark + light theme, queue/status views (in progress)
- Full PL marking pipeline (floor_background, keyed placement, DMA/DDR path) — planned
- **Review 2 & Linux Handoff (added 2026-10-30):** Full plan for Supabase purge, team identity seeding, 512×512 brain MRI upload, web server + snapshots, and Review 2 docx/pdf generation documented in root `AGENTS.md` §0.000.

## Rules (read before editing)

1. **No keys anywhere in git.** `config_local.h`, `.env`, `BOOT.BIN`, `.elf`, `.bit`, `.xsa` are gitignored. Before every commit run: `git ls-files | xargs grep -l "eyJ\|sb_publishable_\|sb_secret_\|gho_\|WIFI_PASS\|DEVICE_SECRET" 2>/dev/null` — must be empty.
2. **No novelty claims** until measured. Banned words: *novel, first, new, unprecedented, 100%*. Numbers only from `hub/results/`.
3. **Commit identity:** `haripriyanr <79777421+haripriyanr@users.noreply.github.com>`. No `Co-Authored-By` line, no AI tool mention in commit messages.
4. **No push** until owner says so. Local only.
5. **Don't move folders** while another agent is editing source files — breaks path resolution.
6. **G1 gate:** if the algorithm fails end-to-end, stop and report — do not build hardware on a broken algorithm.

## Quick references

| Task | File to read |
|---|---|
| Algorithm (locked) | `hub/docs/algorithm.md` |
| System architecture | `hub/docs/system_architecture.md` |
| Hub HTTP API | `hub/docs/hub_http_api.md` |
| App service layer | `app/lib/services/` |
| PL cores | `hub/rtl/` and `hub/vivado/ip_repo/` |
| C port | `hub/hubcore/src/` + `hub/hubcore/handoff/` |
| Supabase schema | `supabase/migrations/` |
| Measured data | `hub/results/` |
