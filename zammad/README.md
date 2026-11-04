# Zammad

Runs the [Zammad](https://zammad.org) helpdesk from the official `ghcr.io/zammad/zammad` image as four Deployments:

- `<fullname>`: NGINX on port 8080, the entry point. It serves static assets and sends `/ws` to the WebSocket server and everything else to Rails.
- `<fullname>-railsserver`: Rails and ActionCable on port 3000.
- `<fullname>-websocket`: the WebSocket server on port 6042.
- `<fullname>-scheduler`: the background worker. Its init container runs Zammad's install or migration on every rollout, then applies the settings below. It runs at most one replica and is recreated.

PostgreSQL, Redis and Memcached are external and configured through `env`, which every component receives. A component's own `components.<name>.env` replaces entries of the same name.

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL`, `POSTGRESQL_HOST`, `POSTGRESQL_PORT` | Database; the host and port are used by the startup checks |
| `REDIS_URL` | Redis |
| `MEMCACHE_SERVERS` | Memcached |
| `ELASTICSEARCH_HOST`, `ELASTICSEARCH_PORT`, `ELASTICSEARCH_SCHEMA`, `ELASTICSEARCH_USER`, `ELASTICSEARCH_PASS` | Optional Elasticsearch; search falls back to the database without a host |
| `ZAMMAD_FQDN`, `ZAMMAD_HTTP_TYPE` | Zammad's URL, applied on every rollout |
| `ZAMMAD_ADMIN_EMAIL`, `ZAMMAD_ADMIN_PASSWORD`, `ZAMMAD_ADMIN_FIRSTNAME`, `ZAMMAD_ADMIN_LASTNAME` | First administrator, created when none exists |
| `SMTP_HOST`, `SMTP_PORT` | Relay for the untouched notification channel |

The deployment values `strategy`, `minReadySeconds`, `progressDeadlineSeconds` and `terminationGracePeriodSeconds` apply to every component, and each component can override them under `components.<name>`.
