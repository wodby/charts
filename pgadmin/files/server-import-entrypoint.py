#!/usr/bin/env python3

"""Prepare persisted pgAdmin users for linked server imports."""

import ast
import os
import shutil
import sqlite3
import sys
from pathlib import Path


DEFAULT_DATABASE_PATH = Path("/var/lib/pgadmin/pgadmin4.db")
DEFAULT_STORAGE_PATH = Path("/var/lib/pgadmin/storage")
OFFICIAL_ENTRYPOINT = "/entrypoint.sh"


def configured_path(variable: str, default: Path) -> Path:
    """Parse a pgAdmin path setting, which may be a Python string literal."""
    raw_path = os.environ.get(variable, "")
    if not raw_path:
        return default

    try:
        parsed_path = ast.literal_eval(raw_path)
    except (SyntaxError, ValueError):
        parsed_path = raw_path

    if not isinstance(parsed_path, str) or not parsed_path:
        return default
    return Path(parsed_path)


def configured_database_path() -> Path:
    return configured_path("PGADMIN_CONFIG_SQLITE_PATH", DEFAULT_DATABASE_PATH)


def configured_storage_path() -> Path:
    return configured_path("PGADMIN_CONFIG_STORAGE_DIR", DEFAULT_STORAGE_PATH)


def resolve_server_import_email(
    configured_email: str, database_path: Path
) -> tuple[str, bool]:
    """Return the import user and whether it exists in the persisted database."""
    if not configured_email or not database_path.is_file():
        return configured_email, False

    try:
        connection = sqlite3.connect(
            f"{database_path.absolute().as_uri()}?mode=ro",
            uri=True,
            timeout=30,
        )
        try:
            rows = list(
                connection.execute(
                    'SELECT u.username, u.active, r.name '
                    'FROM "user" u '
                    'LEFT JOIN roles_users ru ON ru.user_id = u.id '
                    'LEFT JOIN role r ON r.id = ru.role_id '
                    'WHERE u.auth_source = ?',
                    ("internal",),
                )
            )
        finally:
            connection.close()
    except (OSError, sqlite3.Error) as error:
        print(
            f"Warning: could not inspect the persisted pgAdmin users for server import: {error}",
            file=sys.stderr,
        )
        return configured_email, False

    internal_users = {username for username, _active, _role in rows}
    if configured_email in internal_users:
        return configured_email, True

    administrators = {
        username
        for username, active, role in rows
        if active and role == "Administrator"
    }
    if len(administrators) == 1:
        existing_email = administrators.pop()
        print(
            "Using persisted pgAdmin administrator "
            f"{existing_email!r} for linked server import because configured bootstrap user "
            f"{configured_email!r} does not exist",
            file=sys.stderr,
        )
        return existing_email, True

    print(
        "Warning: configured pgAdmin bootstrap user "
        f"{configured_email!r} does not exist and found {len(administrators)} active internal administrators; "
        "linked server import will use the configured user",
        file=sys.stderr,
    )
    return configured_email, False


def refresh_pgpass(source: Path, email: str, storage_path: Path) -> bool:
    """Atomically install the linked database password for an existing user."""
    if not email or not source.is_file():
        return False

    user_storage = storage_path / email.replace("@", "_")
    user_storage.mkdir(parents=True, exist_ok=True)
    destination = user_storage / ".pgpass"
    temporary = user_storage / f".pgpass.tmp-{os.getpid()}"

    try:
        with source.open("rb") as source_file, temporary.open("wb") as target_file:
            shutil.copyfileobj(source_file, target_file)
        temporary.chmod(0o600)
        os.replace(temporary, destination)
        destination.chmod(0o600)
    finally:
        temporary.unlink(missing_ok=True)

    return True


def main() -> None:
    uses_local_configuration_database = not os.environ.get(
        "PGADMIN_CONFIG_CONFIG_DATABASE_URI", ""
    )
    if uses_local_configuration_database and os.path.isfile(
        os.environ.get("PGADMIN_SERVER_JSON_FILE", "")
    ):
        configured_email = os.environ.get("PGADMIN_DEFAULT_EMAIL", "")
        import_email, persisted_user_exists = resolve_server_import_email(
            configured_email,
            configured_database_path(),
        )
        os.environ["PGADMIN_DEFAULT_EMAIL"] = import_email

        pgpass_file = os.environ.get("PGPASS_FILE", "")
        if persisted_user_exists and pgpass_file:
            refresh_pgpass(
                Path(pgpass_file),
                import_email,
                configured_storage_path(),
            )

    os.execve(OFFICIAL_ENTRYPOINT, [OFFICIAL_ENTRYPOINT], os.environ.copy())


if __name__ == "__main__":
    main()
