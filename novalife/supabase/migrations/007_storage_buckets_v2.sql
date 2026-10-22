-- Storage buckets the app actually uses (002/003 only covered medical-images).
-- Owner-scoped: first folder segment must equal auth.uid(), mirroring 003.
-- medical-reports + vault: private. avatars: public read, owner-scoped write.

insert into storage.buckets (id, name, public)
values ('medical-reports', 'medical-reports', false),
       ('vault', 'vault', false),
       ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- ---- medical-reports (private, owner-scoped, PNG + PDF reports) ----
drop policy if exists "medrep_select_own" on storage.objects;
create policy "medrep_select_own"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'medical-reports'
         and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "medrep_insert_own" on storage.objects;
create policy "medrep_insert_own"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'medical-reports'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "medrep_update_own" on storage.objects;
create policy "medrep_update_own"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'medical-reports'
         and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'medical-reports'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "medrep_delete_own" on storage.objects;
create policy "medrep_delete_own"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'medical-reports'
         and (storage.foldername(name))[1] = auth.uid()::text);

-- ---- vault (private, owner-scoped; app path is '<uid>/vault/<file>') ----
drop policy if exists "vault_select_own" on storage.objects;
create policy "vault_select_own"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'vault'
         and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "vault_insert_own" on storage.objects;
create policy "vault_insert_own"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'vault'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "vault_update_own" on storage.objects;
create policy "vault_update_own"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'vault'
         and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'vault'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "vault_delete_own" on storage.objects;
create policy "vault_delete_own"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'vault'
         and (storage.foldername(name))[1] = auth.uid()::text);

-- ---- avatars (public read, owner-scoped write) ----
drop policy if exists "avatars_select_public" on storage.objects;
create policy "avatars_select_public"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'avatars');

drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'avatars'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'avatars'
         and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'avatars'
         and (storage.foldername(name))[1] = auth.uid()::text);
