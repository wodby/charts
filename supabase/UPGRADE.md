# Upgrade and recovery

Version 0.1.0 introduces the Supabase self-hosted/v0.8.1 bundle. There is no supported conversion from an unrelated Supabase chart or an ordinary PostgreSQL service.

Before a bundle update, preserve the service's source tokens, database encryption material, a database backup and matching storage objects. Stop application writers when taking a coordinated recovery point. Test database initialization changes against an existing volume; scripts under `docker-entrypoint-initdb.d` run only on an empty database.

Preserve source credentials on every Helm upgrade. The bootstrap Job derives a consistent bundle and the pod credential gate blocks startup until that bundle is available. If the Job fails, inspect its error and fix the input before retrying with another Helm upgrade. Never print the credential Secret in task logs.

Helm rollback restores chart configuration, not database migrations or object-storage contents. A database-changing upgrade may require restoring the matching backup into a fresh environment. PostgreSQL major upgrades require a separate tested procedure and must not be implemented by changing the image tag against an existing data directory.

The first bundle is single-replica. Scaling individual components or adding HA PostgreSQL requires a separately tested contract.
