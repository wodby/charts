#!/usr/bin/env python3

"""Keep a persisted pgAdmin administrator aligned with the configured email."""

import os
import re
import shutil
import sqlite3
from pathlib import Path


EMAIL_PATTERN = re.compile(
    r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$"
)


def validate_email(email: str) -> str:
    email = email.strip()
    if not EMAIL_PATTERN.fullmatch(email):
        raise RuntimeError(f"Invalid pgAdmin administrator email: {email!r}")
    return email


def read_marker(marker_path: Path) -> str:
    if not marker_path.exists():
        return ""
    return marker_path.read_text(encoding="utf-8").strip()


def write_marker(marker_path: Path, email: str) -> None:
    temporary_path = marker_path.with_name(f"{marker_path.name}.tmp")
    temporary_path.write_text(f"{email}\n", encoding="utf-8")
    temporary_path.replace(marker_path)


def storage_path(storage_root: Path, email: str) -> Path:
    validate_email(email)
    return storage_root / email.replace("@", "_")


def migrate_storage(storage_root: Path, source_email: str, target_email: str) -> None:
    if not source_email or source_email == target_email:
        return

    source_path = storage_path(storage_root, source_email)
    target_path = storage_path(storage_root, target_email)
    if not source_path.exists():
        return

    target_path.parent.mkdir(parents=True, exist_ok=True)
    if target_path.exists():
        shutil.copytree(source_path, target_path, dirs_exist_ok=True)
        shutil.rmtree(source_path)
    else:
        source_path.rename(target_path)


def reconcile_admin_email(
    target_email: str,
    database_path: Path,
    storage_root: Path,
    marker_path: Path,
) -> bool:
    target_email = validate_email(target_email)
    if not database_path.exists():
        print("pgAdmin configuration database is not initialized; administrator reconciliation is not needed")
        return False

    marker_email = read_marker(marker_path)
    if marker_email:
        marker_email = validate_email(marker_email)

    connection = sqlite3.connect(database_path, timeout=30)
    try:
        users = list(connection.execute('SELECT id, username FROM "user" ORDER BY id'))
        target_user = next((user for user in users if user[1] == target_email), None)
        if target_user is not None:
            migrate_storage(storage_root, marker_email, target_email)
            write_marker(marker_path, target_email)
            print(f"pgAdmin administrator email is already {target_email}")
            return False

        source_user = None
        if marker_email:
            source_user = next((user for user in users if user[1] == marker_email), None)
        if source_user is None and len(users) == 1:
            source_user = users[0]
        if source_user is None:
            raise RuntimeError(
                "Cannot determine the managed pgAdmin administrator: "
                f"configured email {target_email!r} is absent and the configuration database contains "
                f"{len(users)} users"
            )

        source_email = validate_email(source_user[1])
        write_marker(marker_path, source_email)
        with connection:
            cursor = connection.execute(
                'UPDATE "user" SET username = ?, email = ? WHERE id = ? AND username = ?',
                (target_email, target_email, source_user[0], source_email),
            )
            if cursor.rowcount != 1:
                raise RuntimeError("The persisted pgAdmin administrator changed during reconciliation")

        migrate_storage(storage_root, source_email, target_email)
        write_marker(marker_path, target_email)
        print(f"Reconciled pgAdmin administrator email from {source_email} to {target_email}")
        return True
    finally:
        connection.close()


def main() -> None:
    data_directory = Path(os.environ.get("PGADMIN_DATA_DIR", "/var/lib/pgadmin"))
    target_email = os.environ.get("PGADMIN_DEFAULT_EMAIL", "")
    reconcile_admin_email(
        target_email,
        data_directory / "pgadmin4.db",
        data_directory / "storage",
        data_directory / ".wodby-admin-email",
    )


if __name__ == "__main__":
    main()
