-- 012_job_insert_hardening.sql -- DRAFT, NOT APPLIED (needs the owner's approval)
--
-- Why: migration 010 lets ANY signed-in account queue any job kind.  The app lets a user pick a role at sign-up
-- (user_metadata), so a self-registered "patient" account could queue `mark_image` jobs and have the board mark
-- images and register handles.  This tightens the insert policy on hub_jobs:
--   * the account must be linked to a hospital user (hub_identity_links),
--   * `mark_image` only for a lab technician (hub_users.role = 'lab_tech'),
--   * the existing rules stay (own rows only, status 'queued', at most 5 active jobs).
-- It also adds `hub_board_status()` so the app can show whether the board is online, without exposing hub_devices.
-- Independent of 009 (does not use its helper functions).

begin;

create or replace function public.hub_is_lab_tech() returns boolean
language sql stable security definer set search_path = public, pg_temp as
$$ select exists (select 1 from public.hub_users u
                   where u.user_id = public.hub_current_user_id() and u.role::text = 'lab_tech') $$;

drop policy if exists hub_jobs_insert_own on public.hub_jobs;
create policy hub_jobs_insert_own on public.hub_jobs
  for insert to authenticated with check (
    auth_uid = auth.uid()
    and public.hub_current_user_id() is not null
    and (kind <> 'mark_image' or public.hub_is_lab_tech())
    and status = 'queued' and result is null and device_id is null and attempts = 0
    and public.hub_active_jobs(auth.uid()) < 5);

create or replace function public.hub_board_status() returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$ select jsonb_build_object(
     'online',  coalesce((select max(last_seen_at) > now() - interval '30 seconds' from public.hub_devices), false),
     'queued',  (select count(*) from public.hub_jobs where status = 'queued'),
     'running', (select count(*) from public.hub_jobs where status = 'running')) $$;
revoke all on function public.hub_board_status() from public, anon;
grant execute on function public.hub_board_status() to authenticated;

commit;
