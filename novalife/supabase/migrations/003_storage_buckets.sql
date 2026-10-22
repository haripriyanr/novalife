-- Phase 07 storage bucket config for stego PNGs.
-- Bucket: medical-images (private). records.image_path points here.

insert into storage.buckets (id, name, public)
values ('medical-images', 'medical-images', false)
on conflict (id) do nothing;

-- Owner-scoped object policies: first folder segment must equal auth.uid().
drop policy if exists "medimg_select_own" on storage.objects;
create policy "medimg_select_own"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'medical-images'
         and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "medimg_insert_own" on storage.objects;
create policy "medimg_insert_own"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'medical-images'
              and (storage.foldername(name))[1] = auth.uid()::text
              and name like '%.png');

drop policy if exists "medimg_update_own" on storage.objects;
create policy "medimg_update_own"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'medical-images'
         and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'medical-images'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "medimg_delete_own" on storage.objects;
create policy "medimg_delete_own"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'medical-images'
         and (storage.foldername(name))[1] = auth.uid()::text);
