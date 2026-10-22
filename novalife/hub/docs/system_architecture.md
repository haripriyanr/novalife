# NovaLife HUB: System Architecture (Hybrid Zynq)

> Status: **PROPOSED architecture (2026-10-10); not yet built.** Two earlier ideas — a dual-core
> ARM/FreeRTOS telemetry gateway and a "pure PL" VexRiscv plan — were dropped; what actually ran on
> the board is recorded in `../results/`. Items marked *proposal* are not built or measured yet.
> Honesty rules in `AGENTS.md` apply: no hardware metric, speedup or robustness claim until
> measured.

## 1. Idea in one paragraph

One Zynq-7010 board (1 GB DDR3) is both the hospital gateway and the hardware root of trust.
The **ARM processor system (PS) runs Linux** and does everything that needs a mature software
stack: network, TLS termination or tunnel, database, API, consent and audit logic, DICOM intake.
The **programmable logic (PL) is a secure enclave**: it holds the hub key, builds and verifies the
image tags, and runs the marking pipeline. Linux can *ask* the enclave to do things but can never
*read the key*.

```
 Zynq-7010 board, 1 GB DDR3 (owned by the PS memory controller)
 +-----------------------------------------+   +------------------------------------------+
 | PS: dual Cortex-A9, Linux (gateway)     |   | PL: secure enclave (trusted, minimal)    |
 |  - Ethernet GEM0 -> LAN / tunnel        |   |  - key store in BRAM (not mapped to PS)  |
 |  - DICOM intake from PACS               |   |  - tag build / verify (Ascon)            |
 |  - database + API (roles, consent,      |   |  - marking pipeline: mask, IWT/DWT, QIM, |
 |    audit, handle table)                 |   |    polar encode/decode                   |
 |  - TLS / outbound tunnel                |   |  - controller: VexRiscv + our RTOS       |
 |  - app-facing server                    |   |    (optional, later; BRAM only)          |
 +--------------------+--------------------+   +---------------------+--------------------+
                      |   AXI mailbox (commands)  +  DMA over AXI HP (image buffers in DDR)  |
                      +----------------------------------------------------------------------+
```

## 2. Why hybrid is the right shape for this board (and what was wrong before)

- **DDR belongs to the PS on Zynq-7000.** The DDR3 chips are wired to the PS memory controller, not
  to PL pins, so a design without the PS cannot reach DDR through a MIG controller. The PL reaches
  DDR only through the PS (AXI HP ports) after the PS has initialised it. An earlier linker script
  assumed "DDR via MIG" and old addresses (`0x00100000`, `0x01000000`, `0x01200000`) collide with
  Linux memory; they must not be reused (verify every address in the block design before relying
  on it).
- **Board support.** The project's own Vivado board preset (`EdgeZ7_10`) lists GEM0 (Gigabit
  Ethernet), SDIO0 (SD card), QSPI and USB, so the PS has the network and storage a Linux gateway
  needs. Confirm the Ethernet PHY works with a ping under U-Boot or Linux before committing.
- **Memory:** 1 GB DDR3 (owner-confirmed). Earlier docs say 512 MB; update them.
- **Linux can run what the PL cannot:** a database, TLS, and the tools a hospital IT team expects.
- **The PL does what software should not hold:** the key and the signing/verification logic.

## 3. The enclave interface (proposal)

The PS talks to the enclave only through a mailbox and DMA buffers. **There is no key register.**
(An earlier register map let software read and write the key. That interface is retired: the
mailbox commands below are the only path.)

| Command | Input | Output | Notes |
|---|---|---|---|
| `BUILD_TAG` | version, hub_id, handle | 128-bit tag block | PL builds the authentication tag from its key |
| `VERIFY_TAG` | 128-bit block | valid / invalid + fields | PL verifies; the server never sees the key |
| `MARK_IMAGE` | cover buffer, handle, region plan | marked buffer, status | runs the pipeline in `algorithm.md`: mask, IWT, pilot grid, QIM, polar encode |
| `EXTRACT_TAG` | image buffer | 128-bit block or "none" | polar soft-combine and decode |
| `STATUS` | none | counters, fault flags, key-loaded flag | no secrets |
| `ADMIN_*` | PL-side console only | n/a | key load, rotate and wipe are **not** reachable from Linux |

Properties and limits:

