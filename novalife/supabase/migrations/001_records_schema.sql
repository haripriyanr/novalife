-- NovaLife HUB records schema (Phase 07).
-- Table: records(patient_id, timestamp, image_path, sha256).

create extension if not exists "pgcrypto";

create table if not exists public.records (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  image_path text not null,
  sha256 char(64) not null check (sha256 ~ '^[0-9a-f]{64}$'),
  report_name text,
  stego_bytes integer check (stego_bytes is null or stego_bytes > 0),
  board_ip text,
  constraint records_image_path_check check (image_path ~ '^[A-Za-z0-9_/-]+\.png$')
);

create index if not exists records_patient_time_idx
  on public.records (patient_id, created_at desc);

create unique index if not exists records_sha256_uidx
  on public.records (sha256);
