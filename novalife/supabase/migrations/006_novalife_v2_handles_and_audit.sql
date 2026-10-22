-- NovaLife v2: opaque tag handles, hash-chained verification audit, consent
-- and erasure records, plus the auth-identity bridge and treating-doctor
-- mapping that the least-privilege policies need.
--
-- Identity model (read before changing any policy):
--   * Supabase auth users are UUIDs; 001/002 already key records/RLS on auth.uid().
--   * The hub domain tables from 004 use short text ids (hub_users.user_id,
--     hub_patients.patient_id). This file adds hub_identity_links to bridge the
--     two worlds so a policy can express "a patient sees only their own rows".
--     Until an admin links a signed-up auth user to a hub_user_id, RLS grants
--     that user nothing (all helpers return null).
--
-- Handle representation: the 64-bit handle is stored as TWO bigint columns
--   handle_hi / handle_lo (upper / lower 32 bits, unsigned 0..4294967295)
--   instead of bytea: JSON/PostgREST-safe, no bytea escaping in clients, and a
--   unique index on the pair. Never expose the raw pair except inside the hub.
--
-- Why each control exists (DPDP Act 2023: consent §6, safeguards §8, audit §10,
--   erasure §13) is documented per table and in supabase/README.md. The section
--   mapping must be re-verified against the notified text. Not legal advice.

create extension if not exists "pgcrypto";

-- ---- enums ----------------------------------------------------------------
do $$ begin
  create type verification_result as enum ('pass', 'fail', 'revoked', 'unknown');
exception when duplicate_object then null;
end $$;

-- ---- auth-identity bridge -------------------------------------------------
-- One row per signed-up user: which hub user (004 text id) are they, and, when
-- that hub user has role 'patient', which patient record (004) are they.
-- patient_id is non-null only for role 'patient' hub users (no cross-table
-- check constraint is possible in Postgres; the gateway enforces this).
create table if not exists public.hub_identity_links (
  auth_uid    uuid primary key references auth.users (id) on delete cascade default auth.uid(),
  hub_user_id text not null unique references public.hub_users (user_id) on delete cascade,
  patient_id  text references public.hub_patients (patient_id) on delete set null,
  created_at  timestamptz not null default now()
);

-- ---- treating-doctor mapping ----------------------------------------------
-- "A doctor sees rows of patients they treat" resolves through this table
-- rather than a column on hub_patients (004): a patient may have several
-- treating doctors, and this file does not alter the 004 tables.
create table if not exists public.hub_treating_doctors (
  patient_id     text not null references public.hub_patients (patient_id) on delete cascade,
  doctor_user_id text not null references public.hub_users (user_id) on delete cascade,
  since          timestamptz not null default now(),
  primary key (patient_id, doctor_user_id)
);

-- ---- tag_handles ----------------------------------------------------------
-- One row per marked image: the 128-bit block (D2) is version 4 + hub_id 12 +
-- handle 64 + tag 48, but only the opaque 64-bit handle lives here; the record
-- itself stays in the database and the image carries a pointer plus tag.
-- record_ref references hub_scans (004): the scan row owns image_path, so a
-- handle always resolves to the marked image and, through it, the patient.
-- perceptual_hash is a coarse server-side hash (16-64 bytes) used to detect
-- swapped images: same handle, different picture.
create table if not exists public.tag_handles (
  id               uuid primary key default gen_random_uuid(),
  handle_hi        bigint not null check (handle_hi between 0 and 4294967295),
  handle_lo        bigint not null check (handle_lo between 0 and 4294967295),
  hub_id           smallint not null check (hub_id between 0 and 4095),
  record_ref       text not null references public.hub_scans (scan_id) on delete restrict,
  issued_at        timestamptz not null default now(),
  issued_by        text not null references public.hub_users (user_id) on delete restrict,
  revoked_at       timestamptz,
  perceptual_hash  bytea check (perceptual_hash is null or length(perceptual_hash) between 16 and 64),
  constraint tag_handles_revoke_after_issue
    check (revoked_at is null or revoked_at >= issued_at)
);

