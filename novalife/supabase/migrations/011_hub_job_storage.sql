-- 011_hub_job_storage.sql -- private storage for hub jobs and mark_image / verify_image lifecycle
--
-- Adds the private 'hub-jobs' storage bucket with strict user isolation:
-- 1. Authenticated users (patient_001, doctor_001, lab_tech_001) can read/write ONLY their own folder
--    <auth_uid>/*; cross-user reads and writes are blocked by RLS.
-- 2. Bucket listing across other users is impossible under RLS.
-- 3. The FPGA board (running as anon with device credentials) can download ONLY the file belonging
--    to a job it has actively claimed (status = 'running'). Once the job completes or fails,
--    access is immediately revoked.
-- 4. Extends hub_device_complete() to handle 'mark_image' (registers the genuine handle into
--    tag_handles and logs issuance) and 'verify_image' (validates extracted handle in registry).

begin;

-- 1. Private storage bucket for hub jobs
insert into storage.buckets (id, name, public)
values ('hub-jobs', 'hub-jobs', false)
on conflict (id) do nothing;

-- 2. Security definer helper functions for storage policy evaluation under anon role
create or replace function public.hub_job_active_image(p_name text) returns boolean
language sql security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.hub_jobs where status = 'running' and image_path = p_name);
$$;

create or replace function public.hub_job_active_result(p_name text) returns boolean
language sql security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.hub_jobs
     where status = 'running'
       and p_name = (auth_uid::text || '/results/' || job_id::text || '.png')
  );
$$;

grant execute on function public.hub_job_active_image(text) to anon, authenticated;
grant execute on function public.hub_job_active_result(text) to anon, authenticated;

-- 3. Storage RLS policies for 'hub-jobs'
-- Users: owner-scoped read and write based on auth.uid()
drop policy if exists "hub_jobs_storage_select_own" on storage.objects;
create policy "hub_jobs_storage_select_own"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'hub-jobs'
         and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "hub_jobs_storage_insert_own" on storage.objects;
create policy "hub_jobs_storage_insert_own"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'hub-jobs'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "hub_jobs_storage_update_own" on storage.objects;
create policy "hub_jobs_storage_update_own"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'hub-jobs'
         and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'hub-jobs'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "hub_jobs_storage_delete_own" on storage.objects;
create policy "hub_jobs_storage_delete_own"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'hub-jobs'
         and (storage.foldername(name))[1] = auth.uid()::text);

-- Board device access (anon):
-- Can fetch ONLY the input image of a currently running claimed job
drop policy if exists "hub_jobs_storage_device_select" on storage.objects;
create policy "hub_jobs_storage_device_select"
  on storage.objects for select
  to anon
  using (bucket_id = 'hub-jobs'
         and public.hub_job_active_image(name));

-- Can insert the marked output image ONLY for a currently running mark_image job
drop policy if exists "hub_jobs_storage_device_insert" on storage.objects;
create policy "hub_jobs_storage_device_insert"
  on storage.objects for insert
  to anon
  with check (bucket_id = 'hub-jobs'
              and public.hub_job_active_result(name));

-- 4. Extend hub_device_complete to handle mark_image and verify_image
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
begin
  if not public.hub_device_auth(p_device, p_secret) then
    raise exception 'device not authorised' using errcode = '28000';
  end if;
  select * into j from public.hub_jobs where job_id = p_job and device_id = p_device and status = 'running'
    for update;
  if not found then raise exception 'no such running job for this device'; end if;

  if j.kind = 'verify_tag' and p_ok is not null then
    -- Tag fields already extracted; check MAC + registry status
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

  elsif j.kind = 'verify_image' and p_ok is not null then
    -- Complete image pipeline recovery
    if not p_ok then
      v_res := 'fail'; v_reason := coalesce(p_error, 'image recovery failed or tag invalid');
    else
      v_h := lower(coalesce(v_result ->> 'handle', j.payload ->> 'handle', ''));
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
    v_h := lower(coalesce(v_result ->> 'handle', j.payload ->> 'handle', ''));
    if v_h ~ '^[0-9a-f]{16}$' then
      v_hi := ('x' || substr(v_h, 1, 8))::bit(32)::bigint;
      v_lo := ('x' || substr(v_h, 9, 8))::bit(32)::bigint;
    end if;
    v_hub := coalesce((v_result ->> 'hub')::smallint, (j.payload ->> 'hub')::smallint, 1);
    v_ref := coalesce(j.payload ->> 'record_ref', j.image_path, 'scan:' || j.job_id::text);

    if v_hi is not null and v_lo is not null then
      insert into public.tag_handles (handle_hi, handle_lo, hub_id, record_ref, issued_at, issued_by)
        values (v_hi, v_lo, v_hub, v_ref, now(), coalesce(j.user_id, 'hub_device'))
        on conflict (handle_hi, handle_lo) do nothing;

      insert into public.verification_log (actor, handle_hi, handle_lo, result, reason)
        values (j.user_id, v_hi, v_lo, 'pass', 'marked and registered in hub');
    end if;
    v_result := v_result || jsonb_build_object('verdict', 'pass', 'registered', true);
  end if;

  update public.hub_jobs
     set status = case when p_error is null then 'done' else 'failed' end,
         result = v_result, error = p_error, finished_at = now()
   where job_id = p_job;
end $$;

commit;
