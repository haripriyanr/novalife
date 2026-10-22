# NovaLife Supabase migrations

Schema for the NovaLife hub: cloud Supabase project `novalife`
(project ref `rtsduiqbgdiyygczivbl`, region `ap-south-1`).

Migrations apply in filename order. `001`–`005` are the Phase 07/08 records
and hub schema (already applied); **`006_novalife_v2_handles_and_audit.sql` is
new** and adds the product tables for opaque tag handles, the hash-chained
verification audit, consent and erasure.

## Applying

**psql (direct, against the cloud project)** — get the connection string from
Dashboard → Project Settings → Database, pass it via the environment (never
commit it):

```sh
export SUPABASE_DB_URL='postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres'
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/006_novalife_v2_handles_and_audit.sql
```

All files are idempotent (`if not exists` / `create or replace` /
`drop policy if exists`), so re-applying is safe.

**Supabase CLI** (from the repo root):

```sh
supabase link --project-ref rtsduiqbgdiyygczivbl
supabase db push          # applies supabase/migrations/* in filename order
```

If the CLI reports the migration history out of sync with what was applied by
psql, reconcile with `supabase migration list` / `supabase migration repair`
before `db push`.

## Tables

| Table | Purpose |
|---|---|
| `records` (001) | Marked PNG uploads keyed to an auth user. |
| `hub_users`, `hub_patients`, `hub_scans`, `hub_reports`, `hub_doctor_notes` (004) | Hub domain: staff/patient accounts, scans, reports, notes. |
| `hub_identity_links` (006) | Bridges Supabase auth UUIDs (`auth.uid()`) to the hub text ids; without a link, RLS grants a user nothing. |
| `hub_treating_doctors` (006) | Which doctors treat which patients; drives doctor-scoped visibility. |
| `tag_handles` (006) | One row per marked image: the opaque 64-bit handle (two bigint columns `handle_hi`/`handle_lo`), hub id, issuer, revocation, record pointer (`hub_scans`), coarse perceptual hash for swap detection. |
| `verification_log` (006) | Append-only, hash-chained audit of every verification lookup (`prev_hash`/`row_hash` maintained by trigger). |
| `consent_records` (006) | Per-purpose consent grants/withdrawals; one live grant per (patient, purpose). |
| `erasure_requests` (006) | Patient-initiated erasure requests and their status. |

## RLS intent (least privilege)

`anon`: nothing. `authenticated`: only what the policies grant. Writes by the
hub gateway (marking, audit appends, admin tasks) use the `service_role` key,
which bypasses RLS; the `row_hash` chain makes audit forgery detectable, though
a superuser can always write — the chain is tamper-evident, not tamper-proof.

- **patient**: sees/withdraws only their own rows (`hub_current_patient_id()`),
  raises their own erasure requests.
- **doctor**: sees rows of patients in `hub_treating_doctors` (their treating
  list), may record a consent grant for a treated patient.
- **lab_tech**: sees only `tag_handles` rows they issued, and the audit rows for
  those handles or their own lookups; may insert a handle and revoke it.
- **`verification_log`**: select-only for every client role — no insert, update
  or delete policy exists and those privileges are revoked from `anon` and
  `authenticated`.

## Why the controls exist (DPDP Act 2023 — not legal advice)

Section mapping is given as commonly cited and **must be re-verified against
the notified DPDP Rules 2025 text before any publication or paper claim.**

| Control | Cited section | Intent |
|---|---|---|
| `consent_records` (per-purpose, grant/withdraw) | consent §6 | Processing needs free, specific, informed consent; withdrawal must be as easy as granting. |
| RLS least privilege, append-only audit | safeguards §8 | Reasonable security safeguards for personal data. |
| `verification_log` hash chain | audit §10 | Every lookup of a patient-linked tag is traceable. |
| `erasure_requests` | erasure §13 | Data subject can ask for erasure; the request itself is tracked. |

Related notes live in `AGENTS.md` (D6: no inbound ports; D10: cloud database)
and `novalife_hub/results/` for measured claims.
