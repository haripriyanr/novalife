-- 010_hub_job_queue.sql -- cloud relay: apps queue jobs, the FPGA board claims them (FCFS)
--
-- The board makes OUTBOUND requests only (design D6): it asks `hub_device_claim` for the oldest
-- queued job, runs it in the PL, and reports with `hub_device_complete`.  Supabase never pushes
-- to the board, so the app works from any network.  The board authenticates with a per-device
-- secret (only its sha-256 is stored here; the secret itself lives in the board's SD config, never
-- in git).  Users see and create only their own jobs.
--
-- Scheduling: strict first-come-first-served by created_at, one running job per device,
-- atomic claim (FOR UPDATE SKIP LOCKED => two claims can never get the same job), a job running
-- longer than 120 s is re-queued (device crashed) up to 3 attempts, and a user may have at most
-- 5 queued/running jobs (one user cannot flood the queue).
--
-- Job kinds today: verify_tag (tag fields already extracted: the PL checks the MAC -- works now),
-- verify_image / mark_image (need the PL image pipeline: the board answers 'not_implemented'
-- until it exists; nothing is faked).

begin;

create table if not exists public.hub_devices (
  device_id    text primary key,
  secret_hash  text not null,                -- hex sha-256 of the device secret
  label        text,
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz
);
alter table public.hub_devices enable row level security;       -- no policies: not readable by clients

create table if not exists public.hub_jobs (
  job_id      uuid primary key default gen_random_uuid(),
  auth_uid    uuid not null default auth.uid(),
  user_id     text references public.hub_users (user_id) on delete set null,
  kind        text not null check (kind in ('verify_tag', 'verify_image', 'mark_image')),
  payload     jsonb not null default '{}'::jsonb,
  image_path  text,
  status      text not null default 'queued'
              check (status in ('queued', 'running', 'done', 'failed')),
  result      jsonb,
  error       text,
  device_id   text references public.hub_devices (device_id),
  attempts    int not null default 0,
  created_at  timestamptz not null default now(),
  claimed_at  timestamptz,
  finished_at timestamptz
);
create index if not exists hub_jobs_queue_idx on public.hub_jobs (created_at) where status = 'queued';
create index if not exists hub_jobs_owner_idx on public.hub_jobs (auth_uid, created_at desc);
alter table public.hub_jobs enable row level security;

create or replace function public.hub_active_jobs(uid uuid) returns int
language sql stable security definer set search_path = public, pg_temp as
$$ select count(*)::int from public.hub_jobs where auth_uid = uid and status in ('queued', 'running') $$;

drop policy if exists hub_jobs_select_own on public.hub_jobs;
create policy hub_jobs_select_own on public.hub_jobs
  for select to authenticated using (auth_uid = auth.uid());

drop policy if exists hub_jobs_insert_own on public.hub_jobs;
create policy hub_jobs_insert_own on public.hub_jobs
  for insert to authenticated with check (
    auth_uid = auth.uid()
    and status = 'queued' and result is null and device_id is null and attempts = 0
    and public.hub_active_jobs(auth.uid()) < 5);
-- no update/delete policies: only the board (via the RPCs below) changes a job.
revoke update, delete on public.hub_jobs from anon, authenticated;

create or replace function public.hub_job_fill_user() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  new.user_id := (select l.hub_user_id from public.hub_identity_links l where l.auth_uid = new.auth_uid);
  return new;
end $$;
drop trigger if exists hub_job_fill_user_trg on public.hub_jobs;
create trigger hub_job_fill_user_trg before insert on public.hub_jobs
  for each row execute function public.hub_job_fill_user();

-- ---- device-side RPCs ------------------------------------------------------
create or replace function public.hub_device_auth(p_device text, p_secret text) returns boolean
language sql security definer set search_path = public, extensions, pg_temp as
$$ select exists (select 1 from public.hub_devices d
                   where d.device_id = p_device
                     and d.secret_hash = encode(digest(p_secret, 'sha256'), 'hex')) $$;

