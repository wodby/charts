# pgAdmin Helm chart

Deploys the official pgAdmin image with a restricted non-root security context, declarative PostgreSQL server registration, and optional persistent configuration.

The chart generates an administrator password when one is not supplied. Wodby supplies a stable generated password through the service manifest. Database passwords are never written to `servers.json`.

Enable `persistence.enabled` to retain pgAdmin accounts, settings, sessions, and saved server configuration. Upgrades always use the `Recreate` strategy because pgAdmin configuration database migrations are forward-only.

```console
helm install pgadmin oci://registry-1.docker.io/wodby/pgadmin
```
