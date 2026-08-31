# pgAdmin Helm chart

Deploys the official pgAdmin image with a restricted non-root security context, declarative PostgreSQL server registration, and optional persistent configuration.

The chart generates an administrator password when one is not supplied. Wodby supplies a stable generated password through the service manifest. Database passwords are never written to `servers.json`.

Set `server.passwordSecret` and `server.passwordKey` together to enable automatic login for the registered PostgreSQL server. An init container reads the password from that Kubernetes Secret and creates the `.pgpass` file consumed through pgAdmin's `PGPASS_FILE` mechanism.

Enable `persistence.enabled` to retain pgAdmin accounts, settings, sessions, and saved server configuration. Upgrades always use the `Recreate` strategy because pgAdmin configuration database migrations are forward-only.

```console
helm install pgadmin oci://registry-1.docker.io/wodby/pgadmin
```
