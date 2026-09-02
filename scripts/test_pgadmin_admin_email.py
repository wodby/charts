#!/usr/bin/env python3

import importlib.util
import sqlite3
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "pgadmin" / "files" / "reconcile-admin-email.py"
SPEC = importlib.util.spec_from_file_location("pgadmin_admin_email", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ReconcileAdminEmailTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.data_directory = Path(self.temporary_directory.name)
        self.database_path = self.data_directory / "pgadmin4.db"
        self.storage_root = self.data_directory / "storage"
        self.marker_path = self.data_directory / ".wodby-admin-email"

    def tearDown(self):
        self.temporary_directory.cleanup()

    def create_database(self, users):
        connection = sqlite3.connect(self.database_path)
        connection.execute(
            'CREATE TABLE "user" ('
            "id INTEGER PRIMARY KEY, username VARCHAR(256) NOT NULL UNIQUE, "
            "email VARCHAR(256), password VARCHAR NOT NULL)"
        )
        connection.executemany(
            'INSERT INTO "user" (id, username, email, password) VALUES (?, ?, ?, ?)',
            users,
        )
        connection.commit()
        connection.close()

    def users(self):
        connection = sqlite3.connect(self.database_path)
        rows = list(connection.execute('SELECT id, username, email, password FROM "user" ORDER BY id'))
        connection.close()
        return rows

    def test_new_database_is_left_for_the_pgadmin_entrypoint(self):
        changed = MODULE.reconcile_admin_email(
            "user@domain.com", self.database_path, self.storage_root, self.marker_path
        )

        self.assertFalse(changed)
        self.assertFalse(self.database_path.exists())
        self.assertFalse(self.marker_path.exists())

    def test_existing_single_administrator_is_renamed_in_place(self):
        self.create_database([(1, "pgadmin@wodby.com", "pgadmin@wodby.com", "password-hash")])
        old_storage = self.storage_root / "pgadmin_wodby.com"
        old_storage.mkdir(parents=True)
        (old_storage / "preferences.json").write_text("preserved", encoding="utf-8")

        changed = MODULE.reconcile_admin_email(
            "user@domain.com", self.database_path, self.storage_root, self.marker_path
        )

        self.assertTrue(changed)
        self.assertEqual(
            self.users(), [(1, "user@domain.com", "user@domain.com", "password-hash")]
        )
        self.assertEqual(self.marker_path.read_text(encoding="utf-8"), "user@domain.com\n")
        self.assertFalse(old_storage.exists())
        self.assertEqual(
            (self.storage_root / "user_domain.com" / "preferences.json").read_text(encoding="utf-8"),
            "preserved",
        )

    def test_marker_makes_later_changes_unambiguous(self):
        self.create_database(
            [
                (1, "user@domain.com", "user@domain.com", "password-hash"),
                (2, "other@example.com", "other@example.com", "other-password-hash"),
            ]
        )
        self.marker_path.write_text("user@domain.com\n", encoding="utf-8")

        changed = MODULE.reconcile_admin_email(
            "admin@example.com", self.database_path, self.storage_root, self.marker_path
        )

        self.assertTrue(changed)
        self.assertEqual(
            self.users(),
            [
                (1, "admin@example.com", "admin@example.com", "password-hash"),
                (2, "other@example.com", "other@example.com", "other-password-hash"),
            ],
        )

    def test_first_reconciliation_refuses_ambiguous_users(self):
        self.create_database(
            [
                (1, "first@example.com", "first@example.com", "first-password-hash"),
                (2, "second@example.com", "second@example.com", "second-password-hash"),
            ]
        )

        with self.assertRaisesRegex(RuntimeError, "contains 2 users"):
            MODULE.reconcile_admin_email(
                "admin@example.com", self.database_path, self.storage_root, self.marker_path
            )

        self.assertEqual(
            self.users(),
            [
                (1, "first@example.com", "first@example.com", "first-password-hash"),
                (2, "second@example.com", "second@example.com", "second-password-hash"),
            ],
        )

    def test_retries_storage_move_after_database_update(self):
        self.create_database([(1, "user@domain.com", "user@domain.com", "password-hash")])
        self.marker_path.write_text("pgadmin@wodby.com\n", encoding="utf-8")
        old_storage = self.storage_root / "pgadmin_wodby.com"
        new_storage = self.storage_root / "user_domain.com"
        old_storage.mkdir(parents=True)
        new_storage.mkdir(parents=True)
        (old_storage / "old.txt").write_text("old", encoding="utf-8")
        (new_storage / "new.txt").write_text("new", encoding="utf-8")

        changed = MODULE.reconcile_admin_email(
            "user@domain.com", self.database_path, self.storage_root, self.marker_path
        )

        self.assertFalse(changed)
        self.assertFalse(old_storage.exists())
        self.assertEqual((new_storage / "old.txt").read_text(encoding="utf-8"), "old")
        self.assertEqual((new_storage / "new.txt").read_text(encoding="utf-8"), "new")
        self.assertEqual(self.marker_path.read_text(encoding="utf-8"), "user@domain.com\n")


if __name__ == "__main__":
    unittest.main()
