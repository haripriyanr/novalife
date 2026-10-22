-- Phase 07 RLS: owners read/write only their patient_id rows.
alter table public.records enable row level security;

drop policy if exists "records_select_own" on public.records;
create policy "records_select_own"
  on public.records for select
  to authenticated
  using (auth.uid() = patient_id);

drop policy if exists "records_insert_own" on public.records;
create policy "records_insert_own"
  on public.records for insert
  to authenticated
  with check (auth.uid() = patient_id);

drop policy if exists "records_update_own" on public.records;
create policy "records_update_own"
  on public.records for update
  to authenticated
  using (auth.uid() = patient_id)
  with check (auth.uid() = patient_id);

drop policy if exists "records_delete_own" on public.records;
create policy "records_delete_own"
  on public.records for delete
  to authenticated
  using (auth.uid() = patient_id);
