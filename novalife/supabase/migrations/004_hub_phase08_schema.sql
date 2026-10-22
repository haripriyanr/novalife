-- Phase 08: HUB user accounts, patients, reports, doctor-notes tables.
-- Extends the Phase 07 records schema with role-based access.

-- Role enum type
do $$ begin
  create type user_role as enum ('patient', 'doctor', 'lab_tech');
exception when duplicate_object then null;
end $$;

-- Users table (lab_tech_001, doctor_001, patient_001)
create table if not exists public.hub_users (
  user_id    text primary key,
  full_name  text not null,
  role       user_role not null,
  abha_id    text check (abha_id is null or length(abha_id) = 14),
  created_at timestamptz not null default now()
);

-- Patients table (5 mock patients with 14-digit ABHA IDs)
create table if not exists public.hub_patients (
  patient_id text primary key,
  abha_id    text not null unique check (length(abha_id) = 14),
  full_name  text not null,
  dob        date,
  gender     text check (gender in ('M','F','O')),
  phone      text,
  created_at timestamptz not null default now()
);

-- Scans table (synthetic scan metadata)
create table if not exists public.hub_scans (
  scan_id     text primary key,
  patient_id  text not null references public.hub_patients(patient_id) on delete cascade,
  sha256      text not null check (length(sha256) = 64),
  image_path  text not null,
  stego_bytes integer check (stego_bytes > 0),
  board_ip    text,
  created_at  timestamptz not null default now()
);

create index if not exists hub_scans_patient_idx
  on public.hub_scans (patient_id, created_at desc);

-- Reports table (10 mock reports)
create table if not exists public.hub_reports (
  report_id   text primary key,
  patient_id  text not null references public.hub_patients(patient_id) on delete cascade,
  scan_id     text,
  title       text not null,
  body        text,
  report_type text check (report_type in ('lab','imaging','clinical','discharge')),
  created_at  timestamptz not null default now()
);

create index if not exists hub_reports_patient_idx
  on public.hub_reports (patient_id, created_at desc);

-- Doctor notes table
create table if not exists public.hub_doctor_notes (
  note_id    text primary key,
  report_id  text not null references public.hub_reports(report_id) on delete cascade,
  user_id    text not null references public.hub_users(user_id),
  note_text  text not null,
  created_at timestamptz not null default now()
);

create index if not exists hub_notes_report_idx
  on public.hub_doctor_notes (report_id, created_at desc);

-- RLS: authenticated users can read all hub data (clinical shared workspace)
alter table public.hub_users enable row level security;
alter table public.hub_patients enable row level security;
alter table public.hub_scans enable row level security;
alter table public.hub_reports enable row level security;
alter table public.hub_doctor_notes enable row level security;

-- Read policies (any authenticated user)
drop policy if exists "hub_users_read" on public.hub_users;
create policy "hub_users_read" on public.hub_users for select to authenticated using (true);

drop policy if exists "hub_patients_read" on public.hub_patients;
create policy "hub_patients_read" on public.hub_patients for select to authenticated using (true);

drop policy if exists "hub_scans_read" on public.hub_scans;
create policy "hub_scans_read" on public.hub_scans for select to authenticated using (true);

drop policy if exists "hub_reports_read" on public.hub_reports;
create policy "hub_reports_read" on public.hub_reports for select to authenticated using (true);

drop policy if exists "hub_notes_read" on public.hub_doctor_notes;
create policy "hub_notes_read" on public.hub_doctor_notes for select to authenticated using (true);

-- Insert policies (doctors and lab_techs can write notes)
drop policy if exists "hub_notes_insert" on public.hub_doctor_notes;
create policy "hub_notes_insert" on public.hub_doctor_notes
  for insert to authenticated
  with check (true);
