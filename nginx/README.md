# README

Fork of https://github.com/bitnami/charts/blob/main/bitnami/nginx/README.md

- disabled tls
- removed initContainers
- removed empty dir volumes
- ClusterIP service type
- HTTP port set to 80
- HTTPS port removed
- disable securityContext
- custom readiness probe
- disabled network policy
