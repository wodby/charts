# Supabase

Self-hosted Supabase APIs and Studio, using the upstream `self-hosted/v0.8.1` image bundle and an external Supabase PostgreSQL 17 database. The chart creates seven Deployments: Envoy, Auth, PostgREST, Realtime, Storage (with imgproxy), postgres-meta, and Studio.

## Database prerequisite

The PostgreSQL server must run `supabase/postgres:17.6.1.136` with the matching upstream initialization SQL, roles, extensions, logical replication configuration and persistent encryption keys. An ordinary empty PostgreSQL database is not sufficient. PostgreSQL is intentionally a separate service so its lifecycle, volumes and database operations remain explicit.

## Credentials

Supply every field under `credentials` before installing. Passwords, seeds, API keys and encryption keys must be generated once per environment and stored outside the Helm release as recovery material. The Wodby service manifest supplies persistent tokens and links the database credentials.

A regular Kubernetes Job derives the ES256 signing key from `SIGNING_SEED`, generates legacy HS256 role tokens and internal ES256 role tokens, and atomically patches the chart-managed credential Secret. Its Role permits only `patch` on that one named Secret. It cannot list or read arbitrary Secrets or create resources. Application service accounts do not have Kubernetes API tokens mounted.

Each pod waits for the credential revision matching its configuration before starting. This gate prevents a new Deployment from starting with an earlier credential bundle while an upgrade Job is running. Helm owns the output Secret object; the Job owns its data fields. Jobs are named by Helm revision, so upgrades and rollbacks run a fresh reconciliation. All these resources are removed with the release; there are no Helm hooks or cluster-scoped resources.

The legacy role tokens expire on 2100-01-01 and must be treated as long-lived API credentials. Change `JWT_SECRET` to rotate them. Changing `SIGNING_SEED` rotates the asymmetric signing key and invalidates sessions signed with the old key. Rotating `SUPABASE_SECRET_KEY` or `SUPABASE_PUBLISHABLE_KEY` alone preserves session signing keys. Encryption keys have a separate data migration requirement and must not be rotated as ordinary passwords.

`JWT_JWKS` includes the legacy symmetric key and is secret. Only Auth's public JWKS HTTP endpoint is intended for public distribution. Generated source tokens and every required database encryption key must accompany a recovery backup.

## Networking and storage

Only the gateway should receive public routing. Studio and database administration routes retain the upstream gateway authentication rules. Functions and MCP access are disabled in this release. ClusterIP services are used throughout; a cloud load balancer is not required.

`storage.backend` defaults to `file`. Storage and imgproxy share one pod and one ReadWriteOnce claim. Studio snippets have a separate claim. Both persistent workloads use `Recreate` to avoid overlapping writers and volume attachment conflicts. Existing claims can be supplied through `storage.persistence.existingClaim` and `studio.persistence.existingClaim`.

For S3, configure the bucket, optional custom endpoint and native AWS credentials. The bucket must already exist. The chart does not create buckets or supply object-store credentials. Existing filesystem objects are not automatically copied when changing backends. An S3 backup is independent of the filesystem backup operation.

## Wodby value mappings

`replicaCount` controls every Deployment, including zero when paused. This initial bundle supports zero or one replica. Names, service accounts and image pull secrets are global; resource, environment, volume, image and rollout paths are under `components.<name>`. The gateway uses the release's full name; other workloads append their component name. Each workload has a distinct `app.kubernetes.io/component` selector.

Wodby integrations enter through `integrationEnv`, the primary container's environment mapping. The chart sends `RELAY_HOST`, `RELAY_PORT`, `RELAY_USER` and `RELAY_PASSWORD` only to Auth, translating them to native `GOTRUE_SMTP_*` variables. Native S3 variables go only to Storage. Other primary-container overrides go to the gateway. Component-specific overrides remain under `components.<name>.env`, with explicit values replacing defaults by name.

SMTP transport behavior follows Supabase Auth's native SMTP implementation. Use port 465 for implicit TLS or a STARTTLS-capable SMTP server on port 587. `RELAY_PROTO` is not a GoTrue setting and is not passed through.

## Validation

```sh
helm lint --strict .
node --test tests/bootstrap.test.cjs
python3 tests/render_test.py
```

The rendering tests require PyYAML. Runtime acceptance must additionally cover fresh initialization, authentication/RLS, Realtime, file/S3 storage, backup/restore, pause/resume, credential preservation across upgrade, and recovery from a failed bootstrap.

## Upstream files

Gateway configuration is adapted from [Supabase self-hosted/v0.8.1](https://github.com/supabase/supabase/tree/self-hosted/v0.8.1/docker), commit `8c7a4d9dbbaf8b552893822e89d7bf06f33f9220`. Adaptations use release-local Kubernetes DNS names, omit Functions, disable MCP, and avoid unauthenticated Realtime/REST health checks. The upstream license is retained in `files/SUPABASE-LICENSE`. Images are consumed directly; this chart does not build images.
