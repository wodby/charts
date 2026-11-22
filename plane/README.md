# Plane

Runs [Plane](https://plane.so) Community Edition from Plane's own images, all at one release, as eight Deployments:

- `<fullname>`: Caddy (`makeplane/plane-proxy`) on port 8080, the entry point. It sends `/api`, `/auth` and `/static` to the API, `/god-mode` to the admin app, `/spaces` to the space app, `/live` to the live server, `/<bucket>` to the S3 storage and everything else to the web app. `/-/health` answers without the other components.
- `<fullname>-web`, `<fullname>-admin`, `<fullname>-space`, `<fullname>-live`, `<fullname>-api`: Plane's web app, God Mode, published projects, real-time editing server and Django API.
- `<fullname>-worker`: Celery workers, `PLANE_WORKER_CONCURRENCY` processes each (default 2).
- `<fullname>-scheduler`: Celery beat. Its init container applies the migrations, registers the instance and sets up the first administrator on every rollout. It runs at most one replica and is recreated. The API and workers wait until the migrations are applied.

PostgreSQL, Redis, RabbitMQ and S3-compatible storage are external and configured through `env`, which every component receives. A component's own `components.<name>.env` replaces entries of the same name.

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL` | PostgreSQL |
| `REDIS_URL` | Redis or Valkey |
| `AMQP_URL` | RabbitMQ. RabbitMQ 4 must permit `transient_nonexcl_queues` for Celery's control queues |
| `AWS_S3_ENDPOINT_URL`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_S3_BUCKET_NAME`, `AWS_REGION` | S3 storage; the API creates the bucket |
| `PLANE_S3_UPSTREAM` | `host:port` of the S3 storage, where the proxy sends the bucket path |
| `USE_MINIO`, `MINIO_ENDPOINT_SSL` | `1` and `1`: presigned URLs use Plane's own HTTPS address, through the proxy |
| `SECRET_KEY`, `LIVE_SERVER_SECRET_KEY` | Required secrets |
| `WEB_URL`, `CORS_ALLOWED_ORIGINS` | Plane's address |
| `PLANE_ADMIN_EMAIL`, `PLANE_ADMIN_PASSWORD`, `PLANE_ADMIN_FIRST_NAME`, `PLANE_INSTANCE_NAME` | First administrator and instance name, applied while no administrator exists. A missing or weak password stops the init container before the migrations, so nothing is served |
| `ENABLE_SIGNUP`, `ENABLE_SMTP`, `EMAIL_*` | Instance settings stored on the first rollout; change them in God Mode afterwards |
| `FILE_SIZE_LIMIT` | Largest upload, in bytes; the proxy enforces it too |
| `GUNICORN_WORKERS`, `PLANE_WORKER_CONCURRENCY` | API and Celery processes |

The deployment values `strategy`, `minReadySeconds`, `progressDeadlineSeconds` and `terminationGracePeriodSeconds` apply to every component, and each component can override them under `components.<name>`. `components.<name>.image` sets a component's repository, and optionally its own registry, tag and pull policy; the shared `image` gives the defaults.
