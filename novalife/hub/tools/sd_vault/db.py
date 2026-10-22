"""SD Vault database operations — insert/query functions backed by SQLite.

Provides SDVaultDB class for the NovaLife HUB edge gateway to cache
patient, scan, report, and note data on a local SD card filesystem.
"""

import sqlite3
from pathlib import Path
from typing import Any, Optional

from .schema import (
    SCHEMA_SQL,
    MOCK_USERS,
    MOCK_PATIENTS,
    MOCK_SCANS,
    MOCK_REPORTS,
    MOCK_NOTES,
    MOCK_ROLES,
)


class SDVaultDB:
    """Thin wrapper around a SQLite database file.

    Usage::

        db = SDVaultDB("/run/media/user/DATA/repos/embedded_proj/novalife_hub/tools/sd_vault/vault.db")
        db.init_schema()
        db.seed_mock_data()
        patients = db.get_all_patients()
    """

    def __init__(self, db_path: str | Path):
        self.db_path = str(db_path)
        self._conn: Optional[sqlite3.Connection] = None

    # -- connection helpers --------------------------------------------------

    def connect(self) -> sqlite3.Connection:
        if self._conn is None:
            self._conn = sqlite3.connect(self.db_path)
            self._conn.row_factory = sqlite3.Row
            self._conn.execute("PRAGMA journal_mode=WAL")
            self._conn.execute("PRAGMA foreign_keys=ON")
        return self._conn

    def close(self) -> None:
        if self._conn:
            self._conn.close()
            self._conn = None

    def __enter__(self):
        self.connect()
        return self

    def __exit__(self, *_):
        self.close()

    # -- schema --------------------------------------------------------------

    def init_schema(self) -> None:
        conn = self.connect()
        conn.executescript(SCHEMA_SQL)
        conn.commit()

    def seed_mock_data(self) -> None:
        conn = self.connect()
        cur = conn.cursor()

        # roles
        for r in MOCK_ROLES:
            cur.execute(
                "INSERT OR IGNORE INTO roles (role_id, role_name) VALUES (?, ?)",
                (r["role_id"], r["role_name"]),
            )
        # users
        for u in MOCK_USERS:
            cur.execute(
                "INSERT OR IGNORE INTO users (user_id, password, full_name, role_id) "
                "VALUES (?, ?, ?, ?)",
                (u["user_id"], u["password"], u["full_name"], u["role_id"]),
            )
        # patients
        for p in MOCK_PATIENTS:
            cur.execute(
                "INSERT OR IGNORE INTO patients (patient_id, abha_id, full_name, dob, gender, phone) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (p["patient_id"], p["abha_id"], p["full_name"], p["dob"], p["gender"], p["phone"]),
            )
        # scans
        for s in MOCK_SCANS:
            cur.execute(
                "INSERT OR IGNORE INTO scans (scan_id, patient_id, sha256, image_path, stego_bytes, board_ip) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (s["scan_id"], s["patient_id"], s["sha256"], s["image_path"], s["stego_bytes"], s["board_ip"]),
            )
        # reports
        for r in MOCK_REPORTS:
            cur.execute(
                "INSERT OR IGNORE INTO reports (report_id, patient_id, scan_id, title, body, report_type) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (r["report_id"], r["patient_id"], r["scan_id"], r["title"], r["body"], r["report_type"]),
            )
        # doctor notes
        for n in MOCK_NOTES:
            cur.execute(
                "INSERT OR IGNORE INTO doctor_notes (note_id, report_id, user_id, note_text) "
                "VALUES (?, ?, ?, ?)",
                (n["note_id"], n["report_id"], n["user_id"], n["note_text"]),
            )
        conn.commit()

    # -- query helpers -------------------------------------------------------

    def _row_to_dict(self, row: sqlite3.Row) -> dict[str, Any]:
        return dict(row)

    def _rows_to_list(self, rows: list[sqlite3.Row]) -> list[dict[str, Any]]:
        return [self._row_to_dict(r) for r in rows]

    # -- users ---------------------------------------------------------------

    def get_user(self, user_id: str) -> Optional[dict[str, Any]]:
        cur = self.connect().execute(
            "SELECT u.*, r.role_name FROM users u JOIN roles r ON u.role_id = r.role_id "
            "WHERE u.user_id = ?",
            (user_id,),
        )
        row = cur.fetchone()
        return self._row_to_dict(row) if row else None

    def authenticate_user(self, user_id: str, password: str) -> Optional[dict[str, Any]]:
        cur = self.connect().execute(
            "SELECT u.*, r.role_name FROM users u JOIN roles r ON u.role_id = r.role_id "
            "WHERE u.user_id = ? AND u.password = ?",
            (user_id, password),
        )
        row = cur.fetchone()
        return self._row_to_dict(row) if row else None

    def get_all_users(self) -> list[dict[str, Any]]:
        cur = self.connect().execute(
            "SELECT u.*, r.role_name FROM users u JOIN roles r ON u.role_id = r.role_id"
        )
        return self._rows_to_list(cur.fetchall())

    # -- patients ------------------------------------------------------------

    def get_all_patients(self) -> list[dict[str, Any]]:
        cur = self.connect().execute("SELECT * FROM patients ORDER BY full_name")
        return self._rows_to_list(cur.fetchall())

    def get_patient(self, patient_id: str) -> Optional[dict[str, Any]]:
        cur = self.connect().execute(
            "SELECT * FROM patients WHERE patient_id = ?", (patient_id,)
        )
        row = cur.fetchone()
        return self._row_to_dict(row) if row else None

    def get_patient_by_abha(self, abha_id: str) -> Optional[dict[str, Any]]:
        cur = self.connect().execute(
            "SELECT * FROM patients WHERE abha_id = ?", (abha_id,)
        )
        row = cur.fetchone()
        return self._row_to_dict(row) if row else None

    # -- scans ---------------------------------------------------------------

    def insert_scan(self, **kwargs: Any) -> None:
        cols = ", ".join(kwargs.keys())
        phs = ", ".join(["?"] * len(kwargs))
        self.connect().execute(
            f"INSERT INTO scans ({cols}) VALUES ({phs})", list(kwargs.values())
        )
        self.connect().commit()

    def get_scans_for_patient(self, patient_id: str) -> list[dict[str, Any]]:
        cur = self.connect().execute(
            "SELECT * FROM scans WHERE patient_id = ? ORDER BY created_at DESC",
            (patient_id,),
        )
        return self._rows_to_list(cur.fetchall())

    # -- reports -------------------------------------------------------------

    def get_reports_for_patient(self, patient_id: str) -> list[dict[str, Any]]:
        cur = self.connect().execute(
            "SELECT r.*, s.image_path, s.stego_bytes "
            "FROM reports r LEFT JOIN scans s ON r.scan_id = s.scan_id "
            "WHERE r.patient_id = ? ORDER BY r.created_at DESC",
            (patient_id,),
        )
        return self._rows_to_list(cur.fetchall())

    def get_report(self, report_id: str) -> Optional[dict[str, Any]]:
        cur = self.connect().execute(
            "SELECT r.*, s.image_path, s.stego_bytes "
            "FROM reports r LEFT JOIN scans s ON r.scan_id = s.scan_id "
            "WHERE r.report_id = ?",
            (report_id,),
        )
        row = cur.fetchone()
        return self._row_to_dict(row) if row else None

    # -- doctor notes --------------------------------------------------------

    def insert_note(self, note_id: str, report_id: str, user_id: str, note_text: str) -> None:
        self.connect().execute(
            "INSERT INTO doctor_notes (note_id, report_id, user_id, note_text) VALUES (?, ?, ?, ?)",
            (note_id, report_id, user_id, note_text),
        )
        self.connect().commit()

    def get_notes_for_report(self, report_id: str) -> list[dict[str, Any]]:
        cur = self.connect().execute(
            "SELECT n.*, u.full_name AS doctor_name "
            "FROM doctor_notes n JOIN users u ON n.user_id = u.user_id "
            "WHERE n.report_id = ? ORDER BY n.created_at DESC",
            (report_id,),
        )
        return self._rows_to_list(cur.fetchall())

    # -- summary stats -------------------------------------------------------

    def stats(self) -> dict[str, int]:
        conn = self.connect()
        return {
            "users": conn.execute("SELECT count(*) FROM users").fetchone()[0],
            "patients": conn.execute("SELECT count(*) FROM patients").fetchone()[0],
            "scans": conn.execute("SELECT count(*) FROM scans").fetchone()[0],
            "reports": conn.execute("SELECT count(*) FROM reports").fetchone()[0],
            "doctor_notes": conn.execute("SELECT count(*) FROM doctor_notes").fetchone()[0],
        }