create or replace function public.hub_device_claim(p_device text, p_secret text)
returns setof public.hub_jobs
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare j public.hub_jobs;
begin
  if not public.hub_device_auth(p_device, p_secret) then
    raise exception 'device not authorised' using errcode = '28000';
  end if;
  update public.hub_devices set last_seen_at = now() where device_id = p_device;

  -- crashed device: re-queue stale running jobs (3 attempts), then fail them
  update public.hub_jobs set status = 'queued', device_id = null, claimed_at = null
   where status = 'running' and claimed_at < now() - interval '120 seconds' and attempts < 3;
  update public.hub_jobs set status = 'failed', error = 'device timeout', finished_at = now()
   where status = 'running' and claimed_at < now() - interval '120 seconds' and attempts >= 3;

  -- one running job per device
  if exists (select 1 from public.hub_jobs where status = 'running' and device_id = p_device) then
    return;
  end if;

  update public.hub_jobs
     set status = 'running', device_id = p_device, claimed_at = now(), attempts = attempts + 1
   where job_id = (select job_id from public.hub_jobs where status = 'queued'
                    order by created_at, job_id
                      for update skip locked limit 1)
  returning * into j;
  if found then return next j; end if;
end $$;

create or replace function public.hub_device_complete(
  p_device text, p_secret text, p_job uuid, p_ok boolean, p_result jsonb, p_error text)
returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  j public.hub_jobs;
  v_hi bigint; v_lo bigint; v_h text; v_row public.tag_handles; v_res verification_result; v_reason text;
  v_result jsonb := coalesce(p_result, '{}'::jsonb);
begin
  if not public.hub_device_auth(p_device, p_secret) then
    raise exception 'device not authorised' using errcode = '28000';
  end if;
  select * into j from public.hub_jobs where job_id = p_job and device_id = p_device and status = 'running'
    for update;
  if not found then raise exception 'no such running job for this device'; end if;

  if j.kind = 'verify_tag' and p_ok is not null then
    -- the PL decided whether the MAC is genuine; now the server-side checks: handle exists, not revoked
    v_h := lower(j.payload ->> 'handle');
    if v_h ~ '^[0-9a-f]{16}$' then
      v_hi := ('x' || substr(v_h, 1, 8))::bit(32)::bigint;
      v_lo := ('x' || substr(v_h, 9, 8))::bit(32)::bigint;
    end if;
    if not p_ok then
      v_res := 'fail'; v_reason := 'tag MAC rejected by the PL enclave';
    else
      select * into v_row from public.tag_handles where handle_hi = v_hi and handle_lo = v_lo;
      if not found then v_res := 'unknown'; v_reason := 'genuine tag, handle not in the registry';
      elsif v_row.revoked_at is not null then v_res := 'revoked'; v_reason := 'handle revoked';
      else v_res := 'pass'; v_reason := 'tag genuine, handle live';
      end if;
    end if;
    insert into public.verification_log (actor, handle_hi, handle_lo, result, reason)
      values (j.user_id, v_hi, v_lo, v_res, v_reason);
    v_result := v_result || jsonb_build_object('verdict', v_res::text, 'reason', v_reason);
  end if;

  update public.hub_jobs
     set status = case when p_error is null then 'done' else 'failed' end,
         result = v_result, error = p_error, finished_at = now()
   where job_id = p_job;
end $$;

-- the board has no user login: it calls these as anon with its device secret
revoke all on function public.hub_device_claim(text, text) from public;
revoke all on function public.hub_device_complete(text, text, uuid, boolean, jsonb, text) from public;
revoke all on function public.hub_device_auth(text, text) from public, anon, authenticated;
grant execute on function public.hub_device_claim(text, text) to anon;
grant execute on function public.hub_device_complete(text, text, uuid, boolean, jsonb, text) to anon;

commit;
