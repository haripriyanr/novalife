-- NovaLife: lock down the `medical-reports` bucket.
-- Run once in the Supabase SQL editor (Dashboard -> SQL). Safe to re-run.
--
-- After this, the bucket is private: files can be read only by their owner, signed in,
-- through the API. Public URLs stop working. Records are also encrypted on the phone, so this
-- is a second lock, not the only one.

update storage.buckets set public = false where id = 'medical-reports';

drop policy if exists "novalife read own records"   on storage.objects;
drop policy if exists "novalife add own records"    on storage.objects;
drop policy if exists "novalife delete own records" on storage.objects;

-- Each user may touch only <their uid>/... inside the bucket.
create policy "novalife read own records" on storage.objects
  for select to authenticated
  using (bucket_id = 'medical-reports' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "novalife add own records" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'medical-reports' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "novalife delete own records" on storage.objects
  for delete to authenticated
  using (bucket_id = 'medical-reports' and (storage.foldername(name))[1] = auth.uid()::text);

-- No update policy on purpose: the app never overwrites a file (upsert is off), so the
-- wrapped vault key and existing records cannot be replaced, only added or deleted.

-- Check: list every policy that applies to the bucket. Remove any older, broader ones
-- (for example a policy that allows "public" or "anon" to select).
select policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'storage' and tablename = 'objects';