- **Symmetric MAC means whoever verifies holds the key.** So verification also runs in the PL
  (`VERIFY_TAG`). In this single-box design one hub verifies the images it issued. Verifying another
  hospital's images would need either shared keys or asymmetric signatures, which do not fit in a
  48-bit tag; that case is left to the national consent flow (ABDM) and is out of scope.
- **Sign oracle.** A compromised Linux could ask the enclave to mint tags. Mitigations: PL-side
  rate limit and counters, tags are only useful for handles that exist in the database, every use is
  counted in the PL and visible in `STATUS`. Linux can never extract the key to mint tags offline.
- **Key loading:** the admin enters a PIN on a console wired to PL pins (not PS), so neither the PIN
  nor the key crosses Linux. The wrapped key lives in storage; the PL unwraps it with a key derived
  from the PIN. Production alternative: encrypted bitstream with an eFUSE key (irreversible: do not
  burn on the only board without a decision).
- **Key escrow:** if the box dies, all tags become unverifiable. Split the key (Shamir) among named
  admins at provisioning and test the recovery.

## 4. Boot flow (proposal)

```
Power on -> BootROM -> FSBL/U-Boot SPL (SD or QSPI) -> U-Boot
  -> program PL bitstream (enclave) -> boot Linux (read-only root, minimal userland)
  -> enclave waits for the admin PIN on its console -> key-loaded flag set
  -> gateway services start; marking is refused until the key-loaded flag is set
```

## 5. Memory map (proposal, to be fixed in the block design)

DDR is Linux's by default. The PL gets a **reserved region** (device-tree `reserved-memory`):

| Region | Owner | Use |
|---|---|---|
| Linux | PS | OS, database, API |
| Reserved window (size TBD, e.g. 128 MB) | PS writes input, PL writes output | cover image, marked image, scratch |
| BRAM (PL-internal) | PL only | enclave code, stack, key store |

Old addresses (`cover 0x01000000`, `stego 0x01200000`, `code 0x00100000`) collide with Linux's
memory and must be redone.

## 6. Storage

- SD card holds the OS and read-mostly data. Frequent database writes wear it: use an industrial SD
  card, or USB storage if the board exposes USB, and keep encrypted off-box backups.
- The database holds roles, consent, audit log (hash-chained), handle table and perceptual hashes.
  Run PostgreSQL or SQLite plus a thin API. Whether the Supabase components run on 32-bit ARM with
  1 GB is **unverified**; the app currently speaks Supabase, so plan an interim where the box syncs
  to a Supabase instance and move on-box later.

## 7. Network exposure

- The box opens **no inbound ports** to the internet. It makes an outbound tunnel (or a VPN) to an
  access gateway, which terminates TLS, enforces multi-factor login and rate limits, and forwards.
- Linux hardening: key-only SSH or none, firewall default-deny, read-only root, no unused services,
  automatic security updates (a reproducible image build, Buildroot or Yocto).

## 8. Threat model (summary)

| Threat | Mitigation | Residual risk |
|---|---|---|
| Internet attacker hits the gateway | outbound-only tunnel, hardened Linux, rate limits | Linux bug gives PS shell |
| Attacker owns Linux | key unreadable (PL), rate-limited enclave, audit | can mint tags for existing handles within limits |
| Stolen box | key wrapped by PIN, no PIN on box | weak PIN; offline guessing, so use a slow KDF and long PIN |
| Forged or edited tag | 48-bit tag, server rate limit | grind attacks bounded by rate limit |
| Insider lookups | role + consent checks, hash-chained audit | collusion |
| Power loss or SD corruption | journalled filesystem, backups, UPS | data loss between backups |

## 9. The algorithm

The marking pipeline is specified and locked in [`algorithm.md`](algorithm.md). Read it before
designing any PL core for this path.

## 10. Resource budget

XC7Z010 is a small part. Targets from earlier plans (`<75%` LUT, `<40%` DSP, `<40%` BRAM) stand,
but **no post-implementation numbers exist yet**; they come from real Vivado reports in Phase H.

## 11. What this architecture corrects from earlier documents

| Earlier statement | Now |
|---|---|
| PS sleeps in WFI, runs no application | PS runs Linux as gateway; PS has no key access |
| VexRiscv + FreeRTOS in PL runs all logic | PL is an enclave; VexRiscv + our RTOS is an optional enclave controller (Phase R) |
| DDR3 MIG 512 MB | DDR via PS controller, 1 GB |
| Whole EHR hidden in the image | 128-bit pointer + tag; record stays in the database |
| `KEY_REG` written by software | mailbox commands only |