create unique index if not exists tag_handles_handle_uidx
  on public.tag_handles (handle_hi, handle_lo);
create index if not exists tag_handles_issued_by_idx
  on public.tag_handles (issued_by);
create index if not exists tag_handles_record_idx
  on public.tag_handles (record_ref);

-- ---- verification_log -----------------------------------------------------
-- Hash-chained audit: every verification lookup (from the app or the hub) is
-- appended here. DPDP audit intent (§10 as cited in README): append-only, no
-- UPDATE or DELETE policies exist for this table and table-level privileges
-- for update/delete are revoked from client roles. The hub gateway writes
-- with the service-role key; because a superuser can forge rows the chain is
-- tamper-evident (row_hash recomputable off-box), not tamper-proof.
-- handle_hi/handle_lo have NO foreign key on purpose: an unknown handle must
-- still be loggable (result 'unknown').
create table if not exists public.verification_log (
  id         bigint generated always as identity primary key,
  at         timestamptz not null default now(),
  actor      text references public.hub_users (user_id) on delete set null,
  handle_hi  bigint check (handle_hi is null or handle_hi between 0 and 4294967295),
  handle_lo  bigint check (handle_lo is null or handle_lo between 0 and 4294967295),
  result     verification_result not null,
  reason     text,
  prev_hash  bytea check (prev_hash is null or length(prev_hash) = 32),
  row_hash   bytea not null unique check (length(row_hash) = 32)
);

create index if not exists verification_log_handle_idx
  on public.verification_log (handle_hi, handle_lo);
create index if not exists verification_log_at_idx
  on public.verification_log (at desc);

-- Chain maintenance, purely in SQL: a BEFORE INSERT trigger takes a
-- transaction-scoped advisory lock (re-entrant inside one transaction, so one
-- transaction may append several rows), reads the current tip, sets prev_hash
-- and computes row_hash = sha256 of the canonical field string below.
-- If this trigger is ever dropped, the equivalent insert pattern is:
--   insert into public.verification_log (actor, handle_hi, handle_lo, result, reason, prev_hash)
--   values (:actor, :hi, :lo, :result, :reason,
--           (select row_hash from public.verification_log order by id desc limit 1));
-- and row_hash must then be computed by the client exactly as in this function.
create or replace function public.verification_log_chain_fnx() returns trigger
language plpgsql security invoker set search_path = public, extensions, pg_temp as $$
declare
  tip_hash bytea;
