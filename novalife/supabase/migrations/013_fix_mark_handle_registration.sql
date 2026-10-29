-- 013_fix_mark_handle_registration.sql -- a marked image's handle was never registered
--
-- Why: the board reports the handle of a mark_image job as "0x<16 hex>" (image_worker.c), but
-- hub_device_complete only accepted bare "<16 hex>".  The handle was silently dropped, nothing was
-- written to tag_handles, and the job still answered {"registered": true}.  Every image marked by
-- the board then verified as 'unknown' (genuine tag, handle not in the registry).  Found in the
-- 2026-10-29 lab-tech end-to-end test (mark job 490ebd2a, verify job 9ec5a922).
--
-- Fix: accept an optional 0x prefix in all three job kinds, and report 'registered' from what was
-- actually written.  A mark job whose handle cannot be registered (unparseable or already taken)
-- now ends 'failed' with the reason, so the app refuses to upload an image that could never verify.

begin;

create or replace function public.hub_device_complete(
  p_device text, p_secret text, p_job uuid, p_ok boolean, p_result jsonb, p_error text)
returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  j public.hub_jobs;
  v_hi bigint; v_lo bigint; v_hub smallint; v_h text;
  v_row public.tag_handles; v_res verification_result; v_reason text;
  v_result jsonb := coalesce(p_result, '{}'::jsonb);
  v_ref text;
  v_error text := p_error;
  v_n int;
begin
  if not public.hub_device_auth(p_device, p_secret) then
    raise exception 'device not authorised' using errcode = '28000';
  end if;
  select * into j from public.hub_jobs where job_id = p_job and device_id = p_device and status = 'running'
    for update;
  if not found then raise exception 'no such running job for this device'; end if;

  if j.kind = 'verify_tag' and p_ok is not null then
    -- Tag fields already extracted; check MAC + registry status
    v_h := regexp_replace(lower(coalesce(j.payload ->> 'handle', '')), '^0x', '');
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

  elsif j.kind = 'verify_image' and p_ok is not null then
    -- Complete image pipeline recovery
    if not p_ok then
      v_res := 'fail'; v_reason := coalesce(p_error, 'image recovery failed or tag invalid');
    else
      v_h := regexp_replace(lower(coalesce(v_result ->> 'handle', j.payload ->> 'handle', '')), '^0x', '');
      if v_h ~ '^[0-9a-f]{16}$' then
        v_hi := ('x' || substr(v_h, 1, 8))::bit(32)::bigint;
        v_lo := ('x' || substr(v_h, 9, 8))::bit(32)::bigint;
      end if;
      select * into v_row from public.tag_handles where handle_hi = v_hi and handle_lo = v_lo;
      if not found then v_res := 'unknown'; v_reason := 'genuine tag recovered, handle not in the registry';
      elsif v_row.revoked_at is not null then v_res := 'revoked'; v_reason := 'handle revoked';
      else v_res := 'pass'; v_reason := 'tag genuine, handle live';
      end if;
    end if;
    if v_hi is not null and v_lo is not null then
      insert into public.verification_log (actor, handle_hi, handle_lo, result, reason)
        values (j.user_id, v_hi, v_lo, v_res, v_reason);
    end if;
    v_result := v_result || jsonb_build_object('verdict', v_res::text, 'reason', v_reason);

  elsif j.kind = 'mark_image' and p_ok is not null and p_ok = true then
    -- Image successfully marked; register the handle in tag_handles
    v_h := regexp_replace(lower(coalesce(v_result ->> 'handle', j.payload ->> 'handle', '')), '^0x', '');
    if v_h ~ '^[0-9a-f]{16}$' then
      v_hi := ('x' || substr(v_h, 1, 8))::bit(32)::bigint;
      v_lo := ('x' || substr(v_h, 9, 8))::bit(32)::bigint;
    end if;
    v_hub := coalesce((v_result ->> 'hub')::smallint, (j.payload ->> 'hub')::smallint, 1);
    v_ref := coalesce(j.payload ->> 'record_ref', j.image_path, 'scan:' || j.job_id::text);

    v_n := 0;
    if v_hi is not null and v_lo is not null then
      insert into public.tag_handles (handle_hi, handle_lo, hub_id, record_ref, issued_at, issued_by)
        values (v_hi, v_lo, v_hub, v_ref, now(), coalesce(j.user_id, 'hub_device'))
        on conflict (handle_hi, handle_lo) do nothing;
      get diagnostics v_n = row_count;
    end if;

    if v_n = 1 then
      insert into public.verification_log (actor, handle_hi, handle_lo, result, reason)
        values (j.user_id, v_hi, v_lo, 'pass', 'marked and registered in hub');
      v_result := v_result || jsonb_build_object('verdict', 'pass', 'registered', true);
    else
      v_result := v_result || jsonb_build_object('registered', false);
      v_error := coalesce(v_error, case when v_hi is null
        then 'marked, but the board returned no valid handle: not registered'
        else 'marked, but the handle is already registered: not registered' end);
    end if;
  end if;

  update public.hub_jobs
     set status = case when v_error is null then 'done' else 'failed' end,
         result = v_result, error = v_error, finished_at = now()
   where job_id = p_job;
end $$;

commit;
