# pgAdmin Helm chart

Deploys the official pgAdmin image with a restricted non-root security context, declarative PostgreSQL server registration, and optional persistent configuration.

The chart generates an administrator password when one is not supplied. Wodby supplies a stable generated password through the service manifest. Database passwords are never written to `servers.json`.

The default entrypoint reconciles `admin.email` with an existing persisted pgAdmin administrator before startup. It updates the existing user record in place, preserving its password, ownership, and configuration, and moves the per-user storage directory to the new email-derived path. The first reconciliation can safely infer a deployment with one existing user; subsequent changes are tracked on the data volume. Reconciliation is skipped when a custom `command` or `args` is configured.

Set `server.passwordSecret` and `server.passwordKey` together to enable automatic login for the registered PostgreSQL server. An init container reads the password from that Kubernetes Secret and creates the `.pgpass` file consumed through pgAdmin's `PGPASS_FILE` mechanism.

Enable `persistence.enabled` to retain pgAdmin accounts, settings, sessions, and saved server configuration. Upgrades always use the `Recreate` strategy because pgAdmin configuration database migrations are forward-only.

```console
helm install pgadmin oci://registry-1.docker.io/wodby/pgadmin
```
