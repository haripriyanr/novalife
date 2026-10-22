# Migration 011 Isolation & Authorization Test Report

- **Date:** 2026-10-22
- **Database:** Supabase project `novalife` (`rtsduiqbgdiyygczivbl.supabase.co`)
- **Target:** `supabase/migrations/011_hub_job_storage.sql` (storage bucket `hub-jobs`, RLS policies, and RPC lifecycle)
- **Status:** PASSED (All isolation checks verified)

---

## 1. Test Methodology

The migration was evaluated in an isolated transaction block testing:
1. **User Isolation**: Impersonating `patient_001` (`fa71e001-0000-4000-8000-000000000001`), `doctor_001` (`d0c70001-0000-4000-8000-000000000001`), and `lab_tech_001` (`83b2d76c-89ab-479b-a79f-4e00095d0627`) via Supabase JWT claims under role `authenticated`.
2. **Cross-Tenant Prevention**: Proving users can write and read only within their own `<auth_uid>/*` path prefix. Cross-folder inserts are rejected by `with check`; cross-folder selects return 0 rows.
3. **Bucket Listing Prevention**: Verified that `select count(*) from storage.objects where bucket_id = 'hub-jobs'` returns strictly the user's own files and never exposes other users' filenames or counts.
4. **Board Scope Limitation**: Proving that the FPGA board (role `anon`):
   - Cannot see any files when idle (0 rows).
   - Cannot see files for jobs that are queued but not yet claimed (0 rows).
   - Upon atomically claiming a job (`hub_device_claim`), can download ONLY that job's specific input file.
   - Cannot see any other user's files during the job.
   - Loses all read access immediately upon job completion (`hub_device_complete`).

---

## 2. Test Execution & Assertions

| Test ID | Role / Actor | Operation | Target Path / Object | Expected Result | Measured Result | Status |
|---|---|---|---|---|---|---|
| **T1.1** | `patient_001` | INSERT | `<patient_uid>/scans/patient_scan.png` | Success (1 row) | 1 row created | **PASS** |
| **T1.2** | `patient_001` | SELECT | `<patient_uid>/scans/patient_scan.png` | 1 row returned | 1 row returned | **PASS** |
| **T1.3** | `patient_001` | INSERT (Cross-user) | `<doctor_uid>/scans/hack.png` | Rejected by RLS | Rejected (RLS policy violation) | **PASS** |
| **T1.4** | `patient_001` | SELECT (Cross-user) | `<doctor_uid>/*` | 0 rows | 0 rows | **PASS** |
| **T2.1** | `doctor_001` | INSERT | `<doctor_uid>/scans/doc_scan.png` | Success (1 row) | 1 row created | **PASS** |
| **T2.2** | `doctor_001` | SELECT | `<doctor_uid>/scans/doc_scan.png` | 1 row returned | 1 row returned | **PASS** |
| **T2.3** | `doctor_001` | SELECT (Cross-user) | `<patient_uid>/*` | 0 rows | 0 rows | **PASS** |
| **T3.1** | `lab_tech_001` | INSERT | `<lab_uid>/scans/lab_scan.png` | Success (1 row) | 1 row created | **PASS** |
| **T3.2** | `lab_tech_001` | SELECT | `<lab_uid>/scans/lab_scan.png` | 1 row returned | 1 row returned | **PASS** |
| **T3.3** | `lab_tech_001` | SELECT (Bucket listing) | `hub-jobs` bucket | Exactly 1 row (own file) | Exactly 1 row (others hidden) | **PASS** |
| **T4.1** | `board-1` (anon) | SELECT (Idle) | `hub-jobs` bucket | 0 rows | 0 rows | **PASS** |
| **T4.2** | `board-1` (anon) | SELECT (Job Queued) | `<patient_uid>/scans/patient_scan.png` | 0 rows (unclaimed) | 0 rows | **PASS** |
| **T4.3** | `board-1` (anon) | RPC Claim | `hub_device_claim('board-1', secret)` | Job returned, status $\to$ running | Job claimed, status = running | **PASS** |
| **T4.4** | `board-1` (anon) | SELECT (Job Running) | `<patient_uid>/scans/patient_scan.png` | 1 row (claimed job) | 1 row returned | **PASS** |
| **T4.5** | `board-1` (anon) | SELECT (Unclaimed) | `<doctor_uid>/*`, `<lab_uid>/*` | 0 rows | 0 rows | **PASS** |
| **T4.6** | `board-1` (anon) | RPC Complete | `hub_device_complete(...)` | Success, status $\to$ done | Status updated to done | **PASS** |
| **T4.7** | `board-1` (anon) | SELECT (Post-complete) | `<patient_uid>/scans/patient_scan.png` | 0 rows (access revoked) | 0 rows | **PASS** |

---

## 3. Findings & Resolution

During initial testing of T4.4, direct subqueries on `public.hub_jobs` inside RLS policies for role `anon` were blocked because `hub_jobs` RLS hides rows from unauthenticated users. This was resolved by creating `security definer` evaluation functions (`public.hub_job_active_image` and `public.hub_job_active_result`) scoped strictly to running jobs. This guarantees that only files actively associated with a running job can be accessed by the hardware device.
