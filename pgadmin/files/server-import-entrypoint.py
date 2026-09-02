#!/usr/bin/env python3

"""Select the persisted pgAdmin administrator used for server imports."""

import ast
import os
import sqlite3
import sys
from pathlib import Path


DEFAULT_DATABASE_PATH = Path("/var/lib/pgadmin/pgadmin4.db")
OFFICIAL_ENTRYPOINT = "/entrypoint.sh"


def configured_database_path() -> Path:
    raw_path = os.environ.get("PGADMIN_CONFIG_SQLITE_PATH", "")
    if not raw_path:
        return DEFAULT_DATABASE_PATH

    try:
        parsed_path = ast.literal_eval(raw_path)
    except (SyntaxError, ValueError):
        parsed_path = raw_path

    if not isinstance(parsed_path, str) or not parsed_path:
        return DEFAULT_DATABASE_PATH
    return Path(parsed_path)


def resolve_server_import_email(configured_email: str, database_path: Path) -> str:
    """Return the configured user or the sole active internal administrator."""
    if not configured_email or not database_path.is_file():
        return configured_email

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
        return configured_email

    internal_users = {username for username, _active, _role in rows}
    if configured_email in internal_users:
        return configured_email

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
        return existing_email

    print(
        "Warning: configured pgAdmin bootstrap user "
        f"{configured_email!r} does not exist and found {len(administrators)} active internal administrators; "
        "linked server import will use the configured user",
        file=sys.stderr,
    )
    return configured_email


def main() -> None:
    uses_local_configuration_database = not os.environ.get(
        "PGADMIN_CONFIG_CONFIG_DATABASE_URI", ""
    )
    if uses_local_configuration_database and os.path.isfile(
        os.environ.get("PGADMIN_SERVER_JSON_FILE", "")
    ):
        configured_email = os.environ.get("PGADMIN_DEFAULT_EMAIL", "")
        os.environ["PGADMIN_DEFAULT_EMAIL"] = resolve_server_import_email(
            configured_email,
            configured_database_path(),
        )

    os.execve(OFFICIAL_ENTRYPOINT, [OFFICIAL_ENTRYPOINT], os.environ.copy())


if __name__ == "__main__":
    main()