begin
  -- Fixed, permanent key for the audit chain; changing it would silently allow
  -- two concurrent appenders to build diverging chains.
  perform pg_advisory_xact_lock(1903471880237444109);

  select l.row_hash into tip_hash
    from public.verification_log l
   order by l.id desc
   limit 1;

  -- Genesis row carries prev_hash = null.
  new.prev_hash := tip_hash;

  new.row_hash := digest(
    concat_ws('|',
      new.id::text,
      to_char(new.at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS.US'),
      coalesce(new.actor, ''),
      coalesce(new.handle_hi::text, ''),
      coalesce(new.handle_lo::text, ''),
      new.result::text,
      coalesce(new.reason, ''),
      coalesce(encode(new.prev_hash, 'hex'), '')
    ), 'sha256');

  return new;
end $$;

drop trigger if exists verification_log_chain_trg on public.verification_log;
create trigger verification_log_chain_trg
  before insert on public.verification_log
  for each row execute function public.verification_log_chain_fnx();

-- ---- consent_records ------------------------------------------------------
-- Per-purpose granularity (DPDP consent §6 as cited in README): one live row
-- per (patient, purpose); withdrawal stamps withdrawn_at and leaves the row as
-- evidence. A re-grant creates a new row.
create table if not exists public.consent_records (
  id           uuid primary key default gen_random_uuid(),
  patient_id   text not null references public.hub_patients (patient_id) on delete cascade,
  purpose      text not null
    check (purpose in ('diagnosis', 'treatment', 'second_opinion', 'research', 'insurance', 'teaching')),
  scope        text,
  granted_at   timestamptz not null default now(),
  withdrawn_at timestamptz,
  granted_by   text references public.hub_users (user_id) on delete set null,
  constraint consent_records_withdraw_after_grant
    check (withdrawn_at is null or withdrawn_at >= granted_at)
);

create unique index if not exists consent_records_live_purpose_uidx
  on public.consent_records (patient_id, purpose) where withdrawn_at is null;
create index if not exists consent_records_patient_idx
  on public.consent_records (patient_id);

-- ---- erasure_requests -----------------------------------------------------
-- Patient-initiated erasure (DPDP §13 as cited in README; verify the notified
-- section before publication). Status transitions are done by the DPO/admin
-- through the service role: authenticated users may insert a request and read
-- their own, but not move the status.
create table if not exists public.erasure_requests (
  id           uuid primary key default gen_random_uuid(),
  patient_id   text not null references public.hub_patients (patient_id) on delete cascade,
  requested_at timestamptz not null default now(),
  status       text not null default 'pending'
    check (status in ('pending', 'in_progress', 'completed', 'rejected')),
  completed_at timestamptz,
  constraint erasure_requests_completed_consistent
    check ((status = 'completed') = (completed_at is not null))
);

create index if not exists erasure_requests_patient_idx
  on public.erasure_requests (patient_id);

-- ---- identity helpers ------------------------------------------------------
-- Stable SQL helpers used by the policies below. They read only the caller's
-- own identity link, so under RLS they return null for unlinked users and the
-- policies simply match nothing. Do not use these inside policies on
-- hub_identity_links itself (self-reference); that table compares auth.uid()
-- directly.
create or replace function public.hub_current_user_id() returns text
language sql stable security invoker set search_path = public, pg_temp
as $$ select l.hub_user_id from public.hub_identity_links l where l.auth_uid = auth.uid() $$;

create or replace function public.hub_current_patient_id() returns text
language sql stable security invoker set search_path = public, pg_temp
as $$ select l.patient_id from public.hub_identity_links l where l.auth_uid = auth.uid() $$;

-- ---- RLS -------------------------------------------------------------------
alter table public.hub_identity_links    enable row level security;
alter table public.hub_treating_doctors  enable row level security;
alter table public.tag_handles           enable row level security;
alter table public.verification_log      enable row level security;
alter table public.consent_records       enable row level security;
alter table public.erasure_requests      enable row level security;

-- Least-privilege grants. Everything starts closed; roles get only what the
-- policies below express. service_role (the hub gateway / admin tooling)
-- keeps its default grants and bypasses RLS.
revoke all on public.hub_identity_links   from anon, authenticated;
revoke all on public.hub_treating_doctors from anon, authenticated;
revoke all on public.tag_handles          from anon, authenticated;
revoke all on public.verification_log     from anon, authenticated;
revoke all on public.consent_records      from anon, authenticated;
revoke all on public.erasure_requests     from anon, authenticated;

-- The policies below (and 004's read policies) read the hub domain tables, so
-- the client roles need SELECT on them. On Supabase this already exists via
-- the project's default privileges; granted explicitly here so the file is
-- self-sufficient and the intent ("004 hub data is readable by any
-- authenticated user; row visibility is mediated by 004's RLS") is on record.
grant select on public.hub_users, public.hub_patients, public.hub_scans
  to authenticated;

-- Column-level writes keep app roles narrow:
--   hub_identity_links: select only - links are provisioned by an admin with
--     the service role; letting clients insert would let a signed-up user
--     claim any hub_user_id (privilege escalation);
--   tag_handles:      revoke a handle (set revoked_at), never change identity of a row;
--   consent_records:  withdraw consent only;
--   verification_log: SELECT only - append-only, inserts happen via service_role.
grant select                  on public.hub_identity_links to authenticated;
grant select                  on public.hub_treating_doctors to authenticated;
grant select, insert          on public.tag_handles to authenticated;
grant update (revoked_at)     on public.tag_handles to authenticated;
grant select                  on public.verification_log to authenticated;
grant select, insert          on public.consent_records to authenticated;
grant update (withdrawn_at)   on public.consent_records to authenticated;
grant select, insert          on public.erasure_requests to authenticated;

-- Anon: nothing anywhere.
-- (No grants to anon above; RLS is enabled on every table.)

-- hub_identity_links: each auth user sees only their own link (writes are
-- service-role only, per the grants above).
drop policy if exists "hub_identity_links_select_own" on public.hub_identity_links;
create policy "hub_identity_links_select_own"
  on public.hub_identity_links for select to authenticated
  using (auth_uid = auth.uid());

-- hub_treating_doctors: doctor sees their assignments; patient sees who treats them.
drop policy if exists "hub_treating_doctors_select_own" on public.hub_treating_doctors;
create policy "hub_treating_doctors_select_own"
  on public.hub_treating_doctors for select to authenticated
  using (doctor_user_id = public.hub_current_user_id()
      or patient_id = public.hub_current_patient_id());

-- tag_handles: patient sees handles on their own scans; doctor sees handles on
-- scans of patients they treat; lab_tech sees only handles they issued.
-- Patient/doctor scoping joins through hub_scans (004), the record owner.
drop policy if exists "tag_handles_select_own" on public.tag_handles;
create policy "tag_handles_select_own"
  on public.tag_handles for select to authenticated
  using (exists (
    select 1 from public.hub_scans s
     where s.scan_id = tag_handles.record_ref
       and s.patient_id = public.hub_current_patient_id()));

drop policy if exists "tag_handles_select_treating" on public.tag_handles;
create policy "tag_handles_select_treating"
  on public.tag_handles for select to authenticated
  using (exists (
    select 1
      from public.hub_scans s
      join public.hub_treating_doctors td on td.patient_id = s.patient_id
     where s.scan_id = tag_handles.record_ref
       and td.doctor_user_id = public.hub_current_user_id()));

drop policy if exists "tag_handles_select_issued" on public.tag_handles;
create policy "tag_handles_select_issued"
  on public.tag_handles for select to authenticated
  using (issued_by = public.hub_current_user_id());

-- Insert: only the issuing lab_tech may record a handle, and only as themselves.
drop policy if exists "tag_handles_insert_lab_tech" on public.tag_handles;
create policy "tag_handles_insert_lab_tech"
  on public.tag_handles for insert to authenticated
  with check (issued_by = public.hub_current_user_id()
    and exists (select 1 from public.hub_users u
                 where u.user_id = public.hub_current_user_id()
                   and u.role = 'lab_tech'));

-- Update: revocation only (column grant limits writes to revoked_at) and only
-- by the issuer. Handles are never deleted: a revoked handle stays as evidence.
drop policy if exists "tag_handles_update_revoke" on public.tag_handles;
create policy "tag_handles_update_revoke"
  on public.tag_handles for update to authenticated
  using (issued_by = public.hub_current_user_id())
  with check (issued_by = public.hub_current_user_id());

-- verification_log: read-only for clients, scoped like tag_handles. No insert,
-- update or delete policy exists, and the grants above withhold those
-- privileges, so no client can mutate the chain. Writes come from the gateway
-- (service_role); the row_hash chain detects off-box forgery.
drop policy if exists "verification_log_select_own" on public.verification_log;
create policy "verification_log_select_own"
  on public.verification_log for select to authenticated
  using (exists (
    select 1
      from public.tag_handles t
      join public.hub_scans s on s.scan_id = t.record_ref
     where t.handle_hi = verification_log.handle_hi
       and t.handle_lo = verification_log.handle_lo
       and s.patient_id = public.hub_current_patient_id()));

drop policy if exists "verification_log_select_treating" on public.verification_log;
create policy "verification_log_select_treating"
  on public.verification_log for select to authenticated
  using (exists (
    select 1
      from public.tag_handles t
      join public.hub_scans s on s.scan_id = t.record_ref
      join public.hub_treating_doctors td on td.patient_id = s.patient_id
     where t.handle_hi = verification_log.handle_hi
       and t.handle_lo = verification_log.handle_lo
       and td.doctor_user_id = public.hub_current_user_id()));

drop policy if exists "verification_log_select_issued" on public.verification_log;
create policy "verification_log_select_issued"
  on public.verification_log for select to authenticated
  using (actor = public.hub_current_user_id()
      or exists (
        select 1 from public.tag_handles t
         where t.handle_hi = verification_log.handle_hi
           and t.handle_lo = verification_log.handle_lo
           and t.issued_by = public.hub_current_user_id()));

-- consent_records: patient governs their own consent; the treating doctor may
-- read it and may record a grant captured at the point of care.
drop policy if exists "consent_records_select_own" on public.consent_records;
create policy "consent_records_select_own"
  on public.consent_records for select to authenticated
  using (patient_id = public.hub_current_patient_id());

drop policy if exists "consent_records_select_treating" on public.consent_records;
create policy "consent_records_select_treating"
  on public.consent_records for select to authenticated
  using (exists (
    select 1 from public.hub_treating_doctors td
     where td.patient_id = consent_records.patient_id
       and td.doctor_user_id = public.hub_current_user_id()));

drop policy if exists "consent_records_insert_own" on public.consent_records;
create policy "consent_records_insert_own"
  on public.consent_records for insert to authenticated
  with check (patient_id = public.hub_current_patient_id());

drop policy if exists "consent_records_insert_treating" on public.consent_records;
create policy "consent_records_insert_treating"
  on public.consent_records for insert to authenticated
  with check (granted_by = public.hub_current_user_id()
    and exists (
      select 1 from public.hub_treating_doctors td
       where td.patient_id = consent_records.patient_id
         and td.doctor_user_id = public.hub_current_user_id()));

-- Withdrawal: the patient updates their own row (column grant limits writes to
-- withdrawn_at; the withdrawn_at check constraint forces a plain withdrawal).
drop policy if exists "consent_records_update_own" on public.consent_records;
create policy "consent_records_update_own"
  on public.consent_records for update to authenticated
  using (patient_id = public.hub_current_patient_id())
  with check (patient_id = public.hub_current_patient_id());

-- erasure_requests: the patient raises and tracks; the treating doctor sees
-- requests for their patients; status changes are service_role (DPO) only.
drop policy if exists "erasure_requests_select_own" on public.erasure_requests;
create policy "erasure_requests_select_own"
  on public.erasure_requests for select to authenticated
  using (patient_id = public.hub_current_patient_id());

drop policy if exists "erasure_requests_select_treating" on public.erasure_requests;
create policy "erasure_requests_select_treating"
  on public.erasure_requests for select to authenticated
  using (exists (
    select 1 from public.hub_treating_doctors td
     where td.patient_id = erasure_requests.patient_id
       and td.doctor_user_id = public.hub_current_user_id()));

drop policy if exists "erasure_requests_insert_own" on public.erasure_requests;
create policy "erasure_requests_insert_own"
  on public.erasure_requests for insert to authenticated
  with check (patient_id = public.hub_current_patient_id()
    and status = 'pending');

-- ---- seed (idempotent; only ids that 005 already created, nothing generated)
-- Deliberately NO hub_identity_links seed rows: auth_uid references
-- auth.users(id), and auth.uids are generated at sign-up, which data
-- migrations must not reference. Links are created out-of-band by an admin
-- with the service role once the matching auth user exists, e.g.
--   insert into public.hub_identity_links (auth_uid, hub_user_id, patient_id)
--   values ('<auth-uuid>', 'patient_001', 'PAT-001');
-- The patient_001 <-> PAT-001 mapping intended by 005 is the ABHA id
-- 12345678901234 shared by hub_users (role patient) and hub_patients.

-- doctor_001 (005) treats the three ABHA-mapped patients; adjust as care teams change.
insert into public.hub_treating_doctors (patient_id, doctor_user_id)
select p.patient_id, u.user_id
  from public.hub_patients p
  cross join public.hub_users u
 where u.user_id = 'doctor_001'
   and p.patient_id in ('PAT-001', 'PAT-002', 'PAT-003')
on conflict (patient_id, doctor_user_id) do nothing;
