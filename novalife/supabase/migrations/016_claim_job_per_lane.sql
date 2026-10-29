-- 016_claim_job_per_lane.sql -- one running job per board LANE, not per board
--
-- Owner decision 2026-10-29: the board runs verify jobs on CPU1 and mark jobs on CPU0 at the same time,
-- so a doctor's verify does not wait for a lab tech's mark.  The board therefore holds up to two running
-- jobs: one in the verify lane (verify_image, verify_tag) and one in the mark lane (mark_image).
-- hub_device_claim_job now refuses a claim only when that job's lane is already busy on this device.
-- hub_device_claim (FCFS, old firmware) keeps its one-job-per-device rule.

begin;

create or replace function public.hub_job_lane(p_kind text) returns text
language sql immutable set search_path = public, pg_temp as
$$ select case when p_kind = 'mark_image' then 'mark' else 'verify' end $$;

create or replace function public.hub_device_claim_job(p_device text, p_secret text, p_job uuid)
returns setof public.hub_jobs
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare j public.hub_jobs;
declare v_kind text;
begin
  if not public.hub_device_auth(p_device, p_secret) then
    raise exception 'device not authorised' using errcode = '28000';
  end if;
  update public.hub_devices set last_seen_at = now() where device_id = p_device;
  perform public.hub_requeue_stale();

  select kind into v_kind from public.hub_jobs where job_id = p_job;
  if not found then return; end if;

  -- one running job per lane per device
  if exists (select 1 from public.hub_jobs
              where status = 'running' and device_id = p_device
                and public.hub_job_lane(kind) = public.hub_job_lane(v_kind)) then
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

revoke all on function public.hub_device_claim_job(text, text, uuid) from public;
grant execute on function public.hub_device_claim_job(text, text, uuid) to anon;

commit;
