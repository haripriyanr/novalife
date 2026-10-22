-- 009_rls_patient_isolation.sql  --  Applied with Unassigned Patient Directory access
--
-- Clinical Term: "Unassigned Patient" / "Non-Treating Patient"
--
-- Rule:
--   patient   -> own rows only
--   doctor    -> full demographics and records of patients in hub_treating_doctors ("Assigned Patients").
--                Directory lookup permitted for "Unassigned Patients", but medical reports/scans restricted.
--   lab tech  -> all rows (hospital diagnostics intake)
--   notes     -> written and read only by treating doctors for assigned patients.

begin;

create or replace function public.hub_current_role() returns text
  language sql stable security definer set search_path = public as
$$ select u.role::text from public.hub_users u where u.user_id = public.hub_current_user_id() $$;

create or replace function public.hub_can_see_patient(p text) returns boolean
  language sql stable security definer set search_path = public as
$$
  select p = public.hub_current_patient_id()
      or public.hub_current_role() in ('doctor', 'lab_tech')
$$;

create or replace function public.hub_can_see_patient_records(p text) returns boolean
  language sql stable security definer set search_path = public as
$$
  select p = public.hub_current_patient_id()
      or public.hub_current_role() = 'lab_tech'
      or exists (select 1 from public.hub_treating_doctors td
                 where td.patient_id = p and td.doctor_user_id = public.hub_current_user_id())
$$;

drop policy if exists hub_patients_read on public.hub_patients;
create policy hub_patients_read on public.hub_patients
  for select to authenticated using (public.hub_can_see_patient(patient_id));

drop policy if exists hub_scans_read on public.hub_scans;
create policy hub_scans_read on public.hub_scans
  for select to authenticated using (public.hub_can_see_patient_records(patient_id));

drop policy if exists hub_reports_read on public.hub_reports;
create policy hub_reports_read on public.hub_reports
  for select to authenticated using (public.hub_can_see_patient_records(patient_id));

drop policy if exists hub_notes_read on public.hub_doctor_notes;
create policy hub_notes_read on public.hub_doctor_notes
  for select to authenticated using (
    user_id = public.hub_current_user_id()
    or exists (select 1 from public.hub_reports r
               where r.report_id = hub_doctor_notes.report_id
                 and public.hub_can_see_patient_records(r.patient_id)
                 and public.hub_current_role() <> 'lab_tech'));

drop policy if exists hub_notes_insert on public.hub_doctor_notes;
create policy hub_notes_insert on public.hub_doctor_notes
  for insert to authenticated with check (
    user_id = public.hub_current_user_id()
    and public.hub_current_role() = 'doctor'
    and exists (select 1 from public.hub_reports r
                join public.hub_treating_doctors td on td.patient_id = r.patient_id
                where r.report_id = hub_doctor_notes.report_id
                  and td.doctor_user_id = public.hub_current_user_id()));

commit;
