# Hub HTTP API — what exists, and what is proposed

> This file is the single reference the app's Dart code points at. It has two halves on purpose:
> **what runs on the board today** (measured) and **what the gateway should expose** (proposal,
> nothing implements it yet). Do not build a client against the second half before it exists.

## Part 1 — Verified on hardware, 2026-09-16

A PS bare-metal build was programmed over JTAG and answered on `192.168.31.86` over the LAN
(0% ping loss). Recorded in [`../results/hardware_2026-09-14_to_16.md`](../results/hardware_2026-09-14_to_16.md).

| Method | Path | Observed | Meaning |
|---|---|---|---|
| GET | `/status` | 167 B JSON, `vault_files = 4` | liveness and vault count |
| GET | `/vault/index.txt` | 176 B JSONL | the SD vault's file index |
| POST | `/embed` | 319 B request, 1255 B response, 1024 B stego body | embed a payload, fed over EMIO UART1 (R19/T19) |

These came from the bare-metal vault build, not from the Linux gateway in
[`system_architecture.md`](system_architecture.md). They are the proof that the network path, SD
storage and DDR all work on this board; they are **not** the product API.

## Part 2 — Proposed gateway API (nothing implements this yet)

Written down here so the app and the gateway agree before either is built. Plane-text, but the
authoritative definitions stay in `system_architecture.md` (Section 3: the enclave mailbox
commands `BUILD_TAG`, `VERIFY_TAG`, `MARK_IMAGE`, `EXTRACT_TAG`, `STATUS`, `ADMIN_*`).

The server is the only thing that decides anything. The app extracts, asks, and renders.

| Method | Path | Request | Response | Notes |
|---|---|---|---|---|
| POST | `/api/v1/verify` | `{version, hub_id, handle, tag, image_hash}` | `{ok: bool, reason}` | the gateway asks the PL enclave to `VERIFY_TAG`, then checks the handle, revocation, role and consent. Rate limited per user and per IP; every attempt audited |
| POST | `/api/v1/records` | `{handle}` | `{record_view}` or `403` | the record view allowed for the caller's role and the patient's consent. The record never leaves the server in any other form |
| POST | `/api/v1/submit` (lab tech) | marked-image upload + metadata | `{handle, status}` | the hub marks and stores; the lab tech sees their own submissions only |
| GET | `/api/v1/me/access-log` (patient) | session | list of lookups | who looked, when, for which record |
| POST | `/api/v1/consent` (patient) | grant or withdraw | `{ok}` | revocation is server-side and instant |
| POST | `/api/v1/admin/*` | — | — | **not reachable over the network.** Key load, rotate and wipe happen on a console wired to PL pins |

Auth: outbound-only access gateway in front, TLS, multi-factor login, rate limits. No inbound
ports on the box (decision D6).

## Current state of the client

`novalife_app/lib/services/hub_api_service.dart` is a **mock** that returns fixed demo data so the
UI and tests can be written before firmware exists. Its demo fixtures (including placeholder
credentials) are test data, not a schema to copy, and must not ship in a release build.
