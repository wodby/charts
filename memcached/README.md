# Memcached Helm chart

This chart deploys a single ephemeral Memcached cache using the
`wodby/memcached` image. It exposes TCP port 11211 through a ClusterIP Service
and explicitly disables UDP.

Memcached nodes do not coordinate with each other. Do not increase
`replicaCount` behind the chart's ClusterIP Service unless clients are given an
explicit server list and implement consistent hashing.

The image supports these environment variables through `envVars`:

| Variable | Default | Description |
| --- | --- | --- |
| `MEMCACHED_MEMORY` | `64` | Memory in MB reserved for cached items |
| `MEMCACHED_THREADS` | `4` | Worker thread count |
| `MEMCACHED_MAX_CONNECTIONS` | `1024` | Maximum simultaneous connections |

`MEMCACHED_MEMORY` is not a container memory limit. Memcached uses additional
memory for the process and connection overhead, so configure Kubernetes memory
resources above the item-cache size.
