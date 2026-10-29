-- 015_job_priority_board_pick.sql -- doctor jobs ahead of lab jobs, chosen by the board
--
-- Owner decision 2026-10-29: the BOARD enforces priority; the database only stores it.  So:
--   * hub_jobs.priority is set server-side from the caller's hospital role (doctor = 2, everyone else
--     = 0) by a BEFORE INSERT trigger.  Whatever the app sends is overwritten, so no app can make its
--     own job urgent.
--   * hub_device_peek lists the queued jobs (id, kind, priority, age) without claiming anything; the
--     board picks one (its rule: priority * 60 + age in seconds, ties to the older job, so a lab job
--     that has waited 2 minutes longer than a doctor job goes first -- nobody starves).
--   * hub_device_claim_job claims exactly the job the board picked, atomically.
-- hub_device_claim (FCFS) is kept unchanged so firmware that does not know these RPCs still works.

begin;

alter table public.hub_jobs add column if not exists priority smallint not null default 0;

create or replace function public.hub_job_set_priority() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  new.priority := case (select u.role::text
                          from public.hub_identity_links l
                          join public.hub_users u on u.user_id = l.hub_user_id
                         where l.auth_uid = new.auth_uid)
                    when 'doctor' then 2
                    else 0
                  end;
  return new;
end $$;
drop trigger if exists hub_job_set_priority_trg on public.hub_jobs;
create trigger hub_job_set_priority_trg before insert on public.hub_jobs
  for each row execute function public.hub_job_set_priority();

-- crashed device: re-queue stale running jobs (3 attempts), then fail them (same rule as hub_device_claim)
create or replace function public.hub_requeue_stale() returns void
language sql security definer set search_path = public, pg_temp as $$
  update public.hub_jobs set status = 'queued', device_id = null, claimed_at = null
   where status = 'running' and claimed_at < now() - interval '120 seconds' and attempts < 3;
  update public.hub_jobs set status = 'failed', error = 'device timeout', finished_at = now()
   where status = 'running' and claimed_at < now() - interval '120 seconds' and attempts >= 3;
$$;

create or replace function public.hub_device_peek(p_device text, p_secret text)
returns table (job_id uuid, kind text, priority smallint, age_s int)
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not public.hub_device_auth(p_device, p_secret) then
    raise exception 'device not authorised' using errcode = '28000';
  end if;
  update public.hub_devices set last_seen_at = now() where device_id = p_device;
  perform public.hub_requeue_stale();
  return query
    select j.job_id, j.kind, j.priority, extract(epoch from now() - j.created_at)::int
      from public.hub_jobs j
     where j.status = 'queued'
     order by j.created_at, j.job_id
     limit 32;
end $$;

create or replace function public.hub_device_claim_job(p_device text, p_secret text, p_job uuid)
returns setof public.hub_jobs
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare j public.hub_jobs;
begin
  if not public.hub_device_auth(p_device, p_secret) then
    raise exception 'device not authorised' using errcode = '28000';
  end if;
  update public.hub_devices set last_seen_at = now() where device_id = p_device;
  perform public.hub_requeue_stale();

  -- one running job per device
  if exists (select 1 from public.hub_jobs where status = 'running' and device_id = p_device) then
    return;
  end if;

  -- empty result: the job is gone or another claim won it; the board peeks again
  update public.hub_jobs
     set status = 'running', device_id = p_device, claimed_at = now(), attempts = attempts + 1
   where job_id = (select h.job_id from public.hub_jobs h
                    where h.job_id = p_job and h.status = 'queued'
                      for update skip locked)
  returning * into j;
  if found then return next j; end if;
end $$;

revoke all on function public.hub_job_set_priority() from public, anon, authenticated;
revoke all on function public.hub_requeue_stale() from public, anon, authenticated;
revoke all on function public.hub_device_peek(text, text) from public;
revoke all on function public.hub_device_claim_job(text, text, uuid) from public;
grant execute on function public.hub_device_peek(text, text) to anon;
grant execute on function public.hub_device_claim_job(text, text, uuid) to anon;

commit;
