"""SQLite schema definitions for the SD Vault.

Tables:
  users         — lab_tech_001, doctor_001, patient_001 with role
  patients      — 5 patients with 14-digit ABHA IDs
  scans         — 10 synthetic scan references (stego PNG metadata)
  reports       — 10 fake diagnostic reports linked to patients
  doctor_notes  — free-text notes doctors add to reports
  roles         — role lookup (patient, doctor, lab_tech)
"""

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS roles (
    role_id   INTEGER PRIMARY KEY,
    role_name TEXT    NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS users (
    user_id   TEXT    PRIMARY KEY,
    password  TEXT    NOT NULL DEFAULT 'changeme',
    full_name TEXT    NOT NULL,
    role_id   INTEGER NOT NULL REFERENCES roles(role_id),
    abha_id   TEXT,
    created_at TEXT   DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS patients (
    patient_id TEXT PRIMARY KEY,
    abha_id    TEXT NOT NULL UNIQUE CHECK (length(abha_id) = 14),
    full_name  TEXT NOT NULL,
    dob        TEXT,
    gender     TEXT CHECK (gender IN ('M','F','O')),
    phone      TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS scans (
    scan_id     TEXT PRIMARY KEY,
    patient_id  TEXT NOT NULL REFERENCES patients(patient_id),
    sha256      TEXT NOT NULL CHECK (length(sha256) = 64),
    image_path  TEXT NOT NULL,
    stego_bytes INTEGER CHECK (stego_bytes > 0),
    board_ip    TEXT,
    created_at  TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS reports (
    report_id   TEXT PRIMARY KEY,
    patient_id  TEXT NOT NULL REFERENCES patients(patient_id),
    scan_id     TEXT REFERENCES scans(scan_id),
    title       TEXT NOT NULL,
    body        TEXT,
    report_type TEXT CHECK (report_type IN ('lab','imaging','clinical','discharge')),
    created_at  TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS doctor_notes (
    note_id    TEXT PRIMARY KEY,
    report_id  TEXT NOT NULL REFERENCES reports(report_id),
    user_id    TEXT NOT NULL REFERENCES users(user_id),
    note_text  TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now'))
);
"""

# ---------------------------------------------------------------------------
# Mock data — 3 user roles, 3 user accounts, 5 patients, 10 scans, 10 reports, 5 notes
# ---------------------------------------------------------------------------

MOCK_USERS = [
    {"user_id": "lab_tech_001",   "password": "lab@1234",   "full_name": "Priya Sharma",   "role_id": 1},
    {"user_id": "doctor_001",     "password": "doc@1234",   "full_name": "Dr. Rajesh Gupta", "role_id": 2},
    {"user_id": "patient_001",    "password": "pat@1234",   "full_name": "Anjali Mehta",    "role_id": 3},
]

MOCK_PATIENTS = [
    {"patient_id": "PAT-001", "abha_id": "12345678901234", "full_name": "Anjali Mehta",       "dob": "1990-03-15", "gender": "F", "phone": "+91-9876543210"},
    {"patient_id": "PAT-002", "abha_id": "23456789012345", "full_name": "Ravi Kumar",         "dob": "1985-07-22", "gender": "M", "phone": "+91-9876543211"},
    {"patient_id": "PAT-003", "abha_id": "34567890123456", "full_name": "Sunita Patel",       "dob": "1978-11-08", "gender": "F", "phone": "+91-9876543212"},
    {"patient_id": "PAT-004", "abha_id": "45678901234567", "full_name": "Arjun Reddy",        "dob": "1995-01-30", "gender": "M", "phone": "+91-9876543213"},
    {"patient_id": "PAT-005", "abha_id": "56789012345678", "full_name": "Meera Joshi",        "dob": "2000-09-12", "gender": "F", "phone": "+91-9876543214"},
]

MOCK_SCANS = [
    {"scan_id": "SCN-001", "patient_id": "PAT-001", "sha256": "a" * 64, "image_path": "scans/PAT-001/scan_001.png", "stego_bytes": 512, "board_ip": "192.168.1.101"},
    {"scan_id": "SCN-002", "patient_id": "PAT-001", "sha256": "b" * 64, "image_path": "scans/PAT-001/scan_002.png", "stego_bytes": 1024, "board_ip": "192.168.1.101"},
    {"scan_id": "SCN-003", "patient_id": "PAT-002", "sha256": "c" * 64, "image_path": "scans/PAT-002/scan_003.png", "stego_bytes": 768, "board_ip": "192.168.1.101"},
    {"scan_id": "SCN-004", "patient_id": "PAT-002", "sha256": "d" * 64, "image_path": "scans/PAT-002/scan_004.png", "stego_bytes": 256, "board_ip": "192.168.1.102"},
    {"scan_id": "SCN-005", "patient_id": "PAT-003", "sha256": "e" * 64, "image_path": "scans/PAT-003/scan_005.png", "stego_bytes": 1024, "board_ip": "192.168.1.101"},
    {"scan_id": "SCN-006", "patient_id": "PAT-003", "sha256": "f" * 64, "image_path": "scans/PAT-003/scan_006.png", "stego_bytes": 512, "board_ip": "192.168.1.102"},
    {"scan_id": "SCN-007", "patient_id": "PAT-004", "sha256": "0" * 64, "image_path": "scans/PAT-004/scan_007.png", "stego_bytes": 1024, "board_ip": "192.168.1.101"},
    {"scan_id": "SCN-008", "patient_id": "PAT-004", "sha256": "1" * 64, "image_path": "scans/PAT-004/scan_008.png", "stego_bytes": 256, "board_ip": "192.168.1.102"},
    {"scan_id": "SCN-009", "patient_id": "PAT-005", "sha256": "2" * 64, "image_path": "scans/PAT-005/scan_009.png", "stego_bytes": 512, "board_ip": "192.168.1.101"},
    {"scan_id": "SCN-010", "patient_id": "PAT-005", "sha256": "3" * 64, "image_path": "scans/PAT-005/scan_010.png", "stego_bytes": 768, "board_ip": "192.168.1.102"},
]

MOCK_REPORTS = [
    {"report_id": "RPT-001", "patient_id": "PAT-001", "scan_id": "SCN-001", "title": "CBC — Complete Blood Count",          "body": "Hemoglobin 12.4 g/dL, WBC 7200, Platelets 2.4L. Within normal limits.",       "report_type": "lab"},
    {"report_id": "RPT-002", "patient_id": "PAT-001", "scan_id": "SCN-002", "title": "Chest X-Ray PA View",                 "body": "Clear lung fields. No cardiomegaly. Normal mediastinum.",                       "report_type": "imaging"},
    {"report_id": "RPT-003", "patient_id": "PAT-002", "scan_id": "SCN-003", "title": "Fasting Lipid Panel",                 "body": "Total cholesterol 210 mg/dL, LDL 140, HDL 38. Borderline high LDL.",            "report_type": "lab"},
    {"report_id": "RPT-004", "patient_id": "PAT-002", "scan_id": "SCN-004", "title": "MRI Brain — Contrast Enhanced",       "body": "No intracranial mass. Normal ventricles. White matter hyperintensities Fazekas 1.", "report_type": "imaging"},
    {"report_id": "RPT-005", "patient_id": "PAT-003", "scan_id": "SCN-005", "title": "Renal Function Panel",                "body": "Creatinine 1.1 mg/dL, BUN 18, eGFR 72. Mildly reduced GFR stage 2 CKD.",       "report_type": "lab"},
    {"report_id": "RPT-006", "patient_id": "PAT-003", "scan_id": "SCN-006", "title": "Abdominal Ultrasound",                "body": "Liver echogenicity normal. No gallstones. Kidneys normal size bilaterally.",     "report_type": "imaging"},
    {"report_id": "RPT-007", "patient_id": "PAT-004", "scan_id": "SCN-007", "title": "HbA1c — Diabetes Screen",            "body": "HbA1c 6.8%. Pre-diabetic range. Recommend lifestyle modification.",             "report_type": "lab"},
    {"report_id": "RPT-008", "patient_id": "PAT-004", "scan_id": "SCN-008", "title": "Discharge Summary —-appendectomy",    "body": "Laparoscopic appendectomy performed. Uncomplicated. Discharged day 2.",          "report_type": "discharge"},
    {"report_id": "RPT-009", "patient_id": "PAT-005", "scan_id": "SCN-009", "title": "Thyroid Profile",                    "body": "TSH 2.4 mIU/L, Free T4 1.1 ng/dL. Normal thyroid function.",                   "report_type": "lab"},
    {"report_id": "RPT-010", "patient_id": "PAT-005", "scan_id": "SCN-010", "title": "Clinical Consultation — Dermatology", "body": "Eczema on bilateral forearms. Prescribed moisturizer + mild topical steroid.",  "report_type": "clinical"},
]

MOCK_NOTES = [
    {"note_id": "NT-001", "report_id": "RPT-001", "user_id": "doctor_001", "note_text": "Values normal. No follow-up needed unless symptomatic."},
    {"note_id": "NT-002", "report_id": "RPT-002", "user_id": "doctor_001", "note_text": "Imaging unremarkable. Annual chest X-ray recommended."},
    {"note_id": "NT-003", "report_id": "RPT-003", "user_id": "doctor_001", "note_text": "LDL elevated. Start statin therapy if no contraindication. Recheck in 3 months."},
    {"note_id": "NT-004", "report_id": "RPT-007", "user_id": "doctor_001", "note_text": "Pre-diabetic. Referral to dietitian. HbA1c recheck in 6 months."},
    {"note_id": "NT-005", "report_id": "RPT-010", "user_id": "doctor_001", "note_text": "Eczema stable. Follow up if no improvement in 2 weeks."},
]

MOCK_ROLES = [
    {"role_id": 1, "role_name": "lab_tech"},
    {"role_id": 2, "role_name": "doctor"},
    {"role_id": 3, "role_name": "patient"},
]
