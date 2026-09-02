#!/usr/bin/env python3

import importlib.util
import stat
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "pgadmin" / "files" / "server-import-entrypoint.py"
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("pgadmin_server_import_entrypoint", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ResolveServerImportEmailTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.database_path = Path(self.temporary_directory.name) / "pgadmin4.db"

    def tearDown(self):
        self.temporary_directory.cleanup()

    def create_database(self, users):
        connection = sqlite3.connect(self.database_path)
        connection.executescript(
            'CREATE TABLE "user" ('
            "id INTEGER PRIMARY KEY, username TEXT NOT NULL, active INTEGER NOT NULL, auth_source TEXT NOT NULL);"
            "CREATE TABLE role (id INTEGER PRIMARY KEY, name TEXT NOT NULL);"
            "CREATE TABLE roles_users (user_id INTEGER NOT NULL, role_id INTEGER NOT NULL);"
            "INSERT INTO role (id, name) VALUES (1, 'Administrator'), (2, 'User');"
        )
        for user_id, username, active, auth_source, role_id in users:
            connection.execute(
                'INSERT INTO "user" (id, username, active, auth_source) VALUES (?, ?, ?, ?)',
                (user_id, username, active, auth_source),
            )
            connection.execute(
                "INSERT INTO roles_users (user_id, role_id) VALUES (?, ?)",
                (user_id, role_id),
            )
        connection.commit()
        connection.close()

    def test_missing_database_keeps_bootstrap_email(self):
        self.assertEqual(
            MODULE.resolve_server_import_email("user@domain.com", self.database_path),
            ("user@domain.com", False),
        )

    def test_existing_configured_user_is_preserved(self):
        self.create_database([(1, "user@domain.com", 1, "internal", 1)])

        self.assertEqual(
            MODULE.resolve_server_import_email("user@domain.com", self.database_path),
            ("user@domain.com", True),
        )

    def test_single_existing_administrator_replaces_missing_bootstrap_email(self):
        self.create_database([(1, "pgadmin@wodby.com", 1, "internal", 1)])
        database_before_resolution = self.database_path.read_bytes()

        self.assertEqual(
            MODULE.resolve_server_import_email("user@domain.com", self.database_path),
            ("pgadmin@wodby.com", True),
        )
        self.assertEqual(self.database_path.read_bytes(), database_before_resolution)

    def test_multiple_administrators_are_not_guessed(self):
        self.create_database(
            [
                (1, "first@example.com", 1, "internal", 1),
                (2, "second@example.com", 1, "internal", 1),
            ]
        )

        self.assertEqual(
            MODULE.resolve_server_import_email("user@domain.com", self.database_path),
            ("user@domain.com", False),
        )

    def test_inactive_and_external_administrators_are_not_selected(self):
        self.create_database(
            [
                (1, "inactive@example.com", 0, "internal", 1),
                (2, "external@example.com", 1, "ldap", 1),
                (3, "ordinary@example.com", 1, "internal", 2),
            ]
        )

        self.assertEqual(
            MODULE.resolve_server_import_email("user@domain.com", self.database_path),
            ("user@domain.com", False),
        )

    def test_pgpass_is_refreshed_for_existing_user(self):
        source = Path(self.temporary_directory.name) / "source.pgpass"
        source.write_text("postgres:5432:app:app:new-password\n")
        storage_path = Path(self.temporary_directory.name) / "storage"
        destination = storage_path / "pgadmin_wodby.com" / ".pgpass"
        destination.parent.mkdir(parents=True)
        destination.write_text("stale-password\n")
        destination.chmod(0o644)

        self.assertTrue(
            MODULE.refresh_pgpass(source, "pgadmin@wodby.com", storage_path)
        )
        self.assertEqual(destination.read_bytes(), source.read_bytes())
        self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o600)
        self.assertEqual(list(destination.parent.glob(".pgpass.tmp-*")), [])

    def test_missing_pgpass_source_is_ignored(self):
        source = Path(self.temporary_directory.name) / "missing.pgpass"
        storage_path = Path(self.temporary_directory.name) / "storage"

        self.assertFalse(
            MODULE.refresh_pgpass(source, "pgadmin@wodby.com", storage_path)
        )
        self.assertFalse(storage_path.exists())


if __name__ == "__main__":
    unittest.main()
