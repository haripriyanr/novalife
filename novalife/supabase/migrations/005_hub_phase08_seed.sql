-- Phase 08 seed data: 5 patients, 10 scans, 10 reports, 3 users, 5 notes.

-- Roles are implicit via user_role enum; seed users.
insert into public.hub_users (user_id, full_name, role, abha_id) values
  ('lab_tech_001', 'Priya Sharma',     'lab_tech', null),
  ('doctor_001',   'Dr. Rajesh Gupta', 'doctor',   null),
  ('patient_001',  'Anjali Mehta',     'patient',  '12345678901234')
on conflict (user_id) do nothing;

-- 5 patients with 14-digit ABHA IDs
insert into public.hub_patients (patient_id, abha_id, full_name, dob, gender, phone) values
  ('PAT-001', '12345678901234', 'Anjali Mehta',  '1990-03-15', 'F', '+91-9876543210'),
  ('PAT-002', '23456789012345', 'Ravi Kumar',    '1985-07-22', 'M', '+91-9876543211'),
  ('PAT-003', '34567890123456', 'Sunita Patel',  '1978-11-08', 'F', '+91-9876543212'),
  ('PAT-004', '45678901234567', 'Arjun Reddy',   '1995-01-30', 'M', '+91-9876543213'),
  ('PAT-005', '56789012345678', 'Meera Joshi',   '2000-09-12', 'F', '+91-9876543214')
on conflict (patient_id) do nothing;

-- 10 synthetic scans
insert into public.hub_scans (scan_id, patient_id, sha256, image_path, stego_bytes, board_ip) values
  ('SCN-001', 'PAT-001', repeat('a',64), 'scans/PAT-001/scan_001.png', 512,  '192.168.1.101'),
  ('SCN-002', 'PAT-001', repeat('b',64), 'scans/PAT-001/scan_002.png', 1024, '192.168.1.101'),
  ('SCN-003', 'PAT-002', repeat('c',64), 'scans/PAT-002/scan_003.png', 768,  '192.168.1.101'),
  ('SCN-004', 'PAT-002', repeat('d',64), 'scans/PAT-002/scan_004.png', 256,  '192.168.1.102'),
  ('SCN-005', 'PAT-003', repeat('e',64), 'scans/PAT-003/scan_005.png', 1024, '192.168.1.101'),
  ('SCN-006', 'PAT-003', repeat('f',64), 'scans/PAT-003/scan_006.png', 512,  '192.168.1.102'),
  ('SCN-007', 'PAT-004', repeat('0',64), 'scans/PAT-004/scan_007.png', 1024, '192.168.1.101'),
  ('SCN-008', 'PAT-004', repeat('1',64), 'scans/PAT-004/scan_008.png', 256,  '192.168.1.102'),
  ('SCN-009', 'PAT-005', repeat('2',64), 'scans/PAT-005/scan_009.png', 512,  '192.168.1.101'),
  ('SCN-010', 'PAT-005', repeat('3',64), 'scans/PAT-005/scan_010.png', 768,  '192.168.1.102')
on conflict (scan_id) do nothing;

-- 10 reports
insert into public.hub_reports (report_id, patient_id, scan_id, title, body, report_type) values
  ('RPT-001', 'PAT-001', 'SCN-001', 'CBC — Complete Blood Count',          'Hemoglobin 12.4 g/dL, WBC 7200, Platelets 2.4L. Within normal limits.',              'lab'),
  ('RPT-002', 'PAT-001', 'SCN-002', 'Chest X-Ray PA View',                 'Clear lung fields. No cardiomegaly. Normal mediastinum.',                              'imaging'),
  ('RPT-003', 'PAT-002', 'SCN-003', 'Fasting Lipid Panel',                 'Total cholesterol 210 mg/dL, LDL 140, HDL 38. Borderline high LDL.',                   'lab'),
  ('RPT-004', 'PAT-002', 'SCN-004', 'MRI Brain — Contrast Enhanced',       'No intracranial mass. Normal ventricles. White matter hyperintensities Fazekas 1.',     'imaging'),
  ('RPT-005', 'PAT-003', 'SCN-005', 'Renal Function Panel',                'Creatinine 1.1 mg/dL, BUN 18, eGFR 72. Mildly reduced GFR stage 2 CKD.',              'lab'),
  ('RPT-006', 'PAT-003', 'SCN-006', 'Abdominal Ultrasound',                'Liver echogenicity normal. No gallstones. Kidneys normal size bilaterally.',            'imaging'),
  ('RPT-007', 'PAT-004', 'SCN-007', 'HbA1c — Diabetes Screen',            'HbA1c 6.8%. Pre-diabetic range. Recommend lifestyle modification.',                    'lab'),
  ('RPT-008', 'PAT-004', 'SCN-008', 'Discharge Summary — Appendectomy',    'Laparoscopic appendectomy performed. Uncomplicated. Discharged day 2.',                  'discharge'),
  ('RPT-009', 'PAT-005', 'SCN-009', 'Thyroid Profile',                     'TSH 2.4 mIU/L, Free T4 1.1 ng/dL. Normal thyroid function.',                           'lab'),
  ('RPT-010', 'PAT-005', 'SCN-010', 'Clinical Consultation — Dermatology', 'Eczema on bilateral forearms. Prescribed moisturizer + mild topical steroid.',          'clinical')
on conflict (report_id) do nothing;

-- 5 doctor notes
insert into public.hub_doctor_notes (note_id, report_id, user_id, note_text) values
  ('NT-001', 'RPT-001', 'doctor_001', 'Values normal. No follow-up needed unless symptomatic.'),
  ('NT-002', 'RPT-002', 'doctor_001', 'Imaging unremarkable. Annual chest X-ray recommended.'),
  ('NT-003', 'RPT-003', 'doctor_001', 'LDL elevated. Start statin therapy if no contraindication. Recheck in 3 months.'),
  ('NT-004', 'RPT-007', 'doctor_001', 'Pre-diabetic. Referral to dietitian. HbA1c recheck in 6 months.'),
  ('NT-005', 'RPT-010', 'doctor_001', 'Eczema stable. Follow up if no improvement in 2 weeks.')
on conflict (note_id) do nothing;
