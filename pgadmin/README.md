# pgAdmin Helm chart

Deploys the official pgAdmin image with a restricted non-root security context, declarative PostgreSQL server registration, and optional persistent configuration.

The chart generates an administrator password when one is not supplied. Wodby supplies a stable generated password through the service manifest. Database passwords are never written to `servers.json`.

When a local pgAdmin configuration database already exists, the chart checks which internal administrator should receive the generated server definitions before running the official entrypoint. If the configured bootstrap email is absent and there is exactly one active internal administrator, the chart uses that existing account for server import without renaming or otherwise modifying the user. It also refreshes that account's `.pgpass` file on every startup so linked database password changes and upgrades of older volumes preserve automatic login. Custom `command` or `args` values disable this compatibility behavior.

Set `server.passwordSecret` and `server.passwordKey` together to enable automatic login for the registered PostgreSQL server. An init container reads the password from that Kubernetes Secret and creates the `.pgpass` file consumed through pgAdmin's `PGPASS_FILE` mechanism. The generated server definition references `.pgpass` through `ConnectionParameters.passfile`, allowing pgAdmin to resolve it inside the logged-in user's storage directory.

Enable `persistence.enabled` to retain pgAdmin accounts, settings, sessions, and saved server configuration. Upgrades always use the `Recreate` strategy because pgAdmin configuration database migrations are forward-only.

```console
helm install pgadmin oci://registry-1.docker.io/wodby/pgadmin
```
